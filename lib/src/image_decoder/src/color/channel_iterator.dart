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

import 'color.dart';

/// An iterator over the channels of a [Color].
class ChannelIterator implements Iterator<num> {
  int index = -1;
  Color color;

  ChannelIterator(this.color);

  @override
  bool moveNext() {
    index++;
    return index < color.length;
  }

  @override
  num get current => color[index];
}
