import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../services/mechanic_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../widgets/mechanic_avatar.dart';

/// Mi perfil: el mecánico ve sus datos y puede cambiar su avatar.
/// Lo que cambie aquí se refleja en el login y en todos lados.
class ProfileScreen extends StatefulWidget {
  final Mechanic mechanic;
  final ValueChanged<Mechanic>? onChanged;

  const ProfileScreen(
      {super.key, required this.mechanic, this.onChanged});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends LocaleAwareState<ProfileScreen> {
  late String _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _avatar = MechanicAvatars.sanitize(widget.mechanic.avatar);
  }

  Future<void> _save() async {
    if (_avatar == widget.mechanic.avatar) {
      safePop(context);
      return;
    }
    setState(() => _busy = true);
    final updated =
        widget.mechanic.copyWith(avatar: _avatar);
    await MechanicService().updateMechanic(updated);
    widget.onChanged?.call(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('profile_saved'))),
      );
      safePop(context, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mechanic;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(t('profile_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                MechanicAvatar(
                    mechanic: m.copyWith(avatar: _avatar),
                    radius: 48),
                const SizedBox(height: 12),
                Text(m.name,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  m.positions.join(' · '),
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t('profile_choose_avatar'),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          AvatarPicker(
            selected: _avatar,
            onSelect: (e) => setState(() => _avatar = e),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(t('common_save'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
