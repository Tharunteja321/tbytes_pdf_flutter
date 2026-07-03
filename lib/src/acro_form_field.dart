// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'package:flutter/material.dart';
import 'acro_form.dart';
import 'internal/logger.dart';
import 'pdf_objects.dart';
import 'pdf_document.dart';

/// Reads AcroForm fields from a PDF document.
class AcroFormReader {
  AcroFormReader(this._doc);

  final PdfDoc _doc;

  /// Checks if the document has a form.
  bool get hasForm {
    final PdfDict? catalog = _doc.catalog;
    return catalog != null && catalog.containsKey('AcroForm');
  }

  /// Reads all form fields.
  List<AcroField> readFields() {
    final List<AcroField> fields = <AcroField>[];

    final PdfDict? catalog = _doc.catalog;
    if (catalog == null) return fields;

    final PdfDict? acroForm = _doc.resolve(catalog['AcroForm']) as PdfDict?;
    if (acroForm == null) return fields;

    final PdfArr? fieldsArr = _doc.resolve(acroForm['Fields']) as PdfArr?;
    if (fieldsArr == null) return fields;

    _walkFields(fieldsArr, '', fields);

    return fields;
  }

  /// Reads a specific field by name.
  AcroField? readField(String name) {
    final List<AcroField> fields = readFields();
    for (final AcroField field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }

  /// Reads fields of a specific type.
  List<AcroField> readFieldsByType(AcroFieldType type) {
    return readFields().where((AcroField f) => f.type == type).toList();
  }

  // Private methods

  void _walkFields(
    PdfArr fieldsArr,
    String parentName,
    List<AcroField> result,
  ) {
    for (int i = 0; i < fieldsArr.length; i++) {
      final PdfDict? fieldDict = _doc.resolve(fieldsArr[i]) as PdfDict?;
      if (fieldDict == null) continue;

      final String name = _buildName(fieldDict, parentName);
      final PdfArr? kids = _doc.resolve(fieldDict['Kids']) as PdfArr?;

      if (kids != null && _isNonTerminal(fieldDict, kids)) {
        // Recurse into children
        _walkFields(kids, name, result);
      } else {
        // Terminal field
        final AcroField? field = _createField(fieldDict, name);
        if (field != null) {
          result.add(field);
        }
      }
    }
  }

  bool _isNonTerminal(PdfDict dict, PdfArr kids) {
    // No FT = grouping node
    if (!dict.containsKey('FT') && _getInherited(dict, 'FT') == null) {
      return true;
    }

    // Check if kids are widgets
    if (kids.length > 0) {
      final PdfDict? firstKid = _doc.resolve(kids[0]) as PdfDict?;
      if (firstKid != null) {
        final PdfName? subtype = _doc.resolve(firstKid['Subtype']) as PdfName?;
        if (subtype?.value == 'Widget') {
          return false; // Terminal with widget kids
        }
      }
    }

    return true;
  }

  String _buildName(PdfDict dict, String parentName) {
    String localName = '';

    final PdfStr? t = _doc.resolve(dict['T']) as PdfStr?;
    if (t != null) {
      localName = t.value;
    }

    if (parentName.isEmpty) return localName;
    if (localName.isEmpty) return parentName;
    return '$parentName.$localName';
  }

  AcroField? _createField(PdfDict dict, String name) {
    final AcroFieldType type = _resolveType(dict);
    if (type == AcroFieldType.unknown) return null;

    final dynamic value = _extractValue(dict, type);
    final List<String>? options = _extractOptions(dict, type);

    return AcroField(
      name: name,
      type: type,
      value: value,
      options: options,
      rawDict: dict,
    );
  }

  AcroFieldType _resolveType(PdfDict dict) {
    PdfName? ft = _doc.resolve(dict['FT']) as PdfName?;
    ft ??= _getInherited(dict, 'FT') as PdfName?;

    if (ft == null) return AcroFieldType.unknown;

    switch (ft.value) {
      case 'Tx':
        return AcroFieldType.text;
      case 'Btn':
        return _resolveButtonType(dict);
      case 'Ch':
        return AcroFieldType.choice;
      case 'Sig':
        return AcroFieldType.signature;
      default:
        return AcroFieldType.unknown;
    }
  }

  AcroFieldType _resolveButtonType(PdfDict dict) {
    final int flags = _getFieldFlags(dict);

    // Bit 17 (1 << 16): Pushbutton
    if ((flags & (1 << 16)) != 0) {
      return AcroFieldType.button;
    }

    // Bit 16 (1 << 15): Radio
    if ((flags & (1 << 15)) != 0) {
      return AcroFieldType.radio;
    }

    return AcroFieldType.checkbox;
  }

  int _getFieldFlags(PdfDict dict) {
    PdfNum? ff = _doc.resolve(dict['Ff']) as PdfNum?;
    ff ??= _getInherited(dict, 'Ff') as PdfNum?;
    return ff?.intValue ?? 0;
  }

  dynamic _extractValue(PdfDict dict, AcroFieldType type) {
    PdfObj? v = _doc.resolve(dict['V']);
    v ??= _getInherited(dict, 'V');

    if (v == null) {
      return type == AcroFieldType.checkbox ? false : null;
    }

    switch (type) {
      case AcroFieldType.text:
        if (v is PdfStr) return v.value;
        return null;

      case AcroFieldType.checkbox:
        if (v is PdfName) return v.value != 'Off';
        return false;

      case AcroFieldType.radio:
        if (v is PdfName) {
          return v.value == 'Off' ? null : v.value;
        }
        return null;

      case AcroFieldType.choice:
        if (v is PdfStr) return v.value;
        if (v is PdfArr) {
          return v.items
              .whereType<PdfStr>()
              .map((PdfStr s) => s.value)
              .toList();
        }
        return null;

      default:
        return null;
    }
  }

  /// Sets the text color of a field using PDF color operators
void setFieldTextColor(String fieldName, {
  required double r,
  required double g,
  required double b,
}) {
  final AcroField? field = findField(fieldName);
  if (field == null) {
    Logger.debug('setFieldTextColor: Field not found: $fieldName');
    return;
  }

  final PdfDict dict = field.rawDict;

  // Get existing DA to preserve font/size, only replace color
  PdfStr? existingDa = _doc.resolve(dict['DA']) as PdfStr?;

  // Also check inherited DA from AcroForm root
  if (existingDa == null) {
    final PdfDict? catalog = _doc.catalog;
    if (catalog != null) {
      final PdfDict? acroForm = _doc.resolve(catalog['AcroForm']) as PdfDict?;
      existingDa = _doc.resolve(acroForm?['DA']) as PdfStr?;
    }
  }

  // Parse font/size from existing DA (e.g. "/MinionPro-Regular 10 Tf 0 g")
  // Strip any existing color operators (g, rg, k) and append new color
  String daBase = existingDa?.value ?? '/Helvetica 10 Tf';
  daBase = _stripColorFromDa(daBase);

  // Append RGB color operator
  // rg = non-stroking RGB color in PDF spec
  final String colorOperator =
      '${_fmt(r)} ${_fmt(g)} ${_fmt(b)} rg';

  dict['DA'] = PdfStr('$daBase $colorOperator');

  // Force appearance regeneration
  final PdfDict? catalog = _doc.catalog;
  if (catalog != null) {
    final PdfDict? acroForm =
        _doc.resolve(catalog['AcroForm']) as PdfDict?;
    if (acroForm != null) {
      acroForm['NeedAppearances'] = const PdfBool(true);
    }
  }

  Logger.debug('Set text color of $fieldName to rgb($r, $g, $b)');
}

String _stripColorFromDa(String da) {
  // Remove existing color operators:
  // "X g"       = grayscale
  // "X X X rg"  = RGB
  // "X X X X k" = CMYK
  return da
      .replaceAll(RegExp(r'\d*\.?\d+\s+g(?=\s|$)'), '')
      .replaceAll(RegExp(r'(\d*\.?\d+\s+){3}rg(?=\s|$)'), '')
      .replaceAll(RegExp(r'(\d*\.?\d+\s+){4}k(?=\s|$)'), '')
      .trim();
}

String _fmt(double v) {
  // Clamp to valid PDF range 0.0–1.0
  final double clamped = v.clamp(0.0, 1.0);
  return clamped == clamped.truncateToDouble()
      ? clamped.toStringAsFixed(1)
      : clamped.toStringAsFixed(3);
}

  List<String>? _extractOptions(PdfDict dict, AcroFieldType type) {
    if (type != AcroFieldType.choice) return null;

    final PdfArr? opt = _doc.resolve(dict['Opt']) as PdfArr?;
    if (opt == null) return null;

    final List<String> options = <String>[];
    for (int i = 0; i < opt.length; i++) {
      final PdfObj? item = _doc.resolve(opt[i]);
      if (item is PdfStr) {
        options.add(item.value);
      } else if (item is PdfArr && item.length > 0) {
        // [exportValue, displayValue]
        final PdfObj? display = _doc.resolve(item[item.length > 1 ? 1 : 0]);
        if (display is PdfStr) {
          options.add(display.value);
        }
      }
    }

    return options;
  }

  PdfObj? _getInherited(PdfDict dict, String key) {
    PdfDict? current = dict;

    while (current != null) {
      final PdfDict? parent = _doc.resolve(current['Parent']) as PdfDict?;
      if (parent == null) break;

      if (parent.containsKey(key)) {
        return _doc.resolve(parent[key]);
      }

      current = parent;
    }

    return null;
  }

  /// Gets a field value by name (re-reads from PDF to get latest)
  dynamic getFieldValue(String fieldName) {
    final AcroField field = readFields().firstWhere(
      (AcroField f) => f.name == fieldName,
      orElse: () => throw Exception('Field not found: $fieldName'),
    );
    return field.value;
  }

  /// Sets a field as read-only — prevents keyboard and editing
  /// Call this after setFieldValue to lock the field
  void setFieldReadOnly(String fieldName) {
    final AcroField? field = findField(fieldName);
    if (field == null) {
      Logger.debug('setFieldReadOnly: Field not found: $fieldName');
      return;
    }

    // Bit 1 (value 1) = ReadOnly flag per PDF spec section 8.6.2
    final int currentFlags =
        (_doc.resolve(field.rawDict['Ff']) as PdfNum?)?.intValue ?? 0;
    field.rawDict['Ff'] = PdfNum(currentFlags | 1);

    Logger.debug('Set $fieldName as ReadOnly');
  }

  /// Sets a field value by name
  ///
  /// For text fields: pass a String
  /// For checkboxes: pass a bool (true=checked, false=unchecked)
  /// For radio buttons: pass a String (the option name)
  void setFieldValue(String fieldName, dynamic value) {
    // Find the field
    final List<AcroField> fields = readFields();
    final AcroField field = fields.firstWhere(
      (AcroField f) => f.name == fieldName,
      orElse: () => throw Exception('Field not found: $fieldName'),
    );

    // Update the underlying PDF dictionary
    final PdfDict dict = field.rawDict;

    switch (field.type) {
      case AcroFieldType.text:
        if (value is! String) {
          throw ArgumentError('Text field requires String value');
        }
        dict['V'] = PdfStr(value);
        break;

      case AcroFieldType.checkbox:
        if (value is! bool) {
          throw ArgumentError('Checkbox field requires bool value');
        }
        // "Yes" or "Off" are standard checkbox values
        dict['V'] = PdfName(value ? 'Yes' : 'Off');
        break;

      case AcroFieldType.radio:
        if (value is! String) {
          throw ArgumentError('Radio field requires String option name');
        }
        dict['V'] = PdfName(value);
        break;

      case AcroFieldType.choice:
        if (value is String) {
          dict['V'] = PdfStr(value);
        } else if (value is List<String>) {
          // Multi-select
          final PdfArr arr = PdfArr();
          for (final String v in value) {
            arr.add(PdfStr(v));
          }
          dict['V'] = arr;
        }
        break;

      default:
        throw UnsupportedError(
          'Setting values for ${field.type} not supported',
        );
    }

    // Mark AcroForm as needing regeneration of appearances
    final PdfDict? catalog = _doc.catalog;
    if (catalog != null) {
      final PdfObj? acroFormRef = catalog['AcroForm'];
      final PdfObj? acroForm = _doc.resolve(acroFormRef);
      if (acroForm is PdfDict) {
        acroForm['NeedAppearances'] = const PdfBool(true);
      }
    }

    Logger.debug('Set $fieldName = $value');
  }

  /// Finds a single field by name (convenience method)
  AcroField? findField(String fieldName) {
    try {
      return readFields().firstWhere((AcroField f) => f.name == fieldName);
    } catch (e) {
      return null;
    }
  }

  /// Gets the rectangle (position) of a field
  Rect? getFieldRect(AcroField field) {
    final PdfDict dict = field.rawDict;

    // Try field's own Rect first
    PdfArr? rect = _doc.resolve(dict['Rect']) as PdfArr?;

    // Check Kids (widget annotations) if not found
    if (rect == null) {
      final PdfArr? kids = _doc.resolve(dict['Kids']) as PdfArr?;
      if (kids != null && kids.length > 0) {
        final PdfDict? widget = _doc.resolve(kids[0]) as PdfDict?;
        if (widget != null) {
          rect = _doc.resolve(widget['Rect']) as PdfArr?;
        }
      }
    }

    if (rect == null || rect.length < 4) return null;

    final double x1 = _getNum(rect[0]!);
    final double y1 = _getNum(rect[1]!);
    final double x2 = _getNum(rect[2]!);
    final double y2 = _getNum(rect[3]!);

    // Return normalized rect (ensure left < right, bottom < top in PDF coords)
    return Rect.fromLTRB(
      x1 < x2 ? x1 : x2,
      y1 < y2 ? y1 : y2,
      x1 > x2 ? x1 : x2,
      y1 > y2 ? y1 : y2,
    );
  }

  double _getNum(PdfObj obj) {
    if (obj is PdfNum) return obj.doubleValue;
    return 0.0;
  }

  /// Gets the page index for a field (0-based)
  int? getFieldPage(AcroField field) {
    final PdfDict dict = field.rawDict;

    // Try field's P entry
    PdfDict? page = _doc.resolve(dict['P']) as PdfDict?;

    // Check Kids if not found
    if (page == null) {
      final PdfArr? kids = _doc.resolve(dict['Kids']) as PdfArr?;
      if (kids != null && kids.length > 0) {
        final PdfDict? widget = _doc.resolve(kids[0]) as PdfDict?;
        if (widget != null) {
          page = _doc.resolve(widget['P']) as PdfDict?;
        }
      }
    }

    if (page == null) return 0; // Default to first page

    return _doc.getPageIndex(page) ?? 0;
  }

  /// Gets the widget annotation dict for a field
  PdfDict? getFieldWidget(AcroField field) {
    final PdfDict dict = field.rawDict;

    // Check if field itself is the widget (merged)
    final PdfName? subtype = _doc.resolve(dict['Subtype']) as PdfName?;
    if (subtype?.value == 'Widget') {
      return dict;
    }

    // Get from Kids
    final PdfArr? kids = _doc.resolve(dict['Kids']) as PdfArr?;
    if (kids != null && kids.length > 0) {
      return _doc.resolve(kids[0]) as PdfDict?;
    }

    // Field itself might be the widget even without Subtype
    if (dict.containsKey('Rect')) {
      return dict;
    }

    return null;
  }
}
