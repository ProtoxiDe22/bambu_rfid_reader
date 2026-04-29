import 'package:shared_preferences/shared_preferences.dart';
import 'filament_cache.dart';

class AppSettings {
  static const _keySpoolmanUrl = 'spoolman_url';
  static const _keySaltHex = 'bambu_salt_hex';

  String spoolmanUrl;
  String saltHex;

  AppSettings({required this.spoolmanUrl, required this.saltHex});

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      spoolmanUrl: prefs.getString(_keySpoolmanUrl) ?? '',
      saltHex: prefs.getString(_keySaltHex) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpoolmanUrl, spoolmanUrl);
    await prefs.setString(_keySaltHex, saltHex);
  }

  bool get isConfigured => spoolmanUrl.isNotEmpty && saltHex.isNotEmpty;

  static Future<void> clearExternalCache() => FilamentCache.clear();

  String get baseUrl {
    var url = spoolmanUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }
}
