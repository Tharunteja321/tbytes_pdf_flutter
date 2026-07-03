// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'pdf_document.dart';
import 'pdf_objects.dart';
import 'internal/logger.dart';

class PdfDecryptor {
  PdfDecryptor(this._doc);

  final PdfDoc _doc;
  Uint8List? _encryptionKey;
  int _keyLength = 40;
  int _revision = 2;
  int? _encryptDictObjNum;

  bool get isEncrypted => _doc.trailer.containsKey('Encrypt');

  bool tryDecrypt([String password = '']) {
    if (!isEncrypted) return true;

    // Store the encrypt dict object number so we never try to decrypt it
    final PdfObj? encryptRef = _doc.trailer['Encrypt'];
    if (encryptRef is PdfRef) {
      _encryptDictObjNum = encryptRef.objNum;
    }

    final PdfDict? encryptDict = _doc.resolve(_doc.trailer['Encrypt']) as PdfDict?;
    if (encryptDict == null) return false;

    Logger.debug('Encrypt dict keys: ${encryptDict.keys.toList()}');

    final PdfName? filter = _doc.resolve(encryptDict['Filter']) as PdfName?;
    if (filter?.value != 'Standard') {
      Logger.debug('Unsupported encryption filter: ${filter?.value}');
      return false;
    }

    _revision = (_doc.resolve(encryptDict['R']) as PdfNum?)?.intValue ?? 2;
    _keyLength = (_doc.resolve(encryptDict['Length']) as PdfNum?)?.intValue ?? 40;

    Logger.debug('Encryption: R=$_revision, Length=$_keyLength bits');

    final PdfStr? oValue = _doc.resolve(encryptDict['O']) as PdfStr?;
    final PdfStr? uValue = _doc.resolve(encryptDict['U']) as PdfStr?;
    final PdfNum? pValue = _doc.resolve(encryptDict['P']) as PdfNum?;

    if (oValue == null || uValue == null || pValue == null) {
      Logger.debug('Missing encryption parameters');
      return false;
    }

    Logger.debug('O length: ${oValue.value.length}, U length: ${uValue.value.length}');
    Logger.debug('P value: ${pValue.intValue}');

    final PdfArr? idArr = _doc.trailer['ID'] as PdfArr?;
    if (idArr == null || idArr.length == 0) {
      Logger.debug('Missing document ID');
      return false;
    }
    final String docId = (idArr[0] as PdfStr).value;
    Logger.debug('Doc ID length: ${docId.length}');

    _encryptionKey = _computeEncryptionKey(
      password,
      oValue.value,
      pValue.intValue,
      docId,
      encryptDict,
    );

    Logger.debug('Computed key length: ${_encryptionKey?.length}');

    if (_verifyUserPassword(uValue.value, docId)) {
      Logger.debug('✅ Decryption key computed successfully');
      return true;
    }

    Logger.debug('❌ Password verification failed');

    final PdfNum? vValue = _doc.resolve(encryptDict['V']) as PdfNum?;
    if (vValue != null) {
      Logger.debug('Encryption V=${vValue.intValue}');
    }

    _encryptionKey = null;
    return false;
  }

  Uint8List _computeEncryptionKey(
    String password,
    String oValue,
    int permissions,
    String docId,
    PdfDict encryptDict,
  ) {
    final Uint8List paddedPassword = _padPassword(password);

    final List<int> data = <int>[
      ...paddedPassword,
      ...oValue.codeUnits,
      permissions & 0xFF,
      (permissions >> 8) & 0xFF,
      (permissions >> 16) & 0xFF,
      (permissions >> 24) & 0xFF,
      ...docId.codeUnits,
    ];

    // Per PDF spec section 3.5.2 Algorithm 2:
    // If R >= 3 and EncryptMetadata is false, append 0xFFFFFFFF
    if (_revision >= 3) {
      bool encryptMetadata = true; // spec default is true when absent
      final PdfObj? encMeta = encryptDict['EncryptMetadata'];
      if (encMeta is PdfBool) {
        encryptMetadata = encMeta.value;
      } else if (encMeta is PdfName && encMeta.value == 'false') {
        encryptMetadata = false;
      }
      Logger.debug('EncryptMetadata: type=${encMeta.runtimeType}, resolved=$encryptMetadata');
      if (!encryptMetadata) {
        data.addAll(<int>[0xFF, 0xFF, 0xFF, 0xFF]);
        Logger.debug('✅ Appended 0xFFFFFFFF (EncryptMetadata=false)');
      }
    }

    Digest hash = md5.convert(data);
    final int keyBytes = (_keyLength ~/ 8).clamp(1, 16);

    if (_revision >= 3) {
      for (int i = 0; i < 50; i++) {
        hash = md5.convert(hash.bytes.sublist(0, keyBytes));
      }
    }

    return Uint8List.fromList(hash.bytes.sublist(0, keyBytes));
  }

