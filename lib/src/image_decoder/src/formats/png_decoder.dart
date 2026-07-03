// This file is derived from the `image` package for Dart
// (https://pub.dev/packages/image), copyright (c) 2013-2022 Brendan Duncan,
// licensed under the MIT License.
//
// It has been trimmed down (unused decoders, encoders, filters, and
// commands removed) for vendoring inside tbytes_pdf_flutter to avoid a
// version conflict with another `image`-package dependency in consuming
// apps. See lib/src/image_decoder/README.md for details.
//
// Original license: https://github.com/brendan-duncan/image/blob/main/LICENSE
// Modifications copyright (c) 2026 tbytes, also under the MIT License.

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../color/color_uint8.dart';
import '../color/format.dart';
import '../draw/blend_mode.dart';
import '../draw/composite_image.dart';
import '../draw/fill_rect.dart';
import '../image/icc_profile.dart';
import '../image/image.dart';
import '../image/palette_uint8.dart';
import '../image/pixel.dart';
import '../util/image_exception.dart';
import '../util/input_buffer.dart';
import 'decode_info.dart';
import 'decoder.dart';
import 'image_format.dart';
import 'png/png_frame.dart';
import 'png/png_info.dart';

/// Decode a PNG encoded image.
class PngDecoder extends Decoder {
  final InternalPngInfo _info = InternalPngInfo();

  @override
  ImageFormat get format => ImageFormat.png;

  /// Is the given file a valid PNG image?
  @override
  bool isValidFile(Uint8List data) {
    final InputBuffer input = InputBuffer(data, bigEndian: true);
    final InputBuffer bytes = input.readBytes(8);
    const List<int> pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (int i = 0; i < 8; ++i) {
      if (bytes[i] != pngHeader[i]) {
        return false;
      }
    }
    return true;
  }

  PngInfo get info => _info;

