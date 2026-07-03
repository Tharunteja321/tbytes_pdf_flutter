# Why this folder exists

This folder (`lib/src/image_decoder/`) contains a trimmed-down, vendored copy
of parts of the [`image`](https://pub.dev/packages/image) package for Dart.

## The problem

`tbytes_pdf_flutter` needs to decode PNG signature images and auto-crop
transparent padding around them ([`SignatureImagePlacer`](../signature_image_placer.dart)
uses this to fit a signature neatly into a form field). The natural choice
was to depend on the `image` package directly.

However, many Flutter apps already depend on `image` (transitively, through
packages like `image_picker`, `flutter_image_compress`, or various QR/barcode
libraries) — often pinned to a specific major version. Adding a second,
differently-versioned dependency on the same package name is not possible in
Dart/Flutter: only one version of a given package can be resolved per app.
This repeatedly caused version-solving conflicts for consumers of this
package.

## The solution

Rather than depending on `package:image` directly, this package vendors
**only the ~85 files actually needed** for the specific operations
`SignatureImagePlacer` performs:

- Decoding a PNG (`formats/png_decoder.dart` and its dependencies)
- Auto-trimming transparent padding (`transform/trim.dart`)
- Reading pixel data (`image/image.dart`, `image/pixel.dart`, and the color/
  palette/image-data type hierarchy they depend on)

This is **not** the full `image` package. It deliberately excludes:

- Every other format's encoder/decoder (BMP, GIF, ICO, JPEG, PSD, PVR, TGA,
  TIFF, WebP, EXR, PNM) — signatures are expected as PNG only
- All 30+ fluent `command/` API wrappers
- All filters (blur, sepia, emboss, etc.)
- Font/glyph rendering data
- All transforms other than `trim`
- EXIF *writing* support (the `ExifData` type is retained only because
  `Image` declares a field of that type internally — it is never populated
  or read by this package)

Because it lives under `lib/src/` with its own internal namespace
(`image_decoder/src/...`), it **cannot conflict** with a consuming app's own
`image` dependency, however that app has it pinned — the two never share a
package name or import path.

## License and attribution

The code in this folder is copyright (c) 2013-2022 Brendan Duncan, and is
used here under the terms of the `image` package's MIT License. Each
vendored file carries a header noting its origin. The original, unmodified
package and its license can be found at:

- Package: https://pub.dev/packages/image
- Repository: https://github.com/brendan-duncan/image
- License: https://github.com/brendan-duncan/image/blob/main/LICENSE

Modifications (removal of unused code) are copyright (c) 2026 tbytes,
licensed under the same MIT terms — see the [LICENSE](../../../LICENSE)
file at the package root.

## If you need another image format

If a future version of this package needs to accept signatures in another
format (e.g. JPEG), the corresponding decoder file and its dependency chain
would need to be re-vendored from the upstream `image` package following the
same process, and `formats/formats.dart`'s `decodeImage` function updated to
try it. This is intentionally not done speculatively, to keep this vendored
subset as small as possible.
