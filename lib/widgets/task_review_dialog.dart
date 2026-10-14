import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';

/// Pregunta al admin/fundador si la tarea marcada como terminada
/// realmente se completó.
/// Devuelve true (✓ terminada), false (✕ incompleta) o null (canceló).
Future<bool?> showTaskReviewDialog(
  BuildContext context, {
  required Task task,
  required String assigneeName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: [
          const Icon(Icons.fact_check,
              color: AppTheme.accent, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(task.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                task.description,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14),
              ),
            ),
          Text(
            t('admin_task_assign_to') + ': $assigneeName',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            t('task_review_title'),
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(ctx).pop(false),
          icon: const Icon(Icons.close, color: Colors.redAccent),
          label: Text(
            t('task_review_reject'),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.check),
          label: Text(t('task_review_done')),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}