  /// Start decoding the data as an animation sequence, but don't actually
  /// process the frames until they are requested with decodeFrame.
  @override
  DecodeInfo? startDecode(Uint8List data) {
    _input = InputBuffer(data, bigEndian: true);

    final InputBuffer pngHeader = _input.readBytes(8);
    const List<int> expectedHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (int i = 0; i < 8; ++i) {
      if (pngHeader[i] != expectedHeader[i]) {
        return null;
      }
    }

    while (true) {
      final int inputPos = _input.position;
      int chunkSize = _input.readUint32();
      final String chunkType = _input.readString(4);
      switch (chunkType) {
        case 'tEXt':
          final Uint8List txtData = _input.readBytes(chunkSize).toUint8List();
          final int l = txtData.length;
          for (int i = 0; i < l; ++i) {
            if (txtData[i] == 0) {
              final String key = latin1.decode(txtData.sublist(0, i));
              final String text = latin1.decode(txtData.sublist(i + 1));
              _info.textData[key] = text;
              break;
            }
          }
          _input.skip(4); //crc
          break;
        case 'pHYs':
          final InputBuffer physData = InputBuffer.from(_input.readBytes(chunkSize));
          final int x = physData.readUint32();
          final int y = physData.readUint32();
          final int unit = physData.readByte();
          _info.pixelDimensions = PngPhysicalPixelDimensions(
              xPxPerUnit: x, yPxPerUnit: y, unitSpecifier: unit);
          _input.skip(4); // CRC
          break;
        case 'IHDR':
          final InputBuffer hdr = InputBuffer.from(_input.readBytes(chunkSize));
          final Uint8List hdrBytes = hdr.toUint8List();
          _info.width = hdr.readUint32();
          _info.height = hdr.readUint32();
          _info.bits = hdr.readByte();
          _info.colorType = hdr.readByte();
          _info.compressionMethod = hdr.readByte();
          _info.filterMethod = hdr.readByte();
          _info.interlaceMethod = hdr.readByte();

          // Validate some of the info in the header to make sure we support
          // the proposed image data.
          if (!PngColorType.isValid(_info.colorType)) {
            return null;
          }

          if (_info.filterMethod != 0) {
            return null;
          }

          switch (_info.colorType) {
            case PngColorType.grayscale:
              if (!<int>[1, 2, 4, 8, 16].contains(_info.bits)) {
                return null;
              }
              break;
            case PngColorType.rgb:
              if (!<int>[8, 16].contains(_info.bits)) {
                return null;
              }
              break;
            case PngColorType.indexed:
              if (!<int>[1, 2, 4, 8].contains(_info.bits)) {
                return null;
              }
              break;
            case PngColorType.grayscaleAlpha:
              if (!<int>[8, 16].contains(_info.bits)) {
                return null;
              }
              break;
            case PngColorType.rgba:
              if (!<int>[8, 16].contains(_info.bits)) {
                return null;
              }
              break;
          }

          final int crc = _input.readUint32();
          final int computedCrc = _crc(chunkType, hdrBytes);
          if (crc != computedCrc) {
            throw ImageException('Invalid $chunkType checksum');
          }
          break;
        case 'PLTE':
          _info.palette = _input.readBytes(chunkSize).toUint8List();
          final int crc = _input.readUint32();
          final int computedCrc = _crc(chunkType, _info.palette as List<int>);
          if (crc != computedCrc) {
            throw ImageException('Invalid $chunkType checksum');
          }
          break;
        case 'tRNS':
          _info.transparency = _input.readBytes(chunkSize).toUint8List();
          final int crc = _input.readUint32();
          final int computedCrc = _crc(chunkType, _info.transparency!);
          if (crc != computedCrc) {
            throw ImageException('Invalid $chunkType checksum');
          }
          break;
        case 'IEND':
          // End of the image.
          _input.skip(4); // CRC
          break;
        /*case 'eXif': // TODO: parse exif
          {
            final exifData = _input.readBytes(chunkSize);
            final exif = ExifData.fromInputBuffer(exifData);
            _input.skip(4); // CRC
            break;
          }*/
        case 'gAMA':
          if (chunkSize != 4) {
            throw ImageException('Invalid gAMA chunk');
          }
          final int gammaInt = _input.readUint32();
          _input.skip(4); // CRC
          // A gamma of 1.0 doesn't have any affect, so pretend we didn't get
          // a gamma in that case.
          if (gammaInt != 100000) {
            _info.gamma = gammaInt / 100000.0;
          }
          break;
        case 'IDAT':
          _info.idat.add(inputPos);
          _input.skip(chunkSize);
          _input.skip(4); // CRC
          break;
        case 'acTL': // Animation control chunk
          _info.numFrames = _input.readUint32();
          _info.repeat = _input.readUint32();
          _input.skip(4); // CRC
          break;
        case 'fcTL': // Frame control chunk
          final int sequenceNumber = _input.readUint32();
          final int width = _input.readUint32();
          final int height = _input.readUint32();
          final int xOffset = _input.readUint32();
          final int yOffset = _input.readUint32();
          final int delayNum = _input.readUint16();
          final int delayDen = _input.readUint16();
          final int dispose = _input.readByte();
          final int blend = _input.readByte();
          final InternalPngFrame frame = InternalPngFrame(
              sequenceNumber: sequenceNumber,
              width: width,
              height: height,
              xOffset: xOffset,
              yOffset: yOffset,
              delayNum: delayNum,
              delayDen: delayDen,
              dispose: PngDisposeMode.values[dispose],
              blend: PngBlendMode.values[blend]);
          _info.frames.add(frame);
          _input.skip(4); // CRC
          break;
        case 'fdAT':
          /*int sequenceNumber =*/ _input.readUint32();
          final InternalPngFrame frame = _info.frames.last as InternalPngFrame;
          frame.fdat.add(inputPos);
          _input.skip(chunkSize - 4);
          _input.skip(4); // CRC
          break;
        case 'bKGD':
          if (_info.colorType == PngColorType.indexed) {
            final int paletteIndex = _input.readByte();
            chunkSize--;
            final int p3 = paletteIndex * 3;
            final int r = _info.palette![p3]!;
            final int g = _info.palette![p3 + 1]!;
            final int b = _info.palette![p3 + 2]!;
            if (_info.transparency != null) {
              final bool isTransparent = _info.transparency!.contains(paletteIndex);
              _info.backgroundColor =
                  ColorRgba8(r, g, b, isTransparent ? 0 : 255);
            } else {
              _info.backgroundColor = ColorRgb8(r, g, b);
            }
          } else if (_info.colorType == PngColorType.grayscale ||
              _info.colorType == PngColorType.grayscaleAlpha) {
            /*int gray =*/ _input.readUint16();
            chunkSize -= 2;
          } else if (_info.colorType == PngColorType.rgb ||
              _info.colorType == PngColorType.rgba) {
            /*int r =*/ _input
              ..readUint16()
              /*int g =*/
              ..readUint16()
              /*int b =*/
              ..readUint16();
            chunkSize -= 24;
          }
          if (chunkSize > 0) {
            _input.skip(chunkSize);
          }
          _input.skip(4); // CRC
          break;
        case 'iCCP':
          _info.iccpName = _input.readString();
          _info.iccpCompression = _input.readByte(); // 0: deflate
          chunkSize -= _info.iccpName.length + 2;
          final InputBuffer profile = _input.readBytes(chunkSize);
          _info.iccpData = profile.toUint8List();
          _input.skip(4); // CRC
          break;
        default:
          //print('Skipping $chunkType');
          _input.skip(chunkSize);
          _input.skip(4); // CRC
          break;
      }

      if (chunkType == 'IEND') {
        break;
      }

      if (_input.isEOS) {
        return null;
      }
    }

    return _info;
  }

