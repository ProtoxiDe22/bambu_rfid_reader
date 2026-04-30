import 'dart:convert';
import 'package:flutter/services.dart';
import 'generic_filament.dart';

const _validTagIds = {0x5BF59264, 0xBC0FCB97};
const _epochOffset = 946684800; // TigerTag epoch: 2000-01-01

// Byte offsets within user data (starts at page 4 = byte 16)
const _offTagId     = 0;
const _offProductId = 4;
const _offMaterialId= 8;
const _offAspect1   = 10;
const _offAspect2   = 11;
const _offDiameter  = 13;
const _offBrandId   = 14;
const _offColor     = 16;
const _offWeight    = 20;
const _offUnitId    = 23;
const _offTempMin   = 24;
const _offTempMax   = 26;
const _offDryTemp   = 28;
const _offDryTime   = 29;
const _offBedTempMax= 31;
const _offTimestamp = 32;

class _TigerTagDb {
  final Map<int, double> diameters;
  final Map<int, String> materialLabels;
  final Map<int, String> materialTypes;
  final Map<int, String> filledTypes;
  final Map<int, String> aspects;
  final Map<int, String> brands;
  final Map<int, String> units;

  const _TigerTagDb({
    required this.diameters,
    required this.materialLabels,
    required this.materialTypes,
    required this.filledTypes,
    required this.aspects,
    required this.brands,
    required this.units,
  });
}

_TigerTagDb? _dbCache;

Future<_TigerTagDb> _loadDb() async {
  if (_dbCache != null) return _dbCache!;

  Future<String> asset(String name) =>
      rootBundle.loadString('assets/tigertag/$name');

  final diametersJson  = jsonDecode(await asset('id_diameter.json')) as List;
  final materialsJson  = jsonDecode(await asset('id_material.json')) as List;
  final aspectsJson    = jsonDecode(await asset('id_aspect.json')) as List;
  final brandsJson     = jsonDecode(await asset('id_brand.json')) as List;
  final unitsJson      = jsonDecode(await asset('id_measure_unit.json')) as List;

  Map<int, T> mapById<T>(List items, T Function(Map<String, dynamic>) fn) {
    final result = <int, T>{};
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final id = (m['id'] as num?)?.toInt();
      if (id != null) result[id] = fn(m);
    }
    return result;
  }

  final diameters = mapById<double>(diametersJson,
      (m) => double.tryParse('${m['label'] ?? m['value'] ?? 1.75}') ?? 1.75);

  final materialLabels = mapById<String>(materialsJson,
      (m) => (m['label'] ?? m['name'] ?? '').toString());
  final materialTypes = mapById<String>(materialsJson,
      (m) => (m['material_type'] ?? m['label'] ?? '').toString());
  final filledTypes = mapById<String>(materialsJson,
      (m) => (m['filled_type'] ?? '').toString());

  final aspects = mapById<String>(aspectsJson,
      (m) => (m['label'] ?? m['name'] ?? '').toString());
  final brands  = mapById<String>(brandsJson,
      (m) => (m['name'] ?? m['label'] ?? '').toString());
  final units   = mapById<String>(unitsJson,
      (m) => (m['label'] ?? m['name'] ?? 'g').toString());

  _dbCache = _TigerTagDb(
    diameters: diameters,
    materialLabels: materialLabels,
    materialTypes: materialTypes,
    filledTypes: filledTypes,
    aspects: aspects,
    brands: brands,
    units: units,
  );
  return _dbCache!;
}

int _uint32be(Uint8List d, int pos) =>
    ((d[pos] << 24) | (d[pos+1] << 16) | (d[pos+2] << 8) | d[pos+3]) & 0xFFFFFFFF;
int _uint16be(Uint8List d, int pos) => (d[pos] << 8) | d[pos + 1];

double _toGrams(int value, int unitId) {
  switch (unitId) {
    case 1: case 21: return value.toDouble();
    case 2: case 35: return value * 1000.0;
    case 10: return value / 1000.0;
    default: return value.toDouble();
  }
}

String _timestampToDate(int ts) {
  if (ts == 0) return '0001-01-01';
  try {
    final unix = ts + _epochOffset;
    final dt = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
    return '${dt.year.toString().padLeft(4,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  } catch (_) {
    return '0001-01-01';
  }
}

Future<GenericFilament?> parseTigerTagAsync(Uint8List data,
    {String tagUid = ''}) async {
  const userDataOffset = 4 * 4; // page 4 → byte 16
  if (data.length < userDataOffset + _offTimestamp + 4) return null;

  final ud = data.sublist(userDataOffset);
  final tagId = _uint32be(ud, _offTagId);
  if (!_validTagIds.contains(tagId)) return null;

  final db = await _loadDb();

  final productId  = _uint32be(ud, _offProductId);
  final materialId = _uint16be(ud, _offMaterialId);
  final aspect1Id  = ud[_offAspect1];
  final aspect2Id  = ud[_offAspect2];
  final diamId     = ud[_offDiameter];
  final brandId    = _uint16be(ud, _offBrandId);

  final r = ud[_offColor];
  final g = ud[_offColor + 1];
  final b = ud[_offColor + 2];
  final a = ud[_offColor + 3];
  final argb = ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

  final weightRaw = (ud[_offWeight] << 16) | (ud[_offWeight+1] << 8) | ud[_offWeight+2];
  final unitId    = ud[_offUnitId];
  final tempMin   = _uint16be(ud, _offTempMin);
  final tempMax   = _uint16be(ud, _offTempMax);
  final dryTemp   = ud[_offDryTemp];
  final dryTime   = ud[_offDryTime];
  final bedTempMax= ud[_offBedTempMax];
  final timestamp = _uint32be(ud, _offTimestamp);

  final materialLabel = db.materialLabels[materialId] ?? 'Unknown';
  final materialType  = db.materialTypes[materialId] ?? materialLabel;
  final filledType    = db.filledTypes[materialId] ?? '';
  final resolvedType  = filledType.isNotEmpty ? '$materialType-$filledType' : materialType;

  final brandName = db.brands[brandId] ?? 'Unknown';
  final diameter  = db.diameters[diamId] ?? 1.75;

  final aspect1 = db.aspects[aspect1Id] ?? '';
  final aspect2 = db.aspects[aspect2Id] ?? '';
  final modifiers = [aspect1, aspect2]
      .where((s) => s.isNotEmpty && s != 'None' && s != '-')
      .toList();

  final weightGrams = _toGrams(weightRaw, unitId);
  final date = _timestampToDate(timestamp);

  return GenericFilament(
    sourceProcessor: 'tigertag',
    uniqueId: 'tigertag:$brandName:$resolvedType:${argb.toRadixString(16)}:$productId',
    manufacturer: brandName,
    type: resolvedType,
    modifiers: modifiers,
    colors: [argb],
    diameterMm: diameter,
    weightGrams: weightGrams,
    hotendMinTemp: tempMin.toDouble(),
    hotendMaxTemp: tempMax.toDouble(),
    bedTemp: bedTempMax.toDouble(),
    dryingTemp: dryTemp.toDouble(),
    dryingTimeHours: dryTime.toDouble(),
    manufacturingDate: date,
    tagUid: tagUid,
  );
}
