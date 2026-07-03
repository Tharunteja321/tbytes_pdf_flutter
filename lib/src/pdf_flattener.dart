// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pdf_document.dart';
import 'pdf_objects.dart';
import 'internal/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Quality enum
// ─────────────────────────────────────────────────────────────────────────────

/// Controls rendering quality for future rasterisation extensions.
/// For the current AP-stream + text flattening path quality has no lossy
/// effect — the AP XObject is embedded as-is.
enum FlattenQuality {
  /// 72 dpi — native PDF resolution, smallest output.
  standard,

  /// 150 dpi — balanced quality/size, recommended default.
  high,

  /// 300 dpi — print / archive quality, largest output.
  ultra,
}

extension FlattenQualityDpi on FlattenQuality {
  double get dpi {
    switch (this) {
      case FlattenQuality.standard:
        return 72.0;
      case FlattenQuality.high:
        return 150.0;
      case FlattenQuality.ultra:
        return 300.0;
    }
  }

  double get scale => dpi / 72.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Target selector
// ─────────────────────────────────────────────────────────────────────────────

enum FlattenTarget {
  /// Only Stamp annotations (signatures).
  stampsOnly,

  /// Only Widget/FreeText annotations (form fields).
  formsOnly,

  /// Both stamps and form fields.
  all,
}

// ─────────────────────────────────────────────────────────────────────────────
// Result
// ─────────────────────────────────────────────────────────────────────────────

class FlattenResult {
  const FlattenResult({
    required this.pagesProcessed,
    required this.annotationsFlattened,
    required this.annotationsSkipped,
  });

  final int pagesProcessed;
  final int annotationsFlattened;
  final int annotationsSkipped;

  @override
  String toString() =>
      'FlattenResult(pages: $pagesProcessed, '
      'flattened: $annotationsFlattened, '
      'skipped: $annotationsSkipped)';
}

// ─────────────────────────────────────────────────────────────────────────────
// PdfFlattener
// ─────────────────────────────────────────────────────────────────────────────

/// Bakes annotations and/or form fields permanently into PDF page content.
///
/// Key design (derived from Syncfusion source analysis):
///
/// • AP-stream path (Stamp/signature):
///   The existing /AP/N Form XObject is referenced as an XObject on the page
///   and drawn with a pure-translation cm matrix:
///     [1 0 0 1 pdfX pdfY] cm  — where pdfY = pageHeight - (annotTop + annotH)
///   This matches exactly how Syncfusion's drawPdfTemplate does it.
///
/// • Text-value path (Widget/FreeText without AP):
///   Reads /V and writes BT...Tj...ET operators at the correct PDF coordinates.
///
/// • Coordinate system:
///   The annotation /Rect is [left, bottom, right, top] in PDF space (Y-up).
///   We normalise to ensure left<right and bottom<top before use.
class PdfFlattener {
  PdfFlattener(this._doc);

  final PdfDoc _doc;

