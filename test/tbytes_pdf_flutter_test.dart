// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'package:flutter_test/flutter_test.dart';
import 'package:tbytes_pdf_flutter/tbytes_pdf_flutter.dart';

void main() {
  group('AcroField', () {
    test('exposes convenience getters correctly', () {
      final field = AcroField(
        name: 'agree',
        type: AcroFieldType.checkbox,
        rawDict: PdfDict(),
        value: true,
      );

      expect(field.isChecked, isTrue);
      expect(field.toString(), contains('agree'));
    });
  });

  group('FlattenResult', () {
    test('toString reports counts', () {
      const result = FlattenResult(
        pagesProcessed: 3,
        annotationsFlattened: 5,
        annotationsSkipped: 1,
      );

      expect(result.toString(), contains('pages: 3'));
      expect(result.toString(), contains('flattened: 5'));
      expect(result.toString(), contains('skipped: 1'));
    });
  });

  group('PdfObjects', () {
    test('PdfDict get/set roundtrips a value', () {
      final dict = PdfDict();
      dict['Key'] = const PdfBool(true);
      expect(dict['Key'], isA<PdfBool>());
    });
  });

  // Full end-to-end coverage (loading a real PDF, filling fields, signing,
  // flattening, decrypting) is exercised interactively in
  // example/lib/pdf_feature_demo_screen.dart, since it requires a real PDF
  // file and, for the signature path, a rendered PNG.
}
