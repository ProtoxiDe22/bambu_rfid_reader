import 'dart:convert';
import 'package:http/http.dart' as http;
import 'generic_filament.dart';
import 'filament_cache.dart';

const _extraKeyTrayUid = 'tray_uid';

String _decodeExtraString(dynamic raw) {
  if (raw == null) return '';
  try {
    final decoded = jsonDecode(raw as String);
    return decoded is String ? decoded : raw;
  } catch (_) {
    return raw as String;
  }
}

class SpoolmanException implements Exception {
  final String message;
  const SpoolmanException(this.message);
  @override
  String toString() => message;
}

class SpoolmanSpool {
  final int id;
  final String trayUid;
  final String filamentName;

  const SpoolmanSpool({
    required this.id,
    required this.trayUid,
    required this.filamentName,
  });

  factory SpoolmanSpool.fromJson(Map<String, dynamic> j) {
    final filament = j['filament'] as Map<String, dynamic>?;
    final extra = j['extra'] as Map<String, dynamic>? ?? {};
    return SpoolmanSpool(
      id: j['id'] as int,
      trayUid: _decodeExtraString(extra[_extraKeyTrayUid]),
      filamentName: filament?['name'] as String? ?? '(unknown)',
    );
  }
}

class SpoolmanClient {
  final String baseUrl;

  SpoolmanClient(String baseUrl)
      : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<http.Response> _post(Uri uri, Map<String, dynamic> body,
      {int redirectCount = 0}) async {
    final resp = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 8));
    if ((resp.statusCode == 301 ||
            resp.statusCode == 302 ||
            resp.statusCode == 307 ||
            resp.statusCode == 308) &&
        redirectCount < 5) {
      final location = resp.headers['location'];
      if (location != null) {
        final next = Uri.parse(location).isAbsolute
            ? Uri.parse(location)
            : uri.resolve(location);
        return _post(next, body, redirectCount: redirectCount + 1);
      }
    }
    return resp;
  }

  Future<void> testConnection() async {
    final resp =
        await http.get(_uri('/api/v1/health')).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw SpoolmanException('Health check failed: HTTP ${resp.statusCode}');
    }
  }

  Future<SpoolmanSpool?> findByTrayUid(String trayUidHex) async {
    final resp = await http
        .get(_uri('/api/v1/spool'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw SpoolmanException('GET spools failed: HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    final items = body is List ? body : (body['items'] as List? ?? []);
    for (final raw in items) {
      final spool = SpoolmanSpool.fromJson(raw as Map<String, dynamic>);
      if (spool.trayUid == trayUidHex) return spool;
    }
    return null;
  }

  Future<int> _resolveFilamentId(GenericFilament f) async {
    final colorHex = f.colors.isNotEmpty
        ? (f.colors.first & 0xFFFFFF)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase()
        : null;

    final manufacturer = f.manufacturer;

    List<ExternalFilament> catalog;
    try {
      catalog = await FilamentCache.get(baseUrl);
    } catch (_) {
      catalog = [];
    }

    final match = catalog.isNotEmpty
        ? FilamentCache.findBestMatch(
            catalog: catalog,
            material: f.type,
            diameterMm: f.diameterMm,
            colorHex: colorHex,
            manufacturer: manufacturer,
          )
        : null;

    if (match != null) {
      final existing = await _findFilamentByExternalId(match.id);
      if (existing != null) return existing;

      final importResp = await _post(
        _uri('/api/v1/filament'),
        {'external_id': match.id},
      );
      if (importResp.statusCode == 200 || importResp.statusCode == 201) {
        return (jsonDecode(importResp.body) as Map<String, dynamic>)['id'] as int;
      }
    }

    final existingId = await _findExistingFilament(f.type, colorHex);
    if (existingId != null) return existingId;

    final vendorId = await _resolveVendorId(manufacturer);
    final name = f.modifiers.isNotEmpty
        ? '${f.type} ${f.modifiers.join(' ')}'
        : f.type;

    final payload = <String, dynamic>{
      'name': name,
      'material': f.type,
      'color_hex': colorHex,
      'diameter': double.parse(f.diameterMm.toStringAsFixed(2)),
      'density': 1.24,
      'settings_extruder_temp': f.hotendMaxTemp.round(),
      'settings_bed_temp': f.bedTemp.round(),
      'vendor_id': vendorId,
    };

    final resp = await _post(_uri('/api/v1/filament'), payload);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw SpoolmanException(
          'Create filament failed: HTTP ${resp.statusCode} – ${resp.body}');
    }
    return (jsonDecode(resp.body) as Map<String, dynamic>)['id'] as int;
  }

  Future<int?> _findExistingFilament(String material, String? colorHex) async {
    final query = <String, String>{'material': material};
    if (colorHex != null) query['color_hex'] = colorHex;
    final resp = await http
        .get(_uri('/api/v1/filament', query))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body);
    final items = body is List ? body : (body['items'] as List? ?? []);
    if (items.isEmpty) return null;
    return (items.first as Map<String, dynamic>)['id'] as int;
  }

  Future<int?> _resolveVendorId(String name) async {
    final resp = await http
        .get(_uri('/api/v1/vendor', {'name': name}))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final items = body is List ? body : (body['items'] as List? ?? []);
      if (items.isNotEmpty) {
        return (items.first as Map<String, dynamic>)['id'] as int;
      }
    }
    final createResp = await _post(_uri('/api/v1/vendor'), {'name': name});
    if (createResp.statusCode == 200 || createResp.statusCode == 201) {
      return (jsonDecode(createResp.body) as Map<String, dynamic>)['id'] as int;
    }
    return null;
  }

  Future<int?> _findFilamentByExternalId(String extId) async {
    final resp = await http
        .get(_uri('/api/v1/filament', {'external_id': '"$extId"'}))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body);
    final items = body is List ? body : (body['items'] as List? ?? []);
    if (items.isEmpty) return null;
    return (items.first as Map<String, dynamic>)['id'] as int;
  }

  Future<void> _ensureTrayUidField() async {
    final resp = await http
        .get(_uri('/api/v1/field/spool'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final fields = jsonDecode(resp.body) as List<dynamic>;
      final exists = fields.any(
          (f) => (f as Map<String, dynamic>)['key'] == _extraKeyTrayUid);
      if (exists) return;
    }
    await _post(
      _uri('/api/v1/field/spool/$_extraKeyTrayUid'),
      {'name': 'Tray UID', 'field_type': 'text'},
    );
  }

  Future<SpoolmanSpool> createSpool(GenericFilament f) async {
    await _ensureTrayUidField();
    final filamentId = await _resolveFilamentId(f);

    final uid = f.deduplicationUid;
    final spoolPayload = <String, dynamic>{
      'filament_id': filamentId,
      if (f.weightGrams > 0) 'initial_weight': f.weightGrams,
      if (f.weightGrams > 0) 'remaining_weight': f.weightGrams,
      'extra': {_extraKeyTrayUid: jsonEncode(uid)},
    };

    final spoolResp = await _post(_uri('/api/v1/spool'), spoolPayload);

    if (spoolResp.statusCode != 200 && spoolResp.statusCode != 201) {
      throw SpoolmanException(
          'Create spool failed: HTTP ${spoolResp.statusCode} – ${spoolResp.body}');
    }
    return SpoolmanSpool.fromJson(
        jsonDecode(spoolResp.body) as Map<String, dynamic>);
  }
}
