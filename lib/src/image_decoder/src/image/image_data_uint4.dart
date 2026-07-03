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

import 'dart:math';
import 'dart:typed_data';

import '../color/color.dart';
import '../color/color_uint4.dart';
import '../color/format.dart';
import 'image_data.dart';
import 'palette.dart';
import 'pixel.dart';
import 'pixel_range_iterator.dart';
import 'pixel_uint4.dart';

class ImageDataUint4 extends ImageData {
  late final Uint8List data;
  @override
  final int rowStride;
  @override
  Palette? palette;

  ImageDataUint4(int width, int height, int numChannels)
      : rowStride = numChannels == 2
            ? width
            : numChannels == 4
                ? width * 2
                : numChannels == 3
                    ? (width * 1.5).ceil()
                    : (width / 2).ceil(),
        palette = null,
        super(width, height, numChannels) {
    data = Uint8List(max(rowStride * height, 1));
  }

  ImageDataUint4.palette(int width, int height, this.palette)
      : rowStride = (width / 2).ceil(),
        super(width, height, 1) {
    data = Uint8List(max(rowStride * height, 1));
  }

  ImageDataUint4.from(ImageDataUint4 other, {bool skipPixels = false})
      : data = skipPixels
            ? Uint8List(other.data.length)
            : Uint8List.fromList(other.data),
        rowStride = other.rowStride,
        palette = other.palette?.clone(),
        super(other.width, other.height, other.numChannels);

  @override
  ImageDataUint4 clone({bool noPixels = false}) =>
      ImageDataUint4.from(this, skipPixels: noPixels);

  @override
  Format get format => Format.uint4;

  @override
  FormatType get formatType => FormatType.uint;

  @override
  ByteBuffer get buffer => data.buffer;

  @override
  PixelUint4 get iterator => PixelUint4.imageData(this);

  @override
  Iterator<Pixel> getRange(int x, int y, int width, int height) =>
      PixelRangeIterator(PixelUint4.imageData(this), x, y, width, height);

  @override
  int get lengthInBytes => data.lengthInBytes;

  @override
  int get length => data.lengthInBytes;

  @override
  num get maxChannelValue => palette?.maxChannelValue ?? 15;

  @override
  num get maxIndexValue => 15;

  @override
  bool get isHdrFormat => false;

  @override
  int get bitsPerChannel => 4;

  @override
  Color getColor(num r, num g, num b, [num? a]) => a == null
      ? ColorUint4.rgb(r.toInt(), g.toInt(), b.toInt())
      : ColorUint4.rgba(r.toInt(), g.toInt(), b.toInt(), a.toInt());

  @override
  Pixel getPixel(int x, int y, [Pixel? pixel]) {
    if (pixel == null || pixel is! PixelUint4 || pixel.image != this) {
      pixel = PixelUint4.imageData(this);
    }
    pixel.setPosition(x, y);
    return pixel;
  }

  PixelUint4? _pixel;

  @override
  void setPixelR(int x, int y, num i) {
    if (numChannels < 1) {
      return;
    }
    _pixel ??= PixelUint4.imageData(this);
    _pixel!.setPosition(x, y);
    _pixel!.index = i;
  }

  @override
  void setPixelRgb(int x, int y, num r, num g, num b) {
    if (numChannels < 1) {
      return;
    }
    _pixel ??= PixelUint4.imageData(this);
    _pixel!.setPosition(x, y);
    _pixel!.setRgb(r, g, b);
  }

  @override
  void setPixelRgba(int x, int y, num r, num g, num b, num a) {
    if (numChannels < 1) {
      return;
    }
    _pixel ??= PixelUint4.imageData(this);
    _pixel!.setPosition(x, y);
    _pixel!.setRgba(r, g, b, a);
  }

  @override
  String toString() => 'ImageDataUint4($width, $height, $numChannels)';

  @override
  void clear([Color? c]) {}
}
