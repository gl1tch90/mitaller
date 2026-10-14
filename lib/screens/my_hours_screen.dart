import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../models/mechanic.dart';
import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../services/attendance_service.dart';
import '../widgets/live_hours.dart';
import '../theme/app_theme.dart';

/// Horas de la semana actual (lunes a domingo) del mecánico en sesión.
/// Solo ve sus propios registros y solo los de esta semana; no puede
/// generar reportes PDF (eso es solo del administrador).
class MyHoursScreen extends StatefulWidget {
  final Mechanic mechanic;

  const MyHoursScreen({super.key, required this.mechanic});

  @override
  State<MyHoursScreen> createState() => _MyHoursScreenState();
}

class _MyHoursScreenState extends LocaleAwareState<MyHoursScreen> {
  List<AttendanceRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all =
        await AttendanceService.getByMechanic(widget.mechanic.id);
    final ws = weekStart(DateTime.now());
    final recs =
        all.where((r) => weekStart(r.date) == ws).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (mounted) {
      setState(() {
        _records = recs;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = weekStart(DateTime.now());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Incluye lo que va corriendo del turno abierto, si lo hay.
    final total =
        _records.fold<double>(0, (s, r) => s + r.hoursSoFar);
    final todayRecs =
        _records.where((r) => r.date == today).toList();
    final hasOpenToday = todayRecs.any((r) => r.isOpen);

    return Scaffold(
      appBar: AppBar(title: Text(t('my_hours_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.surfaceLight, width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatWeekRange(ws),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        formatHours(total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Lo que va del día, en vivo si hay turno abierto.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: hasOpenToday
                          ? Colors.greenAccent.withValues(alpha: 0.6)
                          : AppTheme.surfaceLight,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (hasOpenToday)
                        Container(
                          width: 10,
                          height: 10,
                          margin:
                              const EdgeInsets.only(right: 10),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          t('my_hours_today') +
                              (hasOpenToday
                                  ? ' · ${t('my_hours_in_progress')}'
                                  : ''),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      LiveHoursText.sum(
                        records: todayRecs,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.greenAccent,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      t('my_hours_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 15),
                    ),
                  )
                else
                  ..._records.map(
                    (r) => Container(
                      margin:
                          const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius:
                            BorderRadius.circular(16),
                        border: Border.all(
                            color: AppTheme.surfaceLight,
                            width: 1),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          formatWeekday(r.date),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text.rich(
                          TextSpan(
                            style:
                                const TextStyle(fontSize: 13),
                            children: [
                              TextSpan(
                                  text:
                                      '${formatDay(r.date)}\n'),
                              TextSpan(
                                text: t('my_hours_clock_in', {
                                  'time': formatClock(r.clockIn),
                                }),
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: '   '),
                              TextSpan(
                                text: r.isOpen
                                    ? t('my_hours_clock_out_open')
                                    : t('my_hours_clock_out', {
                                        'time':
                                            formatClock(r.clockOut!),
                                      }),
                                style: TextStyle(
                                  color: r.isOpen
                                      ? AppTheme.textSecondary
                                      : Colors.orangeAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: r.isOpen
                            ? LiveHoursText(
                                record: r,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.greenAccent,
                                  fontSize: 15,
                                ),
                              )
                            : Text(
                                formatHours(r.hoursWorked),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accent,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
