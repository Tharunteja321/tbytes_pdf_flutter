// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

/// Base class for all PDF objects.
abstract class PdfObj {
  const PdfObj();
}

/// PDF null object.
class PdfNull extends PdfObj {
  const PdfNull();
  
  @override
  String toString() => 'null';
}

/// PDF boolean object.
class PdfBool extends PdfObj {
  const PdfBool(this.value);
  final bool value;
  
  @override
  String toString() => value.toString();
}

/// PDF number object (int or double).
class PdfNum extends PdfObj {
  const PdfNum(this.value);
  final num value;
  
  int get intValue => value.toInt();
  double get doubleValue => value.toDouble();
  
  @override
  String toString() => value.toString();
}

/// PDF string object.
class PdfStr extends PdfObj {
  const PdfStr(this.value);
  final String value;
  
  @override
  String toString() => '($value)';
}

/// PDF name object (like /Type, /Fields, etc).
class PdfName extends PdfObj {
  const PdfName(this.value);
  final String value;
  
  @override
  String toString() => '/$value';
  
  @override
  bool operator ==(Object other) =>
      other is PdfName && other.value == value;
  
  @override
  int get hashCode => value.hashCode;
}

/// PDF array object.
class PdfArr extends PdfObj {
  PdfArr([List<PdfObj>? items]) : items = items ?? <PdfObj>[];
  final List<PdfObj> items;
  
  int get length => items.length;
  PdfObj? operator [](int index) => 
      index >= 0 && index < items.length ? items[index] : null;
  
  void add(PdfObj obj) => items.add(obj);
  
  @override
  String toString() => '[${items.join(' ')}]';
}

/// PDF dictionary object.
class PdfDict extends PdfObj {
  PdfDict([Map<String, PdfObj>? entries]) 
      : entries = entries ?? <String, PdfObj>{};
  final Map<String, PdfObj> entries;
  
  PdfObj? operator [](String key) => entries[key];
  void operator []=(String key, PdfObj value) => entries[key] = value;
  
  bool containsKey(String key) => entries.containsKey(key);
  Iterable<String> get keys => entries.keys;
  
  /// Gets a value, resolving references if resolver is provided.
  PdfObj? get(String key, [PdfObj? Function(PdfRef)? resolver]) {
    final PdfObj? obj = entries[key];
    if (obj is PdfRef && resolver != null) {
      return resolver(obj);
    }
    return obj;
  }
  
  @override
  String toString() {
    final Iterable<String> pairs = entries.entries.map((MapEntry<String, PdfObj> e) => '/${e.key} ${e.value}');
    return '<<${pairs.join(' ')}>>';
  }
}

/// PDF stream object (dictionary + binary data).
class PdfStream extends PdfObj {
  PdfStream(this.dict, this.data);
  final PdfDict dict;
  final List<int> data;
  
  @override
  String toString() => '$dict stream[${data.length} bytes]';
}

/// PDF indirect reference (e.g., "5 0 R").
class PdfRef extends PdfObj {
  const PdfRef(this.objNum, this.genNum);
  final int objNum;
  final int genNum;
  
  @override
  String toString() => '$objNum $genNum R';
  
  @override
  bool operator ==(Object other) =>
      other is PdfRef && other.objNum == objNum && other.genNum == genNum;
  
  @override
  int get hashCode => objNum.hashCode ^ genNum.hashCode;
}