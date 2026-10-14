import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';
import '../models/attendance.dart';

/// Guarda los registros de entrada/salida en el teléfono.
class AttendanceService {
  static const _key = 'attendance_records';

  static Future<List<AttendanceRecord>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            AttendanceRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> _saveAll(List<AttendanceRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  /// Turno abierto (con entrada pero sin salida) del mecánico, si hay.
  static Future<AttendanceRecord?> getOpenShift(
      String mechanicId) async {
    final all = await getAll();
    for (final r in all) {
      if (r.mechanicId == mechanicId && r.isOpen) return r;
    }
    return null;
  }

  /// Turno que quedó abierto de un día anterior (se olvidó registrar
  /// la salida). Mientras exista, el mecánico no se considera en turno.
  static Future<AttendanceRecord?> getStaleShift(
      String mechanicId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final all = await getAll();
    for (final r in all) {
      if (r.mechanicId == mechanicId &&
          r.isOpen &&
          r.date.isBefore(today)) return r;
    }
    return null;
  }

  /// Cierra un turno olvidado con la hora de salida que indica el mecánico.
  /// El registro queda marcado como cerrado a mano y pendiente de que el
  /// administrador confirme que la hora es correcta.
  /// Lanza [ArgumentError] si la hora no es válida.
  static Future<AttendanceRecord> closeStaleShift(
      String mechanicId, DateTime clockOut) async {
    final all = await getAll();
    final idx = all.indexWhere(
        (r) => r.mechanicId == mechanicId && r.isOpen);
    if (idx == -1) throw StateError('No hay turno abierto');
    final open = all[idx];
    if (!clockOut.isAfter(open.clockIn)) {
      throw ArgumentError(t('attendance_clockout_after_clockin',
          {'clock': formatClock(open.clockIn)}));
    }
    if (clockOut.isAfter(DateTime.now())) {
      throw ArgumentError(t('attendance_clockout_not_future'));
    }
    all[idx] = open.copyWith(
      clockOut: clockOut,
      manualClose: true,
      confirmed: false,
    );
    await _saveAll(all);
    return all[idx];
  }

  /// El administrador confirma que la hora de un cierre manual es correcta.
  static Future<void> confirmShift(String id) async {
    final all = await getAll();
    final idx = all.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(confirmed: true);
    await _saveAll(all);
  }

  /// El administrador corrige la hora de salida de un registro.
  /// Corregir implica darlo por confirmado.
  static Future<void> correctShift(String id, DateTime clockOut) async {    final all = await getAll();
    final idx = all.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final r = all[idx];
    if (!clockOut.isAfter(r.clockIn)) {
      throw ArgumentError(t('attendance_clockout_after_clockin',
          {'clock': formatClock(r.clockIn)}));
    }
    if (clockOut.isAfter(DateTime.now())) {
      throw ArgumentError(t('attendance_clockout_not_future'));
    }
    all[idx] = r.copyWith(clockOut: clockOut, confirmed: true);
    await _saveAll(all);
  }

  /// El administrador corrige la hora de entrada de un registro
  /// (p. ej. el empleado llegó a las 7 pero registró su entrada a las 8).
  /// Corregir implica darlo por confirmado.
  static Future<void> correctClockIn(String id, DateTime clockIn) async {
    final all = await getAll();
    final idx = all.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final r = all[idx];
    if (r.clockOut != null && !clockIn.isBefore(r.clockOut!)) {
      throw ArgumentError(t('attendance_clockin_before_clockout',
          {'clock': formatClock(r.clockOut!)}));
    }
    if (clockIn.isAfter(DateTime.now())) {
      throw ArgumentError(t('attendance_clockin_not_future'));
    }
    all[idx] = r.copyWith(clockIn: clockIn, confirmed: true);
    await _saveAll(all);
  }

  /// Registros cerrados a mano que el administrador aún no confirma.
  static Future<List<AttendanceRecord>> pendingConfirmation() async {
    final all = await getAll();
    return all.where((r) => r.needsConfirmation).toList();
  }

  /// Registra la entrada. Si ya hay un turno abierto, lo devuelve sin duplicar.
  static Future<AttendanceRecord> clockIn(String mechanicId) async {
    final open = await getOpenShift(mechanicId);
    if (open != null) return open;
    final now = DateTime.now();
    final rec = AttendanceRecord(
      id: now.millisecondsSinceEpoch.toString(),
      mechanicId: mechanicId,
      date: DateTime(now.year, now.month, now.day),
      clockIn: now,
    );
    final all = await getAll();
    all.add(rec);
    await _saveAll(all);
    return rec;
  }

  /// Registra la salida del turno abierto. Devuelve el registro completado.
  static Future<AttendanceRecord?> clockOut(String mechanicId) async {
    final all = await getAll();
    final idx = all.indexWhere(
        (r) => r.mechanicId == mechanicId && r.isOpen);
    if (idx == -1) return null;
    final now = DateTime.now();
    all[idx] = all[idx].copyWith(clockOut: now);
    await _saveAll(all);
    return all[idx];
  }

  /// Registros de un mecánico, del más reciente al más antiguo.
  static Future<List<AttendanceRecord>> getByMechanic(
      String mechanicId) async {
    final all = await getAll();
    final list =
        all.where((r) => r.mechanicId == mechanicId).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Borra un registro (corrección del administrador).
  static Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((r) => r.id == id);
    await _saveAll(all);
  }
}
