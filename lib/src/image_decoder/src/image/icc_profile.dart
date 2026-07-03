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
import 'package:archive/archive.dart';

enum IccProfileCompression { none, deflate }

/// ICC Profile data stored with an image.
class IccProfile {
  String name = '';
  IccProfileCompression compression;
  Uint8List data;

  IccProfile(this.name, this.compression, this.data);

  IccProfile.from(IccProfile other)
      : name = other.name,
        compression = other.compression,
        data = other.data.sublist(0);

  IccProfile clone() => IccProfile.from(this);

  /// Returns the compressed data of the ICC Profile, compressing the stored
  /// data as necessary.
  Uint8List compressed() {
    if (compression == IccProfileCompression.deflate) {
      return data;
    }
    data = const ZLibEncoder().encode(data) as Uint8List;
    compression = IccProfileCompression.deflate;
    return data;
  }

  /// Returns the uncompressed data of the ICC Profile, decompressing the stored
  /// data as necessary.
  Uint8List decompressed() {
    if (compression == IccProfileCompression.none) {
      return data;
    }
    data = const ZLibDecoder().decodeBytes(data) as Uint8List;
    compression = IccProfileCompression.none;
    return data;
  }
}
