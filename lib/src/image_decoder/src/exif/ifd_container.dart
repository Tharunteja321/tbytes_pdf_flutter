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

import 'ifd_directory.dart';

/// An EXIF container of one or more named EXIF IFD directories.
///
/// The typical directory for image EXIF data is ifd0. Sometimes an image
/// may have additional image data, such as for a thumbnail, which would be
/// contained in a directory ifd1.
///
/// Directories may also have sub-containers, such as for GPS data.
class IfdContainer {
  Map<String, IfdDirectory> directories;

  IfdContainer() : directories = {};

  IfdContainer.from(IfdContainer? other) : directories = {} {
    other?.directories
        .forEach((key, value) => directories[key] = value.clone());
  }

  Iterable<String> get keys => directories.keys;

  Iterable<IfdDirectory> get values => directories.values;

  bool get isEmpty {
    if (directories.isEmpty) {
      return true;
    }
    for (var ifd in directories.values) {
      if (!ifd.isEmpty) {
        return false;
      }
    }
    return true;
  }

  bool containsKey(String key) => directories.containsKey(key);

  void clear() {
    directories.clear();
  }

  IfdDirectory operator [](String ifdName) {
    if (!directories.containsKey(ifdName)) {
      directories[ifdName] = IfdDirectory();
    }
    return directories[ifdName]!;
  }

  void operator []=(String ifdName, IfdDirectory value) {
    directories[ifdName] = value;
  }
}
