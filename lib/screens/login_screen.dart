import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../services/business_service.dart';
import '../services/mechanic_service.dart';
import '../services/recovery_code_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../version.dart';
import '../utils/dialog.dart';
import '../widgets/mechanic_avatar.dart';
import 'pin_screen.dart';
import 'vehicle_select_screen.dart';

/// Primera pantalla de la app: selector de mecánico con PIN.
/// El primer usuario registrado queda como administrador (el jefe).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends LocaleAwareState<LoginScreen> {
  final _service = MechanicService();
  List<Mechanic> _mechanics = [];
  bool _loading = true;
  String _businessName = 'Mi Taller';
  // Último usuario (sesión expirada): atajo "Continuar como".
  Mechanic? _lastMechanic;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mechanics = await _service.loadMechanics();
    final businessName = await BusinessService.getName();
    if (!mounted) return;
    setState(() {
      _mechanics = mechanics;
      _businessName = businessName;
      _loading = false;
    });
    // Sesión vigente (menos de 15 min inactiva): entrar directo.
    final sessionId = await SessionService.loadValid();
    if (sessionId != null && mounted) {
      final found =
          mechanics.where((m) => m.id == sessionId).toList();
      if (found.isNotEmpty) {
        final mechanic = found.first;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                VehicleSelectScreen(mechanic: mechanic),
          ),
        );
        return;
      }
      await SessionService.clear();
      return;
    }
    // Sesión expirada: mostrar "Continuar como" con el último usuario.
    final lastId = await SessionService.loadLastUserId();
    if (lastId == null || !mounted) return;
    final found = mechanics.where((m) => m.id == lastId).toList();
    if (found.isEmpty) {
      await SessionService.clear();
      return;
    }
    setState(() => _lastMechanic = found.first);
  }

  Future<void> _openMechanic(Mechanic mechanic) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PinScreen(mechanic: mechanic)),
    );
    if (ok == true && mounted) {
      // Guardar la sesión: si se cierra la app, al reabrir entra directo.
      await SessionService.save(mechanic.id);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VehicleSelectScreen(mechanic: mechanic),
        ),
      );
    }
  }

  /// Solo se usa cuando aún no hay nadie registrado: esa persona es el jefe.
  /// Siempre es administrador y fundador; el puesto queda como Jefe de taller.
  Future<void> _showFirstMechanic() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final pin2Ctrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('login_add_admin')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('login_first_admin_desc'),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: t('login_name_label'),
                    hintText: t('login_name_hint'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: InputDecoration(
                    labelText: t('login_pin_label'),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pin2Ctrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: InputDecoration(
                    labelText: t('login_pin_confirm_label'),
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx, false),
              child: Text(t('common_cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                if (nameCtrl.text.trim().isEmpty ||
                    pinCtrl.text.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t('login_snack_name_pin')),
                    ),
                  );
                  return;
                }
                if (pinCtrl.text != pin2Ctrl.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t('pin_error_pin_mismatch')),
                    ),
                  );
                  return;
                }
                safePop(ctx, true);
              },
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _service.addMechanic(
        nameCtrl.text.trim(),
        pinCtrl.text,
        positions: const ['Jefe de taller'],
        isAdmin: true,
        isFounder: true,
      );
      // El fundador recibe su código de recuperación en papel.
      final code = RecoveryCode.generate();
      final all = await _service.loadMechanics();
      final founder = all.firstWhere((m) => m.isFounder);
      await _service.updateMechanic(
        founder.copyWith(recoveryCodeHash: RecoveryCode.hash(code)),
      );
      if (mounted) {
        await _showRecoveryCodeDialog(code);
      }
      _load();
    }
    disposeDialogControllers([nameCtrl, pinCtrl, pin2Ctrl]);
  }

  /// Muestra el código de recuperación para anotarlo en papel.
  /// No se puede cerrar sin confirmar que ya se anotó.
  Future<void> _showRecoveryCodeDialog(String code) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('login_recovery_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('login_recovery_desc'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('login_recovery_confirm')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1D22), AppTheme.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text(
                  _businessName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('login_who_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_mechanics.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.admin_panel_settings,
                            size: 56,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t('login_empty'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showFirstMechanic,
                            icon: const Icon(Icons.add),
                            label: Text(t('login_add_admin')),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        // Atajo tras sesión expirada: un toque y pide el PIN.
                        if (_lastMechanic != null) ...[
                          _ContinueAsCard(
                            mechanic: _lastMechanic!,
                            onTap: () =>
                                _openMechanic(_lastMechanic!),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Expanded(
                          child: ListView.separated(
                            itemCount: _mechanics.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final m = _mechanics[i];
                              return _MechanicTile(
                                mechanic: m,
                                onTap: () => _openMechanic(m),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'v$kAppVersion',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta "Continuar como {nombre}": atajo tras una sesión expirada.
/// Un toque abre la pantalla de PIN de ese usuario.
class _ContinueAsCard extends StatelessWidget {
  final Mechanic mechanic;
  final VoidCallback onTap;

  const _ContinueAsCard({required this.mechanic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.accent, width: 1.5),
        ),
        child: Row(
          children: [
            MechanicAvatar(mechanic: mechanic, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('login_continue_as',
                        {'name': mechanic.name}),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('login_continue_as_desc'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppTheme.accent,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _MechanicTile extends StatelessWidget {
  final Mechanic mechanic;
  final VoidCallback onTap;

  const _MechanicTile({required this.mechanic, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.surfaceLight, width: 1),
        ),
        child: Row(
          children: [
            MechanicAvatar(mechanic: mechanic, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          mechanic.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (mechanic.isAdmin)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            t('login_admin_badge'),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    positionsLabel(mechanic.positions),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.lock_outline,
              color: AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppTheme.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
