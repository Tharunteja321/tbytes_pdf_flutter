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

/// Ordering of the channels in a pixel, used with Image.fromBytes and
/// Image.getBytes to support alternative channel ordering.
enum ChannelOrder {
  rgba,
  bgra,
  abgr,
  argb,
  rgb,
  bgr,
  grayAlpha,
  red,
}

/// The number of channels for each ChannelOrder.
const channelOrderLength = <ChannelOrder, int>{
  ChannelOrder.rgba: 4,
  ChannelOrder.bgra: 4,
  ChannelOrder.abgr: 4,
  ChannelOrder.argb: 4,
  ChannelOrder.rgb: 3,
  ChannelOrder.bgr: 3,
  ChannelOrder.grayAlpha: 2,
  ChannelOrder.red: 1
};