  bool _verifyUserPassword(String uValue, String docId) {
    if (_encryptionKey == null) return false;

    if (_revision == 2) {
      final Uint8List encrypted = _rc4Encrypt(_encryptionKey!, _paddingBytes);
      return _compareBytes(encrypted, Uint8List.fromList(uValue.codeUnits));
    } else {
      // R=3 and R=4: MD5 of padding + docId, then 20 rounds of RC4
      final Digest hash = md5.convert(<int>[..._paddingBytes, ...docId.codeUnits]);
      Uint8List result = Uint8List.fromList(hash.bytes);

      for (int i = 0; i < 20; i++) {
        final Uint8List modKey = Uint8List(_encryptionKey!.length);
        for (int j = 0; j < _encryptionKey!.length; j++) {
          modKey[j] = _encryptionKey![j] ^ i;
        }
        result = _rc4Encrypt(modKey, result);
      }

      // Compare only first 16 bytes — rest are arbitrary per spec
      return _compareBytes(
        result,
        Uint8List.fromList(uValue.codeUnits.take(16).toList()),
      );
    }
  }

  bool _isAesEncryption() {
    final PdfDict? encryptDict = _doc.resolve(_doc.trailer['Encrypt']) as PdfDict?;
    if (encryptDict == null) return false;
    final PdfDict? cf = _doc.resolve(encryptDict['CF']) as PdfDict?;
    if (cf == null) return false;
    final PdfDict? stdCf = _doc.resolve(cf['StdCF']) as PdfDict?;
    if (stdCf == null) return false;
    final PdfName? cfm = _doc.resolve(stdCf['CFM']) as PdfName?;
    return cfm?.value == 'AESV2' || cfm?.value == 'AESV3';
  }

  // isStream=true  → AES-CBC for stream data
  // isStream=false → RC4 for string values
  Uint8List decryptData(int objNum, int genNum, Uint8List data, {bool isStream = false}) {
    if (_encryptionKey == null) return data;

    // Never decrypt the encrypt dict itself — causes stack overflow and wrong results
    if (_encryptDictObjNum != null && objNum == _encryptDictObjNum) {
      return data;
    }

    final bool isAes = _isAesEncryption();

    final List<int> objKey = <int>[
      ..._encryptionKey!,
      objNum & 0xFF,
      (objNum >> 8) & 0xFF,
      (objNum >> 16) & 0xFF,
      genNum & 0xFF,
      (genNum >> 8) & 0xFF,
      // "sAlT" appended only for AES stream decryption
      if (isAes && isStream) ...<int>[0x73, 0x41, 0x6C, 0x54],
    ];

    final Digest hash = md5.convert(objKey);
    final int keyLen = (_encryptionKey!.length + 5 + (isAes && isStream ? 4 : 0))
        .clamp(0, 16);
    final Uint8List key = Uint8List.fromList(hash.bytes.sublist(0, keyLen));

    if (isAes && isStream) {
      return _aesDecrypt(key, data);
    }
    return _rc4Encrypt(key, data);
  }

  Uint8List _aesDecrypt(Uint8List key, Uint8List data) {
    if (data.length < 16) return data;

    final Uint8List iv = data.sublist(0, 16);
    final Uint8List ciphertext = data.sublist(16);

    final enc.Key aesKey = enc.Key(key);
    final enc.IV aesIV = enc.IV(iv);
    final enc.Encrypter encrypter = enc.Encrypter(
      enc.AES(aesKey, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );

    return Uint8List.fromList(
      encrypter.decryptBytes(enc.Encrypted(ciphertext), iv: aesIV),
    );
  }

  String decryptString(int objNum, int genNum, String str) {
    final Uint8List decrypted = decryptData(
      objNum,
      genNum,
      Uint8List.fromList(str.codeUnits),
      isStream: false, // strings always use RC4
    );
    return String.fromCharCodes(decrypted);
  }

  Uint8List _rc4Encrypt(Uint8List key, Uint8List data) {
    final List<int> s = List<int>.generate(256, (int i) => i);
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final int temp = s[i];
      s[i] = s[j];
      s[j] = temp;
    }

    final Uint8List result = Uint8List(data.length);
    int i = 0;
    j = 0;
    for (int k = 0; k < data.length; k++) {
      i = (i + 1) & 0xFF;
      j = (j + s[i]) & 0xFF;
      final int temp = s[i];
      s[i] = s[j];
      s[j] = temp;
      result[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF];
    }

    return result;
  }

  Uint8List _padPassword(String password) {
    final List<int> bytes = password.codeUnits.take(32).toList();
    while (bytes.length < 32) {
      bytes.add(_paddingBytes[bytes.length]);
    }
    return Uint8List.fromList(bytes);
  }

  bool _compareBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static final Uint8List _paddingBytes = Uint8List.fromList(<int>[
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ]);
}