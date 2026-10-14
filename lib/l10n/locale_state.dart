import 'package:flutter/material.dart';

import '../services/lang_service.dart';

/// Estado base para pantallas: se reconstruye solo cuando cambia el
/// idioma global.
///
/// El cambio de idioma no reinicia las rutas (para no sacar al usuario
/// de donde estaba), así que cada pantalla visible debe re-renderizarse
/// por su cuenta al cambiar [LangService.locale].
abstract class LocaleAwareState<T extends StatefulWidget> extends State<T> {
  @override
  void initState() {
    super.initState();
    LangService.locale.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LangService.locale.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }
}
