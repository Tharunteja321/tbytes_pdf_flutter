// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'dart:convert';
import 'acro_form.dart';
import 'acro_form_field.dart';
import 'image_decoder/src/formats/formats.dart' as img;
import 'image_decoder/src/image/image.dart' as img;
import 'image_decoder/src/image/pixel.dart' as img;
import 'image_decoder/src/transform/trim.dart' as img;
import 'pdf_document.dart';
import 'pdf_objects.dart';
import 'internal/logger.dart';

class SignatureImagePlacer {
  SignatureImagePlacer(this._doc);

  final PdfDoc _doc;

  // ── Counter for unique XObject resource names within a session ───────────
  static int _xObjCounter = 0;

  void placeSignatureOnField({
    required AcroField field,
    required Uint8List imageBytes,
    double? maxWidth,
    double? maxHeight,
    bool transparentBackground = true,
    double offsetX = 0.0,
    double offsetY = 0.0,
  }) {
    final AcroFormReader reader = AcroFormReader(_doc);

    // 1. Get field position
    final Rect? fieldRect = reader.getFieldRect(field);
    if (fieldRect == null) {
      throw Exception('Could not determine field position');
    }
    Logger.debug('🔍 Field rect: $fieldRect');

    // 2. Get the page
    final int? pageIndex = reader.getFieldPage(field);
    if (pageIndex == null) {
      throw Exception('Could not determine field page');
    }
    Logger.debug('📄 Field is on page: $pageIndex');

    // 3. Get the page dict
    final PdfDict? page = _doc.getPage(pageIndex);
    if (page == null) {
      throw Exception('Could not get page $pageIndex');
    }

    // 4. Decode the image
    final img.Image? decodedOriginal = img.decodeImage(imageBytes);
    if (decodedOriginal == null) {
      throw Exception('Could not decode image');
    }

    // 4.5 Auto-crop transparent areas
    final img.Image decoded = img.trim(
      decodedOriginal,
      mode: img.TrimMode.transparent,
    );
    final double imgAspect = decoded.width / decoded.height;
    Logger.debug('✂️  Cropped: ${decoded.width}x${decoded.height}');

    // 5. Calculate display size maintaining aspect ratio
    final double targetMaxWidth  = maxWidth  ?? 150.0;
    final double targetMaxHeight = maxHeight ?? 80.0;
    double sigWidth, sigHeight;
    if (imgAspect > (targetMaxWidth / targetMaxHeight)) {
      sigWidth  = targetMaxWidth;
      sigHeight = targetMaxWidth / imgAspect;
    } else {
      sigHeight = targetMaxHeight;
      sigWidth  = targetMaxHeight * imgAspect;
    }
    Logger.debug('📏 Signature size: ${sigWidth.toStringAsFixed(1)}x${sigHeight.toStringAsFixed(1)}');

    // 6. Calculate PDF coordinates for placement
    //
    // AcroFormReader.getFieldRect() stores raw PDF Y values in a Flutter Rect:
    //   fieldRect.top    = min PDF Y  = PDF BOTTOM of field (lower on page)
    //   fieldRect.bottom = max PDF Y  = PDF TOP    of field (higher on page)
    //
    // sigX    = left edge of signature (PDF X, same axis as screen)
    // sigLLY  = lower-left Y in PDF coordinates (bottom of image, PDF space)
    //         = PDF top of field − sigHeight
    //           ↑ places the signature spanning UP from this point to the field top
    final double sigX   = fieldRect.left + offsetX;
    final double sigLLY = fieldRect.bottom - sigHeight + offsetY;

    Logger.debug('📍 PDF placement: X=$sigX  LLY=$sigLLY  W=$sigWidth  H=$sigHeight');

    // 7. Create the image XObject (your existing method — handles SMask, alpha, etc.)
    final PdfRef imageRef = _createImageXObjectFromDecoded(
      decoded,
      transparentBackground: transparentBackground,
    );
    Logger.debug('✓ Image XObject: $imageRef');

    // 8. Embed directly into page content stream (renderer-agnostic flat graphic)
    _embedImageInPageContent(
      page:      page,
      imageRef:  imageRef,
      sigX:      sigX,
      sigLLY:    sigLLY,
      sigWidth:  sigWidth,
      sigHeight: sigHeight,
    );

    // 9. NeedAppearances → false
    //    The image is now burned into page content, not an annotation.
    //    No viewer regeneration needed.
    final PdfDict? catalog  = _doc.catalog;
    if (catalog != null) {
      final PdfObj? acroForm = _doc.resolve(catalog['AcroForm']);
      if (acroForm is PdfDict) {
        acroForm['NeedAppearances'] = const PdfBool(false);
      }
    }

    Logger.debug('✅ Signature embedded in page content on page $pageIndex');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NEW: Embed the image directly into the page content stream.
  //
  // This appends a new PdfStream to the page's Contents array containing
  // only the drawing operators for this image. The result is a flat graphic
  // in the page — invisible to annotation z-ordering, invisible to
  // NeedAppearances regeneration, renders identically in every PDF renderer.
  //
  // PDF content stream operators used (same as Syncfusion internals):
  //   q                              — save graphics state
  //   w 0 0 h tx ty cm               — scale+translate to image bounds (PDF coords)
  //   /XObjName Do                   — paint the image XObject
  //   Q                              — restore graphics state
  //
  // Coordinate note: tx = sigX (left edge), ty = sigLLY (BOTTOM in PDF space,
  // i.e., lower Y value). PDF Y-axis points UP, so the image occupies
  // [ty, ty+h] vertically — which is exactly the field's position.
  // ─────────────────────────────────────────────────────────────────────────
  void _embedImageInPageContent({
    required PdfDict  page,
    required PdfRef   imageRef,
    required double   sigX,
    required double   sigLLY,
    required double   sigWidth,
    required double   sigHeight,
  }) {
    // 1. Choose a unique resource name so we don't collide with existing XObjects
    final String xObjName = 'VoyagerSig${++_xObjCounter}';

    // 2. Register the image as a named XObject resource on the page
    _addXObjectToPage(page, xObjName, imageRef);

    // 3. Build content stream operators
    //    [a 0 0 d e f] cm  where a=width, d=height, e=tx, f=ty (PDF lly)
    final String w  = _fmt(sigWidth);
    final String h  = _fmt(sigHeight);
    final String tx = _fmt(sigX);
    final String ty = _fmt(sigLLY);

    final String ops = 'q\n$w 0 0 $h $tx $ty cm\n/$xObjName Do\nQ\n';
    Logger.debug('   Content ops: $ops');

    // 4. Compress the stream (FlateDecode) — same approach as Syncfusion
    final Uint8List raw        = Uint8List.fromList(utf8.encode(ops));
    final List<int> compressed = ZLibEncoder().convert(raw);

    final PdfDict streamDict = PdfDict();
    streamDict['Filter'] = const PdfName('FlateDecode');
    // Note: PdfWriter recalculates Length automatically, but set it for compliance
    streamDict['Length'] = PdfNum(compressed.length);

    final PdfStream contentStream = PdfStream(streamDict, compressed);
    final PdfRef streamRef = _doc.addObject(contentStream);
    Logger.debug('   Content stream ref: $streamRef');

    // 5. Append to page Contents
    //    Contents can be: absent | a single PdfRef | a PdfArr of PdfRefs
    _appendToContents(page, streamRef);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Safely add an XObject resource entry to the page.
  //
  // Handles all three resource layouts found in real PDFs:
  //   A) Resources is an inline PdfDict
  //   B) Resources is a PdfRef → resolves the cached PdfDict and mutates it
  //   C) Resources/XObject is itself a PdfRef → same resolve + mutate pattern
  //
  // Because getObject() returns the SAME PdfDict instance that lives in
  // _objectCache, mutating it is enough — the writer serialises objectCache.
  // ─────────────────────────────────────────────────────────────────────────
  void _addXObjectToPage(PdfDict page, String name, PdfRef imageRef) {
    // ── Resolve Resources ────────────────────────────────────────────────
    PdfDict resources;
    final PdfObj? resObj = page['Resources'];
    if (resObj is PdfRef) {
      final PdfDict? resolved = _doc.resolve(resObj) as PdfDict?;
      if (resolved != null) {
        resources = resolved;              // mutate cached object directly
      } else {
        resources = PdfDict();
        page['Resources'] = resources;
      }
    } else if (resObj is PdfDict) {
      resources = resObj;
    } else {
      resources = PdfDict();
      page['Resources'] = resources;
    }

    // ── Resolve XObject sub-dict ─────────────────────────────────────────
    PdfDict xObjects;
    final PdfObj? xObjObj = resources['XObject'];
    if (xObjObj is PdfRef) {
      final PdfDict? resolved = _doc.resolve(xObjObj) as PdfDict?;
      if (resolved != null) {
        xObjects = resolved;
      } else {
        xObjects = PdfDict();
        resources['XObject'] = xObjects;
      }
    } else if (xObjObj is PdfDict) {
      xObjects = xObjObj;
    } else {
      xObjects = PdfDict();
      resources['XObject'] = xObjects;
    }

    xObjects[name] = imageRef;
    Logger.debug('   Registered /$name in page XObject resources');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Append streamRef to the page's Contents.
  //   - No Contents key      → set directly as single stream ref
  //   - Single PdfRef        → promote to a PdfArr([existing, new])
  //   - Already PdfArr       → push to end
  //   - Resolved PdfStream   → promote to array (edge case)
  // ─────────────────────────────────────────────────────────────────────────
  void _appendToContents(PdfDict page, PdfRef streamRef) {
    final PdfObj? existing = page['Contents'];

    if (existing == null) {
      page['Contents'] = streamRef;
      Logger.debug('   Contents: set new single stream');
    } else if (existing is PdfRef) {
      page['Contents'] = PdfArr(<PdfObj>[existing, streamRef]);
      Logger.debug('   Contents: promoted to array [existing, new]');
    } else if (existing is PdfArr) {
      existing.items.add(streamRef);
      Logger.debug('   Contents: appended to existing array (${existing.items.length} streams)');
    } else if (existing is PdfStream) {
      // Rare: Contents was an inline stream — wrap it
      final PdfRef wrappedRef = _doc.addObject(existing);
      page['Contents'] = PdfArr(<PdfObj>[wrappedRef, streamRef]);
      Logger.debug('   Contents: wrapped inline stream + appended new');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Format a double for PDF stream output — no trailing .00 noise
  // ─────────────────────────────────────────────────────────────────────────
  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Everything below is UNCHANGED from your original code
  // ─────────────────────────────────────────────────────────────────────────

  PdfRef _createImageXObjectFromDecoded(
    img.Image image, {
    required bool transparentBackground,
  }) {
    final bool hasAlpha = image.numChannels == 4;
    if (transparentBackground && hasAlpha) {
      return _createTransparentImageXObject(image);
    } else {
      return _createOpaqueImageXObject(image);
    }
  }

  PdfRef _createTransparentImageXObject(img.Image image) {
    final int imgWidth  = image.width;
    final int imgHeight = image.height;

    final Uint8List rgbData   = Uint8List(imgWidth * imgHeight * 3);
    final Uint8List alphaData = Uint8List(imgWidth * imgHeight);
    int rgbIdx = 0, alphaIdx = 0;

    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final img.Pixel p = image.getPixel(x, y);
        rgbData[rgbIdx++]     = p.r.toInt();
        rgbData[rgbIdx++]     = p.g.toInt();
        rgbData[rgbIdx++]     = p.b.toInt();
        alphaData[alphaIdx++] = p.a.toInt();
      }
    }

    final PdfRef smaskRef = _createSoftMask(imgWidth, imgHeight, alphaData);

    final List<int> compressed = ZLibEncoder().convert(rgbData);
    final PdfDict imageDict = PdfDict();
    imageDict['Type']             = const PdfName('XObject');
    imageDict['Subtype']          = const PdfName('Image');
    imageDict['Width']            = PdfNum(imgWidth);
    imageDict['Height']           = PdfNum(imgHeight);
    imageDict['ColorSpace']       = const PdfName('DeviceRGB');
    imageDict['BitsPerComponent'] = const PdfNum(8);
    imageDict['Filter']           = const PdfName('FlateDecode');
    imageDict['SMask']            = smaskRef;

    return _doc.addObject(PdfStream(imageDict, Uint8List.fromList(compressed)));
  }

  PdfRef _createSoftMask(int width, int height, Uint8List alphaData) {
    final PdfDict maskDict = PdfDict();
    maskDict['Type']             = const PdfName('XObject');
    maskDict['Subtype']          = const PdfName('Image');
    maskDict['Width']            = PdfNum(width);
    maskDict['Height']           = PdfNum(height);
    maskDict['ColorSpace']       = const PdfName('DeviceGray');
    maskDict['BitsPerComponent'] = const PdfNum(8);
    maskDict['Filter']           = const PdfName('FlateDecode');

    return _doc.addObject(
      PdfStream(maskDict, Uint8List.fromList(ZLibEncoder().convert(alphaData))),
    );
  }

  PdfRef _createOpaqueImageXObject(img.Image image) {
    final int imgWidth  = image.width;
    final int imgHeight = image.height;
    final bool hasAlpha = image.numChannels == 4;

    final Uint8List rgbData = Uint8List(imgWidth * imgHeight * 3);
    int rgbIdx = 0;

    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final img.Pixel p = image.getPixel(x, y);
        if (hasAlpha && p.a < 255) {
          final double a = p.a / 255.0;
          rgbData[rgbIdx++] = ((p.r * a) + (255 * (1 - a))).round().clamp(0, 255);
          rgbData[rgbIdx++] = ((p.g * a) + (255 * (1 - a))).round().clamp(0, 255);
          rgbData[rgbIdx++] = ((p.b * a) + (255 * (1 - a))).round().clamp(0, 255);
        } else {
          rgbData[rgbIdx++] = p.r.toInt();
          rgbData[rgbIdx++] = p.g.toInt();
          rgbData[rgbIdx++] = p.b.toInt();
        }
      }
    }

    final PdfDict imageDict = PdfDict();
    imageDict['Type']             = const PdfName('XObject');
    imageDict['Subtype']          = const PdfName('Image');
    imageDict['Width']            = PdfNum(imgWidth);
    imageDict['Height']           = PdfNum(imgHeight);
    imageDict['ColorSpace']       = const PdfName('DeviceRGB');
    imageDict['BitsPerComponent'] = const PdfNum(8);
    imageDict['Filter']           = const PdfName('FlateDecode');

    return _doc.addObject(
      PdfStream(imageDict, Uint8List.fromList(ZLibEncoder().convert(rgbData))),
    );
  }
}