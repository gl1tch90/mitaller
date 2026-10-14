/// Registro de asistencia: entrada y salida de un mecánico en un día.
import '../l10n/strings.dart';

class AttendanceRecord {
  final String id;
  final String mechanicId;
  final DateTime date; // Día del registro (sin hora).
  final DateTime clockIn;
  final DateTime? clockOut;

  /// True si la salida se registró a mano por olvido (turno de otro día
  /// que quedó abierto). Estos registros quedan pendientes de que el
  /// administrador confirme que la hora es correcta.
  final bool manualClose;

  /// El administrador ya verificó la hora de este registro.
  /// Los registros normales nacen confirmados; los cerrados a mano no.
  final bool confirmed;

  AttendanceRecord({
    required this.id,
    required this.mechanicId,
    required this.date,
    required this.clockIn,
    this.clockOut,
    this.manualClose = false,
    this.confirmed = true,
  });

  bool get isOpen => clockOut == null;

  /// ¿La hora de este registro aún está por confirmar por el admin?
  bool get needsConfirmation => manualClose && !confirmed;

  /// Horas trabajadas (0 si aún no registra salida).
  double get hoursWorked {
    if (clockOut == null) return 0;
    return clockOut!.difference(clockIn).inMinutes / 60.0;
  }

  /// Horas hasta ahora: si el turno sigue abierto, se calcula con
  /// la hora actual (para ver "el tiempo que va en el día").
  double get hoursSoFar {
    if (clockOut != null) return hoursWorked;
    return DateTime.now().difference(clockIn).inMinutes / 60.0;
  }

  AttendanceRecord copyWith({
    DateTime? clockIn,
    DateTime? clockOut,
    bool? manualClose,
    bool? confirmed,
  }) {
    return AttendanceRecord(
      id: id,
      mechanicId: mechanicId,
      date: date,
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      manualClose: manualClose ?? this.manualClose,
      confirmed: confirmed ?? this.confirmed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mechanicId': mechanicId,
        'date': date.toIso8601String(),
        'clockIn': clockIn.toIso8601String(),
        'clockOut': clockOut?.toIso8601String(),
        'manualClose': manualClose,
        'confirmed': confirmed,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as String,
      mechanicId: json['mechanicId'] as String,
      date: DateTime.parse(json['date'] as String),
      clockIn: DateTime.parse(json['clockIn'] as String),
      clockOut: json['clockOut'] == null
          ? null
          : DateTime.parse(json['clockOut'] as String),
      // Compatibilidad con registros guardados antes de esta función.
      manualClose: json['manualClose'] as bool? ?? false,
      confirmed: json['confirmed'] as bool? ?? true,
    );
  }
}

/// "29/09/2026"
String formatDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// "08:15"
String formatClock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "8.5 h"
String formatHours(double h) =>
    '${h.toStringAsFixed(1).replaceAll('.', ',')} h';

const _monthAbbrKeys = [
  'income_abbr_jan',
  'income_abbr_feb',
  'income_abbr_mar',
  'income_abbr_apr',
  'income_abbr_may',
  'income_abbr_jun',
  'income_abbr_jul',
  'income_abbr_aug',
  'income_abbr_sep',
  'income_abbr_oct',
  'income_abbr_nov',
  'income_abbr_dec',
];

const _weekdayKeys = [
  'income_monday',
  'income_tuesday',
  'income_wednesday',
  'income_thursday',
  'income_friday',
  'income_saturday',
  'income_sunday',
];

/// Lunes de la semana a la que pertenece [d] (la semana va de lunes a domingo).
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// "Semana del 28 sep al 4 oct" / "Week of Sep 28 to Oct 4"
String formatWeekRange(DateTime start) {
  final end = start.add(const Duration(days: 6));
  return t('dates_week_range', {
    'd1': '${start.day}',
    'm1': t(_monthAbbrKeys[start.month - 1]),
    'd2': '${end.day}',
    'm2': t(_monthAbbrKeys[end.month - 1]),
  });
}

/// "Lunes" / "Monday" (DateTime.weekday: lunes = 1).
String formatWeekday(DateTime d) {
  final n = t(_weekdayKeys[d.weekday - 1]);
  return n[0].toUpperCase() + n.substring(1);
}