  /// The number of frames that can be decoded.
  @override
  int numFrames() => _info.numFrames;

  /// Decode the frame (assuming [startDecode] has already been called).
  @override
  Image? decodeFrame(int frame) {
    Uint8List imageData;

    int? width = _info.width;
    int? height = _info.height;

    if (!_info.isAnimated || frame == 0) {
      final List<Uint8List> dataBlocks = <Uint8List>[];
      int totalSize = 0;
      final int len = _info.idat.length;
      for (int i = 0; i < len; ++i) {
        _input.offset = _info.idat[i];
        final int chunkSize = _input.readUint32();
        final String chunkType = _input.readString(4);
        final Uint8List data = _input.readBytes(chunkSize).toUint8List();
        totalSize += data.length;
        dataBlocks.add(data);
        final int crc = _input.readUint32();
        final int computedCrc = _crc(chunkType, data);
        if (crc != computedCrc) {
          throw ImageException('Invalid $chunkType checksum');
        }
      }
      imageData = Uint8List(totalSize);
      int offset = 0;
      for (Uint8List data in dataBlocks) {
        imageData.setAll(offset, data);
        offset += data.length;
      }
    } else {
      if (frame < 0 || frame >= _info.frames.length) {
        throw ImageException('Invalid Frame Number: $frame');
      }

      final InternalPngFrame f = _info.frames[frame] as InternalPngFrame;
      width = f.width;
      height = f.height;
      int totalSize = 0;
      final List<Uint8List> dataBlocks = <Uint8List>[];
      for (int i = 0; i < f.fdat.length; ++i) {
        _input.offset = f.fdat[i];
        final int chunkSize = _input.readUint32();
        _input
          ..readString(4) // fDat chunk header
          ..skip(4); // sequence number
        final Uint8List data = _input.readBytes(chunkSize - 4).toUint8List();
        totalSize += data.length;
        dataBlocks.add(data);
      }
      imageData = Uint8List(totalSize);
      int offset = 0;
      for (Uint8List data in dataBlocks) {
        imageData.setAll(offset, data);
        offset += data.length;
      }
    }

    int numChannels = _info.colorType == PngColorType.indexed
        ? 1
        : _info.colorType == PngColorType.grayscale
            ? 1
            : _info.colorType == PngColorType.grayscaleAlpha
                ? 2
                : _info.colorType == PngColorType.rgba
                    ? 4
                    : 3;

    List<int> uncompressed;
    try {
      uncompressed = const ZLibDecoder().decodeBytes(imageData);
    } catch (error) {
      //print(error);
      return null;
    }

    // input is the decompressed data.
    final InputBuffer input = InputBuffer(uncompressed, bigEndian: true);
    _resetBits();

    PaletteUint8? palette;

    // Non-indexed PNGs may have a palette, but it only provides a suggested
    // set of colors to which an RGB color can be quantized if not displayed
    // directly. In this case, just ignore the palette.
    if (_info.colorType == PngColorType.indexed) {
      if (_info.palette != null) {
        final List<int?> p = _info.palette!;
        final int numColors = p.length ~/ 3;
        final List<int>? t = _info.transparency;
        final int tl = t != null ? t.length : 0;
        final int nc = t != null ? 4 : 3;
        palette = PaletteUint8(numColors, nc);
        for (int i = 0, pi = 0; i < numColors; ++i, pi += 3) {
          int a = 255;
          if (nc == 4 && i < tl) {
            a = t![i];
          }
          palette.setRgba(i, p[pi]!, p[pi + 1]!, p[pi + 2]!, a);
        }
      }
    }

    // grayscale images with no palette but with transparency, get
    // converted to a indexed palette image.
    if (_info.colorType == PngColorType.grayscale &&
        _info.transparency != null &&
        palette == null &&
        _info.bits <= 8) {
      final List<int> t = _info.transparency!;
      final int nt = t.length;
      final int numColors = 1 << _info.bits;
      palette = PaletteUint8(numColors, 4);
      // palette color are 8-bit, so convert the grayscale bit value to the
      // 8-bit palette value.
      final int to8bit = _info.bits == 1
          ? 255
          : _info.bits == 2
              ? 85
              : _info.bits == 4
                  ? 17
                  : 1;
      for (int i = 0; i < numColors; ++i) {
        final int g = i * to8bit;
        palette.setRgba(i, g, g, g, 255);
      }
      for (int i = 0; i < nt; i += 2) {
        final int ti = ((t[i] & 0xff) << 8) | (t[i + 1] & 0xff);
        if (ti < numColors) {
          palette.set(ti, 3, 0);
        }
      }
    }

    final Format format = _info.bits == 1
        ? Format.uint1
        : _info.bits == 2
            ? Format.uint2
            : _info.bits == 4
                ? Format.uint4
                : _info.bits == 16
                    ? Format.uint16
                    : Format.uint8;

    if (_info.colorType == PngColorType.grayscale &&
        _info.transparency != null &&
        _info.bits > 8) {
      numChannels = 4;
    }

    if (_info.colorType == PngColorType.rgb && _info.transparency != null) {
      numChannels = 4;
    }

    final Image image = Image(
        width: width,
        height: height,
        numChannels: numChannels,
        palette: palette,
        format: format);

    final int origW = _info.width;
    final int origH = _info.height;
    _info
      ..width = width
      ..height = height;

    final int w = width;
    final int h = height;
    _progressY = 0;
    if (_info.interlaceMethod != 0) {
      _processPass(input, image, 0, 0, 8, 8, (w + 7) >> 3, (h + 7) >> 3);
      _processPass(input, image, 4, 0, 8, 8, (w + 3) >> 3, (h + 7) >> 3);
      _processPass(input, image, 0, 4, 4, 8, (w + 3) >> 2, (h + 3) >> 3);
      _processPass(input, image, 2, 0, 4, 4, (w + 1) >> 2, (h + 3) >> 2);
      _processPass(input, image, 0, 2, 2, 4, (w + 1) >> 1, (h + 1) >> 2);
      _processPass(input, image, 1, 0, 2, 2, w >> 1, (h + 1) >> 1);
      _processPass(input, image, 0, 1, 1, 2, w, h >> 1);
    } else {
      _process(input, image);
    }

    _info
      ..width = origW
      ..height = origH;

    if (_info.iccpData != null) {
      image.iccProfile = IccProfile(
          _info.iccpName, IccProfileCompression.deflate, _info.iccpData!);
    }

    if (_info.textData.isNotEmpty) {
      image.addTextData(_info.textData);
    }

    return image;
  }

