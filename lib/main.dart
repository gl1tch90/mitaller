import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auto_backup_service.dart';
import 'services/lang_service.dart';
import 'services/session_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LangService.load();
  // Respaldo automático semanal en segundo plano (no bloquea el arranque).
  const AutoBackupService().maybeBackup();
  runApp(const MiTallerApp());
}

class MiTallerApp extends StatefulWidget {
  const MiTallerApp({super.key});

  @override
  State<MiTallerApp> createState() => _MiTallerAppState();
}

class _MiTallerAppState extends State<MiTallerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // La app se fue a segundo plano: marcar actividad para que los
      // 15 minutos de la sesión cuenten inactividad real.
      SessionService.touch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LangService.locale,
      // Al cambiar el idioma se reconstruye el árbol (todo el texto
      // visible se re-renderiza), pero SIN clave: cambiar el idioma
      // ya no reinicia la app ni saca al usuario a la pantalla de
      // login perdiendo en qué estaba.
      builder: (_, locale, __) => MaterialApp(
        title: "MiTaller",
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const _Root(),
      ),
    );
  }
}

/// Decide qué mostrar al abrir: la bienvenida solo en instalaciones
/// nuevas (sin usuarios registrados y sin haberla completado).
/// Escucha el idioma para re-renderizar la bienvenida/login al instante
/// (el cambio de idioma no reinicia la ruta).
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final Future<bool> _show = _showOnboarding();

  Future<bool> _showOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_done') == true) return false;
    return prefs.getString('mechanics') == null;
  }

  @override
  void initState() {
    super.initState();
    LangService.locale.addListener(_onLocale);
  }

  @override
  void dispose() {
    LangService.locale.removeListener(_onLocale);
    super.dispose();
  }

  void _onLocale() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _show,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data! ? const OnboardingScreen() : const LoginScreen();
      },
    );
  }
}
