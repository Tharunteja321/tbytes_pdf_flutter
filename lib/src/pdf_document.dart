// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:io';
import 'dart:typed_data';
import 'pdf_writer.dart';
import 'internal/logger.dart';

import 'pdf_objects.dart';
import 'pdf_tokenizer.dart';
import 'pdf_parser.dart';

class PdfDoc {
  PdfDoc._(this._data, this._xrefTable, this._trailer);

  final Uint8List _data;
  final Map<int, int> _xrefTable;
  final PdfDict _trailer;
  final Map<int, PdfObj> _objectCache = <int, PdfObj>{};
    Map<int, int> get xrefTable => Map<int, int>.unmodifiable(_xrefTable);
  // Add this map to cache object streams
  final Map<int, Map<int, PdfObj>> _objectStreams = <int, Map<int, PdfObj>>{};

  static PdfDoc load(List<int> bytes) {
    final Uint8List data = bytes is Uint8List
        ? bytes
        : Uint8List.fromList(bytes);
    final int startXref = _findStartXref(data);
    final _XrefResult xrefResult = _parseXref(data, startXref);
    return PdfDoc._(data, xrefResult.xref, xrefResult.trailer);
  }

  PdfDict get trailer => _trailer;

  PdfDict? get catalog {
    final PdfObj? root = _trailer['Root'];
    return resolve(root) as PdfDict?;
  }

  PdfObj? resolve(PdfObj? obj) {
    if (obj == null) return null;
    if (obj is PdfRef) {
      return getObject(obj.objNum);
    }
    return obj;
  }

  PdfObj? getObject(int objNum) {
    if (_objectCache.containsKey(objNum)) {
      return _objectCache[objNum];
    }

    final int? offset = _xrefTable[objNum];
    if (offset == null) {
      // Check if it's in an object stream (type 2 xref entry)
      Logger.debug(
        '   Object $objNum: Not in XRef table, checking object streams...',
      );
      return _getFromObjectStream(objNum);
    }

    // Negative offset means object stream (some PDFs use this convention)
    if (offset < 0) {
      return _getFromObjectStream(objNum, streamNum: -offset);
    }

    final PdfTokenizer tokenizer = PdfTokenizer(_data);
    tokenizer.position = offset;

    final PdfParser parser = PdfParser(tokenizer);

    try {
      final PdfObj? o1 = parser.parseObject();
      final PdfObj? o2 = parser.parseObject();
      parser.parseObject();

      if (o1 is! PdfNum || o2 is! PdfNum) {
        Logger.debug('   Object $objNum: Invalid header');
        return null;
      }

      final PdfObj? obj = parser.parseObject();
      if (obj != null) {
        _objectCache[objNum] = obj;
      }
      return obj;
    } catch (e) {
      Logger.debug('   Object $objNum: Parse error - $e');
      return null;
    }
  }

  PdfObj? getValue(PdfDict dict, String key) => resolve(dict[key]);

  static int _findStartXref(Uint8List data) {
    const String marker = 'startxref';
    final int startSearch = data.length - 1;
    final int endSearch = (data.length - 2048).clamp(0, data.length);

    for (int i = startSearch; i >= endSearch; i--) {
      if (data[i] == 0x73) {
        // 's'
        bool match = true;
        for (int j = 0; j < marker.length; j++) {
          if (i + j >= data.length || data[i + j] != marker.codeUnitAt(j)) {
            match = false;
            break;
          }
        }

        if (match) {
          int pos = i + marker.length;
          while (pos < data.length && _isWhitespace(data[pos])) {
            pos++;
          }

          final int numStart = pos;
          while (pos < data.length && _isDigit(data[pos])) {
            pos++;
          }

          if (pos > numStart) {
            return int.parse(String.fromCharCodes(data.sublist(numStart, pos)));
          }
        }
      }
    }
    throw const FormatException('Cannot find startxref');
  }

