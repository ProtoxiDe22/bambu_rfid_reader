import 'dart:typed_data';
import 'generic_filament.dart';

// ─── Constants (mirrored from constants.py) ──────────────────────────────────

const int tagTotalSize = 1024;

const int materialVariantIdPos = 1 * 16 + 0;
const int materialVariantIdLen = 8;
const int materialIdPos = 1 * 16 + 8;
const int materialIdLen = 8;

const int filamentTypePos = 2 * 16 + 0;
const int filamentTypeLen = 16;

const int detailedFilamentTypePos = 4 * 16 + 0;
const int detailedFilamentTypeLen = 16;

const int colorRgbaPos = 5 * 16 + 0;
const int spoolWeightPos = 5 * 16 + 4;
const int filamentDiameterPos = 5 * 16 + 8;

const int dryingTempPos = 6 * 16 + 0;
const int dryingTimePos = 6 * 16 + 2;
const int bedTempTypePos = 6 * 16 + 4;
const int bedTempPos = 6 * 16 + 6;
const int hotendMaxTempPos = 6 * 16 + 8;
const int hotendMinTempPos = 6 * 16 + 10;

const int xcamInfoPos = 8 * 16 + 0;
const int xcamInfoLen = 12;
const int nozzleDiameterPos = 8 * 16 + 12;

const int trayUidPos = 9 * 16 + 0;
const int trayUidLen = 16;

const int spoolWidthPos = 10 * 16 + 4;

const int productionDatetimePos = 12 * 16 + 0;
const int productionDatetimeLen = 16;

const int filamentLengthPos = 14 * 16 + 4;

const int formatIdentifierPos = 16 * 16 + 0;
const int colorCountPos = 16 * 16 + 2;
const int secondColorPos = 16 * 16 + 4;

const int formatColorInfo = 0x0002;

// ─── Binary helpers ──────────────────────────────────────────────────────────

String extractString(Uint8List data, int pos, int len) {
  final bytes = data.sublist(pos, pos + len);
  final end = bytes.indexOf(0);
  final slice = end >= 0 ? bytes.sublist(0, end) : bytes;
  return String.fromCharCodes(slice);
}

int extractUint16LE(Uint8List data, int pos) {
  return data[pos] | (data[pos + 1] << 8);
}

int extractUint32LE(Uint8List data, int pos) {
  return data[pos] |
      (data[pos + 1] << 8) |
      (data[pos + 2] << 16) |
      (data[pos + 3] << 24);
}

double extractFloat32LE(Uint8List data, int pos) {
  final bd = ByteData.sublistView(data, pos, pos + 4);
  return bd.getFloat32(0, Endian.little);
}

// ─── Data model ──────────────────────────────────────────────────────────────

class BambuFilament {
  final String filamentType;
  final String detailedType;
  final String modifier;
  final String materialVariant;
  final String materialId;
  final List<int> colors; // ARGB
  final int weightGrams;
  final double diameterMm;
  final int dryingTemp;
  final int dryingTime;
  final int bedTempType;
  final int bedTemp;
  final int hotendMaxTemp;
  final int hotendMinTemp;
  final String trayUidHex;
  final double nozzleDiameter;
  final int spoolWidth;
  final int filamentLength;
  final String manufacturingDate;
  final String tagUid;

  GenericFilament toGenericFilament() => GenericFilament(
        sourceProcessor: 'bambu',
        uniqueId: trayUidHex,
        manufacturer: 'Bambu Lab',
        type: filamentType,
        modifiers: modifier.isNotEmpty && modifier != filamentType ? [modifier] : [],
        colors: colors,
        diameterMm: diameterMm,
        weightGrams: weightGrams.toDouble(),
        hotendMinTemp: hotendMinTemp.toDouble(),
        hotendMaxTemp: hotendMaxTemp.toDouble(),
        bedTemp: bedTemp.toDouble(),
        dryingTemp: dryingTemp.toDouble(),
        dryingTimeHours: dryingTime.toDouble(),
        manufacturingDate: manufacturingDate,
        tagUid: tagUid,
        trayUid: trayUidHex,
      );

