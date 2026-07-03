// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:typed_data';

import 'pdf_objects.dart';
import 'pdf_tokenizer.dart';


/// Parses PDF objects from tokenized input.
class PdfParser {
  PdfParser(this._tokenizer);
  
  final PdfTokenizer _tokenizer;
  Token? _current;
  
  /// Parses a PDF object at the current position.
  PdfObj? parseObject() {
    _advance();
    return _parseValue();
  }
  
  /// Advances to the next token.
  void _advance() {
    _current = _tokenizer.nextToken();
  }
  
  /// Parses a value based on current token.
  PdfObj? _parseValue() {
    if (_current == null) return null;
    
    switch (_current!.type) {
      case TokenType.number:
        return _parseNumberOrRef();
      
      case TokenType.string:
      case TokenType.hexString:
        return PdfStr(_current!.value as String);
      
      case TokenType.name:
        return PdfName(_current!.value as String);
      
      case TokenType.arrayStart:
        return _parseArray();
      
      case TokenType.dictStart:
        return _parseDictOrStream();
      
      case TokenType.keyword:
        return _parseKeyword();
      
      default:
        return null;
    }
  }
  
  /// Parses a number or reference (X Y R).
  PdfObj _parseNumberOrRef() {
    final num num1 = _current!.value as num;
    final int posAfterNum1 = _tokenizer.position; 
    
    _advance(); 
    
    if (_current?.type == TokenType.number) {
      final num num2 = _current!.value as num;
      
      _advance(); 
      
      if (_current?.type == TokenType.keyword && _current?.value == 'R') {
        return PdfRef(num1.toInt(), num2.toInt());
      }
      
      // Not X Y R (it was X Y [something]). Backtrack to after X.
      _tokenizer.position = posAfterNum1;
      return PdfNum(num1);
    }
    
    // Not X [Number] (it was X [something]). Backtrack to after X.
    _tokenizer.position = posAfterNum1;
    return PdfNum(num1);
  }
  
  /// Parses an array.
  PdfArr _parseArray() {
    final PdfArr arr = PdfArr();
    // [ is already consumed
    
    while (true) {
        // Peek
        final int pos = _tokenizer.position;
        final Token next = _tokenizer.nextToken();
        _tokenizer.position = pos;
        
        if (next.type == TokenType.arrayEnd) {
            _advance(); // Consume ]
            break;
        }
        if (next.type == TokenType.eof) break;
        
        final PdfObj? obj = parseObject();
        if (obj != null) {
            arr.add(obj);
        } else {
            // Safety: consume one token to avoid infinite loop
            _advance();
            if (_current?.type == TokenType.arrayEnd) break;
        }
    }
    return arr;
  }
  
  /// Parses a dictionary (and potentially a stream).
  PdfObj _parseDictOrStream() {
    final PdfDict dict = PdfDict();
    
    while (true) {
        // Peek
        final int pos = _tokenizer.position;
        final Token next = _tokenizer.nextToken();
        _tokenizer.position = pos;
        
        if (next.type == TokenType.dictEnd) {
            _advance(); // Consume >>
            break;
        }
        if (next.type == TokenType.eof) break;
        
        _advance(); // Read Key
        if (_current?.type != TokenType.name) continue;
        
        final String key = _current!.value as String;
        final PdfObj? value = parseObject();
        if (value != null) {
            dict[key] = value;
        }
    }
    
    // Check for stream
    final int posAfterDict = _tokenizer.position;
    final Token next = _tokenizer.nextToken();
    
    if (next.type == TokenType.keyword && next.value == 'stream') {
      _current = next; 
      return _parseStream(dict);
    } else {
      _tokenizer.position = posAfterDict;
    }
    
    return dict;
  }
  
  /// Parses a stream.
  PdfStream _parseStream(PdfDict dict) {
    final int dataStart = _findStreamStart(_tokenizer.position);
    _tokenizer.position = dataStart;
    
    int length = 0;
    final PdfObj? lengthObj = dict['Length'];
    if (lengthObj is PdfNum) {
      length = lengthObj.intValue;
    } else {
        // If Length is a reference or missing, scan for endstream
        length = _scanForEndstream(dataStart);
    }
    
    final Uint8List data = _tokenizer.data.sublist(
      dataStart,
      (dataStart + length).clamp(0, _tokenizer.data.length),
    );
    
    _tokenizer.position = dataStart + length;
    
    // Consume endstream
    final Token next = _tokenizer.nextToken();
    if (next.type == TokenType.keyword && next.value == 'endstream') {
        // OK
    }
    
    return PdfStream(dict, data);
  }
  
  int _scanForEndstream(int start) {
      final Uint8List data = _tokenizer.data;
      final List<int> endMarker = 'endstream'.codeUnits;
      for(int i = start; i < data.length - endMarker.length; i++) {
          bool match = true;
          for(int j=0; j<endMarker.length; j++) {
              if (data[i+j] != endMarker[j]) {
                  match = false;
                  break;
              }
          }
          if (match) {
              // Adjust for newline before endstream
              if (data[i-1] == 0x0A) return i - 1 - start;
              if (data[i-1] == 0x0D) return i - 1 - start;
              return i - start;
          }
      }
      return 0;
  }
  
  int _findStreamStart(int pos) {
    final Uint8List data = _tokenizer.data;
    while(pos < data.length && (data[pos] == 0x20)) {
      pos++;
    }
    
    if (pos < data.length && data[pos] == 0x0D) {
        pos++;
        if (pos < data.length && data[pos] == 0x0A) pos++;
    } else if (pos < data.length && data[pos] == 0x0A) {
        pos++;
    }
    return pos;
  }
  
  PdfObj? _parseKeyword() {
    final String kw = _current!.value as String;
    switch (kw) {
      case 'true': return const PdfBool(true);
      case 'false': return const PdfBool(false);
      case 'null': return const PdfNull();
      default: return null;
    }
  }
}