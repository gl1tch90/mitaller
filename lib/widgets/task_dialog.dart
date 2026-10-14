import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/mechanic.dart';
import '../models/task.dart';
import '../services/mechanic_service.dart';
import '../services/task_service.dart';
import '../theme/app_theme.dart';

/// Datos capturados en el diálogo de crear/editar tarea.
class TaskFormResult {
  final String title;
  final String description;
  final String mechanicId;
  final TaskStatus status;

  const TaskFormResult({
    required this.title,
    required this.description,
    required this.mechanicId,
    required this.status,
  });
}

/// Diálogo para crear o editar una tarea del taller.
/// Devuelve los datos capturados o null si se canceló.
Future<TaskFormResult?> showTaskDialog(
  BuildContext context, {
  Task? existing,
  required List<Mechanic> mechanics,
}) async {
  // Al crear, mostrar las tareas ya asignadas para ver qué hay.
  List<Task> assigned = [];
  Map<String, String> names = {};
  if (existing == null) {
    final all = await TaskService().loadTasks();
    assigned =
        all.where((t) => t.status != TaskStatus.done).toList();
    names = {for (final m in mechanics) m.id: m.name};
    if (names.length < all.length) {
      final more = await MechanicService().loadMechanics();
      names = {for (final m in more) m.id: m.name};
    }
  }
  if (!context.mounted) return null;
  return showDialog<TaskFormResult>(
    context: context,
    builder: (ctx) => _TaskDialog(
      existing: existing,
      mechanics: mechanics,
      assigned: assigned,
      names: names,
    ),
  );
}

/// El diálogo es dueño de sus controladores: los libera en su propio
/// dispose (hacerlo al cerrarse desde fuera truena los TextField con
/// pantalla roja).
class _TaskDialog extends StatefulWidget {
  final Task? existing;
  final List<Mechanic> mechanics;
  final List<Task> assigned;
  final Map<String, String> names;

  const _TaskDialog({
    required this.existing,
    required this.mechanics,
    required this.assigned,
    required this.names,
  });

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _descCtrl =
      TextEditingController(
          text: widget.existing?.description ?? '');
  late String _mechanicId = widget.existing?.mechanicId ??
      (widget.mechanics.isNotEmpty
          ? widget.mechanics.first.id
          : '');
  late TaskStatus _status =
      widget.existing?.status ?? TaskStatus.pending;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('admin_task_valid_title'))),
      );
      return;
    }
    Navigator.of(context).pop(TaskFormResult(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      mechanicId: _mechanicId,
      status: _status,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(existing == null
          ? t('admin_task_assign_title')
          : t('admin_task_edit_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              textCapitalization:
                  TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t('admin_task_title_label'),
                hintText: t('admin_task_title_hint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              textCapitalization:
                  TextCapitalization.sentences,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t('admin_task_desc_label'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: widget.mechanics
                      .any((m) => m.id == _mechanicId)
                  ? _mechanicId
                  : (widget.mechanics.isNotEmpty
                      ? widget.mechanics.first.id
                      : null),
              decoration: InputDecoration(
                  labelText: t('admin_task_assign_to')),
              items: widget.mechanics
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(
                  () => _mechanicId = v ?? _mechanicId),
            ),
            if (existing == null &&
                widget.assigned.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.surfaceLight),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('admin_tasks_header'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final at in widget.assigned)
                      Padding(
                        padding:
                            const EdgeInsets.only(
                                bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: at.status ==
                                      TaskStatus.inReview
                                  ? Colors.purpleAccent
                                  : AppTheme.accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${at.title} — ${widget.names[at.mechanicId] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (existing != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskStatus>(
                value: _status,
                decoration: InputDecoration(
                    labelText:
                        t('admin_task_status_label')),
                items: TaskStatus.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _status = v ?? _status),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t('common_cancel')),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(t('common_save')),
        ),
      ],
    );
  }
}
