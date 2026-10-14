import 'package:flutter/material.dart';

import '../models/mechanic.dart';
import '../theme/app_theme.dart';

/// Círculo con el avatar (emoji) del mecánico.
class MechanicAvatar extends StatelessWidget {
  final Mechanic mechanic;
  final double radius;

  const MechanicAvatar(
      {super.key, required this.mechanic, this.radius = 26});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor:
          AppTheme.accent.withValues(alpha: 0.15),
      child: Text(
        MechanicAvatars.sanitize(mechanic.avatar),
        style: TextStyle(fontSize: radius * 0.95),
      ),
    );
  }
}

/// Cuadrícula para elegir avatar al crear o editar un mecánico.
class AvatarPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const AvatarPicker(
      {super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Wrap en vez de GridView: un GridView con shrinkWrap dentro de un
    // diálogo (scrollable) pide dimensiones intrínsecas al viewport y
    // truena el layout en modo debug (la ventana ni se abría).
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final emoji in MechanicAvatars.options)
          _circle(emoji, emoji == selected),
      ],
    );
  }

  Widget _circle(String emoji, bool isSel) {
    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: () => onSelect(emoji),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accent.withValues(
              alpha: isSel ? 0.3 : 0.1),
          border: Border.all(
            color: isSel
                ? AppTheme.accent
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: Center(
          child: Text(emoji,
              style: const TextStyle(fontSize: 30)),
        ),
      ),
    );
  }
}
