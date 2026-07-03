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

/// Interpolation method to use when resizing images.
enum Interpolation {
  /// Select the closest pixel. Fastest, lowest quality.
  nearest,

  /// Linearly blend between the neighboring pixels.
  linear,

  /// Cubic blend between the neighboring pixels. Slowest, highest Quality.
  cubic,

  /// Average the colors of the neighboring pixels.
  average
}
