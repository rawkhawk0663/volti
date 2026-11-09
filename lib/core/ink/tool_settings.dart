import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'stroke.dart';
import 'text_note.dart';

String _newId() => const Uuid().v4();

/// Einstellung für Stift oder Textmarker: Farbe (inkl. Deckkraft) und Breite.
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

  bool sameLook(DrawingPreset o) => o.tool == tool && o.color == color && (o.width - width).abs() < 1e-6;

  Map<String, dynamic> toJson() => {'id': id, 'tool': tool.name, 'color': color, 'width': width};

  static DrawingPreset fromJson(Map<String, dynamic> j) => DrawingPreset(
    id: j['id'] as String? ?? _newId(),
    tool: InkTool.fromName(j['tool'] as String?),
    color: j['color'] as int,
    width: (j['width'] as num).toDouble(),
  );

  static const minPenWidth = 0.0012, maxPenWidth = 0.008;
  static const minMarkerWidth = 0.006, maxMarkerWidth = 0.03;

  static double minWidth(InkTool t) => t == InkTool.highlighter ? minMarkerWidth : minPenWidth;
  static double maxWidth(InkTool t) => t == InkTool.highlighter ? maxMarkerWidth : maxPenWidth;
}

/// Stil für neue Text-Notizen.
class TextStyleSetting {
  const TextStyleSetting({
    required this.id,
    required this.size,
    required this.color,
    required this.background,
    this.font = TextFont.sans,
    this.bold = false,
    this.italic = false,
  });

  final String id;

  /// Schriftgrösse relativ zur Seitenbreite.
  final double size;
  final int color;

  /// Hintergrund (ARGB), [TextNote.noBackground] = durchsichtig.
  final int background;
  final TextFont font;
  final bool bold;
  final bool italic;

  TextStyleSetting copyWith({
    String? id,
    double? size,
    int? color,
    int? background,
    TextFont? font,
    bool? bold,
    bool? italic,
  }) => TextStyleSetting(
    id: id ?? this.id,
    size: size ?? this.size,
    color: color ?? this.color,
    background: background ?? this.background,
    font: font ?? this.font,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
  );

  bool sameLook(TextStyleSetting o) =>
      (o.size - size).abs() < 1e-6 &&
      o.color == color &&
      o.background == background &&
      o.font == font &&
      o.bold == bold &&
      o.italic == italic;

  Map<String, dynamic> toJson() => {
    'id': id,
    'size': size,
    'color': color,
    'bg': background,
    'font': font.name,
    'b': bold,
    'i': italic,
  };

  static TextStyleSetting fromJson(Map<String, dynamic> j) => TextStyleSetting(
    id: j['id'] as String? ?? _newId(),
    size: (j['size'] as num).toDouble(),
    color: j['color'] as int,
    background: j['bg'] as int? ?? TextNote.noBackground,
    font: TextFont.fromName(j['font'] as String?),
    bold: j['b'] == true,
    italic: j['i'] == true,
  );

  static const minSize = 0.012, maxSize = 0.045;
}

/// Formen, die man mit dem Formen-Werkzeug aufziehen kann.
enum ShapeKind {
  line,
  arrow,
  rectangle,
  ellipse,
  crescendo,
  decrescendo,
  slur,

  /// Fünf waagrechte Notenlinien.
  staff;

  static ShapeKind fromName(String? n) => ShapeKind.values.firstWhere((k) => k.name == n, orElse: () => line);
}

/// Einstellungen für Stempel.
class StampSetting {
  const StampSetting({required this.glyph, required this.size, required this.color, this.custom});

  /// Zeichen in der Schrift Bravura.
  final int glyph;

  /// Eigener Stempel (ID) – hat Vorrang vor [glyph].
  final String? custom;

  /// Schriftgrösse relativ zur Seitenbreite.
  final double size;
  final int color;

  static const _keep = Object();

  /// Ein Zeichen wählen hebt einen eigenen Stempel auf ([custom] = null).
  StampSetting copyWith({int? glyph, double? size, int? color, Object? custom = _keep}) => StampSetting(
    glyph: glyph ?? this.glyph,
    size: size ?? this.size,
    color: color ?? this.color,
    custom: identical(custom, _keep) ? (glyph != null ? null : this.custom) : custom as String?,
  );

