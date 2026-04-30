import 'dart:typed_data';
import 'generic_filament.dart';

// Material ID → (baseType, modifiers)
const _elegooMaterials = <int, Map<int, (String, List<String>)>>{
  0x00: { // PLA
    0x00: ('PLA', []),       0x01: ('PLA', ['+']),    0x02: ('PLA', ['Pro']),
    0x03: ('PLA', ['Silk']), 0x04: ('PLA', ['CF']),   0x05: ('PLA', ['Carbon']),
    0x06: ('PLA', ['Matte']),0x07: ('PLA', ['Fluo']), 0x08: ('PLA', ['Wood']),
    0x09: ('PLA', ['Basic']),0x0A: ('PLA', ['RAPID', '+']),
    0x0B: ('PLA', ['Marble']),0x0C: ('PLA', ['Galaxy']),
    0x0D: ('PLA', ['Red', 'Copper']), 0x0E: ('PLA', ['Sparkle']),
  },
  0x01: { // PETG
    0x00: ('PETG', []),          0x01: ('PETG', ['CF']),
    0x02: ('PETG', ['GF']),      0x03: ('PETG', ['Pro']),
    0x04: ('PETG', ['Translucent']), 0x05: ('PETG', ['RAPID']),
  },
  0x02: {0x00: ('ABS', []), 0x01: ('ABS', ['GF'])},
  0x03: {0x00: ('TPU', []), 0x01: ('TPU', ['95A']), 0x02: ('TPU', ['RAPID', '95A'])},
  0x04: {
    0x00: ('PA', []),   0x01: ('PA', ['CF']),  0x03: ('PA', ['HT', 'CF']),
    0x04: ('PA6', []),  0x05: ('PA6', ['CF']), 0x06: ('PA12', []), 0x07: ('PA12', ['CF']),
  },
  0x05: {0x00: ('CPE', [])},
  0x06: {0x00: ('PC', []), 0x01: ('PC', ['TG']), 0x02: ('PC', ['FR'])},
  0x07: {0x00: ('PVA', [])},
  0x08: {0x00: ('ASA', [])},
  0x09: {0x00: ('BVOH', [])},
  0x0A: {0x00: ('EVA', [])},
  0x0B: {0x00: ('HIPS', [])},
  0x0C: {0x00: ('PP', []), 0x01: ('PP', ['CF']), 0x02: ('PP', ['GF'])},
  0x0D: {0x00: ('PPA', []), 0x01: ('PPA', ['CF']), 0x02: ('PPA', ['GF'])},
  0x0E: {0x00: ('PPS', []), 0x02: ('PPS', ['CF'])},
};

int _uint16be(Uint8List d, int pos) => (d[pos] << 8) | d[pos + 1];

GenericFilament? parseElegooTag(Uint8List data, {String tagUid = ''}) {
  if (data.length < 0x69) return null;

  final fd = data.sublist(0x40, 0x69);
  if (fd[0x01] != 0xEE || fd[0x02] != 0xEE || fd[0x03] != 0xEE || fd[0x04] != 0xEE) {
    return null;
  }

  final materialId  = fd[0x08];
  final modifierId  = fd[0x0C]; // upper byte of uint16be at 0x0C

  final mat = _elegooMaterials[materialId]?[modifierId];
  if (mat == null) return null;

  final (baseType, modifiers) = mat;

  final r = fd[0x10];
  final g = fd[0x11];
  final b = fd[0x12];
  final a = fd[0x13];
  final argb = ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

  final minTemp     = _uint16be(fd, 0x14);
  final maxTemp     = _uint16be(fd, 0x16);
  final diameter    = _uint16be(fd, 0x1C) / 100.0;
  final weightGrams = _uint16be(fd, 0x1E);

  return GenericFilament(
    sourceProcessor: 'elegoo',
    uniqueId: 'elegoo:${materialId.toRadixString(16)}:${modifierId.toRadixString(16)}:$tagUid',
    manufacturer: 'Elegoo',
    type: baseType,
    modifiers: modifiers,
    colors: [argb],
    diameterMm: diameter,
    weightGrams: weightGrams.toDouble(),
    hotendMinTemp: minTemp.toDouble(),
    hotendMaxTemp: maxTemp.toDouble(),
    bedTemp: 0,
    dryingTemp: 0,
    dryingTimeHours: 0,
    manufacturingDate: '0001-01-01',
    tagUid: tagUid,
  );
}
