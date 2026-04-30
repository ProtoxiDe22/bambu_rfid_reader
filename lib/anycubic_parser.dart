import 'dart:typed_data';
import 'generic_filament.dart';

// Adapted from https://github.com/DnG-Crafts/ACE-RFID (via OpenRFID)

GenericFilament? parseAnycubicTag(Uint8List data, {String tagUid = ''}) {
  if (data.length < 0x7C) return null;
  if (data[0x10] != 0x7B || data[0x11] != 0x00 || data[0x12] != 0x65 || data[0x13] != 0x00) {
    return null;
  }

  String readStr(int start, int end) {
    final bytes = data.sublist(start, end);
    final nul = bytes.indexOf(0);
    return String.fromCharCodes(nul >= 0 ? bytes.sublist(0, nul) : bytes).trim();
  }

  final sku          = readStr(0x14, 0x24);
  final brand        = readStr(0x28, 0x38);
  final filamentType = readStr(0x3C, 0x4C);

  final parts = filamentType.replaceAll('-', ' ').split(' ').where((s) => s.isNotEmpty).toList();
  String baseType = parts.isNotEmpty ? parts[0] : 'PLA';
  List<String> modifiers = parts.length > 1 ? parts.sublist(1) : [];

  if (baseType.endsWith('+')) {
    baseType = baseType.substring(0, baseType.length - 1);
    modifiers = ['+', ...modifiers];
  }

  final a = data[0x50];
  final b = data[0x51];
  final g = data[0x52];
  final r = data[0x53];
  final argb = ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

  final extruderMinTemp = _uint16le(data, 0x60);
  final extruderMaxTemp = _uint16le(data, 0x62);
  final bedMaxTemp      = _uint16le(data, 0x76);
  final diameterRaw     = _uint16le(data, 0x78);
  final lengthM         = _uint16le(data, 0x7A);

  final diameterMm = diameterRaw / 100.0;
  final weightGrams = _lengthToGrams(lengthM);

  return GenericFilament(
    sourceProcessor: 'anycubic',
    uniqueId: 'anycubic:$sku:$tagUid',
    manufacturer: brand.isNotEmpty ? brand : 'Anycubic',
    type: baseType,
    modifiers: modifiers,
    colors: [argb],
    diameterMm: diameterMm,
    weightGrams: weightGrams.toDouble(),
    hotendMinTemp: extruderMinTemp.toDouble(),
    hotendMaxTemp: extruderMaxTemp.toDouble(),
    bedTemp: bedMaxTemp.toDouble(),
    dryingTemp: 0,
    dryingTimeHours: 0,
    manufacturingDate: '0001-01-01',
    tagUid: tagUid,
  );
}

int _uint16le(Uint8List d, int pos) => d[pos] | (d[pos + 1] << 8);

int _lengthToGrams(int lengthM) {
  switch (lengthM) {
    case 330: return 1000;
    case 247: return 750;
    case 198: return 600;
    case 165: return 500;
    case 82:  return 250;
    default:  return 1000;
  }
}
