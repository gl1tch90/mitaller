import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

/// Respaldo y restauración de todos los datos de la app.
///
/// Guarda TODO lo que está en SharedPreferences (mecánicos, órdenes,
/// tickets, turnos, catálogos) más las fotos de condición de los tickets,
/// en un solo archivo JSON que se puede mandar por WhatsApp y restaurar
/// en otro teléfono.
class BackupService {
  static const String marker = 'georges_garage_backup';
  static const int version = 1;

  /// Para pruebas: permite inyectar otro directorio de documentos.
  final Directory? docsDirOverride;

  /// Para pruebas: permite inyectar otro directorio temporal.
  final Directory? tempDirOverride;

  const BackupService({this.docsDirOverride, this.tempDirOverride});

  Future<Directory> _docsDir() async =>
      docsDirOverride ?? await getApplicationDocumentsDirectory();

  /// Genera el archivo de respaldo y lo devuelve listo para compartir.
  Future<File> exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {};
    for (final k in prefs.getKeys()) {
      data[k] = prefs.get(k);
    }

    // Fotos: todo lo que vive bajo <docs>/tickets/ y <docs>/shop_vehicles/
    final photos = <String, String>{};
    final docs = await _docsDir();
    for (final sub in ['tickets', 'shop_vehicles', 'orders']) {
      final dir = Directory('${docs.path}/$sub');
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) {
          final rel = e.path.substring(docs.path.length + 1);
          photos[rel] = base64Encode(await e.readAsBytes());
        }
      }
    }

    final payload = {
      'app': marker,
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'prefs': data,
      'photos': photos,
    };

    final tmp = tempDirOverride ?? await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${tmp.path}/mitaller-respaldo-$stamp.json');
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  /// Lee y valida un archivo de respaldo. Lanza [FormatException]
  /// si no es un respaldo válido de esta app.
  static Future<BackupSummary> readBackup(File file) async {
    final payload =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (payload['app'] != marker) {
      throw FormatException(t('backup_invalid'));
    }
    final prefs = (payload['prefs'] as Map).cast<String, dynamic>();
    final photos = (payload['photos'] as Map?)?.length ?? 0;
    return BackupSummary(
      exportedAt: DateTime.tryParse(payload['exportedAt'] as String? ?? ''),
      recordCount: prefs.length,
      photoCount: photos,
    );
  }

  /// Restaura el respaldo: REEMPLAZA todos los datos actuales del teléfono.
  Future<void> restoreBackup(File file) async {
    final payload =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (payload['app'] != marker) {
      throw FormatException(t('backup_invalid'));
    }
    final newData = (payload['prefs'] as Map).cast<String, dynamic>();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    for (final e in newData.entries) {
      final v = e.value;
      if (v is String) {
        await prefs.setString(e.key, v);
      } else if (v is int) {
        await prefs.setInt(e.key, v);
      } else if (v is double) {
        await prefs.setDouble(e.key, v);
      } else if (v is bool) {
        await prefs.setBool(e.key, v);
      } else if (v is List) {
        await prefs.setStringList(e.key, v.cast<String>());
      }
    }

    final docs = await _docsDir();
    final photos = (payload['photos'] as Map?)?.cast<String, String>() ?? {};
    for (final e in photos.entries) {
      final f = File('${docs.path}/${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(base64Decode(e.value));
    }
  }
}

class BackupSummary {
  final DateTime? exportedAt;
  final int recordCount;
  final int photoCount;

  const BackupSummary({
    required this.exportedAt,
    required this.recordCount,
    required this.photoCount,
  });
}