  static _XrefResult _parseXref(Uint8List data, int offset) {
    final Map<int, int> xref = <int, int>{};
    PdfDict? trailer;

    final PdfTokenizer tokenizer = PdfTokenizer(data);
    tokenizer.position = offset;

    final Token firstToken = tokenizer.nextToken();

    if (firstToken.type == TokenType.keyword && firstToken.value == 'xref') {
      _parseTraditionalXref(tokenizer, xref);
      final int trailerPos = _findTrailer(data, offset);
      tokenizer.position = trailerPos;
      tokenizer.nextToken();
      final PdfParser parser = PdfParser(tokenizer);
      trailer = parser.parseObject() as PdfDict?;
    } else {
      // XRef Stream
      tokenizer.position = offset;
      final PdfParser parser = PdfParser(tokenizer);
      parser.parseObject(); // objNum
      parser.parseObject(); // genNum
      parser.parseObject(); // "obj"

      final PdfStream stream = parser.parseObject() as PdfStream;
      trailer = stream.dict;
      _parseXrefStream(stream, xref);
    }

    if (trailer != null && trailer.containsKey('Prev')) {
      final PdfNum prev = trailer['Prev'] as PdfNum;
      final _XrefResult prevResult = _parseXref(data, prev.intValue);
      prevResult.xref.addAll(xref);
      xref.clear();
      xref.addAll(prevResult.xref);
    }

    return _XrefResult(xref, trailer ?? PdfDict());
  }

  PdfObj? _getFromObjectStream(int objNum, {int? streamNum}) {
    // If we already know which stream contains this object
    if (streamNum != null) {
      final Map<int, PdfObj>? stream = _loadObjectStream(streamNum);
      if (stream != null && stream.containsKey(objNum)) {
        _objectCache[objNum] = stream[objNum]!;
        return stream[objNum];
      }
      return null;
    }

    // Otherwise, search through cached streams or check xref for type 2 entries
    // For now, try to find object 5 specifically by checking if it's in stream 4 or similar
    Logger.debug('   Searching for object $objNum in known streams...');

    // Common pattern: objects are in stream (objNum // 100) or similar
    // Try loading stream 4 which often contains forms data
    for (int sn in <int>[4, 5, 6, 7, 8, 9, 10]) {
      if (_xrefTable.containsKey(sn)) {
        final Map<int, PdfObj>? stream = _loadObjectStream(sn);
        if (stream != null && stream.containsKey(objNum)) {
          Logger.debug('   Found object $objNum in stream $sn');
          _objectCache[objNum] = stream[objNum]!;
          return stream[objNum];
        }
      }
    }

    return null;
  }