  @override
  Image? decode(Uint8List bytes, {int? frame}) {
    if (startDecode(bytes) == null) {
      return null;
    }

    if (!_info.isAnimated || frame != null) {
      return decodeFrame(frame ?? 0)!;
    }

    Image? firstImage;
    Image? lastImage;
    for (int i = 0; i < _info.numFrames; ++i) {
      final PngFrame frame = _info.frames[i];
      final Image? image = decodeFrame(i);
      if (image == null) {
        continue;
      }

      if (firstImage == null || lastImage == null) {
        firstImage = image.convert(numChannels: image.numChannels);
        lastImage = firstImage
          // Convert to MS
          ..frameDuration = (frame.delay * 1000).toInt();
        continue;
      }

      final PngFrame prevFrame = _info.frames[i - 1];

      if (image.width == lastImage.width &&
          image.height == lastImage.height &&
          frame.xOffset == 0 &&
          frame.yOffset == 0 &&
          frame.blend == PngBlendMode.source) {
        lastImage = image
          // Convert to MS
          ..frameDuration = (frame.delay * 1000).toInt();
        firstImage.addFrame(lastImage);
        continue;
      }

      lastImage = Image.from(firstImage.getFrame(i - 1));

      final PngDisposeMode dispose = prevFrame.dispose;
      if (dispose == PngDisposeMode.background) {
        fillRect(lastImage,
            x1: prevFrame.xOffset,
            y1: prevFrame.yOffset,
            x2: prevFrame.xOffset + prevFrame.width - 1,
            y2: prevFrame.yOffset + prevFrame.height - 1,
            color: _info.backgroundColor ?? ColorRgba8(0, 0, 0, 0),
            alphaBlend: false);
      } else if (dispose == PngDisposeMode.previous && i > 1) {
        final Image prevImage = firstImage.getFrame(i - 2);
        lastImage = compositeImage(lastImage, prevImage,
            dstX: prevFrame.xOffset,
            dstY: prevFrame.yOffset,
            dstW: prevFrame.width,
            dstH: prevFrame.height,
            srcX: prevFrame.xOffset,
            srcY: prevFrame.yOffset,
            srcW: prevFrame.width,
            srcH: prevFrame.height);
      }

      // Convert to MS
      lastImage.frameDuration = (frame.delay * 1000).toInt();

      lastImage = compositeImage(lastImage, image,
          dstX: frame.xOffset,
          dstY: frame.yOffset,
          blend: frame.blend == PngBlendMode.over
              ? BlendMode.alpha
              : BlendMode.direct);

      firstImage.addFrame(lastImage);
    }

    return firstImage;
  }

