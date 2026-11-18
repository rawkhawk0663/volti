import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../core/ink/text_marks.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import '../library/open_scores.dart';
import '../library/setlists_view.dart' show KeyBadge, showScorePicker;
import '../viewer/viewer_screen.dart';
import 'homework_share.dart';
import '../../core/teaching/school_level.dart';
import 'attendance_table.dart';
import 'rich_editor.dart';
import 'student_dialog.dart';
import 'todo_widgets.dart';

/// Beginn des Schuljahrs (1. August), für die Zahl der Absenzen.
DateTime schoolYearStart() {
  final n = DateTime.now();
  return DateTime(n.month >= 8 ? n.year : n.year - 1, 8, 1);
}

/// Seite einer Schülerin / eines Schülers:
/// links „Neue Lektion“ (Lektion | Hausaufgaben, Speichern) und darunter
/// die vergangenen Lektionen, rechts Repertoire und Notizen.
class StudentPage extends StatefulWidget {
  const StudentPage({
    super.key,
    required this.library,
    required this.studentId,
    required this.actions,
    this.onDeleted,
    this.onOpen,
    this.banner,
  });

  final LibraryController library;
  final String studentId;
  final List<Widget> actions;
  final VoidCallback? onDeleted;

  /// Andere Kartei öffnen (Mitglied einer Gruppe bzw. die Gruppe).
  final void Function(Student s)? onOpen;

  /// Hinweis oben (z. B. Geburtstage dieser Woche).
  final Widget? banner;

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  LibraryController get library => widget.library;
  Student? get _student => library.studentById(widget.studentId);

  /// Wird gerade eine vergangene Lektion bearbeitet? (sonst: neue Lektion)
  String? _editing;
  DateTime _date = _today();
  final _content = RichEditController();
  final _homework = RichEditController();

  /// Textfeld, auf das die Werkzeugleiste wirkt (zuletzt angetippt).
  late final _active = ValueNotifier<RichEditController?>(_content);
  late final FocusNode _contentFocus = FocusNode()..addListener(() => _focusChanged(_contentFocus, _content));
  late final FocusNode _homeworkFocus = FocusNode()..addListener(() => _focusChanged(_homeworkFocus, _homework));

  void _focusChanged(FocusNode node, RichEditController c) {
    if (node.hasFocus) _active.value = c;
  }

  bool _allLessons = false;
  bool _doneTodos = false;

  /// Gelernte Stücke („Kann es“) im Repertoire zeigen.
  bool _showLearned = false;

  /// Mitglieder einer Gruppe (sonst leer).
  List<Student> _members(Student s) => [for (final id in s.members) ?library.studentById(id)];

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _content.addListener(_refresh);
    _homework.addListener(_refresh);
    // Frühere Fassung: ein einziges Notizfeld → als Karte „Infos“ übernehmen.
    final s = _student;
    if (s != null && s.notes.trim().isNotEmpty && s.memos.isEmpty) {
      s
        ..putMemo(StudentNote.create(title: tr('Infos', 'Info'), text: s.notes.trim()))
        ..notes = ''
        ..touch();
      library.saveStudent(s);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    // Nicht gespeicherte neue Lektion beim Wechseln nicht verlieren.
    if (_hasText && _editing == null) _save(quiet: true);
    _content.dispose();
    _homework.dispose();
    _contentFocus.dispose();
    _homeworkFocus.dispose();
    _active.dispose();
    super.dispose();
  }

  bool get _hasText => _content.text.trim().isNotEmpty || _homework.text.trim().isNotEmpty;

