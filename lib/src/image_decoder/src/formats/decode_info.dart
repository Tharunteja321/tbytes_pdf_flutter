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

import '../color/color.dart';

/// Provides information about the image being decoded.
abstract class DecodeInfo {
  /// The width of the image canvas.
  int get width;

  /// The height of the image canvas.
  int get height;

  /// The suggested background color of the canvas.
  Color? get backgroundColor;

  /// The number of frames that can be decoded.
  int get numFrames;
}
