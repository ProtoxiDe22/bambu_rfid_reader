import 'dart:typed_data';
import 'generic_filament.dart';

const _qidiMaterials = <int, (String, List<String>)>{
  0x01: ('PLA', []),           0x02: ('PLA', ['Matte']),
  0x03: ('PLA', ['Metal']),    0x04: ('PLA', ['Silk']),
  0x05: ('PLA-CF', []),        0x06: ('PLA', ['Wood']),
  0x07: ('PLA', ['Basic']),    0x08: ('PLA', ['Matte', 'Basic']),
  0x0B: ('ABS', []),           0x0C: ('ABS-GF', []),
  0x0D: ('ABS', ['Metal']),    0x0E: ('ABS', ['Odorless']),
  0x12: ('ASA', []),           0x13: ('ASA-AERO', []),
  0x18: ('PA', ['Ultra']),     0x19: ('PA12-CF', []),
  0x1A: ('PA-CF', ['Ultra', 'CF25']),
  0x1E: ('PAHT-CF', []),       0x1F: ('PAHT-GF', []),
  0x20: ('BVOH', ['For PAHT']),0x21: ('BVOH', ['For PET/PA']),
  0x22: ('PC-ABS', ['FR']),    0x25: ('PET-CF', []),
  0x26: ('PET-GF', []),        0x27: ('PETG', ['Basic']),
  0x28: ('PETG', ['Tough']),   0x29: ('PETG', []),
  0x2C: ('PPS-CF', []),        0x2D: ('PETG', ['Translucent']),
  0x2F: ('PVA', []),           0x31: ('TPU', ['AERO']),
  0x32: ('TPU', []),
};

const _qidiColors = <int, int>{
  0x01: 0xFAFAFA, 0x02: 0x060606, 0x03: 0xD9E3ED,
  0x04: 0x5CF30F, 0x05: 0x63E492, 0x06: 0x2850FF,
  0x07: 0xFE98FE, 0x08: 0xDFD628, 0x09: 0x228332,
  0x0A: 0x99DEFF, 0x0B: 0x1714B0, 0x0C: 0xCEC0FE,
  0x0D: 0xCADE4B, 0x0E: 0x1353AB, 0x0F: 0x5EA9FD,
  0x10: 0xA878FF, 0x11: 0xFE717A, 0x12: 0xFF362D,
  0x13: 0xE2DFCD, 0x14: 0x898F9B, 0x15: 0x6E3812,
  0x16: 0xCAC59F, 0x17: 0xF28636, 0x18: 0xB87F2B,
};

GenericFilament? parseQidiTag(Uint8List data, {String tagUid = ''}) {
  if (data.length < 112) return null;

  final sector1 = data.sublist(64, 112);
  final materialCode     = sector1[0];
  final colorCode        = sector1[1];
  final manufacturerCode = sector1[2];
  final remaining        = sector1.sublist(3);

  if (remaining.any((b) => b != 0x00)) return null;
  if (materialCode == 0x00 || colorCode == 0x00 || manufacturerCode == 0x00) return null;

  final mat = _qidiMaterials[materialCode];
  if (mat == null) return null;
  final colorRgb = _qidiColors[colorCode];
  if (colorRgb == null) return null;

  final (baseType, modifiers) = mat;
  final argb = 0xFF000000 | colorRgb;

  return GenericFilament(
    sourceProcessor: 'qidi',
    uniqueId: 'qidi:${materialCode.toRadixString(16)}:${colorCode.toRadixString(16)}:${manufacturerCode.toRadixString(16)}',
    manufacturer: 'QIDI',
    type: baseType,
    modifiers: modifiers,
    colors: [argb],
    diameterMm: 1.75,
    weightGrams: 1000,
    hotendMinTemp: 0,
    hotendMaxTemp: 0,
    bedTemp: 0,
    dryingTemp: 0,
    dryingTimeHours: 0,
    manufacturingDate: '0001-01-01',
    tagUid: tagUid,
  );
}
