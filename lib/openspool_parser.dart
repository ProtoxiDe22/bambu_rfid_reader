import 'dart:convert';
import 'dart:typed_data';
import 'generic_filament.dart';
import 'ndef_parser.dart';
export 'ndef_parser.dart' show NdefLogger;

const _openspoolBedTemps = <String, double>{
  'PLA': 60, 'PETG': 70, 'ABS': 100, 'TPU': 50, 'NYLON': 100,
};
const _openspoolDryTemps = <String, double>{
  'PLA': 50, 'PETG': 65, 'ABS': 80, 'TPU': 70, 'NYLON': 80,
};

GenericFilament? parseOpenspoolTag(Uint8List data,
    {String tagUid = '', NdefLogger? log, Uint8List? preloadedPayload}) {
  // If a pre-extracted payload is provided (e.g. from nfc_manager's cached NDEF),
  // skip raw NDEF parsing and go straight to JSON decoding.
  if (preloadedPayload != null) {
    return _parsePayload(preloadedPayload, tagUid: tagUid, log: log);
  }
  final records = parseNdef(data, log: log);
  log?.call('[OpenSpool] Got ${records.length} NDEF record(s)');
  for (final record in records) {
    log?.call('[OpenSpool] Record mimeType="${record.mimeType}" payloadLen=${record.payload.length}');
    if (record.mimeType == 'application/json') {
      final result = _parsePayload(record.payload, tagUid: tagUid, log: log);
      if (result != null) return result;
    }
  }
  return null;
}

GenericFilament? _parsePayload(Uint8List payload,
    {String tagUid = '', NdefLogger? log}) {
  try {
    final str = utf8.decode(payload);
    log?.call('[OpenSpool] JSON: $str');
    final data = jsonDecode(str) as Map<String, dynamic>;
    if (data['protocol'] != 'openspool') {
      log?.call('[OpenSpool] protocol mismatch: ${data["protocol"]}');
      return null;
    }

    final brand    = data['brand'] as String? ?? 'Generic';
    final mainType = (data['type'] as String? ?? 'PLA').toUpperCase();
    final subtype  = data['subtype'] as String? ?? '';
    final colorHexStr = data['color_hex'] as String? ?? 'FFFFFF';
    final alpha    = (data['alpha'] as num?)?.clamp(0, 255).toInt() ?? 255;

    int colorRgb = 0xFFFFFF;
    try {
      final hex = colorHexStr.replaceAll('#', '');
      colorRgb = int.parse(hex, radix: 16);
    } catch (_) {}
    final argb = ((alpha & 0xFF) << 24) | (colorRgb & 0xFFFFFF);

    final diameter   = double.tryParse('${data['diameter'] ?? 1.75}') ?? 1.75;
    final weight     = double.tryParse('${data['weight'] ?? 1000}') ?? 1000.0;
    final minTemp    = double.tryParse('${data['min_temp'] ?? 0}') ?? 0;
    final maxTemp    = double.tryParse('${data['max_temp'] ?? 0}') ?? 0;
    final bedMaxTemp = double.tryParse('${data['bed_max_temp'] ?? 0}') ?? 0;

    final bedTemp  = bedMaxTemp > 0 ? bedMaxTemp : (_openspoolBedTemps[mainType] ?? 0);
    final dryTemp  = _openspoolDryTemps[mainType] ?? 0;

    return GenericFilament(
      sourceProcessor: 'openspool',
      uniqueId: 'openspool:$brand:$mainType:$subtype:${colorRgb.toRadixString(16)}',
      manufacturer: brand,
      type: mainType,
      modifiers: subtype.isNotEmpty ? [subtype] : [],
      colors: [argb],
      diameterMm: diameter,
      weightGrams: weight,
      hotendMinTemp: minTemp,
      hotendMaxTemp: maxTemp,
      bedTemp: bedTemp,
      dryingTemp: dryTemp,
      dryingTimeHours: 8,
      manufacturingDate: '0001-01-01',
      tagUid: tagUid,
    );
  } catch (e) {
    log?.call('[OpenSpool] Exception: $e');
    return null;
  }
}
