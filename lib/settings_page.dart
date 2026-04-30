import 'package:flutter/material.dart';
import 'settings.dart';
import 'spoolman.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _bambuSaltCtrl;
  late final TextEditingController _smSaltCtrl;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _clearingCache = false;
  String? _cacheStatus;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.settings.spoolmanUrl);
    _bambuSaltCtrl = TextEditingController(text: widget.settings.bambuSaltHex);
    _smSaltCtrl = TextEditingController(text: widget.settings.snapmakerSaltHex);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _bambuSaltCtrl.dispose();
    _smSaltCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.settings.spoolmanUrl = _urlCtrl.text.trim();
    widget.settings.bambuSaltHex = _bambuSaltCtrl.text.trim();
    widget.settings.snapmakerSaltHex = _smSaltCtrl.text.trim();
    await widget.settings.save();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _clearCache() async {
    setState(() { _clearingCache = true; _cacheStatus = null; });
    await AppSettings.clearExternalCache();
    setState(() {
      _clearingCache = false;
      _cacheStatus = 'Cache cleared. It will be re-downloaded on next upload.';
    });
  }

  String _normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  Future<void> _testConnection() async {
    final url = _normalizeUrl(_urlCtrl.text);
    if (url == 'http://' || _urlCtrl.text.trim().isEmpty) {
      setState(() { _testResult = 'Enter a Spoolman URL first.'; _testOk = false; });
      return;
    }
    setState(() { _testing = true; _testResult = null; });
    try {
      await SpoolmanClient(url).testConnection();
      setState(() { _testOk = true; _testResult = '✓ Connected successfully.'; });
    } catch (e) {
      setState(() { _testOk = false; _testResult = 'Connection failed: $e'; });
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2130),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('BAMBU RFID'),
          const SizedBox(height: 8),
          _settingsCard(
            child: _field(
              controller: _bambuSaltCtrl,
              label: 'Bambu Salt Hex',
              hint: 'Bambu HKDF salt',
              helper: 'The HKDF salt used to derive Bambu Mifare Classic sector keys.',
              obscure: true,
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('SNAPMAKER RFID'),
          const SizedBox(height: 8),
          _settingsCard(
            child: _field(
              controller: _smSaltCtrl,
              label: 'Snapmaker Salt Hex',
              hint: 'Snapmaker HKDF salt',
              helper: 'The HKDF salt used to derive Snapmaker Mifare Classic sector keys.',
              obscure: true,
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('FILAMENT CATALOG'),
          const SizedBox(height: 8),
          _settingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'The external filament catalog is cached locally for 7 days to speed up uploads.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _clearingCache ? null : _clearCache,
                  icon: _clearingCache
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(_clearingCache ? 'Clearing…' : 'Clear Cached Catalog'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0xFFF87171)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (_cacheStatus != null) ...[  
                  const SizedBox(height: 8),
                  Text(_cacheStatus!, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('SPOOLMAN'),
          const SizedBox(height: 8),
          _settingsCard(
            child: Column(
              children: [
                _field(
                  controller: _urlCtrl,
                  label: 'Spoolman URL',
                  hint: 'http://192.168.1.x:7912',
                  helper: 'Base URL of your Spoolman instance.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_testing ? 'Testing…' : 'Test Connection'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(color: Color(0xFF3B82F6)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _testOk ? const Color(0xFF14532D) : const Color(0xFF450A0A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testOk ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF94A3B8),
          letterSpacing: 1,
        ),
      );

  Widget _settingsCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2130),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2D3348)),
        ),
        child: child,
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569)),
        helperText: helper,
        helperStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
        helperMaxLines: 2,
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2D3348))),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF3B82F6))),
      ),
    );
  }
}