  // Process a pass of an interlaced image.
  void _processPass(InputBuffer input, Image image, int xOffset, int yOffset,
      int xStep, int yStep, int passWidth, int passHeight) {
    final int channels = (_info.colorType == PngColorType.grayscaleAlpha)
        ? 2
        : (_info.colorType == PngColorType.rgb)
            ? 3
            : (_info.colorType == PngColorType.rgba)
                ? 4
                : 1;

    final int pixelDepth = channels * _info.bits;
    final int bpp = (pixelDepth + 7) >> 3;
    final int rowBytes = (pixelDepth * passWidth + 7) >> 3;

    final List<Uint8List?> inData = <Uint8List?>[null, null];

    final List<int> pixel = <int>[0, 0, 0, 0];

    for (int srcY = 0, dstY = yOffset, ri = 0;
        srcY < passHeight;
        ++srcY, dstY += yStep, ri = 1 - ri, _progressY++) {
      final PngFilterType filterType = PngFilterType.values[input.readByte()];
      inData[ri] = input.readBytes(rowBytes).toUint8List();

      final Uint8List? row = inData[ri];
      final Uint8List? prevRow = inData[1 - ri];

      // Before the image is compressed, it was filtered to improve compression.
      // Reverse the filter now.
      _unfilter(filterType, bpp, row!, prevRow);

      // Scanlines are always on byte boundaries, so for bit depths < 8,
      // reset the bit stream counter.
      _resetBits();

      final InputBuffer rowInput = InputBuffer(row, bigEndian: true);

      final int blockHeight = xStep;
      final int blockWidth = xStep - xOffset;

      for (int srcX = 0, dstX = xOffset;
          srcX < passWidth;
          ++srcX, dstX += xStep) {
        _readPixel(rowInput, pixel);
        _setPixel(image.getPixel(dstX, dstY), pixel);

        if (blockWidth > 1 || blockHeight > 1) {
          for (int i = 0; i < blockHeight; ++i) {
            for (int j = 0; j < blockWidth; ++j) {
              _setPixel(image.getPixelSafe(dstX + j, dstY + i), pixel);
            }
          }
        }
      }
    }
  }

