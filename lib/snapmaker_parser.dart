// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'generic_filament.dart';

// All byte offsets: section*64 + block*16 + byte
const _kVendorPos       = 0*64 + 1*16 + 0;   const _kVendorLen       = 16;
const _kMainTypePos     = 1*64 + 0*16 + 2;
const _kSubTypePos      = 1*64 + 0*16 + 4;
const _kColorNumsPos    = 1*64 + 0*16 + 8;
const _kAlphaPos        = 1*64 + 0*16 + 9;
const _kRgb1Pos         = 1*64 + 1*16 + 0;
const _kRgb2Pos         = 1*64 + 1*16 + 3;
const _kRgb3Pos         = 1*64 + 1*16 + 6;
const _kRgb4Pos         = 1*64 + 1*16 + 9;
const _kRgb5Pos         = 1*64 + 1*16 + 12;
const _kDiameterPos     = 2*64 + 0*16 + 0;
const _kWeightPos       = 2*64 + 0*16 + 2;
const _kDryTempPos      = 2*64 + 1*16 + 0;
const _kDryTimePos      = 2*64 + 1*16 + 2;
const _kHotMaxPos       = 2*64 + 1*16 + 4;
const _kHotMinPos       = 2*64 + 1*16 + 6;
const _kBedTempPos      = 2*64 + 1*16 + 10;
const _kSkuPos          = 1*64 + 2*16 + 0;
const _kLengthPos       = 2*64 + 0*16 + 4;
const _kMfgDatePos      = 2*64 + 2*16 + 0;   const _kMfgDateLen      = 8;
const _kRsaVerPos       = 2*64 + 2*16 + 8;

const _kMainTypes = <int, String>{
  1: 'PLA', 2: 'PETG', 3: 'ABS', 4: 'TPU', 5: 'PVA',
};
const _kSubTypes = <int, String>{
  1: 'Basic', 2: 'Matte', 3: 'SnapSpeed', 4: 'Silk',
  5: 'Support', 6: 'HF', 7: '95A', 8: '95A HF',
};

