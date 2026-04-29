import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'bambu_parser.dart';
import 'hkdf.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'spoolman.dart';

void main() {
  runApp(const BambuRfidApp());
}

// ─── App ─────────────────────────────────────────────────────────────────────

class BambuRfidApp extends StatelessWidget {
  const BambuRfidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bambu RFID Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          surface: Color(0xFF1E2130),
        ),
      ),
      home: const ScanPage(),
    );
  }
}

// ─── Log entry ───────────────────────────────────────────────────────────────

enum LogLevel { info, ok, warn, error, data }

class LogEntry {
  final String timestamp;
  final String message;
  final LogLevel level;

  LogEntry._(this.timestamp, this.message, this.level);

  static LogEntry make(String msg, [LogLevel level = LogLevel.info]) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    return LogEntry._(ts, msg, level);
  }
}

// ─── Scan page ───────────────────────────────────────────────────────────────

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _scanning = false;
  bool _nfcAvailable = false;
  BambuFilament? _result;
  final List<LogEntry> _logs = [];
  final ScrollController _logScroll = ScrollController();
  late AppSettings _settings;
  bool _settingsLoaded = false;
  bool _uploading = false;
  String? _uploadStatus;
  bool _uploadOk = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkNfc();
  }

  Future<void> _loadSettings() async {
    final s = await AppSettings.load();
    setState(() {
      _settings = s;
      _settingsLoaded = true;
    });
  }

  void _log(String msg, [LogLevel level = LogLevel.info]) {
    setState(() => _logs.add(LogEntry.make(msg, level)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkNfc() async {
    final available = await NfcManager.instance.isAvailable();
    setState(() => _nfcAvailable = available);
    if (!available) _log('NFC not available on this device.', LogLevel.error);
  }

  Future<void> _startScan() async {
    if (!_nfcAvailable) return;
    setState(() {
      _scanning = true;
      _result = null;
    });
    _log('Starting NFC session…');

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        await _handleTag(tag);
        NfcManager.instance.stopSession();
        setState(() => _scanning = false);
      },
      onError: (e) async {
        _log('Session error: $e', LogLevel.error);
        setState(() => _scanning = false);
      },
    );
  }

  void _stopScan() {
    NfcManager.instance.stopSession();
    setState(() => _scanning = false);
    _log('Scan cancelled.', LogLevel.warn);
  }

  Future<void> _handleTag(NfcTag tag) async {
    _log('Tag detected. Data keys: ${tag.data.keys.join(', ')}', LogLevel.ok);

    final mifare = MifareClassic.from(tag);
    if (mifare == null) {
      _log('Tag is not Mifare Classic. Cannot read Bambu spool.', LogLevel.error);
      return;
    }

    final uidBytes = mifare.identifier;
    final uidHex = uidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    _log('UID: $uidHex  Sectors: ${mifare.sectorCount}', LogLevel.ok);

    List<Uint8List> derivedKeys;
    try {
      derivedKeys = deriveKeys(Uint8List.fromList(uidBytes), saltHex: _settings.saltHex);
      _log('HKDF key derivation OK.', LogLevel.ok);
    } catch (e) {
      _log('HKDF failed: $e', LogLevel.error);
      return;
    }

    final allData = Uint8List(1024);
    int successCount = 0;

    // Mifare Classic 1K: 16 sectors × 4 blocks each.
    // Sectors 0-15 each have 4 blocks; last block of each sector is the sector trailer.
    // Block index = sector * 4 + block-within-sector.
    final sectorCount = mifare.sectorCount.clamp(0, 16);

    for (int sector = 0; sector < sectorCount; sector++) {
      final key = derivedKeys[sector];

      bool authed = await mifare.authenticateSectorWithKeyA(sectorIndex: sector, key: key);
      if (authed) {
        _log('  Sector $sector: auth OK (derived key A)', LogLevel.ok);
      } else {
        authed = await mifare.authenticateSectorWithKeyA(
          sectorIndex: sector,
          key: Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
        );
        if (authed) {
          _log('  Sector $sector: auth OK (default key A)', LogLevel.warn);
        }
      }

      if (!authed) {
        _log('  Sector $sector: auth FAILED – skipping', LogLevel.error);
        continue;
      }

      // Read data blocks only (skip sector trailer = last block in sector)
      for (int b = 0; b < 3; b++) {
        final blockIndex = sector * 4 + b;
        try {
          final blockData = await mifare.readBlock(blockIndex: blockIndex);
          final offset = blockIndex * 16;
          allData.setRange(offset, offset + blockData.length, blockData);
          successCount++;
          _log(
            '    Block $blockIndex: ${blockData.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}',
            LogLevel.data,
          );
        } catch (e) {
          _log('    Block $blockIndex: read failed – $e', LogLevel.error);
        }
      }
    }

    _log('Read $successCount blocks. Parsing…');

    try {
      final filament = parseBambuTag(allData, tagUid: uidHex);
      setState(() {
        _result = filament;
        _uploadStatus = null;
      });
      _log('Parsed: ${filament.filamentType} / ${filament.detailedType} ${filament.weightGrams}g', LogLevel.ok);
    } catch (e) {
      _log('Parse error: $e', LogLevel.error);
    }
  }

  Future<void> _uploadToSpoolman() async {
    final f = _result;
    if (f == null) return;
    if (!_settings.isConfigured) {
      setState(() { _uploadStatus = 'Configure Spoolman URL and Salt in Settings first.'; _uploadOk = false; });
      return;
    }

    setState(() { _uploading = true; _uploadStatus = null; });
    final client = SpoolmanClient(_settings.baseUrl);

    try {
      final existing = await client.findByTrayUid(f.trayUidHex);

      if (existing != null) {
        setState(() {
          _uploadOk = false;
          _uploadStatus = 'Spool already exists in Spoolman (ID #${existing.id}: ${existing.filamentName}).';
        });
        return;
      }

      final spool = await client.createSpool(f);
      setState(() {
        _uploadOk = true;
        _uploadStatus = '✓ Uploaded as Spoolman spool #${spool.id}.';
      });
    } catch (e) {
      setState(() {
        _uploadOk = false;
        _uploadStatus = 'Upload failed: $e';
      });
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(settings: _settings)),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildScanCard(),
            const SizedBox(height: 12),
            _buildLogCard(),
            if (_result != null) ...[
              const SizedBox(height: 12),
              _buildUploadCard(_result!),
              const SizedBox(height: 12),
              _buildResultCard(_result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          children: [
            const Text('🧵', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            const Text(
              'Bambu RFID Reader',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'Reads Bambu Lab filament spool Mifare Classic tags',
              style: TextStyle(fontSize: 13, color: Colors.blueGrey[300]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, color: Color(0xFF64748B)),
            tooltip: 'Settings',
          ),
        ),
      ],
    );
  }

  Widget _buildUploadCard(BambuFilament f) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('SPOOLMAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), letterSpacing: 1)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: (_uploading || !_settings.isConfigured) ? null : _uploadToSpoolman,
            icon: _uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_uploading ? 'Uploading…' : 'Upload to Spoolman'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF334155),
              disabledForegroundColor: const Color(0xFF64748B),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (!_settings.isConfigured) ...[  
            const SizedBox(height: 8),
            const Text(
              'Configure Spoolman URL and Salt in Settings (⚙) first.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          if (_uploadStatus != null) ...[  
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _uploadOk ? const Color(0xFF14532D) : const Color(0xFF450A0A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _uploadStatus!,
                style: TextStyle(
                  color: _uploadOk ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _nfcAvailable ? (_scanning ? _stopScan : _startScan) : null,
            icon: Icon(_scanning ? Icons.stop : Icons.nfc),
            label: Text(_scanning ? 'Stop Scanning' : 'Scan Tag'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _scanning ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          _StatusBar(scanning: _scanning, hasResult: _result != null, nfcAvailable: _nfcAvailable),
        ],
      ),
    );
  }

  Widget _buildLogCard() {
    final levelColor = {
      LogLevel.info:  const Color(0xFF94A3B8),
      LogLevel.ok:    const Color(0xFF4ADE80),
      LogLevel.warn:  const Color(0xFFFCD34D),
      LogLevel.error: const Color(0xFFF87171),
      LogLevel.data:  const Color(0xFFA5B4FC),
    };

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DEBUG LOG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), letterSpacing: 1)),
              TextButton(
                onPressed: () => setState(() => _logs.clear()),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('clear', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2D3348)),
            ),
            child: _logs.isEmpty
                ? const Center(child: Text('No logs yet.', style: TextStyle(color: Color(0xFF475569), fontSize: 12)))
                : ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) {
                      final e = _logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            children: [
                              TextSpan(text: '${e.timestamp}  ', style: const TextStyle(color: Color(0xFF475569))),
                              TextSpan(text: e.message, style: TextStyle(color: levelColor[e.level])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(BambuFilament f) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TAG DATA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: f.colors.map((argb) {
              final color = Color(argb | 0xFF000000);
              final hex = '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: hex,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155), width: 2),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _ResultTable(filament: f),
        ],
      ),
    );
  }
}

