import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/todo.dart';
import '../library/library_controller.dart';
import 'homework_share.dart' show shortDate;

/// To-Do anlegen oder bearbeiten. [student]: vorgewählte Kartei (bei einer
/// Kartei fest, im To-Do-Bereich wählbar, wenn [chooseStudent]).
Future<void> showTodoDialog(
  BuildContext context,
  LibraryController library, {
  Todo? todo,
  String? student,
  bool chooseStudent = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _TodoDialog(library: library, todo: todo, student: student, chooseStudent: chooseStudent),
);

class _TodoDialog extends StatefulWidget {
  const _TodoDialog({required this.library, this.todo, this.student, required this.chooseStudent});
  final LibraryController library;
  final Todo? todo;
  final String? student;
  final bool chooseStudent;

  @override
  State<_TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends State<_TodoDialog> {
  late final _text = TextEditingController(text: widget.todo?.text ?? '');
  late DateTime? _due = widget.todo?.due;
  late String? _student = widget.todo?.student ?? widget.student;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final t = widget.todo ?? Todo.create(text);
    t
      ..text = text
      ..due = _due
      ..student = _student;
    await widget.library.saveTodo(t);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final students = widget.library.students.where((s) => !s.archived).toList();
    return AlertDialog(
      title: Text(widget.todo == null ? tr('Neues To-Do', 'New to-do') : tr('To-Do', 'To-do')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('Was ist zu tun?', 'What needs doing?')),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_due == null ? tr('Ohne Termin', 'No due date') : shortDate(_due!)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _due ?? now,
                      firstDate: DateTime(now.year - 2),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (d != null) setState(() => _due = d);
                  },
                ),
                if (_due != null)
                  IconButton(
                    tooltip: tr('Termin entfernen', 'Remove date'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _due = null),
                  ),
              ],
            ),
            if (widget.chooseStudent) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: students.any((s) => s.id == _student) ? _student : null,
                decoration: InputDecoration(labelText: tr('Für', 'For')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Allgemein', 'General'))),
                  for (final s in students) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _student = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.todo != null)
          TextButton(
            onPressed: () async {
              await widget.library.deleteTodo(widget.todo!);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(tr('Löschen', 'Delete')),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: _save, child: Text(tr('Speichern', 'Save'))),
      ],
    );
  }
}

/// Offene zuerst (nach Termin, ohne Termin zuletzt), erledigte danach.
List<Todo> sortTodos(Iterable<Todo> todos) => todos.toList()
  ..sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    final ad = a.due, bd = b.due;
    if (ad != null && bd != null) return ad.compareTo(bd);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return a.created.compareTo(b.created);
  });

/// Eine To-Do-Zeile mit Häkchen. Antippen öffnet sie zum Bearbeiten.
class TodoTile extends StatelessWidget {
  const TodoTile({super.key, required this.todo, required this.library, this.showStudent = false, this.onOpenStudent});
  final Todo todo;
  final LibraryController library;
  final bool showStudent;
  final void Function(String studentId)? onOpenStudent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final overdue = todo.overdue(now);
    final today = todo.due != null && DateUtils.isSameDay(todo.due, now);
    final who = todo.student == null ? null : library.studentById(todo.student!);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 0, right: 4),
      dense: true,
      leading: Checkbox(
        value: todo.done,
        onChanged: (v) async {
          todo.done = v ?? false;
          await library.saveTodo(todo);
        },
      ),
      title: Text(
        todo.text,
        style: TextStyle(
          fontSize: 15,
          decoration: todo.done ? TextDecoration.lineThrough : null,
          color: todo.done ? scheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: (todo.due == null && (!showStudent || who == null))
          ? null
          : Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (todo.due != null)
                  Text(
                    today
                        ? tr('heute', 'today')
                        : overdue
                        ? tr('überfällig · ${shortDate(todo.due!)}', 'overdue · ${shortDate(todo.due!)}')
                        : shortDate(todo.due!),
                    style: TextStyle(
                      color: overdue ? scheme.error : (today ? scheme.primary : scheme.onSurfaceVariant),
                      fontWeight: overdue || today ? FontWeight.w600 : null,
                    ),
                  ),
                if (showStudent && who != null)
                  InkWell(
                    onTap: onOpenStudent == null ? null : () => onOpenStudent!(who.id),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          who.isGroup ? Icons.groups_outlined : Icons.person_outline,
                          size: 14,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(who.name, style: TextStyle(color: scheme.primary)),
                      ],
                    ),
                  ),
              ],
            ),
      onTap: () => showTodoDialog(context, library, todo: todo, chooseStudent: showStudent),
    );
  }
}