  // ------------------------------------------------------- Lektionen
  /// Lektion speichern: neu (dann ist das Feld wieder leer) oder die bearbeitete.
  Future<Lesson?> _save({bool quiet = false}) async {
    final s = _student;
    if (s == null) return null;
    final edited = _editing == null ? null : s.lessons[_editing];
    if (edited == null && !_hasText) return null;
    // Steht für den Tag schon ein Eintrag aus der Absenzenkontrolle (ohne Text), wird er ergänzt.
    final same = edited == null ? s.lessonOn(_date) : null;
    final reuse = same != null && same.content.trim().isEmpty && same.homework.trim().isEmpty ? same : null;
    final l = edited ?? reuse ?? Lesson.create(_date);
    if (reuse != null) l.status = LessonStatus.held;
    l
      ..date = _date
      ..content = _content.text.trimRight()
      ..homework = _homework.text.trimRight()
      ..touch();
    l
      ..contentMarks = _content.marksFor(l.content)
      ..homeworkMarks = _homework.marksFor(l.homework);
    s.putLesson(l);
    await library.saveStudent(s);
    if (!quiet && mounted) {
      setState(_clear);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(tr('Gespeichert', 'Saved'))));
    }
    return l;
  }

  void _clear() {
    _editing = null;
    _date = _today();
    _content.load('', const []);
    _homework.load('', const []);
  }

  void _edit(Lesson l) => setState(() {
    _editing = l.id;
    _date = l.date;
    _content.load(l.content, l.contentMarks);
    _homework.load(l.homework, l.homeworkMarks);
  });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  /// Absenzenkontrolle: Status an einem Tag setzen (null = leeren).
  Future<void> _setAttendance(Student s, DateTime day, LessonStatus? status, String reason) async {
    final absent = status != null && status != LessonStatus.held;
    final l = s.lessonOn(day);
    if (l == null) {
      if (status == null) return;
      s.putLesson(
        Lesson.create(day)
          ..status = status
          ..reason = absent ? reason : '',
      );
    } else {
      final empty = l.content.trim().isEmpty && l.homework.trim().isEmpty;
      if (status == null && empty) {
        l.deleted = true;
      } else {
        l
          ..status = status ?? LessonStatus.held
          ..reason = absent ? reason : '';
      }
      l.touch();
      s.putLesson(l);
    }
    await library.saveStudent(s);
  }

  /// Grund einer Absenz nachträglich ändern.
  Future<void> _editReason(Lesson l, Student owner) async {
    final r = await showAbsenceReasonDialog(
      context,
      status: l.status,
      day: l.date,
      reason: l.reason,
      who: owner.id == widget.studentId ? null : owner.name,
    );
    if (r == null) return;
    l
      ..reason = r
      ..touch();
    owner.putLesson(l);
    await library.saveStudent(owner);
  }

  /// Note eines Semesters (leer = keine).
  Future<void> _setGrade(Student s, String semesterId, String grade) async {
    if (grade.isEmpty) {
      if (s.grades.remove(semesterId) == null) return;
    } else {
      s.grades[semesterId] = grade;
    }
    s.touch();
    await library.saveStudent(s);
  }

  Future<void> _deleteLesson(Lesson l, [Student? owner]) async {
    final s = owner ?? _student;
    if (s == null) return;
    if (l.id == _editing) setState(_clear);
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
            final now = library.studentById(s.id);
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

  // ------------------------------------------------------- Senden
  Future<void> _send(Lesson l, BuildContext anchor) async {
    final s = _student;
    if (s == null) return;
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    final members = _members(s);
    final emails = homeworkEmails(s, members: members);
    // WhatsApp geht an eine Nummer: bei einer Gruppe pro Mitglied wählbar.
    final chats = members.isEmpty ? [s] : members;
    final choice = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 0,
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(members.isEmpty ? tr('Per E-Mail', 'By email') : tr('Per E-Mail an alle', 'By email to all')),
            subtitle: Text(emails.isEmpty ? tr('Adresse fehlt noch', 'No address yet') : emails.join(', ')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        for (var i = 0; i < chats.length; i++)
          PopupMenuItem(
            value: 10 + i,
            child: ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: Text(
                members.isEmpty
                    ? tr('Per WhatsApp', 'By WhatsApp')
                    : tr('Per WhatsApp an ${chats[i].name}', 'By WhatsApp to ${chats[i].name}'),
              ),
              subtitle: Text(
                chats[i].phone.isEmpty ? tr('Nummer fehlt noch', 'No number yet') : formatPhone(chats[i].phone),
              ),
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
        await sendHomeworkByEmail(s, l, members: members);
      case 2:
        final pieces = await _choosePieces(s);
        if (pieces == null || pieces.isEmpty || !mounted) return;
        await shareHomeworkPdf(context, library, s, l, pieces);
      default:
        await sendHomeworkByWhatsApp(s, l, members: members, phone: chats[choice - 10].phone);
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

  // ------------------------------------------------------- Repertoire
  String _title(StudentPiece x) => x.label ?? library.byRelativePath(x.relativePath)?.title ?? x.relativePath;

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

  // ------------------------------------------------------- Notizen
  Future<void> _editMemo(StudentNote? memo) async {
    final s = _student;
    if (s == null) return;
    final title = TextEditingController(text: memo?.title ?? '');
    final text = RichEditController(text: memo?.text ?? '', marks: memo?.marks ?? const []);
    final target = ValueNotifier<RichEditController?>(text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(memo == null ? tr('Neue Notiz', 'New note') : tr('Notiz', 'Note')),
        content: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                autofocus: memo == null,
                decoration: InputDecoration(labelText: tr('Titel', 'Title'), hintText: tr('z. B. Infos', 'e.g. Info')),
              ),
              const SizedBox(height: 12),
              RichToolbar(target: target),
              const SizedBox(height: 6),
              RichEditorField(
                controller: text,
                minLines: 5,
                maxLines: 14,
                hint: tr('z. B. Eltern, Ziele, Abmachungen …', 'e.g. parents, goals, agreements …'),
                onLink: () => editLink(c, text),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: Text(tr('Speichern', 'Save'))),
        ],
      ),
    );
    final t = title.text.trim(), body = text.text.trimRight();
    final marks = text.marksFor(body);
    title.dispose();
    target.dispose();
    // Erst nach dem Schliessen-Übergang freigeben (das Feld ist noch sichtbar).
    Future.delayed(const Duration(seconds: 1), text.dispose);
    if (ok != true || (t.isEmpty && body.isEmpty)) return;
    final m = memo ?? StudentNote.create();
    m
      ..title = t
      ..text = body
      ..marks = marks
      ..touch();
    s.putMemo(m);
    await library.saveStudent(s);
  }

  Future<void> _deleteMemo(StudentNote m) async {
    final s = _student;
    if (s == null) return;
    m
      ..deleted = true
      ..touch();
    s.putMemo(m);
    await library.saveStudent(s);
  }

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
        title: Text(
          s.isGroup
              ? tr('Gruppe ${s.name} auflösen?', 'Dissolve group ${s.name}?')
              : tr('Kartei von ${s.name} löschen?', 'Delete record of ${s.name}?'),
        ),
        content: Text(
          s.isGroup
              ? tr(
                  'Die Mitglieder behalten ihre eigenen Karteien und Absenzen. Lektionen, Repertoire und Notizen '
                      'der Gruppe werden gelöscht. Tipp: Mit „Archivieren“ bleibt alles erhalten.',
                  'Members keep their own records and attendance. The group’s lessons, repertoire and notes '
                      'will be deleted. Tip: “Archive” keeps everything.',
                )
              : tr(
                  'Lektionen, Hausaufgaben, Repertoire und Notizen werden gelöscht. Die Noten in der Bibliothek bleiben. '
                      'Tipp: Mit „Archivieren“ bleibt alles erhalten.',
                  'Lessons, homework, repertoire and notes will be deleted. The music in the library stays. '
                      'Tip: “Archive” keeps everything.',
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(s.isGroup ? tr('Auflösen', 'Dissolve') : tr('Löschen', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _content.load('', const []);
    _homework.load('', const []);
    await library.deleteStudent(s);
    widget.onDeleted?.call();
  }

  Future<void> _editMembers() async {
    final s = _student;
    if (s == null) return;
    final members = await showGroupMembersDialog(context, library, group: s);
    if (members == null || members.length < 2) return;
    s
      ..members.clear()
      ..members.addAll(members)
      ..touch();
    await library.saveStudent(s);
  }

  // ------------------------------------------------------------ Aufbau
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final s = _student;
        if (s == null) return const SizedBox.shrink();
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save},
          child: LayoutBuilder(
            builder: (context, box) {
              final twoColumns = box.maxWidth >= 900;
              final left = [
                _newLesson(context, s),
                const Divider(height: 48),
                _pastLessons(context, s),
                const SizedBox(height: 90), // Platz für die schwebende Leiste
              ];
              final right = [
                _repertoire(context, s),
                const Divider(height: 40),
                _todos(context, s),
                const Divider(height: 40),
                _memos(context, s),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                    child: Row(
                      children: [
                        Text(tr('Unterrichten', 'Teach'), style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        ...widget.actions,
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ?widget.banner,
                  _header(context, s),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: AttendanceTable(
                      students: s.isGroup ? _members(s) : [s],
                      // Mitglied einer Gruppe: Unterrichtstag der Gruppe.
                      weekday: s.weekday ?? library.groupOf(s.id)?.weekday,
                      calendar: library.calendar,
                      onSet: _setAttendance,
                      onGrade: _setGrade,
                      onEditStudent: _editStudent,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: twoColumns
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 24), children: left),
                              ),
                              const VerticalDivider(width: 1),
                              SizedBox(
                                width: 380,
                                child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: right),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [...left.take(2), ...right, const Divider(height: 48), ...left.skip(2)],
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final when = [
      if (s.weekday != null)
        s.time == null ? weekdayName(s.weekday!) : '${weekdayName(s.weekday!)}, ${s.time} – ${s.endTime}',
      if (s.weekday != null || s.time != null) tr('${s.duration} Minuten', '${s.duration} minutes'),
      if (s.instrument.isNotEmpty) s.instrument,
      ?levelLabel(s.currentLevel()),
      if (s.birthday != null)
        tr('${ageOn(s.birthday!, DateTime.now())} Jahre', '${ageOn(s.birthday!, DateTime.now())} years'),
    ].join(' | ');
    final group = s.isGroup ? null : library.groupOf(s.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(s.isGroup ? Icons.groups_outlined : Icons.person_outline, color: scheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    PopupMenuButton<VoidCallback>(
                      tooltip: tr('Mehr', 'More'),
                      icon: Icon(Icons.more_vert, size: 20, color: scheme.primary),
                      onSelected: (a) => a(),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: _editStudent, child: Text(tr('Angaben bearbeiten …', 'Edit details …'))),
                        if (s.isGroup) PopupMenuItem(value: _editMembers, child: Text(tr('Mitglieder …', 'Members …'))),
                        PopupMenuItem(
                          value: () => _archive(!s.archived),
                          child: Text(
                            s.archived ? tr('Aus dem Archiv holen', 'Restore') : tr('Archivieren', 'Archive'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _delete,
                          child: Text(
                            s.isGroup ? tr('Gruppe auflösen …', 'Dissolve group …') : tr('Löschen …', 'Delete …'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                InkWell(
                  onTap: _editStudent,
                  child: Text(
                    when.isEmpty ? tr('Tag, Zeit und Instrument eintragen …', 'Add day, time and instrument …') : when,
                    style: theme.textTheme.bodyMedium?.copyWith(color: when.isEmpty ? scheme.primary : null),
                  ),
                ),
                // Gruppe: Mitglieder; Mitglied: seine Gruppe. Antippen öffnet die Kartei.
                if (s.isGroup || group != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          s.isGroup ? tr('Mitglieder:', 'Members:') : tr('In der Gruppe:', 'In group:'),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        for (final m in s.isGroup ? _members(s) : [group!])
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(m.isGroup ? Icons.groups_outlined : Icons.person_outline, size: 16),
                            label: Text(m.name),
                            onPressed: widget.onOpen == null ? null : () => widget.onOpen!(m),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _title2(BuildContext context, String text, {List<Widget> trailing = const []}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ...trailing,
      ],
    ),
  );

  Widget _newLesson(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final editing = _editing != null;
    Widget field(String label, RichEditController c, FocusNode focus, String hint) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        RichEditorField(controller: c, focusNode: focus, hint: hint, onLink: () => editLink(context, c)),
      ],
    );
    final lesson = field(tr('Lektion', 'Lesson'), _content, _contentFocus, tr('Lektion …', 'Lesson …'));
    final homework = field(
      tr('Hausaufgaben', 'Homework'),
      _homework,
      _homeworkFocus,
      tr('Hausaufgaben …', 'Homework …'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title2(context, editing ? tr('Lektion bearbeiten', 'Edit lesson') : tr('Neue Lektion', 'New lesson')),
        Row(
          children: [
            Text(tr('Datum', 'Date'), style: theme.textTheme.bodyMedium),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(shortDate(_date)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Werkzeugleiste für das zuletzt angetippte Feld (Lektion oder Hausaufgaben).
        RichToolbar(target: _active),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 520
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lesson),
                    const SizedBox(width: 20),
                    Expanded(child: homework),
                  ],
                )
              : Column(children: [lesson, const SizedBox(height: 16), homework]),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (editing) ...[
              TextButton(onPressed: () => setState(_clear), child: Text(tr('Abbrechen', 'Cancel'))),
              const SizedBox(width: 8),
            ],
            // Speichern und gleich die Hausaufgaben senden.
            Builder(
              builder: (anchor) => OutlinedButton.icon(
                onPressed: _homework.text.trim().isEmpty
                    ? null
                    : () async {
                        final l = await _save(quiet: true);
                        if (l != null && anchor.mounted) {
                          await _send(l, anchor);
                          if (mounted) setState(_clear);
                        }
                      },
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(tr('Speichern & senden', 'Save & send')),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _hasText || editing ? _save : null,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: tr('Speichern', 'Save')),
                    TextSpan(
                      text: '  Ctrl+S',
                      style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pastLessons(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    bool absence(Lesson l) => l.status != LessonStatus.held && l.status != LessonStatus.makeUp;
    // Eigene Lektionen und Absenzen; bei einer Gruppe auch die Absenzen der
    // Mitglieder (mit Namen). Reine „anwesend“-Einträge stehen nur in der Tabelle.
    final all = <({Lesson lesson, Student owner})>[
      for (final l in s.activeLessons)
        if (l.id != _editing && (l.content.trim().isNotEmpty || l.homework.trim().isNotEmpty || absence(l)))
          (lesson: l, owner: s),
      for (final m in _members(s))
        for (final l in m.activeLessons)
          if (absence(l)) (lesson: l, owner: m),
    ]..sort((a, b) => b.lesson.date.compareTo(a.lesson.date));
    final shown = _allLessons ? all : all.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title2(
          context,
          tr('Vergangene Lektionen', 'Past lessons'),
          trailing: [
            const Spacer(),
            if (all.length > shown.length)
              TextButton(
                onPressed: () => setState(() => _allLessons = true),
                child: Text(tr('Alle anzeigen  ›', 'Show all  ›')),
              ),
          ],
        ),
        if (all.isEmpty)
          Text(
            tr('Noch keine.', 'None yet.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        for (final (:lesson, :owner) in shown)
          Builder(
            builder: (context) {
              final l = lesson;
              final isAbsence = absence(l);
              final other = owner.id != s.id;
              final bg = absenceBackground(l.status, theme.brightness);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: bg ?? scheme.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: isAbsence ? () => _editReason(l, owner) : () => _edit(l),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(shortDate(l.date), style: theme.textTheme.titleSmall),
                            const SizedBox(width: 8),
                            Text(
                              _ago(l.date),
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (isAbsence) ...[const SizedBox(width: 10), LessonStatusBadge(l)],
                            if (other) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  owner.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Builder(
                              builder: (anchor) => PopupMenuButton<int>(
                                tooltip: tr('Mehr', 'More'),
                                icon: const Icon(Icons.more_horiz, size: 20),
                                onSelected: (v) => switch (v) {
                                  0 => isAbsence ? _editReason(l, owner) : _edit(l),
                                  1 => _send(l, anchor),
                                  _ => _deleteLesson(l, owner),
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 0,
                                    child: Text(
                                      isAbsence ? tr('Grund bearbeiten', 'Edit reason') : tr('Bearbeiten', 'Edit'),
                                    ),
                                  ),
                                  if (l.homework.trim().isNotEmpty)
                                    PopupMenuItem(
                                      value: 1,
                                      child: Text(tr('Hausaufgaben senden …', 'Send homework …')),
                                    ),
                                  PopupMenuItem(value: 2, child: Text(tr('Löschen', 'Delete'))),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (isAbsence)
                          Text(
                            l.reason.isEmpty ? tr('Kein Grund eingetragen', 'No reason given') : l.reason,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: l.reason.isEmpty ? scheme.onSurfaceVariant : null,
                            ),
                          )
                        else
                          LayoutBuilder(
                            builder: (context, c) {
                              final a = _cell(context, tr('Lektion', 'Lesson'), l.content, l.contentMarks);
                              final b = _cell(context, tr('Hausaufgaben', 'Homework'), l.homework, l.homeworkMarks);
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
                                      children: [a, const SizedBox(height: 10), b],
                                    );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// Text mit Formatierung und Aufzählungen (Zeilen mit „- “, „• “ oder
  /// Nummern), eingerückte Zeilen als Unterpunkte.
  Widget _cell(BuildContext context, String label, String text, List<TextMark> marks) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        RichTextView(text: text, marks: marks, style: theme.textTheme.bodyMedium),
      ],
    );
  }

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

  Widget _repertoire(BuildContext context, Student s) {
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
        leading: Icon(
          done ? Icons.check_circle : Icons.music_note_outlined,
          color: done ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(_title(x), style: TextStyle(fontSize: 15, color: e == null ? scheme.outline : null)),
        subtitle: e == null
            ? Text(tr('Nicht mehr in der Bibliothek', 'No longer in the library'))
            : (e.composer == null || e.composer!.isEmpty ? null : Text(e.composer!)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e?.musicalKey case final k? when k.isNotEmpty) KeyBadge(k),
            PopupMenuButton<int>(
              tooltip: tr('Mehr', 'More'),
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) => v == 0
                  ? _setPiece(x, status: done ? PieceStatus.practising : PieceStatus.learned)
                  : _setPiece(x, delete: true),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 0,
                  child: Text(done ? tr('Wieder üben', 'Practise again') : tr('Kann es', 'Learned')),
                ),
                PopupMenuItem(value: 1, child: Text(tr('Entfernen', 'Remove'))),
              ],
            ),
          ],
        ),
        onTap: e == null ? null : () => _open([...practising, ...learned], x),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title2(
          context,
          tr('Repertoire', 'Repertoire'),
          trailing: [
            const Spacer(),
            if (all.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _addPieces,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Hinzufügen', 'Add')),
              ),
          ],
        ),
        if (all.isEmpty)
          _EmptyBox(
            text: tr('Kein Repertoire erfasst', 'No repertoire yet'),
            action: tr('Stück aus der Bibliothek  ›', 'Piece from the library  ›'),
            onTap: _addPieces,
          ),
        ...practising.map(tile),
        if (all.isNotEmpty && practising.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
            child: Text(
              tr('Gerade wird nichts geübt.', 'Nothing being practised right now.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        // Gelernte Stücke nur auf Wunsch, damit die Liste kurz bleibt.
        if (learned.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showLearned = !_showLearned),
              icon: Icon(_showLearned ? Icons.expand_less : Icons.check_circle_outline, size: 18),
              label: Text(
                _showLearned
                    ? tr('„Kann es“ ausblenden', 'Hide “Learned”')
                    : tr('Kann es (${learned.length})', 'Learned (${learned.length})'),
              ),
            ),
          ),
          if (_showLearned) ...learned.map(tile),
        ],
      ],
    );
  }

  /// To-Dos dieser Kartei (offene; erledigte auf Wunsch).
  Widget _todos(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final all = sortTodos(library.todos.where((t) => t.student == s.id));
    final open = all.where((t) => !t.done).toList();
    final done = all.where((t) => t.done).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title2(
          context,
          tr('To-Dos', 'To-dos'),
          trailing: [
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => showTodoDialog(context, library, student: s.id),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Erstellen', 'Create')),
            ),
          ],
        ),
        if (open.isEmpty)
          _EmptyBox(
            text: tr('Nichts offen', 'Nothing open'),
            action: null,
            onTap: () => showTodoDialog(context, library, student: s.id),
          ),
        for (final t in open) TodoTile(todo: t, library: library),
        if (done.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _doneTodos = !_doneTodos),
              child: Text(
                _doneTodos
                    ? tr('Erledigte ausblenden', 'Hide done')
                    : tr('Erledigte anzeigen (${done.length})', 'Show done (${done.length})'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        if (_doneTodos)
          for (final t in done) TodoTile(todo: t, library: library),
      ],
    );
  }

  Widget _memos(BuildContext context, Student s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final memos = s.activeMemos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title2(
          context,
          tr('Notizen', 'Notes'),
          trailing: [
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _editMemo(null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Erstellen', 'Create')),
            ),
          ],
        ),
        if (memos.isEmpty)
          _EmptyBox(text: tr('Noch keine Notizen', 'No notes yet'), action: null, onTap: () => _editMemo(null)),
        for (final m in memos)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: scheme.primary, width: 4)),
            ),
            child: InkWell(
              onTap: () => _editMemo(m),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.title.isEmpty ? tr('Notiz', 'Note') : m.title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        PopupMenuButton<int>(
                          tooltip: tr('Mehr', 'More'),
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (v) => v == 0 ? _editMemo(m) : _deleteMemo(m),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 0, child: Text(tr('Bearbeiten', 'Edit'))),
                            PopupMenuItem(value: 1, child: Text(tr('Löschen', 'Delete'))),
                          ],
                        ),
                      ],
                    ),
                    if (m.text.isNotEmpty) RichTextView(text: m.text, marks: m.marks),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Leerer Bereich mit Hinweis (antippen = hinzufügen).
class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text, required this.action, required this.onTap});
  final String text;
  final String? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            Text(text, style: theme.textTheme.bodyMedium),
            if (action != null) ...[
              const SizedBox(height: 6),
              Text(action!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

String lessonStatusLabel(LessonStatus s) => switch (s) {
  LessonStatus.held => tr('Gehalten', 'Held'),
  LessonStatus.excused => tr('Entschuldigt', 'Excused'),
  LessonStatus.missed => tr('Unentschuldigt', 'Unexcused'),
  LessonStatus.cancelled => tr('Ausfall', 'Cancelled'),
  LessonStatus.makeUp => tr('Nachgeholt', 'Made up'),
};

/// Kleines farbiges Schild für eine Absenz.
class LessonStatusBadge extends StatelessWidget {
  const LessonStatusBadge(this.lesson, {super.key});
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (lesson.status) {
      LessonStatus.excused => const Color(0xFFB07A00),
      LessonStatus.missed => scheme.error,
      LessonStatus.cancelled => scheme.outline,
      _ => scheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: color.withValues(alpha: 0.14)),
      child: Text(
        lessonStatusLabel(lesson.status),
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
