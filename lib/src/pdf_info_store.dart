// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:convert';
import 'dart:typed_data';

import 'internal/logger.dart';

import 'pdf_document.dart';
import 'pdf_objects.dart';

/// A lightweight key-value store backed by the PDF's Info dictionary.
///
/// The PDF spec defines /Info as a place for document metadata.
/// This class extends that to support storing arbitrary app data
/// (signatures, form state, version info, etc.) invisibly inside the PDF.
///
/// Usage:
/// ```dart
/// final PdfInfoStore store = PdfInfoStore(pdfDoc);
///
/// // Write
/// store.setString('Author', 'CaseAid');
/// store.setBytes('CaseAidSig', signatureBytes);
/// store.setBool('Submitted', true);
///
/// // Read
/// final Uint8List? sig = store.getBytes('CaseAidSig');
/// final bool submitted = store.getBool('Submitted') ?? false;
///
/// // Delete
/// store.remove('CaseAidSig');
/// store.clear(); // wipe all
/// ```
class PdfInfoStore {
  PdfInfoStore(this._doc);

  final PdfDoc _doc;

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Gets or creates the Info dictionary.
  PdfDict _getOrCreateInfoDict() {
    final PdfObj? infoRef = _doc.trailer['Info'];

    if (infoRef != null) {
      final PdfDict? existing = _doc.resolve(infoRef) as PdfDict?;
      if (existing != null) return existing;
    }

    // Create new Info dict and register it
    final PdfDict infoDict = PdfDict();
    final PdfRef ref = _doc.addObject(infoDict);
    _doc.trailer['Info'] = ref;
    Logger.debug('PdfInfoStore: Created new Info dict');
    return infoDict;
  }

  /// Gets the Info dictionary, returns null if it doesn't exist.
  PdfDict? _getInfoDict() {
    final PdfObj? infoRef = _doc.trailer['Info'];
    if (infoRef == null) return null;
    return _doc.resolve(infoRef) as PdfDict?;
  }

  // ── Write operations ─────────────────────────────────────────────────────

  /// Stores a plain string value.
  void setString(String key, String value) {
    try {
      _getOrCreateInfoDict()[key] = PdfStr(value);
      Logger.debug('PdfInfoStore: set string $key');
    } catch (e) {
      Logger.debug('PdfInfoStore setString error: $e');
    }
  }

  /// Stores binary data as a base64-encoded string.
  void setBytes(String key, Uint8List bytes) {
    try {
      _getOrCreateInfoDict()[key] = PdfStr(base64Encode(bytes));
      Logger.debug('PdfInfoStore: set bytes $key (${bytes.length} bytes)');
    } catch (e) {
      Logger.debug('PdfInfoStore setBytes error: $e');
    }
  }

  /// Stores a boolean value as "true" or "false".
  void setBool(String key, bool value) {
    try {
      _getOrCreateInfoDict()[key] = PdfStr(value.toString());
      Logger.debug('PdfInfoStore: set bool $key = $value');
    } catch (e) {
      Logger.debug('PdfInfoStore setBool error: $e');
    }
  }

  /// Stores an integer value.
  void setInt(String key, int value) {
    try {
      _getOrCreateInfoDict()[key] = PdfStr(value.toString());
      Logger.debug('PdfInfoStore: set int $key = $value');
    } catch (e) {
      Logger.debug('PdfInfoStore setInt error: $e');
    }
  }

  // ── Read operations ──────────────────────────────────────────────────────

  /// Reads a plain string value. Returns null if not found.
  String? getString(String key) {
    try {
      final PdfStr? val = _getInfoDict()?[key] as PdfStr?;
      return val?.value;
    } catch (e) {
      Logger.debug('PdfInfoStore getString error: $e');
      return null;
    }
  }

  /// Reads binary data from a base64-encoded string.
  /// Returns null if not found or decoding fails.
  Uint8List? getBytes(String key) {
    try {
      final String? encoded = getString(key);
      if (encoded == null || encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (e) {
      Logger.debug('PdfInfoStore getBytes error for $key: $e');
      return null;
    }
  }

  /// Reads a boolean value. Returns null if not found.
  bool? getBool(String key) {
    try {
      final String? val = getString(key);
      if (val == null) return null;
      return val == 'true';
    } catch (e) {
      Logger.debug('PdfInfoStore getBool error: $e');
      return null;
    }
  }

  /// Reads an integer value. Returns null if not found.
  int? getInt(String key) {
    try {
      final String? val = getString(key);
      if (val == null) return null;
      return int.tryParse(val);
    } catch (e) {
      Logger.debug('PdfInfoStore getInt error: $e');
      return null;
    }
  }

  // ── Delete operations ────────────────────────────────────────────────────

  /// Removes a single key from the Info dictionary.
  void remove(String key) {
    try {
      _getInfoDict()?.entries.remove(key);
      Logger.debug('PdfInfoStore: removed $key');
    } catch (e) {
      Logger.debug('PdfInfoStore remove error: $e');
    }
  }

  /// Removes multiple keys at once.
  void removeAll(List<String> keys) {
    for (final String key in keys) {
      remove(key);
    }
  }

  /// Clears ALL custom keys from the Info dictionary.
  /// Pass [preserveStandard] = true to keep standard PDF keys
  /// like Title, Author, Subject, Creator, Producer etc.
  void clear({bool preserveStandard = true}) {
    try {
      final PdfDict? infoDict = _getInfoDict();
      if (infoDict == null) return;

      if (preserveStandard) {
        const List<String> standardKeys = <String>[
          'Title', 'Author', 'Subject', 'Keywords',
          'Creator', 'Producer', 'CreationDate', 'ModDate', 'Trapped',
        ];
        infoDict.entries.removeWhere(
          (String key, PdfObj _) => !standardKeys.contains(key),
        );
      } else {
        infoDict.entries.clear();
      }

      Logger.debug('PdfInfoStore: cleared (preserveStandard=$preserveStandard)');
    } catch (e) {
      Logger.debug('PdfInfoStore clear error: $e');
    }
  }

  // ── Query operations ─────────────────────────────────────────────────────

  /// Returns true if the key exists in the Info dictionary.
  bool containsKey(String key) {
    try {
      return _getInfoDict()?.containsKey(key) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Returns all keys currently in the Info dictionary.
  List<String> get keys {
    try {
      return _getInfoDict()?.keys.toList() ?? <String>[];
    } catch (e) {
      return <String>[];
    }
  }
}