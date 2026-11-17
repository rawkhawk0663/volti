import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import '../library/open_scores.dart';
import '../library/setlists_view.dart' show KeyBadge, showScorePicker;
import '../viewer/viewer_screen.dart';
import 'homework_share.dart';
import 'student_dialog.dart';

/// Seite einer Schülerin / eines Schülers (wie eine Karteikarte):
/// links die Lektion von heute und die vergangenen Lektionen, rechts die
/// Stücke aus der Bibliothek und freie Notizen.
///
/// Gespeichert wird von selbst (kurz nach dem Tippen und beim Verlassen).
class StudentPage extends StatefulWidget {
  const StudentPage({
    super.key,
    required this.library,
    required this.studentId,
    required this.actions,
    this.onPrevious,
    this.onNext,
    this.onDeleted,
    this.onBack,
  });

  final LibraryController library;
  final String studentId;
  final List<Widget> actions;
  final VoidCallback? onPrevious, onNext, onDeleted, onBack;

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  LibraryController get library => widget.library;
  Student? get _student => library.studentById(widget.studentId);

  // ------------------------------------------------- Lektion im Editor
  String? _lessonId;
  DateTime _date = _today();
  LessonStatus _status = LessonStatus.held;
  final _content = TextEditingController();
  final _homework = TextEditingController();
  final _reason = TextEditingController();
  late final _notes = TextEditingController(text: _student?.notes ?? '');
  Timer? _saveTimer, _notesTimer;
  bool _dirty = false, _notesDirty = false;
  bool _savedShown = false;
  bool _allLessons = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    final s = _student;
    final todays = s?.lessonOn(_date);
    if (todays != null) _load(todays);
    for (final c in [_content, _homework, _reason]) {
      c.addListener(_changed);
    }
    _notes.addListener(() {
      if (_notes.text == (_student?.notes ?? '')) return;
      _notesDirty = true;
      _notesTimer?.cancel();
      _notesTimer = Timer(const Duration(milliseconds: 800), _saveNotes);
    });
  }

  @override
  void dispose() {
    // Beim Verlassen nichts verlieren.
    _saveTimer?.cancel();
    _notesTimer?.cancel();
    if (_dirty) _saveLesson();
    if (_notesDirty) _saveNotes();
    for (final c in [_content, _homework, _reason, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _loading = false;

  void _load(Lesson l) {
    _loading = true;
    _lessonId = l.id;
    _date = l.date;
    _status = l.status;
    _content.text = l.content;
    _homework.text = l.homework;
    _reason.text = l.reason;
    _dirty = false;
    _loading = false;
  }

  void _clearEditor({DateTime? date}) {
    _loading = true;
    _lessonId = null;
    _date = date ?? _today();
    _status = LessonStatus.held;
    _content.clear();
    _homework.clear();
    _reason.clear();
    _dirty = false;
    _loading = false;
  }

  void _changed() {
    if (_loading) return;
    _dirty = true;
    _savedShown = false;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _saveLesson);
    setState(() {});
  }

  bool get _editorEmpty =>
      _content.text.trim().isEmpty && _homework.text.trim().isEmpty && _status == LessonStatus.held;

  /// Lektion speichern (eine leere wird nicht angelegt).
  Future<void> _saveLesson() async {
    _saveTimer?.cancel();
    final s = _student;
    if (s == null || !_dirty) return;
    _dirty = false;
    Lesson? l = _lessonId == null ? null : s.lessons[_lessonId];
    if (l == null) {
      if (_editorEmpty) return;
      l = Lesson.create(_date);
      _lessonId = l.id;
    }
    l
      ..date = _date
      ..status = _status
      ..content = _content.text.trimRight()
      ..homework = _homework.text.trimRight()
      ..reason = _status == LessonStatus.held ? '' : _reason.text.trim()
      ..touch();
    s.putLesson(l);
    await library.saveStudent(s);
    if (mounted) setState(() => _savedShown = true);
  }

  Future<void> _saveNotes() async {
    _notesTimer?.cancel();
    final s = _student;
    if (s == null || !_notesDirty) return;
    _notesDirty = false;
    s
      ..notes = _notes.text.trimRight()
      ..touch();
    await library.saveStudent(s);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    await _saveLesson();
    final s = _student;
    final existing = s?.lessonOn(d);
    setState(() {
      if (existing != null && existing.id != _lessonId) {
        _load(existing);
      } else {
        _date = d;
        if (_lessonId != null) _changed();
      }
    });
  }

  Future<void> _newLesson() async {
    await _saveLesson();
    setState(_clearEditor);
  }

  Future<void> _edit(Lesson l) async {
    await _saveLesson();
    setState(() => _load(l));
  }

  Future<void> _deleteLesson(Lesson l) async {
    final s = _student;
    if (s == null) return;
    if (l.id == _lessonId) _clearEditor();
    l
      ..deleted = true
      ..touch();
    s.putLesson(l);
    await library.saveStudent(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text(tr('Lektion gelöscht', 'Lesson deleted')),
        action: SnackBarAction(
          label: tr('Rückgängig', 'Undo'),
          onPressed: () async {
            final now = _student;
            final back = now?.lessons[l.id];
            if (now == null || back == null) return;
            back
              ..deleted = false
              ..touch();
            await library.saveStudent(now);
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------- Stücke
  Future<void> _addPieces() async {
    final picked = await showScorePicker(context, library);
    final s = _student;
    if (picked == null || picked.isEmpty || s == null) return;
    for (final e in picked) {
      final has = s.activePieces.any((x) => x.relativePath == e.relativePath && x.bookmark == null);
      if (!has) s.putPiece(StudentPiece.create(e.relativePath));
    }
    await library.saveStudent(s);
  }

  Future<void> _setPiece(StudentPiece piece, {PieceStatus? status, bool? delete}) async {
    final s = _student;
    if (s == null) return;
    if (status != null) piece.status = status;
    if (delete != null) piece.deleted = delete;
    piece.touch();
    s.putPiece(piece);
    await library.saveStudent(s);
  }

  /// Noten öffnen – mit den Notizen nur für diese:n Schüler:in.
  Future<void> _open(List<StudentPiece> pieces, StudentPiece start) async {
    final s = _student;
    if (s == null) return;
    final items = <ViewerItem>[];
    var startIndex = 0;
    for (final piece in pieces) {
      final e = library.byRelativePath(piece.relativePath);
      if (e == null) continue;
      if (piece.id == start.id) startIndex = items.length;
      items.add(
        ViewerItem(e.path, piece.label ?? e.title, bookmark: piece.bookmark, setlistId: s.scope, setlistName: s.name),
      );
    }
    await openScores(context, library, items, start: startIndex, setlistName: s.name);
  }

  // ------------------------------------------------------- Senden
  Future<void> _send(Lesson l, BuildContext anchor) async {
    final s = _student;
    if (s == null) return;
    if (l.homework.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Noch keine Hausaufgaben eingetragen.', 'No homework entered yet.'))));
      return;
    }
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    final choice = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 0,
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(tr('Per E-Mail', 'By email')),
            subtitle: s.email.isEmpty ? Text(tr('Adresse fehlt noch', 'No address yet')) : Text(s.email),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(tr('Per WhatsApp', 'By WhatsApp')),
            subtitle: s.phone.isEmpty ? Text(tr('Nummer fehlt noch', 'No number yet')) : Text(s.phone),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 2,
          enabled: s.activePieces.isNotEmpty,
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(tr('Mit Noten teilen …', 'Share with music …')),
            subtitle: Text(tr('PDF mit deinen Notizen', 'PDF with your notes')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 0:
        await sendHomeworkByEmail(s, l);
      case 1:
        await sendHomeworkByWhatsApp(s, l);
      case 2:
        final pieces = await _choosePieces(s);
        if (pieces == null || pieces.isEmpty || !mounted) return;
        await shareHomeworkPdf(context, library, s, l, pieces);
    }
  }

  /// Welche Stücke ins PDF kommen (die „am Üben“ sind vorgewählt).
  Future<List<StudentPiece>?> _choosePieces(Student s) {
    final pieces = s.activePieces;
    final chosen = {
      for (final x in pieces)
        if (x.status == PieceStatus.practising) x.id,
    };
    return showDialog<List<StudentPiece>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(tr('Welche Stücke?', 'Which pieces?')),
          content: SizedBox(
            width: 380,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final x in pieces)
                  CheckboxListTile(
                    value: chosen.contains(x.id),
                    title: Text(_title(x)),
                    onChanged: (v) => setDialog(() => v == true ? chosen.add(x.id) : chosen.remove(x.id)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () => Navigator.of(c).pop([
                for (final x in pieces)
                  if (chosen.contains(x.id)) x,
              ]),
              child: Text(tr('Teilen', 'Share')),
            ),
          ],
        ),
      ),
    );
  }

  String _title(StudentPiece x) => x.label ?? library.byRelativePath(x.relativePath)?.title ?? x.relativePath;

  // -------------------------------------------------- Kartei verwalten
  Future<void> _editStudent() async {
    final s = _student;
    if (s == null) return;
    if (await showStudentDialog(context, s)) await library.saveStudent(s);
  }

  Future<void> _archive(bool archived) async {
    final s = _student;
    if (s == null) return;
    s
      ..archived = archived
      ..touch();
    await library.saveStudent(s);
  }

  Future<void> _delete() async {
    final s = _student;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Kartei von ${s.name} löschen?', 'Delete record of ${s.name}?')),
        content: Text(
          tr(
            'Lektionen, Hausaufgaben und die Liste der Stücke werden gelöscht. Die Noten in der Bibliothek bleiben. '
                'Tipp: Mit „Archivieren“ bleibt alles erhalten.',
            'Lessons, homework and the list of pieces will be deleted. The music in the library stays. '
                'Tip: “Archive” keeps everything.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: Text(tr('Löschen', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    _dirty = false;
    _notesDirty = false;
    await library.deleteStudent(s);
    widget.onDeleted?.call();
  }

  // ------------------------------------------------------------ Aufbau
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final s = _student;
        if (s == null) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, box) {
            final twoColumns = box.maxWidth >= 860;
            final lesson = _lessonEditor(context, s);
            final past = _pastLessons(context, s);
            final side = [_pieces(context, s), const SizedBox(height: 20), _notesCard(context)];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, s),
                const Divider(height: 1),
                Expanded(
                  child: twoColumns
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 12, 32),
                                children: [lesson, const SizedBox(height: 24), past],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              flex: 2,
                              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 20, 32), children: side),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          children: [lesson, const SizedBox(height: 20), ...side, const SizedBox(height: 24), past],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final absences = s.activeLessons.where((l) => l.isAbsence && !l.date.isBefore(_schoolYearStart())).length;
    final summary = [
      studentSummary(s),
      if (absences > 0)
        tr(
          '$absences Absenz${absences == 1 ? '' : 'en'} seit August',
          '$absences absence${absences == 1 ? '' : 's'} since August',
        ),
    ].where((x) => x.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          if (widget.onBack != null) IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    PopupMenuButton<VoidCallback>(
                      tooltip: tr('Mehr', 'More'),
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (a) => a(),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _editStudent,
                          child: ListTile(
                            leading: const Icon(Icons.edit_outlined),
                            title: Text(tr('Angaben bearbeiten …', 'Edit details …')),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: () => _archive(!s.archived),
                          child: ListTile(
                            leading: Icon(s.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                            title: Text(s.archived ? tr('Zurückholen', 'Restore') : tr('Archivieren', 'Archive')),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: _delete,
                          child: ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: Text(tr('Löschen …', 'Delete …')),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (summary.isNotEmpty)
                  InkWell(
                    onTap: _editStudent,
                    child: Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: _editStudent,
                    child: Text(tr('Tag, Zeit und Instrument eintragen …', 'Add day, time and instrument …')),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Vorherige:r', 'Previous'),
            icon: const Icon(Icons.chevron_left),
            onPressed: widget.onPrevious,
          ),
          IconButton(tooltip: tr('Nächste:r', 'Next'), icon: const Icon(Icons.chevron_right), onPressed: widget.onNext),
          const SizedBox(width: 4),
          ...widget.actions,
        ],
      ),
    );
  }

  static DateTime _schoolYearStart() {
    final n = DateTime.now();
    return DateTime(n.month >= 8 ? n.year : n.year - 1, 8, 1);
  }

  Widget _sectionTitle(BuildContext context, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _lessonEditor(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final existing = _lessonId != null && s.lessons[_lessonId]?.deleted == false;
    final isToday = sameDay(_date, _today());
    final title = !existing
        ? tr('Neue Lektion', 'New lesson')
        : isToday
        ? tr('Lektion von heute', 'Today’s lesson')
        : tr('Lektion vom ${shortDate(_date)}', 'Lesson of ${shortDate(_date)}');
    final statuses = {
      LessonStatus.held: tr('Gehalten', 'Held'),
      LessonStatus.excused: tr('Abgemeldet', 'Excused'),
      LessonStatus.missed: tr('Gefehlt', 'Missed'),
      LessonStatus.cancelled: tr('Abgesagt', 'Cancelled'),
    };
    InputDecoration box(String hint) => InputDecoration(
      hintText: hint,
      border: const OutlineInputBorder(),
      alignLabelWithHint: true,
      contentPadding: const EdgeInsets.all(12),
    );
    final lessonField = TextField(
      controller: _content,
      minLines: 6,
      maxLines: 14,
      decoration: box(tr('Was habt ihr gemacht?', 'What did you work on?')),
    );
    final homeworkField = TextField(
      controller: _homework,
      minLines: 6,
      maxLines: 14,
      decoration: box(tr('Hausaufgaben …', 'Homework …')),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          context,
          title,
          trailing: existing
              ? TextButton.icon(
                  onPressed: _newLesson,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Neue Lektion', 'New lesson')),
                )
              : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(shortDate(_date)),
            ),
            for (final e in statuses.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _status == e.key,
                onSelected: (_) {
                  _status = e.key;
                  _changed();
                },
              ),
          ],
        ),
        if (_status != LessonStatus.held) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            decoration: InputDecoration(labelText: tr('Grund (freiwillig)', 'Reason (optional)'), isDense: true),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 520
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _labeled(context, tr('Lektion', 'Lesson'), lessonField)),
                    const SizedBox(width: 12),
                    Expanded(child: _labeled(context, tr('Hausaufgaben', 'Homework'), homeworkField)),
                  ],
                )
              : Column(
                  children: [
                    _labeled(context, tr('Lektion', 'Lesson'), lessonField),
                    const SizedBox(height: 12),
                    _labeled(context, tr('Hausaufgaben', 'Homework'), homeworkField),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _dirty
                    ? tr('Wird gespeichert …', 'Saving …')
                    : _savedShown
                    ? tr('Gespeichert ✓', 'Saved ✓')
                    : tr('Wird von selbst gespeichert.', 'Saved automatically.'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Builder(
              builder: (anchor) => FilledButton.tonalIcon(
                onPressed: _homework.text.trim().isEmpty
                    ? null
                    : () async {
                        await _saveLesson();
                        final l = _lessonId == null ? null : _student?.lessons[_lessonId];
                        if (l != null && anchor.mounted) await _send(l, anchor);
                      },
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(tr('Hausaufgaben senden', 'Send homework')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _labeled(BuildContext context, String label, Widget field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4, left: 2),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      field,
    ],
  );

  Widget _pastLessons(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = [
      for (final l in s.activeLessons)
        if (l.id != _lessonId) l,
    ];
    final shown = _allLessons ? all : all.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          context,
          tr('Vergangene Lektionen', 'Past lessons'),
          trailing: all.length > shown.length
              ? TextButton(
                  onPressed: () => setState(() => _allLessons = true),
                  child: Text(tr('Alle anzeigen (${all.length})', 'Show all (${all.length})')),
                )
              : null,
        ),
        if (all.isEmpty)
          Text(
            tr('Noch keine.', 'None yet.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        for (final l in shown)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _edit(l),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(shortDate(l.date), style: theme.textTheme.titleSmall),
                        const SizedBox(width: 8),
                        Text(_ago(l.date), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        if (l.status != LessonStatus.held) ...[const SizedBox(width: 8), _StatusBadge(l)],
                        const Spacer(),
                        Builder(
                          builder: (anchor) => PopupMenuButton<int>(
                            tooltip: tr('Mehr', 'More'),
                            icon: const Icon(Icons.more_horiz, size: 20),
                            onSelected: (v) => v == 0 ? _send(l, anchor) : _deleteLesson(l),
                            itemBuilder: (_) => [
                              if (l.homework.trim().isNotEmpty)
                                PopupMenuItem(value: 0, child: Text(tr('Hausaufgaben senden …', 'Send homework …'))),
                              PopupMenuItem(value: 1, child: Text(tr('Löschen', 'Delete'))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    LayoutBuilder(
                      builder: (context, c) {
                        final a = _cell(
                          context,
                          tr('Lektion', 'Lesson'),
                          l.content.isEmpty ? (l.reason.isEmpty ? '–' : l.reason) : l.content,
                        );
                        final b = _cell(context, tr('Hausaufgaben', 'Homework'), l.homework.isEmpty ? '–' : l.homework);
                        return c.maxWidth >= 480
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: a),
                                  const SizedBox(width: 16),
                                  Expanded(child: b),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [a, const SizedBox(height: 8), b],
                              );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, String label, String text) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(text, maxLines: 8, overflow: TextOverflow.ellipsis),
      ],
    ),
  );

  static String _ago(DateTime d) {
    final days = _today().difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return tr('(heute)', '(today)');
    if (days < 0) return '';
    if (days < 7) return tr('(vor $days Tag${days == 1 ? '' : 'en'})', '($days day${days == 1 ? '' : 's'} ago)');
    final w = (days / 7).round();
    if (w == 1) return tr('(letzte Woche)', '(last week)');
    if (days < 60) return tr('(vor $w Wochen)', '($w weeks ago)');
    final m = (days / 30).round();
    return tr('(vor $m Monaten)', '($m months ago)');
  }

  Widget _pieces(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = s.activePieces;
    final practising = all.where((x) => x.status == PieceStatus.practising).toList();
    final learned = all.where((x) => x.status != PieceStatus.practising).toList();
    Widget tile(StudentPiece x) {
      final e = library.byRelativePath(x.relativePath);
      final done = x.status != PieceStatus.practising;
      return ListTile(
        contentPadding: const EdgeInsets.only(left: 4),
        dense: true,
        leading: IconButton(
          tooltip: done ? tr('Wieder üben', 'Practise again') : tr('Kann es', 'Learned'),
          icon: Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? scheme.primary : scheme.outline,
          ),
          onPressed: () => _setPiece(x, status: done ? PieceStatus.practising : PieceStatus.learned),
        ),
        title: Text(
          _title(x),
          style: TextStyle(fontSize: 15, color: e == null ? scheme.outline : (done ? scheme.onSurfaceVariant : null)),
        ),
        subtitle: e == null
            ? Text(tr('Nicht mehr in der Bibliothek', 'No longer in the library'))
            : (e.composer == null || e.composer!.isEmpty ? null : Text(e.composer!)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e?.musicalKey case final k? when k.isNotEmpty) KeyBadge(k),
            IconButton(
              tooltip: tr('Entfernen', 'Remove'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => _setPiece(x, delete: true),
            ),
          ],
        ),
        onTap: e == null ? null : () => _open([...practising, ...learned], x),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          context,
          tr('Stücke', 'Pieces'),
          trailing: OutlinedButton.icon(
            onPressed: _addPieces,
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('Hinzufügen', 'Add')),
          ),
        ),
        if (all.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              tr(
                'Füge Noten aus deiner Bibliothek hinzu. Was du darin notierst, gilt nur für diese:n Schüler:in.',
                'Add music from your library. What you write in it applies only to this student.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ...practising.map(tile),
        if (learned.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 0, 2),
            child: Text(
              tr('Kann es', 'Learned'),
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          ...learned.map(tile),
        ],
      ],
    );
  }

  Widget _notesCard(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionTitle(context, tr('Notizen', 'Notes')),
      TextField(
        controller: _notes,
        minLines: 4,
        maxLines: 16,
        decoration: InputDecoration(
          hintText: tr('z. B. Geburtstag, Klasse, Eltern, Ziele …', 'e.g. birthday, class, parents, goals …'),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    ],
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.lesson);
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (lesson.status) {
      LessonStatus.excused => (tr('Abgemeldet', 'Excused'), scheme.tertiary),
      LessonStatus.missed => (tr('Gefehlt', 'Missed'), scheme.error),
      LessonStatus.cancelled => (tr('Abgesagt', 'Cancelled'), scheme.outline),
      LessonStatus.makeUp => (tr('Nachgeholt', 'Made up'), scheme.primary),
      LessonStatus.held => ('', scheme.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: color.withValues(alpha: 0.14)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