// ─── Status bar ──────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final bool scanning;
  final bool hasResult;
  final bool nfcAvailable;

  const _StatusBar({required this.scanning, required this.hasResult, required this.nfcAvailable});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String text;

    if (!nfcAvailable) {
      bg = const Color(0xFF450A0A); fg = const Color(0xFFF87171);
      text = 'NFC not available on this device.';
    } else if (scanning) {
      bg = const Color(0xFF1E3A5F); fg = const Color(0xFF60A5FA);
      text = 'Scanning… hold a Bambu spool near your device.';
    } else if (hasResult) {
      bg = const Color(0xFF14532D); fg = const Color(0xFF4ADE80);
      text = '✓ Tag parsed successfully.';
    } else {
      bg = const Color(0xFF1E293B); fg = const Color(0xFF64748B);
      text = 'Ready – tap Scan Tag then hold a spool near your device.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
    );
  }
}

// ─── Result table ────────────────────────────────────────────────────────────

class _ResultTable extends StatelessWidget {
  final BambuFilament filament;
  const _ResultTable({required this.filament});

  @override
  Widget build(BuildContext context) {
    final f = filament;
    final rows = [
      ['Filament Type',   f.filamentType],
      ['Detailed Type',   f.detailedType.isEmpty ? '—' : f.detailedType],
      ['Modifier',        f.modifier.isEmpty ? '—' : f.modifier],
      ['Material Variant',f.materialVariant.isEmpty ? '—' : f.materialVariant],
      ['Material ID',     f.materialId.isEmpty ? '—' : f.materialId],
      ['Diameter',        '${f.diameterMm.toStringAsFixed(2)} mm'],
      ['Weight',          '${f.weightGrams} g'],
      ['Filament Length', f.filamentLength > 0 ? '${f.filamentLength} m' : '—'],
      ['Hotend Temp',     '${f.hotendMinTemp} – ${f.hotendMaxTemp} °C'],
      ['Bed Temp',        '${f.bedTemp} °C'],
      ['Drying Temp',     '${f.dryingTemp} °C'],
      ['Drying Time',     '${f.dryingTime} h'],
      ['Nozzle Diameter', f.nozzleDiameter > 0 ? '${f.nozzleDiameter.toStringAsFixed(2)} mm' : '—'],
      ['Spool Width',     f.spoolWidth > 0 ? '${f.spoolWidth} mm' : '—'],
      ['Manufacturing',   f.manufacturingDate],
      ['Tray UID',        f.trayUidHex],
      ['Tag UID',         f.tagUid.isEmpty ? '—' : f.tagUid],
    ];

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1)},
      children: rows.asMap().entries.map((entry) {
        final isLast = entry.key == rows.length - 1;
        final row = entry.value;
        return TableRow(
          decoration: isLast
              ? null
              : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2D3348)))),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(row[0], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                row[1],
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ─── Card wrapper ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2130),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2D3348)),
      ),
      child: child,
    );
  }
}