  void _process(InputBuffer input, Image image) {
    final int channels = (_info.colorType == PngColorType.grayscaleAlpha)
        ? 2
        : (_info.colorType == PngColorType.rgb)
            ? 3
            : (_info.colorType == PngColorType.rgba)
                ? 4
                : 1;

    final int pixelDepth = channels * _info.bits;

    final int w = _info.width;
    final int h = _info.height;

    final int rowBytes = (w * pixelDepth + 7) >> 3;
    final int bpp = (pixelDepth + 7) >> 3;

    final List<int> line = List<int>.filled(rowBytes, 0);
    final List<dynamic> inData = <List<int>>[line, line];

    final List<int> pixel = <int>[0, 0, 0, 0];

    final Iterator<Pixel> pIter = image.iterator..moveNext();
    for (int y = 0, ri = 0; y < h; ++y, ri = 1 - ri) {
      final PngFilterType filterType = PngFilterType.values[input.readByte()];
      inData[ri] = input.readBytes(rowBytes).toUint8List();

      final List<int> row = inData[ri];
      final List<int> prevRow = inData[1 - ri];

      // Before the image is compressed, it was filtered to improve compression.
      // Reverse the filter now.
      _unfilter(filterType, bpp, row, prevRow);

      // Scanlines are always on byte boundaries, so for bit depths < 8,
      // reset the bit stream counter.
      _resetBits();

      final InputBuffer rowInput = InputBuffer(inData[ri], bigEndian: true);

      for (int x = 0; x < w; ++x) {
        _readPixel(rowInput, pixel);
        _setPixel(pIter.current, pixel);
        pIter.moveNext();
      }
    }
  }

  void _unfilter(
      PngFilterType filterType, int bpp, List<int> row, List<int>? prevRow) {
    final int rowBytes = row.length;

    switch (filterType) {
      case PngFilterType.none:
        break;
      case PngFilterType.sub:
        for (int x = bpp; x < rowBytes; ++x) {
          row[x] = (row[x] + row[x - bpp]) & 0xff;
        }
        break;
      case PngFilterType.up:
        for (int x = 0; x < rowBytes; ++x) {
          final int b = prevRow != null ? prevRow[x] : 0;
          row[x] = (row[x] + b) & 0xff;
        }
        break;
      case PngFilterType.average:
        for (int x = 0; x < rowBytes; ++x) {
          final int a = x < bpp ? 0 : row[x - bpp];
          final int b = prevRow != null ? prevRow[x] : 0;
          row[x] = (row[x] + ((a + b) >> 1)) & 0xff;
        }
        break;
      case PngFilterType.paeth:
        for (int x = 0; x < rowBytes; ++x) {
          final int a = x < bpp ? 0 : row[x - bpp];
          final int b = prevRow != null ? prevRow[x] : 0;
          final int c = x < bpp || prevRow == null ? 0 : prevRow[x - bpp];

          final int p = a + b - c;

          final int pa = (p - a).abs();
          final int pb = (p - b).abs();
          final int pc = (p - c).abs();

          int paeth = 0;
          if (pa <= pb && pa <= pc) {
            paeth = a;
          } else if (pb <= pc) {
            paeth = b;
          } else {
            paeth = c;
          }

          row[x] = (row[x] + paeth) & 0xff;
        }
        break;
      }
  }

