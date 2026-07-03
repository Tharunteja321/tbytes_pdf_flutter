## 0.1.0

- Initial release.
- `PdfDoc` — PDF parsing, object graph resolution, page tree traversal.
- `AcroFormReader` — read and fill AcroForm fields (text, checkbox, radio,
  choice, signature).
- `PdfFlattener` — flatten filled fields / annotations into static page
  content.
- `PdfDecryptor` — decrypt password-protected PDFs (RC4 and AES).
- `SignatureImagePlacer` — place a signature image (PNG) onto a form field,
  with automatic transparent-padding trim and aspect-ratio-preserving fit.
- `PdfWriter` — serialize a modified `PdfDoc` back to bytes.
- `PdfInfoStore` — read/write the PDF Info dictionary.
