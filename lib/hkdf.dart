import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// HKDF-SHA256 implementation matching processor.py __hkdf_create_key
// Python: HKDF(SHA256, length=96, salt=key, info=b"RFID-A\0").derive(uid)

Uint8List _hmacSha256(List<int> key, List<int> data) {
  final hmac = Hmac(sha256, key);
  return Uint8List.fromList(hmac.convert(data).bytes);
}

Uint8List hkdfExpand(List<int> prk, List<int> info, int length) {
  final output = <int>[];
  var t = <int>[];
  int counter = 1;
  while (output.length < length) {
    t = _hmacSha256(prk, [...t, ...info, counter]);
    output.addAll(t);
    counter++;
  }
  return Uint8List.fromList(output.sublist(0, length));
}

Uint8List hkdfExtract(List<int> salt, List<int> ikm) {
  return _hmacSha256(salt, ikm);
}

List<Uint8List> deriveKeys(Uint8List uid, {required String saltHex}) {
  final saltBytes = _hexToBytes(saltHex);
  final info = [...'RFID-A'.codeUnits, 0]; // "RFID-A\0"

  final prk = hkdfExtract(saltBytes, uid);
  final okm = hkdfExpand(prk, info, 6 * 16);

  return List.generate(16, (i) => okm.sublist(i * 6, (i + 1) * 6));
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}
