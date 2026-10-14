import 'package:shared_preferences/shared_preferences.dart';

/// Nombre comercial del taller que usa la app.
///
/// Cada instalación configura el suyo (el fundador lo cambia en
/// Administración → Datos del negocio) y aparece en los tickets,
/// PDFs, pantallas y respaldos. Así la app (MiTaller) se puede
/// publicar y cada taller la usa con su propia marca.
class BusinessService {
  static const _key = 'business_name';

  /// Nombre del negocio. En instalaciones existentes sin nombre guardado
  /// se conserva "GEORGE'S GARAGE"; en instalaciones nuevas, "Mi Taller".
  static Future<String> getName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    // Migración: si ya hay mecánicos registrados, es una instalación
    // anterior y se conserva la marca que ya usaba.
    if (prefs.getString('mechanics') != null) {
      return "GEORGE'S GARAGE";
    }
    return 'Mi Taller';
  }

  static Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name.trim());
  }
}
