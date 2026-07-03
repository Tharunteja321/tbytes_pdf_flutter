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

import '../image/image.dart';
import 'png_decoder.dart';

/// Minimal decode entry point — trimmed down to PNG only for the
/// Signature Image Placer. Signature uploads are expected to always be
/// PNG (to preserve alpha transparency for the trim/auto-crop step).
///
/// If you ever need to accept another format (e.g. JPEG), re-vendor that
/// decoder file plus its dependencies and add a branch here.
Image? decodeImage(Uint8List data, {int? frame}) {
  final decoder = PngDecoder();
  if (decoder.isValidFile(data)) {
    return decoder.decode(data, frame: frame);
  }
  return null;
}
