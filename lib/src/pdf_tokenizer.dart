// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:typed_data';

/// Token types for PDF parsing.
enum TokenType {
  number,
  string,
  hexString,
  name,
  keyword,
  arrayStart,
  arrayEnd,
  dictStart,
  dictEnd,
  eof,
}

/// Represents a PDF token.
class Token {
  const Token(this.type, this.value);
  final TokenType type;
  final dynamic value;
  
  @override
  String toString() => 'Token($type, $value)';
}

/// Tokenizes PDF content from bytes.
class PdfTokenizer {
  PdfTokenizer(this.data);
  
  final Uint8List data;
  int _pos = 0;
  
  int get position => _pos;
  set position(int value) => _pos = value.clamp(0, data.length);
  
  bool get isEof => _pos >= data.length;
  
  /// Reads the next token.
  Token nextToken() {
    _skipWhitespaceAndComments();
    
    if (isEof) {
      return const Token(TokenType.eof, null);
    }
    
    final int ch = data[_pos];
    
    // Array delimiters
    if (ch == 0x5B) { // [
      _pos++;
      return const Token(TokenType.arrayStart, '[');
    }
    if (ch == 0x5D) { // ]
      _pos++;
      return const Token(TokenType.arrayEnd, ']');
    }
    
    // Dictionary delimiters
    if (ch == 0x3C && _peek(1) == 0x3C) { // <<
      _pos += 2;
      return const Token(TokenType.dictStart, '<<');
    }
    if (ch == 0x3E && _peek(1) == 0x3E) { // >>
      _pos += 2;
      return const Token(TokenType.dictEnd, '>>');
    }
    
    // Hex string
    if (ch == 0x3C) { // <
      return _readHexString();
    }
    
    // Literal string
    if (ch == 0x28) { // (
      return _readLiteralString();
    }
    
    // Name
    if (ch == 0x2F) { // /
      return _readName();
    }
    
    // Number or keyword
    if (_isDigit(ch) || ch == 0x2D || ch == 0x2B || ch == 0x2E) {
      return _readNumberOrKeyword();
    }
    
    // Keyword
    if (_isAlpha(ch)) {
      return _readKeyword();
    }
    
    // Unknown - skip
    _pos++;
    return nextToken();
  }
  
  /// Peeks at a character at offset from current position.
  int _peek(int offset) {
    final int idx = _pos + offset;
    return idx < data.length ? data[idx] : -1;
  }
  
  /// Skips whitespace and comments.
  void _skipWhitespaceAndComments() {
    while (!isEof) {
      final int ch = data[_pos];
      
      // Whitespace
      if (_isWhitespace(ch)) {
        _pos++;
        continue;
      }
      
      // Comment
      if (ch == 0x25) { // %
        while (!isEof && data[_pos] != 0x0A && data[_pos] != 0x0D) {
          _pos++;
        }
        continue;
      }
      
      break;
    }
  }
  
  /// Reads a name token.
  Token _readName() {
    _pos++; // skip /
    final int start = _pos;
    
    while (!isEof && _isNameChar(data[_pos])) {
      _pos++;
    }
    
    final String name = String.fromCharCodes(data.sublist(start, _pos));
    return Token(TokenType.name, _decodeName(name));
  }
  
  /// Decodes name escape sequences (#XX).
  String _decodeName(String name) {
    final StringBuffer result = StringBuffer();
    int i = 0;
    
    while (i < name.length) {
      if (name[i] == '#' && i + 2 < name.length) {
        final String hex = name.substring(i + 1, i + 3);
        final int? code = int.tryParse(hex, radix: 16);
        if (code != null) {
          result.writeCharCode(code);
          i += 3;
          continue;
        }
      }
      result.write(name[i]);
      i++;
    }
    
    return result.toString();
  }
  
  /// Reads a literal string (parentheses).
  Token _readLiteralString() {
    _pos++; // skip (
    final StringBuffer buffer = StringBuffer();
    int depth = 1;
    
    while (!isEof && depth > 0) {
      final int ch = data[_pos++];
      
      if (ch == 0x28) { // (
        depth++;
        buffer.writeCharCode(ch);
      } else if (ch == 0x29) { // )
        depth--;
        if (depth > 0) buffer.writeCharCode(ch);
      } else if (ch == 0x5C) { // backslash
        buffer.write(_readEscapeSequence());
      } else {
        buffer.writeCharCode(ch);
      }
    }
    
    return Token(TokenType.string, buffer.toString());
  }
  
