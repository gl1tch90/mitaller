import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../models/attendance.dart';
import '../models/mechanic.dart';
import '../models/work_order.dart';
import '../screens/login_screen.dart';
import '../screens/my_hours_screen.dart';
import '../screens/profile_screen.dart';
import 'mechanic_avatar.dart';
import '../services/attendance_service.dart';
import '../services/session_service.dart';
import '../services/lang_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import 'forgot_shift_dialog.dart';

/// Nombre del mecánico en sesión: al tocarlo despliega el menú con
/// "Mis horas", "Registrar entrada" / "Registrar salida" y
/// "Cerrar sesión" (esta última pide confirmación antes de salir).
class SessionMenu extends StatefulWidget {
  final Mechanic mechanic;

  const SessionMenu({super.key, required this.mechanic});

  @override
  State<SessionMenu> createState() => _SessionMenuState();
}

class _SessionMenuState extends State<SessionMenu> {
  AttendanceRecord? _openShift;
  late String _avatar;

  @override
  void initState() {
    super.initState();
    _avatar = MechanicAvatars.sanitize(widget.mechanic.avatar);
    _load();
  }

  Future<void> _load() async {
    final s =
        await AttendanceService.getOpenShift(widget.mechanic.id);
    if (mounted) setState(() => _openShift = s);
  }

  Future<void> _clockIn() async {
    // Si quedó un turno abierto de otro día, hay que cerrarlo primero:
    // clockIn no crea uno nuevo mientras haya uno abierto.
    final stale =
        await AttendanceService.getStaleShift(widget.mechanic.id);
    if (stale != null && mounted) {
      final closed = await showForgotShiftDialog(
          context, widget.mechanic, stale);
      if (!closed) return;
    }
    final rec =
        await AttendanceService.clockIn(widget.mechanic.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t('session_menu_clock_in_ok',
              {'time': formatClock(rec.clockIn)}),
        ),
      ),
    );
    // Si trae tareas en pausa, recordárselas al entrar.
    final active = await WorkOrderService().active();
    final paused = active
        .where((o) =>
            o.mechanicId == widget.mechanic.id &&
            o.status == OrderStatus.paused)
        .length;
    if (paused > 0 && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(t('session_menu_paused_reminder_title')),
          content: Text(t('session_menu_paused_reminder_body',
              {'n': '$paused'})),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx),
              child: Text(
                t('common_accept'),
                style: const TextStyle(color: AppTheme.accent),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _clockOut() async {
    // Avisar si trae tareas en pausa o corriendo: al salir, las que están
    // en curso se pausan solas.
    final active = await WorkOrderService().active();
    final mine = active
        .where((o) => o.mechanicId == widget.mechanic.id)
        .toList();
    final paused =
        mine.where((o) => o.status == OrderStatus.paused).length;
    final running = mine
        .where((o) =>
            o.status == OrderStatus.inProgress && o.isTimerRunning)
        .length;
    String content = t('session_menu_clock_out_confirm');
    if (paused > 0 || running > 0) {
      final parts = <String>[];
      if (paused > 0) {
        parts.add(t('session_menu_clock_out_paused',
            {'n': '$paused'}));
      }
      if (running > 0) {
        parts.add(t('session_menu_clock_out_running',
            {'n': '$running'}));
      }
      content +=
          '\n\n${parts.join(' ')} ${t('session_menu_clock_out_will_pause')}';
    }
    // Confirmar antes de registrar la salida: un toque accidental
    // cerraría el turno y pausaría los cronómetros.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(t('session_menu_clock_out')),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(
              t('common_cancel'),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => safePop(ctx, true),
            child: Text(
              t('session_menu_clock_out'),
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final rec =
        await AttendanceService.clockOut(widget.mechanic.id);
    // Al cerrar el turno se pausan los trabajos en curso: el cronómetro
    // no sigue corriendo sin turno abierto.
    await WorkOrderService().pauseRunningFor(widget.mechanic.id);
    await _load();
    if (mounted && rec != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('session_menu_clock_out_ok',
                {'hours': formatHours(rec.hoursWorked)}),
          ),
        ),
      );
    }
  }

  /// Cambiar el idioma de toda la app desde el menú del mecánico.
  Future<void> _pickLanguage() async {
    final current = LangService.locale.value;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(t('session_menu_language_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: LangService.spanish,
              groupValue: current,
              activeColor: AppTheme.accent,
              onChanged: (v) => safePop(ctx, v),
              title: const Text('Español'),
            ),
            RadioListTile<String>(
              value: LangService.english,
              groupValue: current,
              activeColor: AppTheme.accent,
              onChanged: (v) => safePop(ctx, v),
              title: const Text('English'),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked != current && mounted) {
      await LangService.setLocale(picked);
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(t('session_menu_logout')),
        content: Text(
          t('session_menu_logout_confirm',
              {'name': widget.mechanic.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              t('common_cancel'),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            // Al entrar se hizo pushReplacement: la pantalla de selección
            // quedó como primera ruta, así que popUntil no tenía a dónde
            // regresar. Se navega explícito al login limpiando la pila.
            onPressed: () async {
              // Cerrar la sesión guardada: la próxima vez pedirá el PIN.
              await SessionService.clear();
              if (!ctx.mounted) return;
              Navigator.of(ctx).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Text(
              t('session_menu_logout'),
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mechanic = widget.mechanic;
    final hasOpen = _openShift != null;

    return PopupMenuButton<String>(
      tooltip: t('session_menu_options'),
      offset: const Offset(0, 46),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: AppTheme.surface,
      onSelected: (value) async {
        if (value == 'profile') {
          final updated =
              await Navigator.of(context).push<Mechanic>(
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                  mechanic: widget.mechanic
                      .copyWith(avatar: _avatar)),
            ),
          );
          if (updated != null && mounted) {
            setState(() => _avatar =
                MechanicAvatars.sanitize(updated.avatar));
          }
        } else if (value == 'myhours') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  MyHoursScreen(mechanic: mechanic),
            ),
          );
        } else if (value == 'clockin') {
          _clockIn();
        } else if (value == 'clockout') {
          _clockOut();
        } else if (value == 'language') {
          _pickLanguage();
        } else if (value == 'logout') {
          _confirmLogout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Text(t('session_menu_profile')),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'myhours',
          child: Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Text(t('session_menu_my_hours')),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'language',
          child: Row(
            children: [
              const Icon(
                Icons.language,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Text(t('session_menu_language')),
              const SizedBox(width: 8),
              Text(
                LangService.isEnglish ? 'EN' : 'ES',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (hasOpen)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              t('session_menu_clock_in_today',
                  {'time': formatClock(_openShift!.clockIn)}),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        PopupMenuItem<String>(
          value: hasOpen ? 'clockout' : 'clockin',
          child: Row(
            children: [
              Icon(
                hasOpen ? Icons.logout : Icons.login,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Text(hasOpen
                  ? t('session_menu_clock_out')
                  : t('session_menu_clock_in')),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              const Icon(
                Icons.power_settings_new,
                size: 18,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 10),
              Text(t('session_menu_logout')),
            ],
          ),
        ),
      ],
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _avatar,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 6),
            Text(
              mechanic.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (mechanic.isAdmin)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t('session_menu_admin_badge'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                    letterSpacing: 1,
                  ),
                ),
              ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
