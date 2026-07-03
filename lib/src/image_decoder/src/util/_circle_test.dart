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

import '../image/pixel.dart';

/// Test if the pixel [p] is within the circle centered at [x],[y] with a
/// squared radius of [rad2]. This will test the corners, edges, and center
/// of the pixel and return the ratio of samples within the circle.
num circleTest(Pixel p, int x, int y, num rad2, {bool antialias = true}) {
  /*if (!antialias) {
    final dx1 = p.x - x;
    final dy1 = p.y - y;
    final d1 = dx1 * dx1 + dy1 * dy1;
    return d1 <= rad2 ? 1 : 0;
  }*/

  int total = 0;
  final int dx1 = p.x - x;
  final int dy1 = p.y - y;
  final int d1 = dx1 * dx1 + dy1 * dy1;
  final int r1 = d1 <= rad2 ? 1 : 0;
  total += r1;

  final int dx2 = (p.x + 1) - x;
  final int dy2 = p.y - y;
  final int d2 = dx2 * dx2 + dy2 * dy2;
  final int r2 = d2 <= rad2 ? 1 : 0;
  total += r2;

  final int dx3 = (p.x + 1) - x;
  final int dy3 = (p.y + 1) - y;
  final int d3 = dx3 * dx3 + dy3 * dy3;
  final int r3 = d3 <= rad2 ? 1 : 0;
  total += r3;

  final int dx4 = p.x - x;
  final int dy4 = (p.y + 1) - y;
  final int d4 = dx4 * dx4 + dy4 * dy4;
  final int r4 = d4 <= rad2 ? 1 : 0;
  total += r4;

  //return total / 4;

  final double dx5 = (p.x + 0.5) - x;
  final int dy5 = p.y - y;
  final double d5 = dx5 * dx5 + dy5 * dy5;
  final int r5 = d5 <= rad2 ? 1 : 0;
  total += r5;

  final double dx6 = (p.x + 0.5) - x;
  final int dy6 = (p.y + 1) - y;
  final double d6 = dx6 * dx6 + dy6 * dy6;
  final int r6 = d6 <= rad2 ? 1 : 0;
  total += r6;

  final int dx7 = p.x - x;
  final double dy7 = (p.y + 0.5) - y;
  final double d7 = dx7 * dx7 + dy7 * dy7;
  final int r7 = d7 <= rad2 ? 1 : 0;
  total += r7;

  final int dx8 = (p.x + 1) - x;
  final double dy8 = (p.y + 0.5) - y;
  final double d8 = dx8 * dx8 + dy8 * dy8;
  final int r8 = d8 <= rad2 ? 1 : 0;
  total += r8;

  final double dx9 = (p.x + 0.5) - x;
  final double dy9 = (p.y + 0.5) - y;
  final double d9 = dx9 * dx9 + dy9 * dy9;
  final int r9 = d9 <= rad2 ? 1 : 0;
  total += r9;

  return antialias
      ? total / 9
      : total > 0
          ? 1
          : 0;
}
