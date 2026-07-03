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

import 'pixel.dart';

class PixelRangeIterator implements Iterator<Pixel> {
  Pixel pixel;
  int x1;
  int y1;
  int x2;
  int y2;

  PixelRangeIterator(this.pixel, int x, int y, int width, int height)
      : x1 = x,
        y1 = y,
        x2 = x + width - 1,
        y2 = y + height - 1 {
    pixel.setPosition(x - 1, y);
  }

  @override
  bool moveNext() {
    if ((pixel.x + 1) > x2) {
      pixel.setPosition(x1, pixel.y + 1);
      return pixel.y <= y2;
    }
    return pixel.moveNext();
  }

  @override
  Pixel get current => pixel;
}
