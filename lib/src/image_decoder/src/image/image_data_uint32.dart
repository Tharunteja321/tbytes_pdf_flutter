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

import 'dart:typed_data';

import '../color/color.dart';
import '../color/color_uint32.dart';
import '../color/format.dart';
import 'image_data.dart';
import 'pixel.dart';
import 'pixel_range_iterator.dart';
import 'pixel_uint32.dart';

class ImageDataUint32 extends ImageData {
  final Uint32List data;

  ImageDataUint32(int width, int height, int numChannels)
      : data = Uint32List(width * height * numChannels),
        super(width, height, numChannels);

  ImageDataUint32.from(ImageDataUint32 other, {bool skipPixels = false})
      : data = skipPixels
            ? Uint32List(other.data.length)
            : Uint32List.fromList(other.data),
        super(other.width, other.height, other.numChannels);

  @override
  ImageDataUint32 clone({bool noPixels = false}) =>
      ImageDataUint32.from(this, skipPixels: noPixels);

  @override
  Format get format => Format.uint32;

  @override
  FormatType get formatType => FormatType.uint;

  @override
  ByteBuffer get buffer => data.buffer;

  @override
  int get rowStride => width * numChannels * 4;

  @override
  int get bitsPerChannel => 32;

  @override
  num get maxChannelValue => 0xffffffff;

  @override
  num get maxIndexValue => 0xffffffff;

  @override
  PixelUint32 get iterator => PixelUint32.imageData(this);

  @override
  Iterator<Pixel> getRange(int x, int y, int width, int height) =>
      PixelRangeIterator(PixelUint32.imageData(this), x, y, width, height);

  @override
  int get lengthInBytes => data.lengthInBytes;

  @override
  int get length => data.lengthInBytes;

  @override
  bool get isHdrFormat => true;

  @override
  Color getColor(num r, num g, num b, [num? a]) => a == null
      ? ColorUint32.rgb(r.toInt(), g.toInt(), b.toInt())
      : ColorUint32.rgba(r.toInt(), g.toInt(), b.toInt(), a.toInt());

  @override
  Pixel getPixel(int x, int y, [Pixel? pixel]) {
    if (pixel == null || pixel is! PixelUint32 || pixel.image != this) {
      pixel = PixelUint32.imageData(this);
    }
    pixel.setPosition(x, y);
    return pixel;
  }

  @override
  void setPixelR(int x, int y, num i) {
    final index = y * width * numChannels + (x * numChannels);
    data[index] = i.toInt();
  }

  @override
  void setPixelRgb(int x, int y, num r, num g, num b) {
    final index = y * width * numChannels + (x * numChannels);
    data[index] = r.toInt();
    if (numChannels > 1) {
      data[index + 1] = g.toInt();
      if (numChannels > 2) {
        data[index + 2] = b.toInt();
      }
    }
  }

  @override
  void setPixelRgba(int x, int y, num r, num g, num b, num a) {
    final index = y * width * numChannels + (x * numChannels);
    data[index] = r.toInt();
    if (numChannels > 1) {
      data[index + 1] = g.toInt();
      if (numChannels > 2) {
        data[index + 2] = b.toInt();
        if (numChannels > 3) {
          data[index + 3] = a.toInt();
        }
      }
    }
  }

  @override
  String toString() => 'ImageDataUint32($width, $height, $numChannels)';

  @override
  void clear([Color? c]) {}
}
