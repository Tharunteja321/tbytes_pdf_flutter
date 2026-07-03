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

/// Represents a floating-point number in rational form of [numerator]
/// and [denominator].
class Rational {
  int numerator;
  int denominator;

  Rational(this.numerator, this.denominator);

  void simplify() {
    final int d = numerator.gcd(denominator);
    if (d != 0) {
      numerator ~/= d;
      denominator ~/= d;
    }
  }

  int toInt() => denominator == 0 ? 0 : numerator ~/ denominator;

  double toDouble() => denominator == 0 ? 0.0 : numerator / denominator;

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}
