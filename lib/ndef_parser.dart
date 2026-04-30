import 'dart:typed_data';

typedef NdefLogger = void Function(String msg);

class NdefRecord {
  final String mimeType;
  final Uint8List payload;
  const NdefRecord(this.mimeType, this.payload);
}

List<NdefRecord> parseNdef(Uint8List data, {NdefLogger? log}) {
  void dbg(String msg) => log?.call('[NDEF] $msg');
  try {
    dbg('data length=${data.length}, first bytes: ${data.take(16).map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')}');

    int startOffset = 0;
    if (data.length > 12 && data[0] != 0xE1) {
      for (int i = 0; i < data.length - 4 && i < 16; i++) {
        if (data[i] == 0xE1 &&
            (data[i + 1] == 0x10 || data[i + 1] == 0x11 || data[i + 1] == 0x40)) {
          startOffset = i;
          break;
        }
      }
    }
    dbg('CC search → startOffset=$startOffset');

    int pos = startOffset;
    if (pos + 4 > data.length) { dbg('Too short for CC block'); return []; }
    if (data[pos] != 0xE1) { dbg('CC magic not found (got 0x${data[pos].toRadixString(16)})'); return []; }
    dbg('CC bytes: ${data.sublist(pos, pos+4).map((b)=>b.toRadixString(16).padLeft(2,"0")).join(" ")}');
    pos += 4;

    final records = <NdefRecord>[];

    while (pos + 1 < data.length) {
      final tag = data[pos++];
      dbg('TLV tag=0x${tag.toRadixString(16)} at pos=${pos-1}');
      if (tag == 0xFE) { dbg('Terminator found'); break; }

      int tlvLen = data[pos++];
      if (tlvLen == 0xFF) {
        if (pos + 2 > data.length) break;
        tlvLen = (data[pos] << 8) | data[pos + 1];
        pos += 2;
      }
      dbg('  TLV len=$tlvLen');

      if (tag == 0x03) {
        if (pos + tlvLen > data.length) { dbg('  NDEF TLV truncated (need ${pos+tlvLen}, have ${data.length})'); break; }
        final ndefData = data.sublist(pos, pos + tlvLen);
        pos += tlvLen;
        dbg('  Parsing NDEF message (${ndefData.length} bytes)');
        _parseNdefMessage(ndefData, records, log: log);
      } else {
        dbg('  Skipping non-NDEF TLV tag=0x${tag.toRadixString(16)}');
        pos += tlvLen;
      }
    }
    dbg('Found ${records.length} NDEF record(s)');
    return records;
  } catch (e) {
    log?.call('[NDEF] Exception: $e');
    return [];
  }
}

void _parseNdefMessage(Uint8List ndefData, List<NdefRecord> out, {NdefLogger? log}) {
  void dbg(String msg) => log?.call('[NDEF] $msg');
  int offset = 0;
  while (offset < ndefData.length - 2) {
    final header = ndefData[offset++];
    final tnf      = header & 0x07;
    final srFlag   = (header >> 4) & 0x01;
    final ilFlag   = (header >> 3) & 0x01;

    dbg('  record header=0x${header.toRadixString(16)} TNF=$tnf SR=$srFlag IL=$ilFlag');

    if (offset >= ndefData.length) break;
    final typeLen = ndefData[offset++];

    int payloadLen;
    if (srFlag == 1) {
      if (offset >= ndefData.length) break;
      payloadLen = ndefData[offset++];
    } else {
      if (offset + 4 > ndefData.length) break;
      payloadLen = (ndefData[offset] << 24) |
          (ndefData[offset + 1] << 16) |
          (ndefData[offset + 2] << 8) |
          ndefData[offset + 3];
      offset += 4;
    }

    int idLen = 0;
    if (ilFlag == 1) {
      if (offset >= ndefData.length) break;
      idLen = ndefData[offset++];
    }

    dbg('  typeLen=$typeLen payloadLen=$payloadLen idLen=$idLen');

    if (offset + typeLen + idLen + payloadLen > ndefData.length) {
      dbg('  record overflows buffer \u2013 truncated?');
      break;
    }

    final mimeType = String.fromCharCodes(
        ndefData.sublist(offset, offset + typeLen));
    offset += typeLen;
    offset += idLen;

    final payload = ndefData.sublist(offset, offset + payloadLen);
    offset += payloadLen;

    dbg('  mimeType="$mimeType" payloadPreview="${String.fromCharCodes(payload.take(40).where((b)=>b>=0x20&&b<0x7F))}"');

    if (tnf == 0x02) {
      out.add(NdefRecord(mimeType, payload));
    } else {
      dbg('  skipped (TNF=$tnf, expected 0x02 for MIME)');
    }
  }
}
