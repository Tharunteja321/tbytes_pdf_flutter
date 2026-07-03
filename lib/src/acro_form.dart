// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'pdf_objects.dart';

/// Represents the type of a form field.
enum AcroFieldType {
  text,
  checkbox,
  radio,
  choice,
  button,
  signature,
  unknown,
}

/// Represents a single form field extracted from a PDF.
class AcroField {
  AcroField({
    required this.name,
    required this.type,
    required this.rawDict,
    this.value,
    this.options,
  });
  
  /// Fully qualified field name.
  final String name;
  
  /// Field type.
  final AcroFieldType type;
  
  /// Current value.
  dynamic value;
  
  /// Options for choice fields.
  final List<String>? options;
  
  /// Raw PDF dictionary (for advanced access).
  final PdfDict rawDict;
  
  // Convenience getters
  
  /// Gets value as string (for text fields).
  String? get textValue => value as String?;
  
  /// Gets checked state (for checkboxes).
  bool get isChecked => type == AcroFieldType.checkbox && value == true;
  
  /// Gets selected option (for radio/choice).
  String? get selectedOption => value as String?;
  
  @override
  String toString() => 'AcroField($name, $type, $value)';
}