  FlattenResult flatten({
    FlattenQuality quality = FlattenQuality.high,
    FlattenTarget target = FlattenTarget.all,
  }) {
    int pagesProcessed = 0;
    int flattened = 0;
    int skipped = 0;

    for (int pageIndex = 0; ; pageIndex++) {
      final PdfDict? page = _doc.getPage(pageIndex);
      if (page == null) break;

      pagesProcessed++;

      // Get page height from MediaBox for coordinate conversion
      final double pageHeight = _getPageHeight(page);

      final PdfArr? annots = _doc.resolve(page['Annots']) as PdfArr?;
      if (annots == null || annots.items.isEmpty) continue;

      final List<PdfObj> remaining = <PdfObj>[];

      for (final PdfObj annotRef in annots.items) {
        final PdfDict? annot = _doc.resolve(annotRef) as PdfDict?;
        if (annot == null) {
          remaining.add(annotRef);
          skipped++;
          continue;
        }

        final String subtype =
            (_doc.resolve(annot['Subtype']) as PdfName?)?.value ?? '';

        final bool isStamp    = subtype == 'Stamp';
        final bool isWidget   = subtype == 'Widget';
        final bool isFreeText = subtype == 'FreeText';

        final bool shouldFlatten = switch (target) {
          FlattenTarget.stampsOnly => isStamp,
          FlattenTarget.formsOnly  => isWidget || isFreeText,
          FlattenTarget.all        => isStamp || isWidget || isFreeText,
        };

        if (!shouldFlatten) {
          remaining.add(annotRef);
          continue;
        }

        // ── Parse annotation Rect ──────────────────────────────────────────
        // PDF Rect = [left, bottom, right, top] in PDF coords (Y-up)
        final PdfArr? rectArr = _doc.resolve(annot['Rect']) as PdfArr?;
        if (rectArr == null || rectArr.length < 4) {
          remaining.add(annotRef);
          skipped++;
          Logger.debug('PdfFlattener: skipped $subtype — no Rect');
          continue;
        }

        final double x1 = _num(rectArr[0]);
        final double y1 = _num(rectArr[1]);
        final double x2 = _num(rectArr[2]);
        final double y2 = _num(rectArr[3]);

        // Normalise so left<right, bottom<top in PDF coords
        final double left   = x1 < x2 ? x1 : x2;
        final double bottom = y1 < y2 ? y1 : y2;
        final double right  = x1 > x2 ? x1 : x2;
        final double top    = y1 > y2 ? y1 : y2;
        final double w = right - left;
        final double h = top - bottom;

        if (w <= 0 || h <= 0) {
          remaining.add(annotRef);
          skipped++;
          Logger.debug('PdfFlattener: skipped $subtype — zero-size Rect');
          continue;
        }

        // ── Try AP/N stream first (Stamp and signed widgets) ───────────────
        final PdfDict? ap = _doc.resolve(annot['AP']) as PdfDict?;
        final PdfObj? nRef = ap?['N'];

        if (nRef != null) {
          final bool ok = _flattenApStream(
            page: page,
            apRef: nRef,
            pdfLeft: left,
            pdfBottom: bottom,
            width: w,
            height: h,
            pageHeight: pageHeight,
          );

          if (ok) {
            flattened++;
            Logger.debug(
              'PdfFlattener: ✓ flattened $subtype via AP '
              '[$left,$bottom,$right,$top]',
            );
          } else {
            remaining.add(annotRef);
            skipped++;
            Logger.debug('PdfFlattener: skipped $subtype — AP bake failed');
          }

        } else if (isWidget || isFreeText) {
          // ── No AP — try to draw text value directly ──────────────────────
          final bool ok = _flattenTextValue(
            page: page,
            annot: annot,
            pdfLeft: left,
            pdfBottom: bottom,
            width: w,
            height: h,
          );

          if (ok) {
            flattened++;
            Logger.debug(
              'PdfFlattener: ✓ flattened $subtype via /V text '
              '[$left,$bottom]',
            );
          } else {
            remaining.add(annotRef);
            skipped++;
            Logger.debug(
              'PdfFlattener: skipped $subtype — no AP and no /V text',
            );
          }
        } else {
          remaining.add(annotRef);
          skipped++;
        }
      }

      // Replace Annots keeping only non-flattened ones
      annots.items
        ..clear()
        ..addAll(remaining);
    }

    _setNeedAppearances(false);

    Logger.debug(
      'PdfFlattener: done — $flattened flattened, '
      '$skipped skipped across $pagesProcessed pages',
    );

    return FlattenResult(
      pagesProcessed: pagesProcessed,
      annotationsFlattened: flattened,
      annotationsSkipped: skipped,
    );
  }

  // ── AP-stream path ────────────────────────────────────────────────────────

  bool _flattenApStream({
    required PdfDict page,
    required PdfObj apRef,
    required double pdfLeft,
    required double pdfBottom,
    required double width,
    required double height,
    required double pageHeight,
  }) {
    final PdfObj? apStream = _doc.resolve(apRef);
    if (apStream == null) return false;

    // Syncfusion formula:
    //   matrix.translate(location.dx, -(location.dy + size.height))
    // where location is the top-left in Syncfusion's Y-down screen space.
    //
    // In PDF space (Y-up):
    //   pdfLeft  = left edge (same in both coordinate systems)
    //   pdfBottom = bottom of annotation in PDF coords
    //
    // The AP/N Form XObject has BBox [0 0 w h].
    // To place it so its bottom-left is at (pdfLeft, pdfBottom) in PDF space:
    //   cm = [1 0 0 1 pdfLeft pdfBottom]
    //
    // This is the correct pure-translation matrix — no scaling needed because
    // the BBox dimensions already match the annotation rect dimensions.

    final String xName = _uniqueXObjectName(page);
    _addXObjectToPageResources(page, xName, apRef);

    final String pdfX = pdfLeft.toStringAsFixed(4);
    final String pdfY = pdfBottom.toStringAsFixed(4);

    final String ops =
        'q\n'
        '1 0 0 1 $pdfX $pdfY cm\n'  // translate to annotation position
        '/$xName Do\n'               // paint the AP Form XObject
        'Q\n';

    _appendContentStream(page, ops);
    return true;
  }

