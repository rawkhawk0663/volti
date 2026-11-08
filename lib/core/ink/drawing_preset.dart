import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'stroke.dart';

/// Eine Stift-Vorlage: Werkzeug, Farbe (inkl. Deckkraft) und Breite.
///
/// Vorlagen gelten für alle Stücke und werden zwischen Geräten
/// synchronisiert (`.volti/presets.json` in der Bibliothek).
class DrawingPreset {
  const DrawingPreset({required this.id, required this.tool, required this.color, required this.width});

  final String id;
  final InkTool tool;

  /// Farbe als ARGB; der Alphawert ist die Deckkraft.
  final int color;

  /// Breite relativ zur Seitenbreite.
  final double width;

  DrawingPreset copyWith({String? id, InkTool? tool, int? color, double? width}) =>
      DrawingPreset(id: id ?? this.id, tool: tool ?? this.tool, color: color ?? this.color, width: width ?? this.width);

  Map<String, dynamic> toJson() => {'id': id, 'tool': tool.name, 'color': color, 'width': width};

  static DrawingPreset fromJson(Map<String, dynamic> j) => DrawingPreset(
    id: j['id'] as String,
    tool: InkTool.fromName(j['tool'] as String?),
    color: j['color'] as int,
    width: (j['width'] as num).toDouble(),
  );

  /// Breitenstufen (relativ zur Seitenbreite) für den Regler.
  static const minPenWidth = 0.0012, maxPenWidth = 0.008;
  static const minMarkerWidth = 0.006, maxMarkerWidth = 0.03;

  static final defaults = <DrawingPreset>[
    const DrawingPreset(id: 'std-schwarz', tool: InkTool.pen, color: 0xFF1B1B1B, width: 0.003),
    const DrawingPreset(id: 'std-rot', tool: InkTool.pen, color: 0xFFC62828, width: 0.003),
    const DrawingPreset(id: 'std-blau', tool: InkTool.pen, color: 0xFF1565C0, width: 0.003),
    const DrawingPreset(id: 'std-bleistift', tool: InkTool.pen, color: 0xB3555555, width: 0.0018),
    const DrawingPreset(id: 'std-gelb', tool: InkTool.highlighter, color: 0x99FFE066, width: 0.014),
    const DrawingPreset(id: 'std-gruen', tool: InkTool.highlighter, color: 0x8077DD99, width: 0.014),
    // Weiss deckend: um Teile der Noten abzudecken (z. B. bei Wiederholungen).
    const DrawingPreset(id: 'std-abdecken', tool: InkTool.pen, color: 0xFFFFFFFF, width: 0.02),
  ];
}

/// Liest und speichert die Stift-Vorlagen im Bibliotheksordner.
class PresetStore {
  PresetStore(this.libraryRoot);
  final String libraryRoot;

  static const relativePath = '.volti/presets.json';
  File get _file => File(p.join(libraryRoot, '.volti', 'presets.json'));

  Future<List<DrawingPreset>> load() async {
    try {
      if (!await _file.exists()) return List.of(DrawingPreset.defaults);
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final list = [
        for (final e in json['presets'] as List? ?? const []) DrawingPreset.fromJson(e as Map<String, dynamic>),
      ];
      return list.isEmpty ? List.of(DrawingPreset.defaults) : list;
    } catch (_) {
      return List.of(DrawingPreset.defaults);
    }
  }

  Future<void> save(List<DrawingPreset> presets) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'format': 'volti-presets',
        'version': 1,
        // Für den Sync: die jüngste Fassung gewinnt.
        'modified': DateTime.now().toUtc().toIso8601String(),
        'presets': [for (final p in presets) p.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  static String newId() => const Uuid().v4();
}
