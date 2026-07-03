// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:convert';
import 'internal/logger.dart';

import 'pdf_objects.dart';
import 'pdf_document.dart';

class PdfWriter {
  final List<int> _buffer = <int>[];
  final Map<int, int> _newOffsets = <int, int>{};
  
  List<int> write(PdfDoc doc) {
    _buffer.clear();
    _newOffsets.clear();
    
    // Get original XRef - we need to preserve ALL object numbers
    final Map<int, int> originalXref = doc.xrefTable;
    Logger.debug('   Writer: Original XRef has ${originalXref.length} entries');
    
    // Collect all objects we need to write
    final Map<int, PdfObj> objectsToWrite = <int, PdfObj>{};
    
    // Always write these critical objects if they exist
    for (int num in <int>[1, 2, 3, 4, 5, 47, 49, 51, 53, 54]) {
      final PdfObj? obj = doc.getObject(num);
      if (obj != null) {
        objectsToWrite[num] = obj;
        Logger.debug('   Writer: Loaded object $num = ${obj.runtimeType}');
      }
    }
    
    // Also try to load any objects from the original XRef
    for (final MapEntry<int, int> entry in originalXref.entries) {
      if (!objectsToWrite.containsKey(entry.key)) {
        final PdfObj? obj = doc.getObject(entry.key);
        if (obj != null) {
          objectsToWrite[entry.key] = obj;
        }
      }
    }

    for (final MapEntry<int, PdfObj> entry in doc.newObjects.entries) {
      objectsToWrite[entry.key] = entry.value;
    }

    Logger.debug('   Writer: Will write ${objectsToWrite.length} objects');
    
    // Write header
    _writeLine('%PDF-1.7');
    _writeLine('%âãÏÓ');
    
    // Write objects in numerical order
    final List<int> sortedNums = objectsToWrite.keys.toList()..sort();
    for (final int num in sortedNums) {
      _newOffsets[num] = _buffer.length;
      _writeObject(num, objectsToWrite[num]!);
    }
    
    // Calculate XRef offset
    final int xrefOffset = _buffer.length;
    
    // Write XRef table
    _writeXref();
    
    // Build trailer preserving Root reference
    final PdfDict trailer = PdfDict();
    final PdfDict oldTrailer = doc.trailer;
    
    // Copy essential entries
    if (oldTrailer.containsKey('Root')) {
      trailer['Root'] = oldTrailer['Root']!; // Preserve original reference
    }
    if (oldTrailer.containsKey('Info')) {
      trailer['Info'] = oldTrailer['Info']!;
    }
    
    // Update Size to our object count + 1
    final int maxObj = sortedNums.isEmpty ? 1 : sortedNums.last + 1;
    trailer['Size'] = PdfNum(maxObj);
    
    // Generate new ID
    final int now = DateTime.now().millisecondsSinceEpoch;
    final PdfStr id1 = PdfStr('${now}1234567890abcdef');
    final PdfStr id2 = PdfStr('${now}fedcba0987654321');
    trailer['ID'] = PdfArr(<PdfObj>[id1, id2]);
    
    _writeTrailer(trailer, xrefOffset);
    
    return List<int>.from(_buffer);
  }
  
  void _writeObject(int num, PdfObj obj) {
    _writeLine('$num 0 obj');
    _writeObjectContent(obj);
    _writeLine('endobj');
    _writeLine('');
  }
  
  void _writeObjectContent(PdfObj obj) {
    if (obj is PdfDict) {
      _write('<<');
      bool first = true;
      for (final MapEntry<String, PdfObj> e in obj.entries.entries) {
        if (!first) _write(' ');
        first = false;
        _write('/${e.key} ');
        _writeValue(e.value);
      }
      _write('>>');
    } else if (obj is PdfArr) {
      _write('[');
      for (int i = 0; i < obj.items.length; i++) {
        if (i > 0) _write(' ');
        _writeValue(obj.items[i]);
      }
      _write(']');
    } else if (obj is PdfStream) {
      _write('<<');
      for (final MapEntry<String, PdfObj> e in obj.dict.entries.entries) {
        if (e.key != 'Length') { // Skip Length, we'll calculate
          _write('/${e.key} ');
          _writeValue(e.value);
        }
      }
      _write('/Length ${obj.data.length}');
      _write('>>');
      _writeLine('');
      _writeLine('stream');
      _buffer.addAll(obj.data);
      _writeLine('');
      _writeLine('endstream');
    } else {
      _writeValue(obj);
    }
  }
  
  void _writeValue(PdfObj obj) {
    if (obj is PdfName) {
      _write('/${obj.value}');
    } else if (obj is PdfStr) {
      final String escaped = obj.value
        .replaceAll('\\', '\\\\')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)')
        .replaceAll('\r', '\\r')
        .replaceAll('\n', '\\n');
      _write('($escaped)');
    } else if (obj is PdfNum) {
      _write(obj.value.toString());
    } else if (obj is PdfBool) {
      _write(obj.value ? 'true' : 'false');
    } else if (obj is PdfNull) {
      _write('null');
    } else if (obj is PdfRef) {
      _write('${obj.objNum} ${obj.genNum} R');
    } else {
      _writeObjectContent(obj);
    }
  }
  
  void _writeXref() {
    if (_newOffsets.isEmpty) return;
    
    final int maxNum = _newOffsets.keys.reduce((int a, int b) => a > b ? a : b);
    
    _writeLine('xref');
    _writeLine('0 ${maxNum + 1}');
    _writeLine('0000000000 65535 f ');
    
    for (int i = 1; i <= maxNum; i++) {
      if (_newOffsets.containsKey(i)) {
        _writeLine('${_newOffsets[i]!.toString().padLeft(10, '0')} 00000 n ');
      } else {
        _writeLine('0000000000 00001 f ');
      }
    }
  }
  
  void _writeTrailer(PdfDict trailer, int xrefOffset) {
    _writeLine('trailer');
    _write('<<');
    for (final MapEntry<String, PdfObj> e in trailer.entries.entries) {
      _write('/${e.key} ');
      _writeValue(e.value);
    }
    _write('>>');
    _writeLine('');
    _writeLine('startxref');
    _writeLine('$xrefOffset');
    _writeLine('%%EOF');
  }
  
  void _write(String s) => _buffer.addAll(utf8.encode(s));
  void _writeLine(String s) {
    _buffer.addAll(utf8.encode(s));
    _buffer.addAll(<int>[0x0D, 0x0A]);
  }
}