  // Return the CRC of the bytes
  int _crc(String type, List<int> bytes) {
    final int crc = getCrc32(type.codeUnits);
    return getCrc32(bytes, crc);
  }

  int _bitBuffer = 0;
  int _bitBufferLen = 0;

  void _resetBits() {
    _bitBuffer = 0;
    _bitBufferLen = 0;
  }

  // Read a number of bits from the input stream.
  int _readBits(InputBuffer input, int numBits) {
    if (numBits == 0) {
      return 0;
    }

    if (numBits == 8) {
      return input.readByte();
    }

    if (numBits == 16) {
      return input.readUint16();
    }

    // not enough buffer
    while (_bitBufferLen < numBits) {
      if (input.isEOS) {
        throw ImageException('Invalid PNG data.');
      }

      // input byte
      final int octet = input.readByte();

      // concat octet
      _bitBuffer = octet << _bitBufferLen;
      _bitBufferLen += 8;
    }

    // output byte
    final int mask = (numBits == 1)
        ? 1
        : (numBits == 2)
            ? 3
            : (numBits == 4)
                ? 0xf
                : (numBits == 8)
                    ? 0xff
                    : (numBits == 16)
                        ? 0xffff
                        : 0;

    final int octet = (_bitBuffer >> (_bitBufferLen - numBits)) & mask;

    _bitBufferLen -= numBits;

    return octet;
  }

  // Read the next pixel from the input stream.
  void _readPixel(InputBuffer input, List<int> pixel) {
    switch (_info.colorType) {
      case PngColorType.grayscale:
        pixel[0] = _readBits(input, _info.bits);
        return;
      case PngColorType.rgb:
        pixel[0] = _readBits(input, _info.bits);
        pixel[1] = _readBits(input, _info.bits);
        pixel[2] = _readBits(input, _info.bits);
        return;
      case PngColorType.indexed:
        pixel[0] = _readBits(input, _info.bits);
        return;
      case PngColorType.grayscaleAlpha:
        pixel[0] = _readBits(input, _info.bits);
        pixel[1] = _readBits(input, _info.bits);
        return;
      case PngColorType.rgba:
        pixel[0] = _readBits(input, _info.bits);
        pixel[1] = _readBits(input, _info.bits);
        pixel[2] = _readBits(input, _info.bits);
        pixel[3] = _readBits(input, _info.bits);
        return;
    }

    throw ImageException('Invalid color type: ${_info.colorType}.');
  }

  // Get the color with the list of components.
  void _setPixel(Pixel p, List<int> raw) {
    switch (_info.colorType) {
      case PngColorType.grayscale:
        if (_info.transparency != null && _info.bits > 8) {
          final List<int> t = _info.transparency!;
          final int a = ((t[0] & 0xff) << 24) | (t[1] & 0xff);
          final int g = raw[0];
          p.setRgba(g, g, g, g != a ? p.maxChannelValue : 0);
          return;
        }
        p.setRgb(raw[0], 0, 0);
        return;
      case PngColorType.rgb:
        final int r = raw[0];
        final int g = raw[1];
        final int b = raw[2];

        if (_info.transparency != null) {
          final List<int> t = _info.transparency!;
          final int tr = ((t[0] & 0xff) << 8) | (t[1] & 0xff);
          final int tg = ((t[2] & 0xff) << 8) | (t[3] & 0xff);
          final int tb = ((t[4] & 0xff) << 8) | (t[5] & 0xff);
          if (raw[0] != tr || raw[1] != tg || raw[2] != tb) {
            p.setRgba(r, g, b, p.maxChannelValue);
            return;
          }
        }

        p.setRgb(r, g, b);
        return;
      case PngColorType.indexed:
        p.index = raw[0];
        return;
      case PngColorType.grayscaleAlpha:
        p.setRgb(raw[0], raw[1], 0);
        return;
      case PngColorType.rgba:
        p.setRgba(raw[0], raw[1], raw[2], raw[3]);
        return;
    }

    throw ImageException('Invalid color type: ${_info.colorType}.');
  }

  late InputBuffer _input;
  int _progressY = 0;
}