  Map<String, dynamic> toJson() => {'glyph': glyph, 'size': size, 'color': color, 'custom': ?custom};

  static StampSetting fromJson(Map<String, dynamic> j) => StampSetting(
    glyph: j['glyph'] as int,
    size: (j['size'] as num).toDouble(),
    color: j['color'] as int? ?? 0xFF1B1B1B,
    custom: j['custom'] as String?,
  );

  static const minSize = 0.02, maxSize = 0.09;
}

/// Alle Werkzeug-Einstellungen und Favoriten. Gilt für alle Stücke und wird
/// zwischen Geräten abgeglichen (`.volti/presets.json`, jüngste Fassung gewinnt).
class ToolSettings {
  ToolSettings({
    required this.pen,
    required this.highlighter,
    required this.text,
    required this.eraserRadius,
    this.eraserPartial = false,
    required this.penFavorites,
    required this.highlighterFavorites,
    required this.textFavorites,
    this.stamp = const StampSetting(glyph: 0xE52D, size: 0.045, color: 0xFF1B1B1B),
    List<int>? recentStamps,
    this.shape = const DrawingPreset(id: 'shape', tool: InkTool.pen, color: 0xFF1B1B1B, width: 0.0025),
    this.shapeKind = ShapeKind.crescendo,
  }) : recentStamps = recentStamps ?? [];

  DrawingPreset pen;
  DrawingPreset highlighter;
  TextStyleSetting text;
  double eraserRadius;

  /// Radierer: false = ganze Elemente löschen, true = nur berührte Teile.
  bool eraserPartial;
  final List<DrawingPreset> penFavorites;
  final List<DrawingPreset> highlighterFavorites;
  final List<TextStyleSetting> textFavorites;

  StampSetting stamp;

  /// Zuletzt benutzte Stempel (neueste zuerst).
  final List<int> recentStamps;

  DrawingPreset shape;
  ShapeKind shapeKind;

  static ToolSettings defaults() => ToolSettings(
    pen: const DrawingPreset(id: 'pen', tool: InkTool.pen, color: 0xFF1B1B1B, width: 0.003),
    highlighter: const DrawingPreset(id: 'hl', tool: InkTool.highlighter, color: 0x99FFE066, width: 0.014),
    text: const TextStyleSetting(id: 'text', size: 0.022, color: 0xFF1B1B1B, background: TextNote.noBackground),
    eraserRadius: 14,
    penFavorites: const [
      DrawingPreset(id: 'std-schwarz', tool: InkTool.pen, color: 0xFF1B1B1B, width: 0.003),
      DrawingPreset(id: 'std-rot', tool: InkTool.pen, color: 0xFFC62828, width: 0.003),
      DrawingPreset(id: 'std-blau', tool: InkTool.pen, color: 0xFF1565C0, width: 0.003),
      DrawingPreset(id: 'std-bleistift', tool: InkTool.pen, color: 0xB3555555, width: 0.0018),
      // Weiss deckend: um Teile der Noten abzudecken (z. B. bei Wiederholungen).
      DrawingPreset(id: 'std-abdecken', tool: InkTool.pen, color: 0xFFFFFFFF, width: 0.008),
    ].toList(),
    highlighterFavorites: const [
      DrawingPreset(id: 'std-gelb', tool: InkTool.highlighter, color: 0x99FFE066, width: 0.014),
      DrawingPreset(id: 'std-gruen', tool: InkTool.highlighter, color: 0x8077DD99, width: 0.014),
      DrawingPreset(id: 'std-rosa', tool: InkTool.highlighter, color: 0x80FF9EC4, width: 0.014),
    ].toList(),
    textFavorites: const [
      TextStyleSetting(id: 'std-text', size: 0.022, color: 0xFF1B1B1B, background: TextNote.noBackground),
      TextStyleSetting(id: 'std-text-rot', size: 0.022, color: 0xFFC62828, background: TextNote.noBackground),
      TextStyleSetting(id: 'std-text-gelb', size: 0.022, color: 0xFF1B1B1B, background: 0x99FFE066),
    ].toList(),
  );

