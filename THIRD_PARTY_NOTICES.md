# Third-Party Notices

`tbytes_pdf_flutter` is licensed under the MIT License (see [LICENSE](LICENSE)).
It vendors a subset of one third-party library and depends on a small number
of others. This file lists all of them, along with the packages used by the
**example app** to demonstrate the package (which are not dependencies of
the package itself).

---

## Vendored code

### `image` (subset) — used inside `lib/src/image_decoder/`

- **What it's for:** decoding PNG signature images and auto-trimming
  transparent padding around them, used by `SignatureImagePlacer`.
- **Why vendored instead of a normal dependency:** many Flutter apps already
  depend on `package:image` transitively (via `image_picker`,
  `flutter_image_compress`, barcode/QR libraries, etc.), often pinned to a
  specific major version. Only one version of a given package can be
  resolved per app, so adding a second dependency on `image` under a
  different version repeatedly caused dependency resolution conflicts for
  consumers. Vendoring a trimmed, internally-namespaced copy avoids this
  entirely — see [`lib/src/image_decoder/README.md`](lib/src/image_decoder/README.md)
  for the full explanation and exactly what was kept vs. removed.
- **Source:** https://pub.dev/packages/image
- **Repository:** https://github.com/brendan-duncan/image
- **License:** MIT, Copyright (c) 2013-2022 Brendan Duncan.
  Full text vendored at [`lib/src/image_decoder/LICENSE`](lib/src/image_decoder/LICENSE).

---

## Direct dependencies

### `archive`

- **What it's for:** zlib/DEFLATE inflation of PNG pixel data (used inside
  the vendored `image_decoder` PNG decoder).
- **Source:** https://pub.dev/packages/archive
- **License:** MIT, Copyright (c) 2013-2021 Brendan Duncan.

### `crypto`

- **What it's for:** MD5/RC4 key-derivation support used by `PdfDecryptor`
  when decrypting password-protected PDFs.
- **Source:** https://pub.dev/packages/crypto
- **License:** BSD-style, Copyright 2015, the Dart project authors.

### `encrypt`

- **What it's for:** AES decryption support used by `PdfDecryptor` for PDFs
  encrypted with AES-based security handlers.
- **Source:** https://pub.dev/packages/encrypt
- **License:** BSD-3-Clause, Copyright (c) 2018, Leo Cavalcante.

---

## Example app only (not dependencies of the package itself)

The `example/` app demonstrates `tbytes_pdf_flutter` alongside a PDF
*viewer*, since this package intentionally does not include a viewer (it
focuses on parsing, filling, flattening, decrypting, and signing). The
example's viewer glue (`example/lib/cached_pdf_view.dart`) uses:

### `pdfrx`

- **What it's for:** rendering/viewing PDFs on Android, Web, desktop, and
  other non-iOS platforms in the example app.
- **Source:** https://pub.dev/packages/pdfrx
- **License:** MIT.

### `flutter_pdfview`

- **What it's for:** rendering/viewing PDFs on iOS in the example app
  (wraps native PDFKit).
- **Source:** https://pub.dev/packages/flutter_pdfview
- **License:** MIT.

### `http`, `path_provider`, `shared_preferences`

- **What they're for:** downloading and caching PDFs locally for the
  example's viewer.
- **Source:** https://pub.dev/packages/http,
  https://pub.dev/packages/path_provider,
  https://pub.dev/packages/shared_preferences
- **License:** BSD-3-Clause (all three are published by the Dart/Flutter
  teams).

If you use `tbytes_pdf_flutter` in your own app without the example's
viewer glue, none of the packages in this last section apply to you — they
are not pulled in by depending on `tbytes_pdf_flutter` itself.

---

## Verifying this list

Dependency licenses can change between versions. Before shipping, it's
good practice to double check the current license of any pinned version
using `flutter pub deps` and each package's `/license` page on pub.dev
(e.g. https://pub.dev/packages/archive/license), since this file reflects
the versions pinned in `pubspec.yaml` at the time it was written.
