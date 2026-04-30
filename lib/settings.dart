import 'package:shared_preferences/shared_preferences.dart';
import 'filament_cache.dart';

class AppSettings {
  static const _keySpoolmanUrl = 'spoolman_url';
  static const _keyBambuSaltHex = 'bambu_salt_hex';
  static const _keySnapmakerSaltHex = 'snapmaker_salt_hex';

  String spoolmanUrl;
  String bambuSaltHex;
  String snapmakerSaltHex;

  AppSettings({required this.spoolmanUrl, required this.bambuSaltHex, required this.snapmakerSaltHex});

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      spoolmanUrl: prefs.getString(_keySpoolmanUrl) ?? '',
      bambuSaltHex: prefs.getString(_keyBambuSaltHex) ?? '',
      snapmakerSaltHex: prefs.getString(_keySnapmakerSaltHex) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpoolmanUrl, spoolmanUrl);
    await prefs.setString(_keyBambuSaltHex, bambuSaltHex);
    await prefs.setString(_keySnapmakerSaltHex, snapmakerSaltHex);
  }

  bool get isConfigured => spoolmanUrl.isNotEmpty;

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
