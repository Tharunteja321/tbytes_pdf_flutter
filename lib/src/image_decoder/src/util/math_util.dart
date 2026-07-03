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

num fract(num x) => x - x.floorToDouble();

num smoothstep(num edge0, num edge1, num x) {
  final double t0 = (x - edge0) / (edge1 - edge0);
  final num t = t0.clamp(0, 1);
  return t * t * (3 - 2 * t);
}

num mix(num x, num y, num a) => x * (1 - a) + y * a;

num sign(num x) => x < 0
    ? -1
    : x > 0
        ? 1
        : 0;

num step(num edge, num x) => x < edge ? 0 : 1;

num length3(num x, num y, num z) => sqrt(x * x + y * y + z * z);