  /// Reads an escape sequence in a string.
  String _readEscapeSequence() {
    if (isEof) return '';
    
    final int ch = data[_pos++];
    switch (ch) {
      case 0x6E: return '\n'; // n
      case 0x72: return '\r'; // r
      case 0x74: return '\t'; // t
      case 0x62: return '\b'; // b
      case 0x66: return '\f'; // f
      case 0x28: return '(';
      case 0x29: return ')';
      case 0x5C: return '\\';
      case 0x0D: // CR
        if (!isEof && data[_pos] == 0x0A) _pos++; // skip LF
        return '';
      case 0x0A: // LF
        return '';
      default:
        // Octal
        if (ch >= 0x30 && ch <= 0x37) {
          String octal = String.fromCharCode(ch);
          for (int i = 0; i < 2 && !isEof; i++) {
            final int next = data[_pos];
            if (next >= 0x30 && next <= 0x37) {
              octal += String.fromCharCode(next);
              _pos++;
            } else {
              break;
            }
          }
          return String.fromCharCode(int.parse(octal, radix: 8) & 0xFF);
        }
        return String.fromCharCode(ch);
    }
  }
  
  /// Reads a hex string.
  Token _readHexString() {
    _pos++; // skip <
    final StringBuffer buffer = StringBuffer();
    
    while (!isEof) {
      final int ch = data[_pos];
      if (ch == 0x3E) { // >
        _pos++;
        break;
      }
      if (_isHexDigit(ch)) {
        buffer.writeCharCode(ch);
      }
      _pos++;
    }
    
    String hex = buffer.toString();
    if (hex.length % 2 != 0) {
      hex += '0';
    }
    
    // Convert hex to string
    final StringBuffer result = StringBuffer();
    for (int i = 0; i < hex.length; i += 2) {
      final int code = int.parse(hex.substring(i, i + 2), radix: 16);
      result.writeCharCode(code);
    }
    
    return Token(TokenType.hexString, result.toString());
  }
  
  /// Reads a number or keyword starting with digit/sign.
  Token _readNumberOrKeyword() {
    final int start = _pos;
    bool hasDecimal = false;
    
    // Handle sign
    if (data[_pos] == 0x2D || data[_pos] == 0x2B) {
      _pos++;
    }
    
    while (!isEof) {
      final int ch = data[_pos];
      if (_isDigit(ch)) {
        _pos++;
      } else if (ch == 0x2E && !hasDecimal) {
        hasDecimal = true;
        _pos++;
      } else {
        break;
      }
    }
    
    final String str = String.fromCharCodes(data.sublist(start, _pos));
    final num? value = num.tryParse(str);
    
    if (value != null) {
      return Token(TokenType.number, value);
    }
    
    // Might be keyword that starts with number (rare)
    return Token(TokenType.keyword, str);
  }
  
  /// Reads a keyword.
  Token _readKeyword() {
    final int start = _pos;
    
    while (!isEof && _isAlphaNumeric(data[_pos])) {
      _pos++;
    }
    
    final String keyword = String.fromCharCodes(data.sublist(start, _pos));
    return Token(TokenType.keyword, keyword);
  }
  
  // Character classification helpers
  bool _isWhitespace(int ch) =>
      ch == 0x00 || ch == 0x09 || ch == 0x0A || 
      ch == 0x0C || ch == 0x0D || ch == 0x20;
  
  bool _isDigit(int ch) => ch >= 0x30 && ch <= 0x39;
  
  bool _isAlpha(int ch) =>
      (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A);
  
  bool _isAlphaNumeric(int ch) => _isAlpha(ch) || _isDigit(ch);
  
  bool _isHexDigit(int ch) =>
      _isDigit(ch) || 
      (ch >= 0x41 && ch <= 0x46) || 
      (ch >= 0x61 && ch <= 0x66);
  
  bool _isNameChar(int ch) =>
      ch > 0x20 && ch != 0x25 && ch != 0x28 && ch != 0x29 &&
      ch != 0x2F && ch != 0x3C && ch != 0x3E && ch != 0x5B &&
      ch != 0x5D && ch != 0x7B && ch != 0x7D;
}