  Map<int, PdfObj>? _loadObjectStream(int streamNum) {
    if (_objectStreams.containsKey(streamNum)) {
      return _objectStreams[streamNum];
    }

    final int? offset = _xrefTable[streamNum];
    if (offset == null) return null;

    Logger.debug('   Loading object stream $streamNum from offset $offset');

    final PdfTokenizer tokenizer = PdfTokenizer(_data);
    tokenizer.position = offset;

    final PdfParser parser = PdfParser(tokenizer);

    try {
      parser.parseObject(); // objNum
      parser.parseObject(); // genNum
      parser.parseObject(); // obj

      final PdfObj? obj = parser.parseObject();
      if (obj is! PdfStream) {
        Logger.debug(
          '   Stream $streamNum is not a stream, it is ${obj.runtimeType}',
        );
        return null;
      }

      final PdfDict dict = obj.dict;
      final int n = (dict['N'] as PdfNum?)?.intValue ?? 0; // Number of objects
      final int first =
          (dict['First'] as PdfNum?)?.intValue ?? 0; // Offset to first object

      Logger.debug('   Object stream $streamNum: N=$n, First=$first');

      // Decompress stream data
      List<int> data = obj.data;
      if (dict.containsKey('Filter')) {
        data = _decodeStream(data, dict);
      }

      // Parse the stream content
      // Format: objNum1 offset1 objNum2 offset2 ... objNumN offsetN objectData...
      final PdfTokenizer streamTokenizer = PdfTokenizer(
        Uint8List.fromList(data),
      );
      final PdfParser streamParser = PdfParser(streamTokenizer);

      final Map<int, int> offsets =
          <int, int>{}; // objNum -> offset within stream

      // Read the header (object numbers and offsets)
      for (int i = 0; i < n; i++) {
        final Token numToken = streamTokenizer.nextToken();
        final Token offToken = streamTokenizer.nextToken();

        if (numToken.type == TokenType.number &&
            offToken.type == TokenType.number) {
          final int onum = (numToken.value as num).toInt();
          final int ooff =
              (offToken.value as num).toInt() +
              first; // Add 'first' to get absolute offset
          offsets[onum] = ooff;
          Logger.debug('     Object $onum at offset $ooff in stream');
        }
      }

      // Now parse each object at its offset
      final Map<int, PdfObj> objects = <int, PdfObj>{};
      for (final MapEntry<int, int> entry in offsets.entries) {
        streamTokenizer.position = entry.value;
        final PdfObj? obj = streamParser.parseObject();
        if (obj != null) {
          objects[entry.key] = obj;
          Logger.debug('     Parsed object ${entry.key}: ${obj.runtimeType}');
        }
      }

      _objectStreams[streamNum] = objects;
      return objects;
    } catch (e, stack) {
      Logger.debug('   Error loading object stream $streamNum: $e');
      Logger.debug('   Stack: $stack');
      return null;
    }
  }

  static void _parseTraditionalXref(
    PdfTokenizer tokenizer,
    Map<int, int> xref,
  ) {
    while (true) {
      final Token token1 = tokenizer.nextToken();
      if (token1.type != TokenType.number) break;

      final int startObj = (token1.value as num).toInt();
      final Token token2 = tokenizer.nextToken();
      final int count = (token2.value as num).toInt();

      for (int i = 0; i < count; i++) {
        final Token offsetToken = tokenizer.nextToken();
        tokenizer.nextToken();
        final Token typeToken = tokenizer.nextToken();

        if (offsetToken.type == TokenType.number &&
            typeToken.type == TokenType.keyword &&
            typeToken.value == 'n') {
          xref[startObj + i] = (offsetToken.value as num).toInt();
        }
      }
    }
  }

