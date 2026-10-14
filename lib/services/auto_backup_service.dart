import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

/// Respaldo automático semanal a Descargas/MiTaller/.
///
/// Cada 7 días (al abrir la app) genera el mismo JSON del respaldo manual
/// y lo guarda en la carpeta compartida Descargas/MiTaller/ usando
/// MediaStore (canal nativo), así sobrevive a desinstalar la app.
/// Conserva los 5 más recientes y borra los viejos.
class AutoBackupService {
  static const MethodChannel _channel =
      MethodChannel('georges_garage/media');

  /// Clave con la fecha del último respaldo automático (ISO 8601).
  static const String lastBackupKey = 'auto_backup_last';

  /// Si el respaldo automático está activado.
  static const String enabledKey = 'auto_backup_enabled';

  /// Cada cuántos días se hace (clave).
  static const String intervalKey = 'auto_backup_interval_days';

  /// Intervalo por defecto en días.
  static const int defaultIntervalDays = 7;

  /// Cuántos respaldos se conservan (los más recientes).
  static const int keepCount = 5;

  /// Opciones de intervalo que se ofrecen en la UI.
  static const List<int> intervalOptions = [3, 7, 15, 30];

  const AutoBackupService();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
  }

  Future<int> getIntervalDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(intervalKey) ?? defaultIntervalDays;
  }

  Future<void> setIntervalDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(intervalKey, days);
  }

  /// Revisa si toca respaldo y lo hace en segundo plano.
  /// No lanza excepciones: un fallo aquí nunca debe tumbar la app.
  Future<void> maybeBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(enabledKey) ?? true)) return;
      final interval = prefs.getInt(intervalKey) ?? defaultIntervalDays;
      final lastRaw = prefs.getString(lastBackupKey);
      if (lastRaw != null) {
        final last = DateTime.tryParse(lastRaw);
        if (last != null &&
            DateTime.now().difference(last).inDays < interval) {
          return; // Todavía no toca.
        }
      }
      await runBackup();
      await prefs.setString(
          lastBackupKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Silencioso: el respaldo automático es un extra, no debe molestar.
    }
  }

  /// Genera el respaldo y lo guarda en Descargas/MiTaller/.
  /// Devuelve el nombre del archivo creado.
  Future<String> runBackup() async {
    final file = await const BackupService().exportBackup();
    final bytes = await file.readAsBytes();
    final name = await saveToDownloads(bytes);
    try {
      await file.delete();
    } catch (_) {}
    return name;
  }

  /// Guarda un respaldo en Descargas/MiTaller/ (visible en Mis archivos).
  /// [prefix] distingue el origen, ej. 'manual'. Devuelve el nombre creado.
  /// Cuenta para los 5 recientes (se borran los más viejos).
  Future<String> saveToDownloads(List<int> bytes, {String? prefix}) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}-${_two(now.month)}-${_two(now.day)}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final tag = prefix == null ? '' : '$prefix-';
    final name = 'mitaller-respaldo-$tag$stamp.json';
    await _channel.invokeMethod('saveBackup', {
      'name': name,
      'bytes': bytes,
    });
    await _pruneOld();
    return name;
  }

  /// Borra los respaldos viejos dejando solo los [keepCount] recientes.
  Future<void> _pruneOld() async {
    final raw = await _channel.invokeMethod('listBackups');
    final names = (raw as List).map((e) => e.toString()).toList()
      ..sort();
    while (names.length > keepCount) {
      final oldest = names.removeAt(0);
      try {
        await _channel.invokeMethod('deleteBackup', {
          'name': oldest,
        });
      } catch (_) {}
    }
  }

  /// Fecha del último respaldo automático, o null si nunca se ha hecho.
  Future<DateTime?> lastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(lastBackupKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