  // ── Text-value path ───────────────────────────────────────────────────────

  bool _flattenTextValue({
    required PdfDict page,
    required PdfDict annot,
    required double pdfLeft,
    required double pdfBottom,
    required double width,
    required double height,
  }) {
    final PdfObj? vObj = _doc.resolve(annot['V']);
    final String value = vObj is PdfStr ? vObj.value : '';
    if (value.isEmpty) return false;

    // Parse font name and size from /DA — e.g. "/MinionPro-Regular 10 Tf 0 g"
    final String da =
        (_doc.resolve(annot['DA']) as PdfStr?)?.value ??
        '/Helvetica 10 Tf 0 g';

    final RegExp fontRe = RegExp(r'/(\S+)\s+([\d.]+)\s+Tf');
    final Match? m = fontRe.firstMatch(da);
    final String fontName = m?.group(1) ?? 'Helvetica';
    final double fontSize = double.tryParse(m?.group(2) ?? '9') ?? 9.0;

    // Baseline in PDF coords: ~20% up from bottom of field rect
    final double tx = pdfLeft + 2.0;
    final double ty = pdfBottom + (height * 0.2);

    final String escaped = _escapePdf(value);

    final String ops =
        'q\n'
        'BT\n'
        '/$fontName ${fontSize.toStringAsFixed(2)} Tf\n'
        '0 0 0 rg\n'
        '${tx.toStringAsFixed(4)} ${ty.toStringAsFixed(4)} Td\n'
        '($escaped) Tj\n'
        'ET\n'
        'Q\n';

    _appendContentStream(page, ops);

    // Hide the original widget
    annot['F'] = const PdfNum(2);
    return true;
  }

  // ── Page geometry ─────────────────────────────────────────────────────────

  double _getPageHeight(PdfDict page) {
    // Try MediaBox first, then CropBox
    for (final String key in <String>['MediaBox', 'CropBox']) {
      final PdfArr? box = _doc.resolve(page[key]) as PdfArr?;
      if (box != null && box.length >= 4) {
        // MediaBox = [left, bottom, right, top]
        final double top    = _num(box[3]);
        final double bottom = _num(box[1]);
        final double h = top - bottom;
        if (h > 0) return h;
      }
    }
    return 792.0; // US Letter fallback
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _appendContentStream(PdfDict page, String ops) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(ops));
    final List<int> compressed = ZLibEncoder().convert(bytes);

    final PdfDict streamDict = PdfDict();
    streamDict['Filter'] = const PdfName('FlateDecode');
    streamDict['Length'] = PdfNum(compressed.length);

    final PdfRef streamRef = _doc.addObject(
      PdfStream(streamDict, Uint8List.fromList(compressed)),
    );

    final PdfObj? existing = _doc.resolve(page['Contents']);
    if (existing is PdfArr) {
      existing.items.add(streamRef);
    } else if (existing != null) {
      page['Contents'] = PdfArr(<PdfObj>[existing, streamRef]);
    } else {
      page['Contents'] = streamRef;
    }
  }

  void _addXObjectToPageResources(PdfDict page, String name, PdfObj ref) {
    PdfDict? resources = _doc.resolve(page['Resources']) as PdfDict?;
    if (resources == null) {
      resources = PdfDict();
      page['Resources'] = resources;
    }

    PdfDict? xObjects = _doc.resolve(resources['XObject']) as PdfDict?;
    if (xObjects == null) {
      xObjects = PdfDict();
      resources['XObject'] = xObjects;
    }

    xObjects[name] = ref;
  }

  String _uniqueXObjectName(PdfDict page) {
    final PdfDict? resources = _doc.resolve(page['Resources']) as PdfDict?;
    final PdfDict? xObjects =
        _doc.resolve(resources?['XObject']) as PdfDict?;

    int index = 0;
    while (true) {
      final String name = 'FlatAP$index';
      if (xObjects == null || !xObjects.containsKey(name)) return name;
      index++;
    }
  }

  void _setNeedAppearances(bool value) {
    final PdfDict? catalog = _doc.catalog;
    if (catalog == null) return;
    final PdfObj? acroForm = _doc.resolve(catalog['AcroForm']);
    if (acroForm is PdfDict) {
      acroForm['NeedAppearances'] = PdfBool(value);
    }
  }

  double _num(PdfObj? obj) =>
      obj is PdfNum ? obj.doubleValue : 0.0;

  String _escapePdf(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');
}