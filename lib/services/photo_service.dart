import '../l10n/strings.dart';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Toma y guarda las fotos de condición del vehículo.
///
/// Las fotos se comprimen al capturarlas (maxWidth 1600, calidad 70):
/// cada foto pesa ~200-400 KB en lugar de 3-5 MB, así 4 fotos ≈ 1 MB
/// por vehículo y no se llena el teléfono.
///
/// Se guardan en la carpeta de documentos de la app:
/// `tickets/<ticketId>/<slot>.jpg`
///
/// NOTA iOS: agregar en Info.plist la clave NSCameraUsageDescription
/// con un texto como "Se usa la cámara para registrar la condición
/// del vehículo al recibirlo."
class PhotoService {
  static const List<String> slots = ['front', 'rear', 'left', 'right'];

  static Map<String, String> get slotLabels => {
        'front': t('photo_front'),
        'rear': t('photo_rear'),
        'left': t('photo_left'),
        'right': t('photo_right'),
      };

  final ImagePicker _picker = ImagePicker();

  /// Abre la cámara y guarda la foto comprimida. Devuelve la ruta
  /// del archivo guardado, o null si el usuario canceló.
  Future<String?> capture(String ticketId, String slot) async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (xfile == null) return null;
    final dir = await _ticketDir(ticketId);
    final dest = File('${dir.path}/$slot.jpg');
    // Sobrescribe si ya había foto en ese ángulo (retomar).
    await File(xfile.path).copy(dest.path);
    return dest.path;
  }

  /// Borra el archivo de una foto.
  Future<void> remove(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  Future<Directory> _ticketDir(String ticketId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/tickets/$ticketId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
