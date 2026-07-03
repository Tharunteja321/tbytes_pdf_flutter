// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

/// Fill, flatten, decrypt, and sign PDF forms in Flutter.
///
/// This library exposes the public API for parsing PDF documents, working
/// with AcroForm fields, flattening filled forms into static content,
/// decrypting password-protected PDFs, and placing signature images onto
/// PDF pages.
///
/// See the package README for a full usage guide, and `example/` for a
/// runnable demo of every feature.
library tbytes_pdf_flutter;

// Core document model — parsing, object graph, low-level PDF primitives.
export 'src/pdf_document.dart' show PdfDoc;
export 'src/pdf_objects.dart'
    show
        PdfObj,
        PdfNull,
        PdfBool,
        PdfNum,
        PdfStr,
        PdfName,
        PdfArr,
        PdfDict,
        PdfStream,
        PdfRef;
export 'src/pdf_writer.dart' show PdfWriter;

// AcroForm reading and field model.
export 'src/acro_form.dart' show AcroField, AcroFieldType;
export 'src/acro_form_field.dart' show AcroFormReader;

// Flattening (baking form fields / annotations into static page content).
export 'src/pdf_flattener.dart'
    show PdfFlattener, FlattenResult, FlattenQuality, FlattenTarget;

// Decryption of password-protected PDFs.
export 'src/pdf_decryptor.dart' show PdfDecryptor;

// Document metadata (Info dictionary) read/write.
export 'src/pdf_info_store.dart' show PdfInfoStore;

// Signature image placement.
export 'src/signature_image_placer.dart' show SignatureImagePlacer;

// Note: lib/src/image_decoder/ (a trimmed vendored subset of the `image`
// package) is intentionally NOT exported. It is an internal implementation
// detail of SignatureImagePlacer. See lib/src/image_decoder/README.md.
