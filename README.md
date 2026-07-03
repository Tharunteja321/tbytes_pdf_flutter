# tbytes_pdf_flutter

Fill, flatten, decrypt, and sign PDF forms in Flutter — parse AcroForm
fields, fill them, flatten filled forms into static content, decrypt
password-protected PDFs, and place signature images onto PDF pages. No
native PDF SDK, no platform channels, pure Dart.

This package is deliberately **not** a PDF viewer. Pair it with whichever
viewer you already use (`pdfrx`, `flutter_pdfview`, `syncfusion_flutter_pdfviewer`,
etc.) — see [`example/`](example) for a working combination with `pdfrx` +
`flutter_pdfview`.

There was no solid native option for this on Flutter — Android had no
good package for AcroForm filling, and iOS's PDFKit annotations would
have meant heavy per-platform method-channel work with no shared data
model. So this package's PDF engine was built from Adobe's openly
published spec instead of wrapping an existing library — see
[How this was built](#how-this-was-built) for the full story, and
[Contributing](#contributing) if you'd like to help extend it.

## Features

| Feature | Class | What it does |
|---|---|---|
| 📄 Parse | `PdfDoc` | Load a PDF, walk its object graph, resolve references |
| 📝 Read form fields | `AcroFormReader` | Discover AcroForm fields, read values/types/positions |
| ✏️ Fill form fields | `AcroFormReader.setFieldValue` | Set text, checkbox, radio, and choice field values |
| 🧾 Flatten | `PdfFlattener` | Bake filled fields / annotations into static page content |
| 🔒 Decrypt | `PdfDecryptor` | Unlock password-protected PDFs (RC4 and AES) |
| ✍️ Place a signature | `SignatureImagePlacer` | Auto-crop a signature PNG and stamp it onto a field |
| 💾 Write | `PdfWriter` | Serialize a modified `PdfDoc` back to bytes |
| ℹ️ Document metadata | `PdfInfoStore` | Read/write the PDF Info dictionary |

## Getting started

```yaml
dependencies:
  tbytes_pdf_flutter: ^0.1.0
```

```dart
import 'package:tbytes_pdf_flutter/tbytes_pdf_flutter.dart';
```

## Usage

The examples below are trimmed for readability. See
[`example/lib/pdf_feature_demo_screen.dart`](example/lib/pdf_feature_demo_screen.dart)
for a complete, runnable demo of every feature with a full Flutter UI
around it.

### 1. Load a PDF and read its AcroForm fields

```dart
final bytes = await File(path).readAsBytes();
final doc = PdfDoc.load(bytes);
final reader = AcroFormReader(doc);

if (reader.hasForm) {
  final fields = reader.readFields();
  for (final field in fields) {
    print('${field.name}: ${field.type} = ${field.value}');
  }
}
```

### 2. Fill form fields

```dart
final reader = AcroFormReader(doc);

reader.setFieldValue('full_name', 'Jane Doe');           // text field
reader.setFieldValue('subscribe', true);                  // checkbox
reader.setFieldValue('plan', 'Pro');                       // radio button

final bytes = PdfWriter().write(doc);
await File(outputPath).writeAsBytes(bytes);
```

### 3. Place a signature image on a field

```dart
// signaturePng: Uint8List of a PNG, e.g. rendered from a drawing canvas.
// SignatureImagePlacer auto-trims transparent padding and preserves
// aspect ratio when fitting the image into maxWidth x maxHeight.
final field = reader.findField('signature_1')!;

SignatureImagePlacer(doc).placeSignatureOnField(
  field: field,
  imageBytes: signaturePng,
  maxWidth: 200,
  maxHeight: 60,
  offsetX: 10,
  offsetY: 5,
  transparentBackground: true,
);

final signedBytes = PdfWriter().write(doc);
```

### 4. Flatten filled fields into static content

Once a form is filled (and optionally signed), flattening bakes the
appearance streams directly into page content so the result is no longer
an editable form — useful before archiving or sending a final copy.

```dart
final flattener = PdfFlattener(doc);
final result = flattener.flatten(
  quality: FlattenQuality.high,     // standard (72dpi) | high (150dpi) | ultra (300dpi)
  target: FlattenTarget.all,        // stampsOnly | formsOnly | all
);

print(result); // FlattenResult(pages: 3, flattened: 5, skipped: 0)

final flatBytes = PdfWriter().write(doc);
```

### 5. Decrypt a password-protected PDF

```dart
final decryptor = PdfDecryptor(doc);

if (decryptor.isEncrypted) {
  final ok = decryptor.tryDecrypt('the-password'); // or '' for owner-only encryption
  if (!ok) {
    throw Exception('Wrong password or unsupported encryption scheme');
  }
}

final decryptedBytes = PdfWriter().write(doc);
```

### 6. Read/write document metadata

```dart
final info = PdfInfoStore(doc);
info.setString('Title', 'Signed Agreement');
info.setString('Author', 'Jane Doe');

final title = info.getString('Title');
```

## Running the example

```bash
cd example
flutter pub get
flutter run
```

The example lets you paste a PDF URL or local path and exercises every
feature above through a tabbed UI (Fields → Fill → Sign → Flatten →
Decrypt → Result), using `pdfrx` and `flutter_pdfview` purely to *view*
the output — those two packages are not dependencies of
`tbytes_pdf_flutter` itself, only of the example app.

## Why is there a vendored `image` package subset inside this package?

`SignatureImagePlacer` needs to decode PNG signature images and auto-crop
transparent padding. Rather than depending on `package:image` directly —
which many apps already depend on transitively at a different, pinned
version, causing dependency resolution conflicts — this package vendors
only the ~85 files actually needed for that specific job, under
`lib/src/image_decoder/`, with its own internal namespace. It cannot
conflict with your app's own `image` dependency, however you have that
pinned.

Full details, exactly what's included vs. excluded, and license
attribution: [`lib/src/image_decoder/README.md`](lib/src/image_decoder/README.md).

## Third-party licenses

This package depends on `archive`, `crypto`, and `encrypt`, and vendors a
trimmed subset of `image`. The example app additionally uses `pdfrx` and
`flutter_pdfview` for PDF viewing. Full attribution and license text for
all of these: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## How this was built

I couldn't find a good native option for this on Flutter. On Android there
was no solid package for filling AcroForm fields directly. On iOS,
PDFKit exposes annotations, but wiring that up properly would have meant
heavy method-channel work per platform, keeping two native
implementations in sync, and still not getting a shared Dart-side data
model to reason about fields, values, and coordinates the same way on
both platforms. So instead of going down the method-channel route, I
decided to actually learn the PDF format and write a pure-Dart engine
that works identically everywhere.

I went through Adobe's [PDF Reference, version 1.7](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf) —
the openly published specification of the file format — to understand PDF
from the byte level up, rather than from the outside-in shape of an
existing library's API. A PDF isn't really "one format" so much as a
byte stream that has to be pulled apart layer by layer, and building
`PdfTokenizer` and `PdfParser` meant reading it exactly like that: a PDF
loads as a `Uint8List`, and the tokenizer walks it byte-by-byte, comparing
each byte against the hex codes for PDF's structural punctuation —
`0x3C 0x3C` for `<<` (dictionary open), `0x2F` for `/` (a name like
`/AcroForm` or `/FT`), `0x5B`/`0x5D` for array brackets, and so on — to
figure out where dictionaries, names, arrays, and streams start and end,
with no assumptions about what "kind" of PDF it is.

Once the tokenizer could turn raw bytes into a stream of typed tokens, the
next problem was finding the form itself. An AcroForm isn't a special
file section — it's just a `/AcroForm` dictionary hanging off the
document's root `/Catalog`, pointing at a `/Fields` array, where each
field dictionary carries a `/FT` (field type — `Tx` for text, `Btn` for
button/checkbox/radio, `Ch` for choice, `Sig` for signature) and often
inherits attributes like `/FT` or `/DA` from a `/Parent` field rather than
declaring them itself. `AcroFormReader` walks that structure recursively,
resolving indirect references (`PdfRef` → the actual object via the
cross-reference table) along the way, since a field's kids, parent, and
even its own value can each live in a completely different part of the
file. Getting field values in and back out correctly also meant handling
PDF's own string encodings (literal strings, hex strings, and the octal/
UTF escape sequences inside them) so that filled-in text round-trips
correctly instead of corrupting on write.

The last piece — placing a signature *on top of* an existing AcroForm
field rather than replacing it — meant generating a PDF content stream by
hand: creating an Image XObject from the decoded signature PNG, adding it
to the target page's `/Resources`, and emitting the `cm`/`Do` operators
that position and draw it at the field's `/Rect`, converted into PDF's
Y-up coordinate space. `PdfFlattener` builds on the same idea for baking
filled values and stamped signatures permanently into page content
afterward.

None of this wraps an existing PDF library — it's the spec, read
end-to-end and implemented piece by piece, which is also why I'm sharing
the source rather than keeping it as a black box.

**Contributions are very welcome.** If you spot a place where the
implementation deviates from the spec, or want to extend coverage (more
encryption revisions, more filter types, more field types), please open
an issue or PR — see [Contributing](#contributing) below.

## Contributing

Issues and pull requests are welcome — please open an issue first for
anything beyond a small fix, so we can discuss the approach. If you're
proposing a change to the core PDF parsing/writing logic, a reference to
the relevant section of the [PDF Reference 1.7](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf)
in your PR description is very helpful for review.

## License

MIT — see [LICENSE](LICENSE). Third-party code and dependencies are
separately licensed; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).