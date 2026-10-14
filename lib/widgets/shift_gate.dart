import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/mechanic.dart';
import '../services/attendance_service.dart';
import '../theme/app_theme.dart';
import 'forgot_shift_dialog.dart';

/// ¿El mecánico puede trabajar? El administrador (jefe) siempre puede;
/// los demás necesitan tener su turno iniciado HOY
/// (entrada registrada sin salida registrada).
/// Un turno que quedó abierto de otro día no cuenta: primero hay que
/// cerrarlo con la hora real de salida (diálogo al iniciar sesión).
Future<bool> isOnShift(Mechanic mechanic) async {
  if (mechanic.isAdmin) return true;
  final open =
      await AttendanceService.getOpenShift(mechanic.id);
  if (open == null) return false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return !open.date.isBefore(today);
}

/// Registra la entrada manejando el turno olvidado: si quedó un turno
/// abierto de otro día, primero pide la hora real de salida. Devuelve
/// true si el mecánico quedó en turno.
Future<bool> clockInWithStaleCheck(
    BuildContext context, Mechanic mechanic) async {
  // Si quedó un turno abierto de otro día, hay que cerrarlo primero:
  // clockIn no crea uno nuevo mientras haya uno abierto.
  final stale =
      await AttendanceService.getStaleShift(mechanic.id);
  if (stale != null && context.mounted) {
    final closed = await showForgotShiftDialog(
        context, mechanic, stale);
    if (!closed) return false;
  }
  await AttendanceService.clockIn(mechanic.id);
  return true;
}

/// Tarjeta que bloquea una acción hasta que el mecánico registre su entrada.
/// Incluye el botón para iniciar el turno ahí mismo, sin ir al menú.
class ShiftGateCard extends StatelessWidget {
  final Mechanic mechanic;
  final VoidCallback onShiftStarted;

  /// Qué acción queda bloqueada, ej. "empezar a trabajar", "crear la orden".
  /// Si no se pasa, se usa el texto por defecto localizado.
  final String? actionLabel;

  const ShiftGateCard({
    super.key,
    required this.mechanic,
    required this.onShiftStarted,
    this.actionLabel,
  });

  Future<void> _clockIn(BuildContext context) async {
    final ok = await clockInWithStaleCheck(context, mechanic);
    if (!ok) return;
    onShiftStarted();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('shift_gate_shift_started'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.amber.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🕐', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('shift_gate_title'),
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t('shift_gate_need_shift', {
              'action':
                  actionLabel ?? t('shift_gate_action_default'),
            }),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _clockIn(context),
              icon: const Text('⇤',
                  style: TextStyle(fontSize: 18)),
              label: Text(t('shift_gate_clock_in'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