  const BambuFilament({
    required this.filamentType,
    required this.detailedType,
    required this.modifier,
    required this.materialVariant,
    required this.materialId,
    required this.colors,
    required this.weightGrams,
    required this.diameterMm,
    required this.dryingTemp,
    required this.dryingTime,
    required this.bedTempType,
    required this.bedTemp,
    required this.hotendMaxTemp,
    required this.hotendMinTemp,
    required this.trayUidHex,
    required this.nozzleDiameter,
    required this.spoolWidth,
    required this.filamentLength,
    required this.manufacturingDate,
    required this.tagUid,
  });
}

// ─── Parser ──────────────────────────────────────────────────────────────────

String _parseProductionDate(String s) {
  try {
    final parts = s.split('_');
    if (parts.length >= 3) {
      final year = parts[0];
      final month = parts[1].padLeft(2, '0');
      final day = parts[2].padLeft(2, '0');
      return '$year-$month-$day';
    }
  } catch (_) {}
  return '1970-01-01';
}

BambuFilament parseBambuTag(Uint8List data, {String tagUid = ''}) {
  if (data.length < tagTotalSize) {
    // Pad if shorter
    final padded = Uint8List(tagTotalSize);
    padded.setRange(0, data.length, data);
    data = padded;
  }

  final filamentType = extractString(data, filamentTypePos, filamentTypeLen);
  final detailedType = extractString(data, detailedFilamentTypePos, detailedFilamentTypeLen);
  final materialVariant = extractString(data, materialVariantIdPos, materialVariantIdLen);
  final materialId = extractString(data, materialIdPos, materialIdLen);

  final r = data[colorRgbaPos];
  final g = data[colorRgbaPos + 1];
  final b = data[colorRgbaPos + 2];
  final a = data[colorRgbaPos + 3];
  final argb1 = ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

  final weightGrams = extractUint16LE(data, spoolWeightPos);
  final diameterMm = extractFloat32LE(data, filamentDiameterPos);
  final dryingTemp = extractUint16LE(data, dryingTempPos);
  final dryingTime = extractUint16LE(data, dryingTimePos);
  final bedTempType = extractUint16LE(data, bedTempTypePos);
  final bedTemp = extractUint16LE(data, bedTempPos);
  final hotendMaxTemp = extractUint16LE(data, hotendMaxTempPos);
  final hotendMinTemp = extractUint16LE(data, hotendMinTempPos);

  final trayUidBytes = data.sublist(trayUidPos, trayUidPos + trayUidLen);
  final trayUidHex = trayUidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

  final nozzleDiameter = extractFloat32LE(data, nozzleDiameterPos);
  final spoolWidth = extractUint16LE(data, spoolWidthPos);
  final filamentLength = extractUint16LE(data, filamentLengthPos);

  final productionDatetimeRaw = extractString(data, productionDatetimePos, productionDatetimeLen);
  final manufacturingDate = _parseProductionDate(productionDatetimeRaw);

  final formatIdentifier = extractUint16LE(data, formatIdentifierPos);
  final colorCount = extractUint16LE(data, colorCountPos);

  final colors = [argb1];
  if (formatIdentifier == formatColorInfo && colorCount > 1) {
    final abgr2 = extractUint32LE(data, secondColorPos);
    final a2 = (abgr2 >> 24) & 0xFF;
    final b2 = (abgr2 >> 16) & 0xFF;
    final g2 = (abgr2 >> 8) & 0xFF;
    final r2 = abgr2 & 0xFF;
    colors.add(((a2 & 0xFF) << 24) | ((r2 & 0xFF) << 16) | ((g2 & 0xFF) << 8) | (b2 & 0xFF));
  }

  final modifier = detailedType.startsWith(filamentType)
      ? detailedType.substring(filamentType.length).trim()
      : detailedType;

  return BambuFilament(
    filamentType: filamentType,
    detailedType: detailedType,
    modifier: modifier,
    materialVariant: materialVariant,
    materialId: materialId,
    colors: colors,
    weightGrams: weightGrams,
    diameterMm: diameterMm,
    dryingTemp: dryingTemp,
    dryingTime: dryingTime,
    bedTempType: bedTempType,
    bedTemp: bedTemp,
    hotendMaxTemp: hotendMaxTemp,
    hotendMinTemp: hotendMinTemp,
    trayUidHex: trayUidHex,
    nozzleDiameter: nozzleDiameter,
    spoolWidth: spoolWidth,
    filamentLength: filamentLength,
    manufacturingDate: manufacturingDate,
    tagUid: tagUid,
  );
}
