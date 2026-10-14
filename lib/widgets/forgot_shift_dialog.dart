import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/attendance.dart';
import '../models/mechanic.dart';
import '../services/attendance_service.dart';
import '../theme/app_theme.dart';

/// Diálogo que aparece al iniciar sesión cuando el mecánico dejó un turno
/// abierto de otro día. Pide la hora real de salida y cierra el turno;
/// el registro queda marcado como cerrado a mano, pendiente de que el
/// administrador confirme que la hora es correcta.
/// No se puede descartar sin cerrar el turno.
Future<bool> showForgotShiftDialog(
  BuildContext context,
  Mechanic mechanic,
  AttendanceRecord stale,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ForgotShiftDialog(
      mechanic: mechanic,
      stale: stale,
    ),
  );
  return result == true;
}

class _ForgotShiftDialog extends StatefulWidget {
  final Mechanic mechanic;
  final AttendanceRecord stale;

  const _ForgotShiftDialog({
    required this.mechanic,
    required this.stale,
  });

  @override
  State<_ForgotShiftDialog> createState() =>
      _ForgotShiftDialogState();
}

class _ForgotShiftDialogState extends State<_ForgotShiftDialog> {
  TimeOfDay _picked = const TimeOfDay(hour: 18, minute: 0);
  String? _error;
  bool _busy = false;

  Future<void> _chooseTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _picked,
      helpText: t('forgot_shift_dialog_time_help'),
    );
    if (picked != null) setState(() => _picked = picked);
  }

  Future<void> _close() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final d = widget.stale.date;
    final clockOut = DateTime(
        d.year, d.month, d.day, _picked.hour, _picked.minute);
    try {
      await AttendanceService.closeStaleShift(
          widget.mechanic.id, clockOut);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = t('forgot_shift_dialog_close_error');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stale = widget.stale;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          const Text('🕐', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(t('forgot_shift_dialog_title')),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('forgot_shift_dialog_body', {
              'day': formatDay(stale.date),
              'time': formatClock(stale.clockIn),
            }),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _chooseTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.schedule,
                      color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Text(
                    _picked.format(context),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            t('forgot_shift_dialog_admin_confirm'),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _busy ? null : _close,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 20),
            backgroundColor: Colors.green.shade700,
          ),
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(t('forgot_shift_dialog_close_shift'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
