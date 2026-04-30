class GenericFilament {
  final String sourceProcessor;
  final String uniqueId;
  final String manufacturer;
  final String type;
  final List<String> modifiers;
  final List<int> colors;
  final double diameterMm;
  final double weightGrams;
  final double hotendMinTemp;
  final double hotendMaxTemp;
  final double bedTemp;
  final double dryingTemp;
  final double dryingTimeHours;
  final String manufacturingDate;
  final String tagUid;
  final String? trayUid;

  const GenericFilament({
    required this.sourceProcessor,
    required this.uniqueId,
    required this.manufacturer,
    required this.type,
    required this.modifiers,
    required this.colors,
    required this.diameterMm,
    required this.weightGrams,
    required this.hotendMinTemp,
    required this.hotendMaxTemp,
    required this.bedTemp,
    required this.dryingTemp,
    required this.dryingTimeHours,
    required this.manufacturingDate,
    required this.tagUid,
    this.trayUid,
  });

  String get displayType {
    if (modifiers.isEmpty) return type;
    return '$type ${modifiers.join(' ')}';
  }

  String get colorHex {
    if (colors.isEmpty) return 'FFFFFF';
    return (colors.first & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  String get deduplicationUid => trayUid ?? tagUid;
}
