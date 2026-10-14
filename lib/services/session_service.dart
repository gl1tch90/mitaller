import 'package:shared_preferences/shared_preferences.dart';

/// Sesión del mecánico: guarda quién está dentro para que al cerrar y
/// reabrir la app no tenga que volver a poner su PIN.
///
/// La sesión dura 15 minutos de inactividad (desde que la app se va a
/// segundo plano). Pasado ese tiempo, hay que poner el PIN otra vez,
/// pero el login muestra "Continuar como {nombre}" como atajo.
///
/// La sesión solo se borra con "Cerrar sesión" explícito (menú de sesión
/// o botón atrás en la pantalla de selección). Registrar la salida del
/// turno NO cierra la sesión.
class SessionService {
  static const _keyId = 'session_mechanic_id';
  static const _keyTs = 'session_last_active';
  static const sessionTimeout = Duration(minutes: 15);

  static Future<void> save(String mechanicId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyId, mechanicId);
    await prefs.setInt(
        _keyTs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Marca actividad (se llama al mandar la app a segundo plano) para
  /// que los 15 minutos cuenten inactividad real.
  static Future<void> touch() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyId)) return;
    await prefs.setInt(
        _keyTs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Id con sesión vigente (menos de 15 min inactiva). Null si expiró
  /// o nunca hubo sesión.
  static Future<String?> loadValid() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyId);
    final ts = prefs.getInt(_keyTs);
    if (id == null || ts == null) return null;
    final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
    if (ageMs > sessionTimeout.inMilliseconds) return null;
    return id;
  }

  /// Último usuario sin importar si la sesión expiró
  /// (para la tarjeta "Continuar como").
  static Future<String?> loadLastUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyId);
    await prefs.remove(_keyTs);
  }
}
