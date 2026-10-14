import 'package:shared_preferences/shared_preferences.dart';

/// Puestos personalizados del taller (ej. "Pintor"), creados por el fundador
/// desde el formulario de mecánico. Se guardan en español, igual que los
/// puestos base, y se incluyen automáticamente en el respaldo (va todo
/// SharedPreferences).
class PositionService {
  static const _key = 'custom_positions';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  static Future<void> add(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    if (!list.any((p) => p.toLowerCase() == clean.toLowerCase())) {
      list.add(clean);
      await prefs.setStringList(_key, list);
    }
  }
}
