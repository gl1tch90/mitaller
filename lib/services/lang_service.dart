import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idioma de la app: 'es' (español de México) o 'en' (inglés de EE. UU.).
///
/// Hay un idioma predeterminado global (el del teléfono, solo lo cambia el
/// fundador) y cada mecánico puede tener su propio idioma: al entrar con su
/// PIN la app cambia al suyo, y al cerrar sesión vuelve al predeterminado.
class LangService {
  static const _key = 'app_locale';
  static const spanish = 'es';
  static const english = 'en';

  /// Notificador global: al cambiar, la raíz reconstruye toda la app.
  static final ValueNotifier<String> locale = ValueNotifier(spanish);

  /// Idioma predeterminado guardado (el del teléfono).
  static String _savedDefault = spanish;
  static String get defaultLocale => _savedDefault;

  static bool get isEnglish => locale.value == english;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _savedDefault = prefs.getString(_key) ?? spanish;
    locale.value = _savedDefault;
  }

  /// Cambia el idioma predeterminado global (lo usa el fundador).
  static Future<void> setLocale(String value) async {
    if (value != spanish && value != english) return;
    _savedDefault = value;
    locale.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
  }

  /// Cambia el idioma en pantalla sin tocar el predeterminado guardado
  /// (se usa para aplicar el idioma propio de cada mecánico al entrar).
  static void applyLocale(String value) {
    if (value != spanish && value != english) return;
    locale.value = value;
  }

  /// Vuelve al idioma predeterminado global (al cerrar sesión).
  static void restoreDefault() {
    locale.value = _savedDefault;
  }

  /// Idioma efectivo de un mecánico: el suyo, o el predeterminado si no
  /// tiene uno elegido.
  static String effectiveLocale(String mechanicLanguage) {
    if (mechanicLanguage == english) return english;
    if (mechanicLanguage == spanish) return spanish;
    return _savedDefault;
  }
}
