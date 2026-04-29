import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _keyCache = 'external_filament_cache';
const _keyTimestamp = 'external_filament_cache_ts';
const _ttlDays = 7;

class ExternalFilament {
  final String id;
  final String manufacturer;
  final String name;
  final String material;
  final double density;
  final double weight;
  final double diameter;
  final String? colorHex;
  final int? extruderTemp;
  final int? bedTemp;

  const ExternalFilament({
    required this.id,
    required this.manufacturer,
    required this.name,
    required this.material,
    required this.density,
    required this.weight,
    required this.diameter,
    this.colorHex,
    this.extruderTemp,
    this.bedTemp,
  });

  factory ExternalFilament.fromJson(Map<String, dynamic> j) {
    return ExternalFilament(
      id: j['id'] as String,
      manufacturer: j['manufacturer'] as String,
      name: j['name'] as String,
      material: j['material'] as String,
      density: (j['density'] as num).toDouble(),
      weight: (j['weight'] as num).toDouble(),
      diameter: (j['diameter'] as num).toDouble(),
      colorHex: j['color_hex'] as String?,
      extruderTemp: j['extruder_temp'] as int?,
      bedTemp: j['bed_temp'] as int?,
    );
  }
}

class FilamentCache {
  FilamentCache._();

  static Future<List<ExternalFilament>> get(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final tsStr = prefs.getString(_keyTimestamp);
    final cached = prefs.getString(_keyCache);

    if (tsStr != null && cached != null) {
      final ts = DateTime.tryParse(tsStr);
      if (ts != null &&
          DateTime.now().difference(ts).inDays < _ttlDays) {
        return _decode(cached);
      }
    }

    return _fetch(baseUrl, prefs);
  }

  static Future<List<ExternalFilament>> refresh(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    return _fetch(baseUrl, prefs);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCache);
    await prefs.remove(_keyTimestamp);
  }

  static Future<List<ExternalFilament>> _fetch(
      String baseUrl, SharedPreferences prefs) async {
    final url = Uri.parse('$baseUrl/api/v1/external/filament');
    final resp = await http.get(url).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch external filament catalog: HTTP ${resp.statusCode}');
    }
    await prefs.setString(_keyCache, resp.body);
    await prefs.setString(_keyTimestamp, DateTime.now().toIso8601String());
    return _decode(resp.body);
  }

  static List<ExternalFilament> _decode(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => ExternalFilament.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static ExternalFilament? findBestMatch({
    required List<ExternalFilament> catalog,
    required String material,
    required double diameterMm,
    required String? colorHex,
  }) {
    final diaTarget = double.parse(diameterMm.toStringAsFixed(2));

    final byMaterial = catalog.where((f) =>
        f.material.toLowerCase() == material.toLowerCase() &&
        (f.diameter - diaTarget).abs() < 0.05);

    if (colorHex == null || colorHex.isEmpty) {
      return byMaterial.isNotEmpty ? byMaterial.first : null;
    }

    final targetR = int.parse(colorHex.substring(0, 2), radix: 16);
    final targetG = int.parse(colorHex.substring(2, 4), radix: 16);
    final targetB = int.parse(colorHex.substring(4, 6), radix: 16);

    ExternalFilament? best;
    double bestDist = double.infinity;

    for (final f in byMaterial) {
      if (f.colorHex == null || f.colorHex!.length < 6) continue;
      final hex = f.colorHex!.replaceAll('#', '');
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      final dist = ((r - targetR) * (r - targetR) +
              (g - targetG) * (g - targetG) +
              (b - targetB) * (b - targetB))
          .toDouble();
      if (dist < bestDist) {
        bestDist = dist;
        best = f;
      }
    }

    return best;
  }
}