// 10 RSA-2048 public keys (PKCS#8 DER, converted from PEM at build time via the
// _parsePemKey helper below).
const _kRsaPemKeys = <int, String>{
  0: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA8oEF7YuKO863TbUxnrvY
H1JFrvCnMapm8Ho952KlfNWbf6IEDMlX6QJpBuvUkrkjWpLJJQurIWL3KFeLUhCh
POrYdiGrdsUlp4YO037iLSlgmzo1dUdgbawAcGox1PvR/Naw5ADibubO2rN49WQR
+BkxxigvoWHSFetaoMCswQ5B/niq3byhzktgmWOcv71F4yFwcxivF8R+s0gSBL4i
/1zNeSUZkbvP4/T0B08i3D+e6fl9xpCnINZ3P9OWcx+p3SB2o4TdmAeKV4hkT9n7
o+/OWr92fx6qbiNKJr04oMhrRsFK6w7hitp2n8RGS64w9lhtplnBgxtbgxAYyUnp
qwIDAQAB
-----END RSA PUBLIC KEY-----''',
  1: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA8nbtQNABbc5PkyzI0A5m
VH/E8y23Wld0iykvTOoBYJOrPwJDmXsnSyyX84Nv6voSr8FYv3Fb2SqSdOgQLFqp
BXvntXew8rPpq5Ll8gSzLRxE1VmEOVtZWCTJ4Wxwwi79rrFmpa/nAtUeYZIGiiud
w2MzCHXW5G3c1FWhQ0C8vUUMfBQXmGnoHGsul6R8xld6CDCWY8ia/FvfR+KCtMRn
VYyYguYsq4rODWJHiFCOef4FZconUR3RTh0ojvq78CsHk94goxidWzZoKcVnvWhh
bOixTjU37W4JDECEOui3ObMMvJkzxkZo1irlAH7jTiPqhP94U/JbRDpBlHOOn67b
GQIDAQAB
-----END RSA PUBLIC KEY-----''',
  2: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxZQPYewwMFaPlcEHq+SH
QS1C1NhVmAaY56qxLyHJ4aNc2iWdCx4/9ZKY4CL6xkeCD88Zndv/xzImplRdoAzo
whD47Vm4iuq8+NqHUI8na6ISd+MZ/O6/eo/ggaEZBX8lR+Yf0qfWtntsI9flUOoJ
mq1IXvNXqOxflUmPyffT40QSkAN4Rr3scB3ozlxuJZehWM/lUmZ1H5PQDwAqsM0T
Rj6ChzVmUbSvwEvbDTwpXkpMA0C5//OW0T//IKDEBYxEl928vYbraLRDRIetgdaD
o+77+ztfOv4AyP/ipikprHwIWi7yga5KUXq/XpNPy6cPISZD+/LBUJBxLELspREP
rQIDAQAB
-----END RSA PUBLIC KEY-----''',
  3: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvK8cJyeFeTkFgkSLCCAg
EgR9KAvIHmvK8CRdtn+W6PiIbN04MFIg8jiYW/3fq+AcBFFMo+HtR2gym8JNVx2I
RDI4WdfbR/0gaIHjOQ41OwlXmqqSkDsFmjxVI6bDRZYpHkOfkC+9Vi1Aii4l/Yq9
O7s+2j4zP9GoUWWJPb3mW07Vu+EnHB/XIuaoDJVQAS+ov3xTotCeKdcdgySnNP5g
kOvWUvWtwNQldCRcQ0eo3j5RO+4J4IRK2J8q7BrdV/gbJUE/BBPIOuURPLzNJJO3
wgx4PEwlb5uYEUL35ARL7NzL8ZOxebzs5H4tXuWrBhALw6O33Tfg3TmTmwR2JUpv
7QIDAQAB
-----END RSA PUBLIC KEY-----''',
  4: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvafhk7Bdb3F+5B9w7YXv
chrNzl09QkZc27NLxL0ViRitGQhX9KC/xVg+XkBGI8XfioAwYkJ3jYgwmci5gJOL
ofPyNXcFtvtzq2NZNuDZY26krrXLORhS1o8ue92RB2gM92Rc2heWVrsvLycNl2Qz
OUjUEGmWpSMo98xIsgkTZJ4aYxWVN86yqknOcHVpTmcr5SBRB90K9hTRtsaMD97O
FYVc7AA/TGwqFJOnXXzWczWtg7kUY2vqCHwsvKs3G/EIFKOIe1n37V94OcxHTySC
co9Kc6Y0bGFIwIruinH1WkFVt6TAzo+0ZdZy5Sq493AG9y1RZ5nYj5qUmc1PMmrD
gwIDAQAB
-----END RSA PUBLIC KEY-----''',
  5: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxWdxd7qeouSFbZ2Sldv3
apDrgAupOYiDRkO85C+qkZaezOzqW0EsOV0x7nG/smw++TRfHyGIK4gXCdg1JfNR
WYjqckRdnLYMzGdDk24VV5Bbrsgska0v0Oy1ucz3CYu+F22ais00OqK0MY0B96MI
/B/0pRSTAIyxvC6LjhHy8DYyPdqNF9EMikKfAfcn7ytsH1PoSSGVtrZqyNe5OLrW
yAw+FQsTg/VFJcYxPTQJ1ymwQmDCdKgApe3PVajyYswoIA7R0S8ujau0aAFEO3dU
GDEwjOnaHfwFlg3OKMFJTxc2sl/WEB8xtWuKl0Guf0VnzWJ6noxqf/DiaN1fuHG0
AwIDAQAB
-----END RSA PUBLIC KEY-----''',
  6: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqF+YJNHLHC6c25oTDgNg
liahUxWBPSkgght1/gJu5vBRDKWEn6i/RuKAFdTOsH+Hlvr5qWms7bBUHx78UMF+
FF1Nq9tb4jhFuqq4HWsBBjNnU6O0JhFTjKJU2nudmphXlpdLQfcKSIYMQe795GHL
izh8WsNTcTHNNBkjhi7y4c4RUqnJso0L6vrf0B3EB/9DDUJitrwfw+1/OrKOEVEP
624sEa802cHfb+BG9zKBXjFwzYCYF9gWey9yeA3UA7EYmPpqA1lqNv8m0r7YjZ4n
uGBDjs+AXaGtdqrW3IUtkUF2vWwNSRncbcXi3mNfzslrtPhsDVAFki4vDSw7yNht
2wIDAQAB
-----END RSA PUBLIC KEY-----''',
  7: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuKWRCTTgxPltfflWHdhu
2ITxWC/LTEl7OtatNWFhMFQZF2J5SN/45bjH6xIPTcDglTSl2/UMC1D/ugiq+j0z
dGSdE7xn3ZSzLTMCwgRkvXmd8aQgafBYbB7E6oAgus+6lRXZPwnMfZAe0yaJNHyt
1Wd8ZUlRY7BHSPPtmG1liVEzxoTb6urB6mK49r24+oC7xa65q5NSdlZWSTeaK4Xt
DVVDiwe+uubNTm59KnVAKgBMNd3qN942pH6fo/dBz++BzJVEG/qJewHUTGZAeIl+
CgqhSEbmEIgolsDgaKY99ZWa2FWJdo+ohYhmjc92TyB9kWw6yIwez+tlRUkssLGt
SwIDAQAB
-----END RSA PUBLIC KEY-----''',
  8: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAt7XOTs6P2xB8v8/xWVdR
wVefphRDXSuv74RObtr0pwLTc7BytkcDw8r60BNPv9hGDpW2S1szxqS8x4EaOHP7
81qNpIUULlUdXxty1RvpSdfRb044kpwl7A/s4OEakkyJZF1ed+Qte1FqOFDDIZ+l
g+Co8FjOwWixoSyIlR22mEP7r6Y98GL5tnSohkVoGAgEipswWb6549mssjZmES+J
hB0axY6Dl/LlDYxN6jjUZwSIo7bw0GXGm9ScW2qTVaT1m2A9etpD6OIG+iQVLQqP
whVBs5q0o/EM4nBN88RBsF2OmfkcZPJ2NdX6o3qx+pCZ9NDgkHjGDZdnGEnM5Lu2
dwIDAQAB
-----END RSA PUBLIC KEY-----''',
  9: '''-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz/d5C5FpqlcF7NbUEvBN
fiDJWH0BF63PEwHPiX+cS6l+q4NqqYI167u1pGkZGJV1njgGYFTM08x2KO7/bk6o
CWcGuKWNM8Tp1+tv3XioNGVCnIpHmdUx5F9qcXlPtDx74wQk/+JZLQ/sLnLvHcV3
YTaz55fpyzVUHkgXusdVynSyAt3ywWWQRcjp3sspGa/udC0j6LCvrzqLACv3gMGA
Id0b6REzjSn03UzkwBIwSb8DszieeNhaCOK4M/TxPFNyrhQRYcAvhiZJu+tylqJs
VP+gaWFvElFeFkxcHvYXHdJPlJLjYeT51hm/pdll26yYLhpeBa0inHwSqv4D3jFZ
PQIDAQAB
-----END RSA PUBLIC KEY-----''',
};

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Derives the two 16-sector key sets (A and B) used to authenticate a
/// Snapmaker Mifare Classic 1K tag, given the first 4 bytes of the UID and
/// the hex-encoded salt.
List<List<Uint8List>> snapmakerDeriveKeys(Uint8List uid4, String saltHex) {
  final saltBytes = _hexToBytes(saltHex);
  final keysA = _hkdfKeys(uid4, saltBytes.sublist(0, 25), 'a');
  final keysB = _hkdfKeys(uid4, saltBytes, 'b');
  return [keysA, keysB];
}

GenericFilament? parseSnapmakerTag(Uint8List data, {
  String tagUid = '',
  List<Uint8List>? keysA,
  List<Uint8List>? keysB,
}) {
  if (data.length != 1024) { print('Snapmaker: data length ${data.length} != 1024'); return null; }

  if (!_verifySignature(data, keysA: keysA, keysB: keysB)) { print('Snapmaker: signature verification failed'); return null; }

  final vendor       = _readAscii(data, _kVendorPos, _kVendorLen);
  final mainTypeCode = _readU16LE(data, _kMainTypePos);
  final subTypeCode  = _readU16LE(data, _kSubTypePos);

  final mainType = _kMainTypes[mainTypeCode];
  final subType  = _kSubTypes[subTypeCode];
  print('Snapmaker: vendor=$vendor mainTypeCode=$mainTypeCode subTypeCode=$subTypeCode');
  if (mainType == null || subType == null) { print('Snapmaker: unknown type codes'); return null; }

  final alpha     = 0xFF - data[_kAlphaPos];
  final colorNums = data[_kColorNumsPos].clamp(0, 5);

  int readRgb(int pos) =>
      (data[pos] << 16) | (data[pos + 1] << 8) | data[pos + 2];

  final rgbPositions = [_kRgb1Pos, _kRgb2Pos, _kRgb3Pos, _kRgb4Pos, _kRgb5Pos];
  final colors = <int>[
    for (int i = 0; i < colorNums; i++)
      (alpha << 24) | readRgb(rgbPositions[i]),
  ];
  if (colors.isEmpty) colors.add((alpha << 24) | readRgb(_kRgb1Pos));

  final sku        = _readU32LE(data, _kSkuPos);
  final length     = _readU16LE(data, _kLengthPos);
  final mfgDate    = _readAscii(data, _kMfgDatePos, _kMfgDateLen);
  final diameter   = _readU16LE(data, _kDiameterPos) / 100.0;
  final weight     = _readU16LE(data, _kWeightPos).toDouble();
  final dryTemp    = _readU16LE(data, _kDryTempPos).toDouble();
  final dryTime    = _readU16LE(data, _kDryTimePos).toDouble();
  final hotMax     = _readU16LE(data, _kHotMaxPos).toDouble();
  final hotMin     = _readU16LE(data, _kHotMinPos).toDouble();
  final bed        = _readU16LE(data, _kBedTempPos).toDouble();

  return GenericFilament(
    sourceProcessor: 'snapmaker',
    uniqueId: 'snapmaker:$vendor:$mainType:$subType:${colors.first.toRadixString(16)}:$sku:${length}m:$mfgDate',
    manufacturer: vendor,
    type: mainType,
    modifiers: [subType],
    colors: colors,
    diameterMm: diameter,
    weightGrams: weight,
    hotendMinTemp: hotMin,
    hotendMaxTemp: hotMax,
    bedTemp: bed,
    dryingTemp: dryTemp,
    dryingTimeHours: dryTime,
    manufacturingDate: mfgDate,
    tagUid: tagUid,
  );
}

// ---------------------------------------------------------------------------
// RSA signature verification
// ---------------------------------------------------------------------------

bool _verifySignature(Uint8List data, {List<Uint8List>? keysA, List<Uint8List>? keysB}) {
  final rsaVer = data[_kRsaVerPos] | (data[_kRsaVerPos + 1] << 8);
  print('Snapmaker: RSA key version = $rsaVer');
  final pem = _kRsaPemKeys[rsaVer];
  if (pem == null) { print('Snapmaker: no RSA key for version $rsaVer'); return false; }

  // Reassemble the 256-byte signature scattered across sectors 10-15
  final sigBytes = BytesBuilder();
  for (int i = 0; i < 6; i++) {
    sigBytes.add(data.sublist((10 + i) * 64, (10 + i) * 64 + 48));
  }
  final signature = sigBytes.toBytes().sublist(0, 256);

  // NFC zeroes out key A/B bytes when reading sector trailers.
  // Reconstruct the original trailer bytes from the derived keys before hashing.
  final msgBuf = Uint8List.fromList(data.sublist(0, 640));
  if (keysA != null && keysB != null) {
    for (int s = 0; s < 10; s++) {
      final trailerOff = s * 64 + 48;
      msgBuf.setRange(trailerOff,       trailerOff + 6,  keysA[s]); // key A
      msgBuf.setRange(trailerOff + 10,  trailerOff + 16, keysB[s]); // key B
    }
  }
  final message = msgBuf;
  print('Snapmaker: sig[0..3]=${signature.take(4).map((b)=>b.toRadixString(16).padLeft(2,'0')).join()} msg len=${message.length}');

  try {
    final key = _parsePemKey(pem);
    // SHA-256 DigestInfo OID for pointycastle RSASigner
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(false, PublicKeyParameter<RSAPublicKey>(key));
    final result = signer.verifySignature(message, RSASignature(signature));
    print('Snapmaker: RSA verify result = $result');
    return result;
  } catch (e) {
    print('Snapmaker: RSA exception: $e');
    return false;
  }
}

// Manual DER TLV parser — avoids pointycastle ASN1 bugs with large integers.
// Handles PKCS#1 (BEGIN RSA PUBLIC KEY): SEQUENCE { INTEGER, INTEGER }
// and SPKI (BEGIN PUBLIC KEY): SEQUENCE { SEQUENCE{OID,NULL}, BIT STRING { PKCS#1 } }
RSAPublicKey _parsePemKey(String pem) {
  final lines = pem.split('\n')
    .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
    .join();
  final der = Uint8List.fromList(
    Uri.parse('data:application/octet-stream;base64,$lines')
        .data!.contentAsBytes());

  // Returns (value_bytes, next_offset) for a TLV at der[offset]
  (Uint8List, int) readTlv(Uint8List d, int offset) {
    offset++; // skip tag byte
    int len;
    if (d[offset] & 0x80 == 0) {
      len = d[offset++];
    } else {
      final numBytes = d[offset++] & 0x7F;
      len = 0;
      for (int i = 0; i < numBytes; i++) { len = (len << 8) | d[offset++]; }
    }
    return (Uint8List.sublistView(d, offset, offset + len), offset + len);
  }

  BigInt readInt(Uint8List bytes) {
    // Strip leading zero padding byte from DER positive integer
    int start = 0;
    while (start < bytes.length - 1 && bytes[start] == 0) { start++; }
    BigInt result = BigInt.zero;
    for (int i = start; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  // Read outer SEQUENCE
  final (seqBytes, _) = readTlv(der, 0);

  // Check first byte inside: 0x02 = INTEGER (PKCS#1), 0x30 = SEQUENCE (SPKI)
  Uint8List pkcs1;
  if (seqBytes[0] == 0x30) {
    // SPKI: skip inner SEQUENCE (algorithm), then read BIT STRING
    final (_, afterAlg) = readTlv(seqBytes, 0);
    final (bitStrBytes, _) = readTlv(seqBytes, afterAlg);
    // BIT STRING has a leading unused-bits byte, skip it
    pkcs1 = Uint8List.sublistView(bitStrBytes, 1);
    // pkcs1 is itself a SEQUENCE, unwrap it
    final (innerSeq, _) = readTlv(pkcs1, 0);
    pkcs1 = innerSeq;
  } else {
    // PKCS#1: seqBytes IS the SEQUENCE content already
    pkcs1 = seqBytes;
  }

  // Read modulus INTEGER then exponent INTEGER from pkcs1 content
  final (modBytes, nextOff) = readTlv(pkcs1, 0);
  final (expBytes, _)       = readTlv(pkcs1, nextOff);

  return RSAPublicKey(readInt(modBytes), readInt(expBytes));
}

// ---------------------------------------------------------------------------
// HKDF key derivation (Snapmaker variant)
// ---------------------------------------------------------------------------

List<Uint8List> _hkdfKeys(Uint8List ikm, Uint8List salt, String keyType) {
  // Strip trailing null byte from salt if present (matching Python behaviour)
  final s = (salt.isNotEmpty && salt.last == 0) ? salt.sublist(0, salt.length - 1) : salt;
  final prk = Uint8List.fromList(
    Hmac(sha256, s).convert(ikm).bytes);

  return List.generate(16, (i) {
    final info = 'key_${keyType}_$i'.codeUnits;
    final okm  = <int>[];
    var t = <int>[];
    int counter = 1;
    while (okm.length < 6) {
      t = Hmac(sha256, prk).convert([...t, ...info, counter]).bytes;
      okm.addAll(t);
      counter++;
    }
    return Uint8List.fromList(okm.sublist(0, 6));
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Numeric fields: little-endian (Python reversed=True slice then big-endian int = LE)
int _readU16LE(Uint8List d, int pos) => d[pos] | (d[pos + 1] << 8);
int _readU32LE(Uint8List d, int pos) =>
    d[pos] | (d[pos + 1] << 8) | (d[pos + 2] << 16) | (d[pos + 3] << 24);

String _readAscii(Uint8List d, int pos, int len) =>
    String.fromCharCodes(d.sublist(pos, pos + len).takeWhile((b) => b != 0));

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