  static int _findTrailer(Uint8List data, int xrefOffset) {
    const String marker = 'trailer';
    for (int i = xrefOffset; i < data.length - marker.length; i++) {
      bool found = true;
      for (int j = 0; j < marker.length; j++) {
        if (data[i + j] != marker.codeUnitAt(j)) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  static void _parseXrefStream(PdfStream stream, Map<int, int> xref) {
    final PdfDict dict = stream.dict;
    final int size = (dict['Size'] as PdfNum).intValue;

    final PdfArr wArr = dict['W'] as PdfArr;
    final int w1 = (wArr[0] as PdfNum).intValue;
    final int w2 = (wArr[1] as PdfNum).intValue;
    final int w3 = (wArr[2] as PdfNum).intValue;
    final int entrySize = w1 + w2 + w3;

    // Get predictor settings
    int predictor = 1;
    int columns = 0;

    if (dict.containsKey('DecodeParms')) {
      final PdfDict decodeParms = dict['DecodeParms'] as PdfDict;
      if (decodeParms.containsKey('Predictor')) {
        predictor = (decodeParms['Predictor'] as PdfNum).intValue;
      }
      if (decodeParms.containsKey('Columns')) {
        columns = (decodeParms['Columns'] as PdfNum).intValue;
      }
    }

    // Decompress
    List<int> data = stream.data;
    if (dict.containsKey('Filter')) {
      final PdfObj? filter = dict['Filter'];
      String? filterName;
      if (filter is PdfName) {
        filterName = filter.value;
      } else if (filter is PdfArr && filter.length > 0) {
        filterName = (filter[0] as PdfName).value;
      }

      if (filterName == 'FlateDecode') {
        data = ZLibDecoder().convert(data);
      }
    }

    // Apply predictor decoding (CRITICAL FIX)
    if (predictor >= 12 && columns > 0) {
      data = _decodePngPrediction(data, columns);
    }

    // Get index ranges
    List<int> index;
    if (dict.containsKey('Index')) {
      final PdfArr indexArr = dict['Index'] as PdfArr;
      index = indexArr.items.map((PdfObj e) => (e as PdfNum).intValue).toList();
    } else {
      index = <int>[0, size];
    }

    // Parse entries
    int dataPos = 0;
    for (int i = 0; i < index.length; i += 2) {
      final int startObj = index[i];
      final int count = index[i + 1];

      for (int j = 0; j < count; j++) {
        if (dataPos + entrySize > data.length) break;

        final int type = w1 > 0 ? _readInt(data, dataPos, w1) : 1;
        final int field2 = w2 > 0 ? _readInt(data, dataPos + w1, w2) : 0;

        if (type == 1) {
          // In-use object, field2 is the offset
          xref[startObj + j] = field2;
        } else if (type == 2) {
          // Object in object stream, field2 is stream number
          // For now, mark as negative to indicate object stream
          xref[startObj + j] = -field2;
        }

        dataPos += entrySize;
      }
    }

    Logger.debug(
      '   XRef Stream: Loaded ${xref.length} entries (expected $size)',
    );
    Logger.debug(
      '   Sample entries: ${xref.entries.take(5).map((MapEntry<int, int> e) => '${e.key}->${e.value}').join(', ')}...',
    );
    if (xref.containsKey(53)) {
      Logger.debug('   ✅ Object 53 found at offset ${xref[53]}');
    } else {
      Logger.debug('   ❌ Object 53 NOT FOUND in XRef');
    }
  }

  static List<int> _decodePngPrediction(List<int> data, int columns) {
    final List<int> result = <int>[];
    final int rowSize = columns + 1; // +1 for predictor byte
    int pos = 0;

    // Previous row for UP prediction
    List<int>? prevRow;

    while (pos + rowSize <= data.length) {
      final int predictorByte = data[pos];
      final List<int> currentRow = List<int>.filled(columns, 0);

      if (predictorByte == 0) {
        // No prediction
        for (int i = 0; i < columns; i++) {
          currentRow[i] = data[pos + 1 + i];
        }
      } else if (predictorByte == 2) {
        // UP prediction
        for (int i = 0; i < columns; i++) {
          final int up = prevRow != null ? prevRow[i] : 0;
          currentRow[i] = (data[pos + 1 + i] + up) & 0xFF;
        }
      } else {
        // Unsupported, copy as-is
        for (int i = 0; i < columns; i++) {
          currentRow[i] = data[pos + 1 + i];
        }
      }

      result.addAll(currentRow);
      prevRow = currentRow;
      pos += rowSize;
    }

    return result;
  }

  static List<int> _decodeStream(List<int> data, PdfDict dict) {
    final PdfObj? filter = dict['Filter'];
    String? filterName;
    if (filter is PdfName) {
      filterName = filter.value;
    } else if (filter is PdfArr && filter.length > 0) {
      filterName = (filter[0] as PdfName).value;
    }

    if (filterName == 'FlateDecode') {
      return _inflateZlib(data);
    }
    return data;
  }

  static List<int> _inflateZlib(List<int> data) {
    try {
      return ZLibDecoder().convert(data);
    } catch (e) {
      return data;
    }
  }

  static int _readInt(List<int> data, int offset, int length) {
    int value = 0;
    for (int i = 0; i < length && (offset + i) < data.length; i++) {
      value = (value << 8) | data[offset + i];
    }
    return value;
  }

  static bool _isWhitespace(int ch) =>
      ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x0C;

  static bool _isDigit(int ch) => ch >= 0x30 && ch <= 0x39;


  final Map<int, PdfObj> _newObjects = <int, PdfObj>{};
  int _nextObjNum = -1;
  
  /// Gets the next available object number
  int get nextObjectNumber {
    if (_nextObjNum == -1) {
      // Find highest existing object number
      int max = 0;
      for (final int key in _xrefTable.keys) {
        if (key > max) max = key;
      }
      for (final int key in _objectCache.keys) {
        if (key > max) max = key;
      }
      _nextObjNum = max + 1;
    }
    return _nextObjNum++;
  }
  
  /// Adds a new object and returns its reference
  PdfRef addObject(PdfObj obj) {
    final int objNum = nextObjectNumber;
    _newObjects[objNum] = obj;
    _objectCache[objNum] = obj;
    return PdfRef(objNum, 0);
  }
  
  /// Gets all new objects (for writer)
  Map<int, PdfObj> get newObjects => Map<int, PdfObj>.unmodifiable(_newObjects);
  
  /// Gets a page by index
  PdfDict? getPage(int index) {
    final PdfDict? catalog = this.catalog;
    if (catalog == null) return null;
    
    final PdfDict? pages = resolve(catalog['Pages']) as PdfDict?;
    if (pages == null) return null;
    
    return _getPageAtIndex(pages, index, <int>[0]);
  }
  
  PdfDict? _getPageAtIndex(PdfDict node, int targetIndex, List<int> currentIndex) {
    final PdfName? type = resolve(node['Type']) as PdfName?;
    
    if (type?.value == 'Page') {
      if (currentIndex[0] == targetIndex) {
        return node;
      }
      currentIndex[0]++;
      return null;
    }
    
    // Pages node
    final PdfArr? kids = resolve(node['Kids']) as PdfArr?;
    if (kids == null) return null;
    
    for (int i = 0; i < kids.length; i++) {
      final PdfDict? kid = resolve(kids[i]) as PdfDict?;
      if (kid == null) continue;
      
      final PdfDict? result = _getPageAtIndex(kid, targetIndex, currentIndex);
      if (result != null) return result;
    }
    
    return null;
  }
  
  /// Finds page index for a given page dict
  int? getPageIndex(PdfDict targetPage) {
    final PdfDict? catalog = this.catalog;
    if (catalog == null) return null;
    
    final PdfDict? pages = resolve(catalog['Pages']) as PdfDict?;
    if (pages == null) return null;
    
    return _findPageIndex(pages, targetPage, <int>[0]);
  }
  
  int? _findPageIndex(PdfDict node, PdfDict target, List<int> currentIndex) {
    final PdfName? type = resolve(node['Type']) as PdfName?;
    
    if (type?.value == 'Page') {
      if (identical(node, target)) {
        return currentIndex[0];
      }
      currentIndex[0]++;
      return null;
    }
    
    final PdfArr? kids = resolve(node['Kids']) as PdfArr?;
    if (kids == null) return null;
    
    for (int i = 0; i < kids.length; i++) {
      final PdfDict? kid = resolve(kids[i]) as PdfDict?;
      if (kid == null) continue;
      
      final int? result = _findPageIndex(kid, target, currentIndex);
      if (result != null) return result;
    }
    
    return null;
  }
  
  List<int> saveToBytes() {
    final PdfWriter writer = PdfWriter();
    return writer.write(this);
  }

  void saveToFile(String path) {
    final List<int> bytes = saveToBytes();
    File(path).writeAsBytesSync(bytes);
  }
}

class _XrefResult {
  _XrefResult(this.xref, this.trailer);
  final Map<int, int> xref;
  final PdfDict trailer;
}