  Map<String, dynamic> toJson() => {
    'format': 'volti-tools',
    'version': 2,
    // Für den Sync: die jüngste Fassung gewinnt.
    'modified': DateTime.now().toUtc().toIso8601String(),
    'pen': pen.toJson(),
    'highlighter': highlighter.toJson(),
    'text': text.toJson(),
    'eraserRadius': eraserRadius,
    'eraserPartial': eraserPartial,
    'penFavorites': [for (final f in penFavorites) f.toJson()],
    'highlighterFavorites': [for (final f in highlighterFavorites) f.toJson()],
    'textFavorites': [for (final f in textFavorites) f.toJson()],
    'stamp': stamp.toJson(),
    'recentStamps': recentStamps,
    'shape': shape.toJson(),
    'shapeKind': shapeKind.name,
  };

  static ToolSettings fromJson(Map<String, dynamic> j) {
    final d = defaults();
    // Version 1 (Paket 1a): nur eine Liste von Stift-Vorlagen → zu Favoriten.
    if (j['format'] == 'volti-presets') {
      final old = [
        for (final e in j['presets'] as List? ?? const []) DrawingPreset.fromJson(e as Map<String, dynamic>),
      ];
      final pens = old.where((p) => p.tool == InkTool.pen).toList();
      final hls = old.where((p) => p.tool == InkTool.highlighter).toList();
      return ToolSettings(
        pen: pens.isEmpty ? d.pen : pens.first,
        highlighter: hls.isEmpty ? d.highlighter : hls.first,
        text: d.text,
        eraserRadius: d.eraserRadius,
        penFavorites: pens.isEmpty ? d.penFavorites : pens,
        highlighterFavorites: hls.isEmpty ? d.highlighterFavorites : hls,
        textFavorites: d.textFavorites,
      );
    }
    List<DrawingPreset> drawList(String key, List<DrawingPreset> fallback) {
      final l = j[key];
      return l is List ? [for (final e in l) DrawingPreset.fromJson(e as Map<String, dynamic>)] : fallback;
    }

    return ToolSettings(
      pen: j['pen'] is Map ? DrawingPreset.fromJson(j['pen'] as Map<String, dynamic>) : d.pen,
      highlighter: j['highlighter'] is Map
          ? DrawingPreset.fromJson(j['highlighter'] as Map<String, dynamic>)
          : d.highlighter,
      text: j['text'] is Map ? TextStyleSetting.fromJson(j['text'] as Map<String, dynamic>) : d.text,
      eraserRadius: (j['eraserRadius'] as num?)?.toDouble() ?? d.eraserRadius,
      eraserPartial: j['eraserPartial'] == true,
      penFavorites: drawList('penFavorites', d.penFavorites),
      highlighterFavorites: drawList('highlighterFavorites', d.highlighterFavorites),
      textFavorites: j['textFavorites'] is List
          ? [for (final e in j['textFavorites'] as List) TextStyleSetting.fromJson(e as Map<String, dynamic>)]
          : d.textFavorites,
      stamp: j['stamp'] is Map ? StampSetting.fromJson(j['stamp'] as Map<String, dynamic>) : d.stamp,
      recentStamps: (j['recentStamps'] as List?)?.cast<int>().toList(),
      shape: j['shape'] is Map ? DrawingPreset.fromJson(j['shape'] as Map<String, dynamic>) : d.shape,
      shapeKind: ShapeKind.fromName(j['shapeKind'] as String?),
    );
  }
}

/// Liest und speichert die Werkzeug-Einstellungen im Bibliotheksordner.
class ToolStore {
  ToolStore(this.libraryRoot);
  final String libraryRoot;

  static const relativePath = '.volti/presets.json';
  File get _file => File(p.join(libraryRoot, '.volti', 'presets.json'));

  Future<ToolSettings> load() async {
    try {
      if (!await _file.exists()) return ToolSettings.defaults();
      return ToolSettings.fromJson(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return ToolSettings.defaults();
    }
  }

  Future<void> save(ToolSettings s) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(s.toJson()), flush: true);
    await tmp.rename(_file.path);
  }

  static String newId() => _newId();
}
