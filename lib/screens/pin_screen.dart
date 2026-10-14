import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../services/mechanic_service.dart';
import '../services/recovery_code_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';

/// Teclado numérico para ingresar el PIN del mecánico.
class PinScreen extends StatefulWidget {
  final Mechanic mechanic;

  const PinScreen({super.key, required this.mechanic});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends LocaleAwareState<PinScreen> {
  static const int _pinLength = 4;
  String _pin = '';
  bool _error = false;
  late Mechanic _mechanic;
  Timer? _validateTimer;

  @override
  void initState() {
    super.initState();
    _mechanic = widget.mechanic;
  }

  @override
  void dispose() {
    _validateTimer?.cancel();
    super.dispose();
  }

  void _addDigit(String d) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == _pinLength) {
      // Pequeño retardo para que se vea el 4to punto antes de validar.
      // Se cancela si el usuario sale antes (evita doble pop).
      _validateTimer?.cancel();
      _validateTimer = Timer(const Duration(milliseconds: 250), _validate);
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  void _validate() {
    if (!mounted) return;
    // Si la ruta ya no es la actual (el usuario volvió atrás durante
    // los 250ms), no hacer nada: evita un segundo pop y un setState
    // en plena transición, que corrompía el Navigator (pantalla roja).
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    if (_pin == _mechanic.pin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  /// Recupera el acceso del fundador con su código en papel (solo fundador).
  Future<void> _recoverPin() async {
    final hash = _mechanic.recoveryCodeHash;
    if (hash == null) return;
    final codeCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final pin2Ctrl = TextEditingController();
    bool step2 = false;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(step2 ? t('pin_new_pin_title') : t('pin_recover_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!step2) ...[
                Text(
                  t('pin_recovery_code_desc'),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t('pin_code_label'),
                    hintText: 'XXXX-XXXX-XXXX',
                  ),
                ),
              ] else ...[
                Text(
                  t('pin_new_pin_desc'),
                  style: const TextStyle(fontSize: 13),
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
                    labelText: t('pin_new_pin_label'),
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
                    labelText: t('pin_confirm_pin_label'),
                    counterText: '',
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx, false),
              child: Text(t('common_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!step2) {
                  if (!RecoveryCode.verify(codeCtrl.text, hash)) {
                    setD(() => error = t('pin_error_code'));
                    return;
                  }
                  setD(() {
                    step2 = true;
                    error = null;
                  });
                } else {
                  if (pinCtrl.text.length != 4) {
                    setD(() => error = t('pin_error_pin_length'));
                    return;
                  }
                  if (pinCtrl.text != pin2Ctrl.text) {
                    setD(() => error = t('pin_error_pin_mismatch'));
                    return;
                  }
                  await MechanicService().updateMechanic(
                    _mechanic.copyWith(pin: pinCtrl.text),
                  );
                  if (ctx.mounted) safePop(ctx, true);
                }
              },
              child: Text(step2 ? t('common_save') : t('common_continue')),
            ),
          ],
        ),
      ),
    );
    disposeDialogControllers([codeCtrl, pinCtrl, pin2Ctrl]);
    if (ok == true && mounted) {
      final fresh = await MechanicService().loadMechanics();
      final updated = fresh.firstWhere(
        (m) => m.id == _mechanic.id,
        orElse: () => _mechanic,
      );
      setState(() {
        _mechanic = updated;
        _pin = '';
        _error = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('pin_updated_snack')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('pin_title'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 36,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
              child: Text(
                _mechanic.name.isNotEmpty
                    ? _mechanic.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _mechanic.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppTheme.accent : Colors.transparent,
                    border: Border.all(
                      color:
                          _error ? Colors.redAccent : AppTheme.textSecondary,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            SizedBox(
              height: 28,
              child: _error
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        t('pin_error_invalid'),
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 14),
                      ),
                    )
                  : null,
            ),
            const Spacer(),
            _Keypad(onDigit: _addDigit, onBackspace: _backspace),
            const SizedBox(height: 12),
            if (_mechanic.isFounder && _mechanic.recoveryCodeHash != null)
              TextButton(
                onPressed: _recoverPin,
                child: Text(t('pin_forgot')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  const _Keypad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, bool ghost = false}) {
      // onTapDown en vez de onTap: el dígito se registra al presionar,
      // no al soltar. Con onTap, el setState de cada dígito redibuja
      // el teclado y los toques rápidos se pierden.
      void handleDown(_) {
        final cb = onTap;
        if (cb != null) {
          cb();
        } else {
          onDigit(label);
        }
      }

      return Expanded(
        child: AspectRatio(
          aspectRatio: 1.5,
          child: ghost
              ? const SizedBox.shrink()
              : InkWell(
                  onTapDown: handleDown,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: label == 'back'
                          ? const Icon(Icons.backspace_outlined,
                              color: AppTheme.textSecondary)
                          : Text(
                              label,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
        ),
      );
    }

    const gap = SizedBox(width: 12);
    const rowGap = SizedBox(height: 12);
    return Column(
      children: [
        Row(children: [key('1'), gap, key('2'), gap, key('3')]),
        rowGap,
        Row(children: [key('4'), gap, key('5'), gap, key('6')]),
        rowGap,
        Row(children: [key('7'), gap, key('8'), gap, key('9')]),
        rowGap,
        Row(children: [
          key('', ghost: true),
          gap,
          key('0'),
          gap,
          key('back', onTap: onBackspace),
        ]),
      ],
    );
  }
}
