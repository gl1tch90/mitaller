import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../services/lang_service.dart';
import '../models/attendance.dart';
import '../models/mechanic.dart';
import '../models/service_item.dart';
import '../models/task.dart';
import '../models/ticket.dart';
import '../models/vehicle_type.dart';
import '../services/attendance_service.dart';
import '../services/attendance_report.dart';
import '../services/backup_service.dart';
import '../services/auto_backup_service.dart';
import '../services/business_service.dart';
import '../services/income_service.dart';
import '../services/position_service.dart';
import '../services/mechanic_service.dart';
import '../services/recovery_code_service.dart';
import '../services/service_catalog_service.dart';
import '../services/task_service.dart';
import '../widgets/task_dialog.dart';
import '../widgets/live_hours.dart';
import '../services/ticket_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../utils/dates.dart';
import '../utils/duration.dart';
import '../utils/money.dart';
import '../widgets/mechanic_avatar.dart';
import 'onboarding_screen.dart';

/// Panel exclusivo del administrador: gestiona mecánicos y tareas.
class AdminScreen extends StatefulWidget {
  final String currentMechanicId;

  /// Pestaña inicial (0 Mecánicos, 1 Tareas, 2 Horas, 3 Servicios,
  /// 4 Ingresos, 5 Por cobrar, 6 Negocio).
  final int initialTab;

  const AdminScreen(
      {super.key,
      required this.currentMechanicId,
      this.initialTab = 0});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends LocaleAwareState<AdminScreen> {
  final _mechService = MechanicService();
  final _taskService = TaskService();
  final _catalogService = ServiceCatalogService();
  final _ticketService = TicketService();
  List<Mechanic> _mechanics = [];
  List<Task> _tasks = [];
  List<AttendanceRecord> _records = [];
  List<ServiceItem> _services = [];
  List<Ticket> _tickets = [];
  int _incomeMode = 0; // 0 = día, 1 = semana, 2 = mes
  String _businessName = 'Mi Taller';
  bool _backupBusy = false;
  DateTime? _lastAutoBackup;
  bool _autoBackupEnabled = true;
  int _autoBackupInterval = AutoBackupService.defaultIntervalDays;
  bool _amIFounder = false;  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mechanics = await _mechService.loadMechanics();
    final tasks = await _taskService.loadTasks();
    final records = await AttendanceService.getAll();
    final services = await _catalogService.load();
    final tickets = await _ticketService.list();
    final businessName = await BusinessService.getName();
    final lastAuto = await const AutoBackupService().lastBackupDate();
    final autoEnabled = await const AutoBackupService().isEnabled();
    final autoInterval =
        await const AutoBackupService().getIntervalDays();
    if (mounted) {
      setState(() {
        _mechanics = mechanics;
        _tasks = tasks;
        _records = records;
        _services = services;
        _tickets = tickets;
        _businessName = businessName;
        _lastAutoBackup = lastAuto;
        _autoBackupEnabled = autoEnabled;
        _autoBackupInterval = autoInterval;
        _amIFounder = mechanics
            .where((m) => m.id == widget.currentMechanicId)
            .any((m) => m.isFounder);
        _loading = false;
      });
    }
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _mechanicName(String id) {
    final found = _mechanics.where((m) => m.id == id);
    return found.isEmpty ? t('admin_unassigned') : found.first.name;
  }

  bool _isLastAdmin(Mechanic m) =>
      m.isAdmin &&
      !_mechanics.any((o) => o.id != m.id && o.isAdmin);

  // ---------------- Ingresos ----------------

  Widget _incomeTab() {
    final buckets = _incomeMode == 0
        ? groupIncomeByDay(_tickets)
        : _incomeMode == 1
            ? groupIncomeByWeek(_tickets)
            : groupIncomeByMonth(_tickets);
    final grandTotal = _tickets.fold(0.0, (s, tk) => s + tk.total);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('admin_income_total'),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                Text(
                  formatMoney(grandTotal),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                  ),
                ),
                Text(
                  t('admin_income_tickets_total',
                      {'n': '${_tickets.length}'}),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                Text(
                  t('admin_income_outstanding', {
                    'amount': formatMoney(_tickets.fold(
                        0.0, (s, tk) => s + tk.balance))
                  }),
                  style: const TextStyle(
                      fontSize: 13, color: Colors.orange),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(
                  value: 0, label: Text(t('admin_income_day'))),
              ButtonSegment(
                  value: 1, label: Text(t('admin_income_week'))),
              ButtonSegment(
                  value: 2, label: Text(t('admin_income_month'))),
            ],
            selected: {_incomeMode},
            onSelectionChanged: (s) =>
                setState(() => _incomeMode = s.first),
          ),
        ),
        Expanded(
          child: buckets.isEmpty
              ? Center(
                  child: Text(
                    t('admin_income_empty'),
                    style: const TextStyle(
                        color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: buckets.length,
                  itemBuilder: (ctx, i) {
                    final b = buckets[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text(
                          b.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          t('admin_income_bucket_count', {
                            'n': '${b.count}',
                            'plural': b.count == 1 ? '' : 's',
                          }),
                          style: const TextStyle(
                              color: AppTheme.textSecondary),
                        ),
                        trailing: Text(
                          formatMoney(b.total),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accent,
                          ),
                        ),
                        children: b.tickets.map((ticket) {
                          final v = ticket.vehicle;
                          return ListTile(
                            dense: true,
                            title: Text(t('admin_ticket_ref', {
                              'id': '${ticket.id}',
                              'vehicle':
                                  '${v.brand} ${v.model} ${v.year}',
                            })),
                            subtitle: Text(ticket.mechanicName),
                            trailing: Text(
                              formatMoney(ticket.total),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------- Por cobrar ----------------

  Widget _debtsTab() {
    final debts = _tickets.where((tk) => !tk.isPaid).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final totalOwed = debts.fold(0.0, (s, tk) => s + tk.balance);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('admin_debts_total'),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                Text(
                  formatMoney(totalOwed),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.orange,
                  ),
                ),
                Text(
                  t('admin_debts_count', {
                    'n': '${debts.length}',
                    'plural': debts.length == 1 ? '' : 's',
                  }),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: debts.isEmpty
              ? Center(
                  child: Text(
                    t('admin_debts_empty'),
                    style: const TextStyle(
                        color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: debts.length,
                  itemBuilder: (ctx, i) {
                    final ticket = debts[i];
                    final v = ticket.vehicle;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ticket.customer.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16),
                                  ),
                                ),
                                Text(
                                  formatMoney(ticket.balance),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t('admin_ticket_ref', {
                                'id': '${ticket.id}',
                                'vehicle':
                                    '${v.brand} ${v.model} ${v.year}',
                              }),
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13),
                            ),
                            Text(
                              t('admin_ticket_sub', {
                                'date': _fmtDate(ticket.dateTime),
                                'mechanic': ticket.mechanicName,
                              }),
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (ticket.payments.isNotEmpty)
                                  TextButton(
                                    onPressed: () =>
                                        _showPayments(ticket),
                                    child: Text(t(
                                        'admin_debts_view_payments')),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _registerPayment(ticket),
                                  icon: const Icon(Icons.payments,
                                      size: 18),
                                  label:
                                      Text(t('admin_payment_btn')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _registerPayment(Ticket ticket) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => _PaymentDialog(ticket: ticket),
    );
    if (amount == null || !mounted) return;

    final updated = ticket.copyWith(
      amountPaid: (ticket.amountPaid ?? 0) + amount,
      payments: [
        ...ticket.payments,
        TicketPayment(date: DateTime.now(), amount: amount)
      ],
    );
    await _ticketService.update(updated);
    await _load();
    if (mounted) {
      _msg(t('admin_payment_recorded',
          {'amount': formatMoney(amount)}));
    }
  }

  Future<void> _showPayments(Ticket ticket) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            t('admin_payments_title', {'id': '${ticket.id}'})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ticket.payments
              .map((p) => ListTile(
                    dense: true,
                    title: Text(formatMoney(p.amount)),
                    subtitle: Text(_fmtDate(p.date)),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t('common_close')),
          ),
        ],
      ),
    );
  }

  // ---------------- Mecánicos ----------------

  Future<void> _showMechanicForm({Mechanic? existing}) async {
    // Solo el fundador puede editar la ficha del fundador.
    if (existing != null && existing.isFounder && !_amIFounder) {
      _msg(t('admin_only_founder_edit_self'));
      return;
    }
    // Solo el fundador puede editar a otro administrador.
    if (existing != null &&
        existing.isAdmin &&
        !_amIFounder &&
        existing.id != widget.currentMechanicId) {
      _msg(t('admin_only_founder_edit_admin'));
      return;
    }
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final pinCtrl = TextEditingController();
    final pin2Ctrl = TextEditingController();
    bool isAdmin = existing?.isAdmin ?? false;
    // El interruptor de "Es administrador" se bloquea al editar al fundador
    // (siempre es admin) o cuando un no-fundador edita a otro administrador.
    final bool adminSwitchLocked = (existing?.isFounder ?? false) ||
        (existing != null &&
            existing.isAdmin &&
            !_amIFounder);
    // Puestos: base (sin "Otro") + personalizados guardados. Si el usuario
    // tiene puestos que ya no están en la lista, se reintegran.
    final positionOptions = <String>[
      ...MechanicPositions.options.where((p) => p != 'Otro'),
      ...await PositionService.load(),
    ];
    // Puestos del mecánico: puede tener varios; los chips prenden/apagan.
    final posValues = <String>{};
    if (existing != null && existing.positions.isNotEmpty) {
      for (final p in existing.positions) {
        if (!positionOptions.contains(p)) {
          await PositionService.add(p);
          positionOptions.add(p);
        }
      }
      posValues.addAll(existing.positions);
    } else {
      posValues.add(MechanicPositions.def);
    }
    // Campo en línea para el puesto nuevo (sin diálogo anidado: abrir un
    // segundo diálogo dejaba el foco a medias y provocaba la pantalla roja).
    bool showNewPosition = false;
    // Al editar, los campos de PIN se ocultan tras un botón ("¿Quieres
    // cambiar la contraseña de este usuario?"); al crear, se muestran
    // directo porque el PIN es obligatorio.
    bool showPinFields = existing == null;
    // Error de validación visible DENTRO del diálogo (el SnackBar quedaba
    // atrás del diálogo y casi no se veía).
    String? formError;
    final newPosCtrl = TextEditingController();
    String avatarValue = existing?.avatar ?? MechanicAvatars.def;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          scrollable: true,
          title: Text(existing == null
              ? t('admin_mechanic_add_title')
              : t('admin_mechanic_edit_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (formError != null) {
                    setD(() => formError = null);
                  }
                },
                decoration: InputDecoration(
                    labelText: t('admin_field_name')),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t('admin_field_avatar'),
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                AvatarPicker(
                  selected: avatarValue,
                  onSelect: (e) =>
                      setD(() => avatarValue = e),
                ),
                const SizedBox(height: 12),
                // Puesto como chips: todo visible sin abrir menú
                // (el dropdown abría una ruta y dejaba el foco agarrado,
                // lo que provocaba la pantalla roja al cancelar).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('admin_field_position'),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in positionOptions)
                          ChoiceChip(
                            label: Text(positionLabel(p)),
                            selected: posValues.contains(p),
                            onSelected: (_) => setD(() {
                              if (posValues.contains(p)) {
                                posValues.remove(p);
                              } else {
                                posValues.add(p);
                              }
                            }),
                            selectedColor: AppTheme.accent
                                .withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              color: posValues.contains(p)
                                  ? AppTheme.accent
                                  : AppTheme.textPrimary,
                              fontWeight: posValues.contains(p)
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            side: BorderSide(
                              color: posValues.contains(p)
                                  ? AppTheme.accent
                                  : AppTheme.surfaceLight,
                            ),
                            backgroundColor: AppTheme.surface,
                          ),
                        ActionChip(
                          label: Text(
                            t('admin_position_new'),
                            style: const TextStyle(
                                color: AppTheme.accent),
                          ),
                          side: const BorderSide(
                              color: AppTheme.accent),
                          backgroundColor: AppTheme.surface,
                          onPressed: () =>
                              setD(() => showNewPosition = true),
                        ),
                      ],
                    ),
                    // Campo en línea para escribir el puesto nuevo.
                    if (showNewPosition) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newPosCtrl,
                              textCapitalization:
                                  TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText: t(
                                    'admin_position_new_hint'),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: t('common_cancel'),
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              // Quitar el foco antes de ocultar el campo:
                              // si se oculta con el foco adentro, sale la
                              // pantalla roja.
                              FocusManager.instance.primaryFocus
                                  ?.unfocus();
                              await Future.delayed(const Duration(
                                  milliseconds: 50));
                              newPosCtrl.clear();
                              setD(
                                  () => showNewPosition = false);
                            },
                          ),
                          IconButton(
                            tooltip: t('common_save'),
                            icon: const Icon(Icons.check,
                                color: AppTheme.accent),
                            onPressed: () async {
                              final name =
                                  newPosCtrl.text.trim();
                              if (name.isEmpty) return;
                              if (positionOptions.any((p) =>
                                  p.toLowerCase() ==
                                  name.toLowerCase())) {
                                _msg(t('admin_position_exists'));
                                return;
                              }
                              // Quitar el foco y dar un instante para que
                              // se procese antes de ocultar el campo.
                              FocusManager.instance.primaryFocus
                                  ?.unfocus();
                              await Future.delayed(const Duration(
                                  milliseconds: 50));
                              await PositionService.add(name);
                              setD(() {
                                positionOptions.add(name);
                                // El puesto nuevo se SUMA a los que ya
                                // tenía, no los reemplaza.
                                posValues.add(name);
                                showNewPosition = false;
                              });
                              newPosCtrl.clear();
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Al editar, el cambio de PIN va tras un botón para no
                // estorbar; al crear se pide directo (es obligatorio).
                if (existing != null && !showPinFields)
                  OutlinedButton(
                    onPressed: () =>
                        setD(() => showPinFields = true),
                    child:
                        Text(t('admin_change_pin_button')),
                  )
                else ...[
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    onChanged: (_) {
                      if (formError != null) {
                        setD(() => formError = null);
                      }
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: InputDecoration(
                      labelText: existing == null
                          ? t('admin_field_pin')
                          : t('admin_field_pin_new'),
                      counterText: '',
                      helperText: (_amIFounder && existing != null)
                          ? t('admin_field_pin_current',
                              {'pin': existing.pin})
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pin2Ctrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    onChanged: (_) {
                      if (formError != null) {
                        setD(() => formError = null);
                      }
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: InputDecoration(
                      labelText: t('login_pin_confirm_label'),
                      counterText: '',
                    ),
                  ),
                ],
                SwitchListTile(
                  title: Text(t('admin_field_is_admin')),
                  subtitle: Text(
                    t('admin_field_is_admin_desc'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: isAdmin,
                  activeColor: AppTheme.accent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: adminSwitchLocked
                      ? null
                      : (v) => setD(() => isAdmin = v),
                ),
                // Error de validación dentro del diálogo, bien visible.
                if (formError != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formError!,
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13),
                        ),
                      ),
                    ],
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
                final name = nameCtrl.text.trim();
                final pin = pinCtrl.text;
                final pin2 = pin2Ctrl.text;
                // Los errores se muestran dentro del diálogo.
                void fail(String key) =>
                    setD(() => formError = t(key));
                setD(() => formError = null);
                if (name.isEmpty) {
                  fail('admin_valid_name');
                  return;
                }
                if (existing == null && pin.length != 4) {
                  fail('admin_valid_pin');
                  return;
                }
                if (pin.isNotEmpty && pin.length != 4) {
                  fail('admin_valid_pin');
                  return;
                }
                if (pin.isNotEmpty && pin != pin2) {
                  fail('pin_error_pin_mismatch');
                  return;
                }
                if (existing != null &&
                    existing.isFounder &&
                    !isAdmin) {
                  fail('admin_founder_always_admin');
                  return;
                }
                if (existing != null &&
                    existing.isAdmin &&
                    !isAdmin &&
                    !_amIFounder) {
                  fail('admin_only_founder_demote');
                  return;
                }
                if (existing != null &&
                    existing.isAdmin &&
                    !isAdmin &&
                    _isLastAdmin(existing)) {
                  fail('admin_need_one_admin');
                  return;
                }
                // Si el campo de puesto nuevo quedó abierto con texto
                // (sin darle a la paloma), se guarda como puesto también.
                final inlinePos = newPosCtrl.text.trim();
                if (showNewPosition &&
                    inlinePos.isNotEmpty &&
                    !positionOptions.any((p) =>
                        p.toLowerCase() ==
                        inlinePos.toLowerCase())) {
                  await PositionService.add(inlinePos);
                  positionOptions.add(inlinePos);
                  posValues.add(inlinePos);
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
      // Los puestos elegidos; si apagó todos, se queda el predeterminado.
      final finalPositions = posValues.isEmpty
          ? const [MechanicPositions.def]
          : posValues.toList();
      if (existing == null) {
        await _mechService.addMechanic(
          nameCtrl.text.trim(),
          pinCtrl.text,
          positions: finalPositions,
          isAdmin: isAdmin,
          avatar: avatarValue,
        );
      } else {
        await _mechService.updateMechanic(existing.copyWith(
          name: nameCtrl.text.trim(),
          pin: pinCtrl.text.isEmpty ? existing.pin : pinCtrl.text,
          positions: finalPositions,
          isAdmin: isAdmin,
          avatar: avatarValue,
        ));
      }
      _load();
    }
    // Los controladores se liberan con disposeDialogControllers: el future
    // de showDialog se completa al llamar a pop, antes de la animación de
    // salida; liberarlos antes provoca la pantalla roja.
    disposeDialogControllers(
        [nameCtrl, pinCtrl, pin2Ctrl, newPosCtrl]);
  }

  /// Pide el nombre de un puesto nuevo. Devuelve null si se cancela o está vacío.
  Future<void> _deleteMechanic(Mechanic m) async {
    if (m.id == widget.currentMechanicId) {
      _msg(t('admin_cannot_delete_self'));
      return;
    }
    if (m.isFounder) {
      _msg(t('admin_cannot_delete_founder'));
      return;
    }
    if (m.isAdmin && !_amIFounder) {
      _msg(t('admin_only_founder_delete_admin'));
      return;
    }
    if (_isLastAdmin(m)) {
      _msg(t('admin_need_one_admin'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('admin_delete_mechanic_title')),
        content: Text(t('admin_delete_mechanic_body',
            {'name': m.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common_cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('common_delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _mechService.deleteMechanic(m.id);
      _load();
    }
  }

  // ---------------- Tareas ----------------

  Future<void> _showTaskForm({Task? existing}) async {
    if (_mechanics.isEmpty) {
      _msg(t('admin_add_mechanic_first'));
      return;
    }
    final result = await showTaskDialog(
      context,
      existing: existing,
      mechanics: _mechanics,
    );
    if (result == null) return;
    if (existing == null) {
      await _taskService.addTask(
        result.title,
        result.description,
        result.mechanicId,
      );
    } else {
      await _taskService.updateTask(existing.copyWith(
        title: result.title,
        description: result.description,
        mechanicId: result.mechanicId,
        status: result.status,
        completedAt:
            result.status == TaskStatus.done && existing.completedAt == null
                ? DateTime.now()
                : null,
      ));
    }
    _load();
  }

  Future<void> _deleteTask(Task task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('admin_task_delete_title')),
        content:
            Text(t('admin_task_delete_body', {'title': task.title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common_cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('common_delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _taskService.deleteTask(task.id);
      _load();
    }
  }

  Color _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending:
        return AppTheme.accent;
      case TaskStatus.inProgress:
        return Colors.lightBlueAccent;
      case TaskStatus.done:
        return Colors.greenAccent;
      case TaskStatus.inReview:
        return Colors.purpleAccent;
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('admin_title')),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppTheme.accent,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: [
              Tab(text: t('admin_tab_mechanics')),
              Tab(text: t('admin_tab_tasks')),
              Tab(text: t('admin_tab_hours')),
              Tab(text: t('admin_tab_services')),
              Tab(text: t('admin_tab_income')),
              Tab(text: t('admin_tab_debts')),
              Tab(text: t('admin_tab_business')),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _mechanicsTab(),
                  _tasksTab(),
                  _hoursTab(),
                  _servicesTab(),
                  _incomeTab(),
                  _debtsTab(),
                  _businessTab(),
                ],
              ),
      ),
    );
  }

  Mechanic? get _myRecord {
    final found =
        _mechanics.where((m) => m.id == widget.currentMechanicId);
    return found.isEmpty ? null : found.first;
  }

  /// Tarjeta del código de recuperación en papel (solo el fundador la ve).
  Widget _recoveryCodeCard() {
    final hasCode = (_myRecord?.recoveryCodeHash) != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hasCode
              ? AppTheme.surface
              : Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: hasCode
              ? null
              : Border.all(color: Colors.amber.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(
              hasCode ? Icons.key_outlined : Icons.warning_amber_rounded,
              color: hasCode ? AppTheme.textSecondary : Colors.amber,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasCode
                    ? t('admin_recovery_configured')
                    : t('admin_recovery_not_set'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _generateRecoveryCode,
              child: Text(hasCode
                  ? t('admin_recovery_regenerate')
                  : t('admin_recovery_generate')),
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta para configurar el nombre comercial del taller (solo fundador).
  /// Ese nombre aparece en tickets, PDFs, pantallas y respaldos.
  Widget _businessCard() {
    final ctrl = TextEditingController(text: _businessName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.store_outlined,
                    color: AppTheme.accent),
                const SizedBox(width: 10),
                Text(
                  t('admin_business_title'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('admin_business_desc'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    style:
                        const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: t('admin_business_name_label'),
                      labelStyle: const TextStyle(
                          color: AppTheme.textSecondary),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    final name = ctrl.text.trim();
                    if (name.isEmpty) {
                      _msg(t('admin_business_name_empty'));
                      return;
                    }
                    await BusinessService.setName(name);
                    setState(() => _businessName = name);
                    _msg(t('admin_business_saved', {'name': name}));
                  },
                  child: Text(t('common_save')),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const OnboardingScreen(isPreview: true),
                  ),
                ),
                child: Text(t('admin_business_preview')),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  t('admin_language_label'),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(width: 8),
                _langButton('Español', LangService.spanish),
                const SizedBox(width: 8),
                _langButton('English', LangService.english),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                t('admin_language_desc'),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _langButton(String label, String code) {
    final selected = LangService.locale.value == code;
    return OutlinedButton(
      onPressed: () => LangService.setLocale(code),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            selected ? AppTheme.accent : AppTheme.textSecondary,
        side: BorderSide(
          color: selected ? AppTheme.accent : AppTheme.textSecondary,
          width: selected ? 2 : 1,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child:
          Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  /// Botón de idioma para el formulario de mecánico: no cambia nada global,
  /// solo marca la selección (se guarda al pulsar Guardar).

  /// Tarjeta de respaldo/restauración (solo fundador).
  Widget _backupCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.backup_outlined,
                    color: AppTheme.accent),
                const SizedBox(width: 10),
                Text(
                  t('admin_backup_title'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('admin_backup_desc'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            // Interruptor del respaldo automático.
            Row(
              children: [
                const Icon(Icons.autorenew,
                    color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('admin_backup_auto_title'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _autoBackupEnabled,
                  activeColor: AppTheme.accent,
                  onChanged: (v) async {
                    await const AutoBackupService()
                        .setEnabled(v);
                    if (mounted) {
                      setState(() => _autoBackupEnabled = v);
                    }
                  },
                ),
              ],
            ),
            if (_autoBackupEnabled) ...[
              const SizedBox(height: 4),
              Text(
                t('admin_backup_auto_every'),
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final days
                      in AutoBackupService.intervalOptions)
                    ChoiceChip(
                      label: Text(t('admin_backup_auto_days',
                          {'n': '$days'})),
                      selected: _autoBackupInterval == days,
                      selectedColor: AppTheme.accent,
                      labelStyle: TextStyle(
                        color: _autoBackupInterval == days
                            ? Colors.white
                            : AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                      onSelected: (_) async {
                        await const AutoBackupService()
                            .setIntervalDays(days);
                        if (mounted) {
                          setState(
                              () => _autoBackupInterval = days);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _lastAutoBackup == null
                          ? t('admin_backup_auto_none')
                          : t('admin_backup_auto_last', {
                              'date': _formatShortDate(
                                  _lastAutoBackup!)
                            }),
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _backupBusy ? null : _exportBackup,
                    icon: const Icon(Icons.upload, size: 18),
                    label: Text(t('admin_backup_btn')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _backupBusy ? null : _importBackup,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(t('admin_restore_btn')),
                  ),
                ),
              ],
            ),
            if (_backupBusy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      final file = await const BackupService().exportBackup();
      final bytes = await file.readAsBytes();
      // Además de compartirlo, se guarda en Descargas/MiTaller para
      // encontrarlo en la app Mis archivos.
      final name = await const AutoBackupService()
          .saveToDownloads(bytes, prefix: 'manual');
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: t('admin_backup_share_text', {'name': _businessName}),
        ),
      );
      try {
        await file.delete();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(t('admin_backup_saved', {'name': name}))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('admin_backup_failed',
                  {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.path == null) return;
    final file = File(picked.path!);

    BackupSummary summary;
    try {
      summary = await BackupService.readBackup(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('admin_restore_invalid'))),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('admin_restore_title')),
        content: Text(
          t('admin_restore_body', {
            'date': summary.exportedAt != null
                ? _fmtDate(summary.exportedAt!)
                : t('admin_restore_unknown_date'),
            'records': '${summary.recordCount}',
            'photos': '${summary.photoCount}',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('admin_restore_confirm')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _backupBusy = true);
    try {
      await const BackupService().restoreBackup(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('admin_restore_done')),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  t('admin_restore_failed', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Genera (o regenera) el código de recuperación del fundador y lo muestra
  /// para anotarlo en papel. El anterior queda invalidado.
  Future<void> _generateRecoveryCode() async {
    final me = _myRecord;
    if (me == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('admin_recovery_dialog_title')),
        content: Text(me.recoveryCodeHash == null
            ? t('admin_recovery_dialog_body_new')
            : t('admin_recovery_dialog_body_regen')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('admin_recovery_generate')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final code = RecoveryCode.generate();
    await _mechService.updateMechanic(
      me.copyWith(recoveryCodeHash: RecoveryCode.hash(code)),
    );
    await _load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('admin_recovery_save_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('admin_recovery_save_body'),
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
              child: Text(t('admin_recovery_noted')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mechanicsTab() {
    // Toda la pestaña desliza junta (tarjetas + lista).
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('admin_mechanics_header'),
                    style: const TextStyle(
                        fontSize: 15, color: AppTheme.textSecondary),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showMechanicForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t('common_add')),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.separated(
            itemCount: _mechanics.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final m = _mechanics[i];
              final isSelf = m.id == widget.currentMechanicId;
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppTheme.surfaceLight, width: 1),
                ),
                child: ListTile(
                  leading: MechanicAvatar(
                      mechanic: m, radius: 20),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                      if (m.isAdmin || m.isFounder)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              if (m.isAdmin)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent
                                        .withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    t('admin_badge_admin'),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accent,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              if (m.isFounder)
                                Container(
                                  margin:
                                      const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber
                                        .withValues(alpha: 0.2),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    t('admin_badge_founder'),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.amber,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(isSelf
                      ? t('admin_mechanic_you',
                          {'position': positionsLabel(m.positions)})
                      : positionsLabel(m.positions)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((!m.isFounder || _amIFounder) &&
                          (!m.isAdmin || _amIFounder || isSelf))
                        IconButton(
                          tooltip: t('common_edit'),
                          icon: const Icon(Icons.edit,
                              color: AppTheme.textSecondary, size: 20),
                          onPressed: () =>
                              _showMechanicForm(existing: m),
                        ),
                      if (!m.isFounder && !(m.isAdmin && !_amIFounder))
                        IconButton(
                          tooltip: t('common_delete'),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () => _deleteMechanic(m),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Pestaña Negocio: datos del negocio (solo fundador).
  Widget _businessTab() {
    if (!_amIFounder) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t('admin_business_founder_only'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          _businessCard(),
          _recoveryCodeCard(),
          _backupCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ---------------- Servicios (catálogo) ----------------

  Widget _servicesTab() {
    final carros =
        _services.where((s) => s.types.contains(VehicleType.carro)).toList();
    final motos =
        _services.where((s) => s.types.contains(VehicleType.moto)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('admin_services_header'),
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showServiceForm(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('common_add')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _serviceGroup(t('admin_section_cars'), carros),
              const SizedBox(height: 8),
              _serviceGroup(t('admin_section_bikes'), motos),
            ],
          ),
        ),
      ],
    );
  }

  Widget _serviceGroup(String title, List<ServiceItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight, width: 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        iconColor: AppTheme.accent,
        collapsedIconColor: AppTheme.textSecondary,
        title: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${items.length}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        children: items.map(_serviceRow).toList(),
      ),
    );
  }

  Widget _serviceRow(ServiceItem s) {
    return ListTile(
      title: Text(
        s.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: s.types.length > 1
          ? Text(t('admin_section_both'))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatMoney(s.price),
            style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
                fontSize: 16),
          ),
          IconButton(
            tooltip: t('common_edit'),
            icon: const Icon(Icons.edit,
                color: AppTheme.textSecondary, size: 20),
            onPressed: () => _showServiceForm(existing: s),
          ),
          IconButton(
            tooltip: t('common_delete'),
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            onPressed: () => _deleteService(s),
          ),
        ],
      ),
    );
  }

  Future<void> _showServiceForm({ServiceItem? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
        text: existing == null ? '' : existing.price.round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
            existing == null
                ? t('admin_service_add_title')
                : t('admin_service_edit_title'),
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: t('admin_service_name_label'),
                labelStyle: const TextStyle(
                    color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'))
              ],
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: t('admin_service_price_label'),
                labelStyle: const TextStyle(
                    color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price =
                  double.tryParse(priceCtrl.text.trim()) ?? 0;
              if (name.isEmpty || price <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                      content: Text(t('admin_service_invalid'))),
                );
                return;
              }
              safePop(ctx, true);
            },
            child: Text(existing == null
                ? t('common_add')
                : t('common_save')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final price = double.parse(priceCtrl.text.trim());
    if (existing == null) {
      final item = ServiceItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        price: price,
        types: {VehicleType.carro, VehicleType.moto},
      );
      await _catalogService.add(item);
      setState(() => _services.add(item));
      _msg(t('admin_service_added'));
    } else {
      final updated = ServiceItem(
        id: existing.id,
        name: name,
        price: price,
        types: existing.types,
      );
      await _catalogService.update(updated);
      setState(() {
        final i = _services.indexWhere((e) => e.id == existing.id);
        if (i != -1) _services[i] = updated;
      });
      _msg(t('admin_service_price_updated'));
    }
  }

  Future<void> _deleteService(ServiceItem s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('admin_service_delete_title'),
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(
            t('admin_service_delete_body', {'name': s.name}),
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('common_delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _catalogService.remove(s.id);
    setState(() => _services.removeWhere((e) => e.id == s.id));
    _msg(t('admin_service_deleted'));
  }

  Widget _tasksTab() {
    // Las terminadas van en una sección colapsada al final para que
    // no se acumulen en la lista (petición de George).
    final active =
        _tasks.where((t) => t.status != TaskStatus.done).toList();
    final done =
        _tasks.where((t) => t.status == TaskStatus.done).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('admin_tasks_header'),
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showTaskForm(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('admin_tasks_assign_btn')),
              ),
            ],
          ),
        ),
        Expanded(
          child: active.isEmpty && done.isEmpty
              ? Center(
                  child: Text(
                    t('admin_tasks_empty'),
                    style: const TextStyle(
                        color: AppTheme.textSecondary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  children: [
                    for (final task in active) ...[
                      _taskRow(task),
                      const SizedBox(height: 10),
                    ],
                    if (done.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius:
                              BorderRadius.circular(16),
                          border: Border.all(
                              color: AppTheme.surfaceLight,
                              width: 1),
                        ),
                        child: ExpansionTile(
                          title: Text(
                            "${t('admin_tasks_done_section')} (${done.length})",
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 14),
                          ),
                          children: [
                            for (final task in done)
                              _taskRow(task,
                                  compact: true),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Fila de tarea en el tab Tareas (activa o del historial).
  Widget _taskRow(Task task, {bool compact = false}) {
    final color = _statusColor(task.status);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.surfaceLight, width: 1),
      ),
      child: ListTile(
        dense: compact,
        onTap: () => _showTaskForm(existing: task),
        title: Text(
          task.title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: compact
                  ? TextDecoration.lineThrough
                  : null,
              color: compact
                  ? AppTheme.textSecondary
                  : AppTheme.textPrimary),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                t('admin_task_sub', {
                  'mechanic':
                      _mechanicName(task.mechanicId),
                  'status': t(
                      'my_tasks_status_${task.status.name}'),
                }),
                style: TextStyle(
                    color: color, fontSize: 13),
              ),
              if (task.status == TaskStatus.done &&
                  task.completedAt != null)
                Padding(
                  padding:
                      const EdgeInsets.only(top: 2),
                  child: Text(
                    t('task_done_info', {
                      'date':
                          formatDateTime(task.completedAt!),
                      'duration': formatWorkTime(
                          task.completedAt!
                              .difference(task.startedAt ??
                                  task.createdAt)
                              .inSeconds),
                    }),
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: t('common_delete'),
          icon: const Icon(Icons.delete_outline,
              color: Colors.redAccent, size: 20),
          onPressed: () => _deleteTask(task),
        ),
      ),
    );
  }

  // ---------------- Horas trabajadas ----------------

  Future<void> _shareWeekPdf(
      Mechanic m, _WeekGroup g) async {
    try {
      await AttendanceReport.shareWeekPdf(
          m, g.start, g.records);
    } catch (e) {
      if (mounted) {
        _msg(t('admin_pdf_failed', {'error': '$e'}));
      }
    }
  }

  Future<void> _confirmRecord(AttendanceRecord r) async {
    await AttendanceService.confirmShift(r.id);
    _load();
    _msg(t('admin_hours_confirmed'));
  }

  /// El administrador corrige la hora de entrada y/o salida de un registro
  /// (p. ej. el empleado llegó a las 7 pero registró su entrada a las 8).
  Future<void> _correctRecord(AttendanceRecord r) async {
    TimeOfDay inTime = TimeOfDay.fromDateTime(r.clockIn);
    TimeOfDay? outTime =
        r.clockOut != null ? TimeOfDay.fromDateTime(r.clockOut!) : null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String fmt(TimeOfDay tod) => formatClock(
              DateTime(2020, 1, 1, tod.hour, tod.minute));
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text(t('admin_hours_correct_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('admin_hours_in_label')),
                  trailing: Text(fmt(inTime),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                  onTap: () async {
                    final p = await showTimePicker(
                      context: ctx,
                      initialTime: inTime,
                      helpText: t('admin_hours_in_help'),
                    );
                    if (p != null) setD(() => inTime = p);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('admin_hours_out_label')),
                  trailing: Text(
                      outTime == null ? '—' : fmt(outTime!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                  onTap: () async {
                    final p = await showTimePicker(
                      context: ctx,
                      initialTime: outTime ??
                          const TimeOfDay(hour: 18, minute: 0),
                      helpText: t('admin_hours_out_help'),
                    );
                    if (p != null) setD(() => outTime = p);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t('common_cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final d = r.date;
                  final newOut = outTime == null
                      ? null
                      : DateTime(d.year, d.month, d.day,
                          outTime!.hour, outTime!.minute);
                  final newIn = DateTime(d.year, d.month, d.day,
                      inTime.hour, inTime.minute);
                  try {
                    // Primero la salida y luego la entrada, para que las
                    // validaciones comparen contra los valores nuevos.
                    if (newOut != null && newOut != r.clockOut) {
                      await AttendanceService.correctShift(
                          r.id, newOut);
                    }
                    if (newIn != r.clockIn) {
                      await AttendanceService.correctClockIn(
                          r.id, newIn);
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  } on ArgumentError catch (e) {
                    _msg(e.message);
                  }
                },
                child: Text(t('common_save')),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      _load();
      _msg(t('admin_hours_corrected'));
    }
  }

  Future<void> _deleteRecord(AttendanceRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('admin_hours_delete_title')),
        content: Text(
          t('admin_hours_delete_body', {
            'day': formatDay(r.date),
            'name': _mechanicName(r.mechanicId),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              t('common_cancel'),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              t('common_delete'),
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AttendanceService.delete(r.id);
      _load();
      _msg(t('admin_hours_deleted'));
    }
  }

  Widget _hoursTab() {
    if (_mechanics.isEmpty) {
      return Center(
        child: Text(
          t('admin_hours_no_mechanics'),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _mechanics.length,
      itemBuilder: (context, i) {
        final m = _mechanics[i];
        final recs =
            _records.where((r) => r.mechanicId == m.id).toList();
        recs.sort((a, b) => b.date.compareTo(a.date));
        // El total incluye lo que va corriendo del turno abierto.
        final total =
            recs.fold<double>(0, (s, r) => s + r.hoursSoFar);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final openToday =
            recs.where((r) => r.isOpen && r.date == today).toList();
        final pendingCount =
            recs.where((r) => r.needsConfirmation).length;

        return Card(
          color: AppTheme.surface,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: pendingCount > 0
                ? BorderSide(
                    color: Colors.amber.withValues(alpha: 0.7),
                    width: 1.5)
                : BorderSide.none,
          ),
          child: ExpansionTile(
            leading:
                MechanicAvatar(mechanic: m, radius: 20),
            // Nombre y total siempre en una línea (con 2+ puestos el
            // subtítulo se alargaba y el total se recorría abajo).
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    m.name,
                    style:
                        const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                // Tiempo que va hoy, en vivo si tiene turno abierto.
                if (openToday.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${t('admin_hours_today_prefix')} ',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        LiveHoursText.sum(
                          records: openToday,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  formatHours(total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              positionsLabel(m.positions) +
                  (pendingCount > 0
                      ? t('admin_hours_pending_suffix',
                          {'n': '$pendingCount'})
                      : ''),
              style: TextStyle(
                color: pendingCount > 0
                    ? Colors.amber
                    : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: pendingCount > 0
                    ? FontWeight.w700
                    : FontWeight.normal,
              ),
            ),
            children: [
              if (recs.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t('admin_hours_no_records'),
                      style: const TextStyle(
                          color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ..._weekGroups(recs).map(
                  (g) => ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatWeekRange(g.start),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          formatHours(g.totalHours),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          tooltip: t('admin_hours_report_pdf'),
                          visualDensity:
                              VisualDensity.compact,
                          icon: const Icon(
                              Icons.picture_as_pdf,
                              size: 20,
                              color: AppTheme.accent),
                          onPressed: () =>
                              _shareWeekPdf(m, g),
                        ),
                      ],
                    ),
                    children: [
                      ...g.records.map(
                        (r) => ListTile(
                          dense: true,
                          title: Text(
                            formatWeekday(r.date),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text.rich(
                            TextSpan(
                              style:
                                  const TextStyle(fontSize: 13),
                              children: [
                                TextSpan(
                                    text:
                                        '${formatDay(r.date)}\n'),
                                TextSpan(
                                  text: t('admin_hours_row_in', {
                                    'time': formatClock(r.clockIn)
                                  }),
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: '   '),
                                TextSpan(
                                  text: r.isOpen
                                      ? t('admin_hours_row_out_open')
                                      : t('admin_hours_row_out', {
                                          'time': formatClock(
                                              r.clockOut!)
                                        }),
                                  style: TextStyle(
                                    color: r.isOpen
                                        ? AppTheme.textSecondary
                                        : Colors.orangeAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (r.needsConfirmation)
                                  TextSpan(
                                    text: t(
                                        'admin_hours_manual_close'),
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // El admin confirma que la hora es correcta
                              // o la corrige: así ninguna hora a mano pasa
                              // desapercibida.
                              if (r.needsConfirmation)
                                IconButton(
                                  tooltip: t('admin_hours_confirm_tip'),
                                  visualDensity:
                                      VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.greenAccent,
                                    size: 22,
                                  ),
                                  onPressed: () =>
                                      _confirmRecord(r),
                                ),
                              IconButton(
                                tooltip: t('admin_hours_correct_title'),
                                visualDensity:
                                    VisualDensity.compact,
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _correctRecord(r),
                              ),
                              r.isOpen
                                  ? LiveHoursText(
                                      record: r,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.greenAccent,
                                        fontSize: 14,
                                      ),
                                    )
                                  : Text(
                                      formatHours(
                                          r.hoursWorked),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.accent,
                                        fontSize: 14,
                                      ),
                                    ),
                              IconButton(
                                tooltip: t('common_delete'),
                                icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 20),
                                onPressed: () =>
                                    _deleteRecord(r),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Registros de un mecánico agrupados por semana (lunes a domingo),
/// de la semana más reciente a la más antigua.
List<_WeekGroup> _weekGroups(List<AttendanceRecord> recs) {
  final byWeek = <DateTime, List<AttendanceRecord>>{};
  for (final r in recs) {
    final ws = weekStart(r.date);
    byWeek.putIfAbsent(ws, () => []).add(r);
  }
  final groups = byWeek.entries
      .map((e) => _WeekGroup(start: e.key, records: e.value))
      .toList();
  for (final g in groups) {
    g.records.sort((a, b) => b.date.compareTo(a.date));
  }
  groups.sort((a, b) => b.start.compareTo(a.start));
  return groups;
}

class _WeekGroup {
  final DateTime start;
  final List<AttendanceRecord> records;

  _WeekGroup({required this.start, required this.records});

  double get totalHours =>
      records.fold<double>(0, (s, r) => s + r.hoursWorked);
}

/// Fecha corta (ej. "6 oct 2026").
String _formatShortDate(DateTime d) {
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Diálogo para registrar un abono en Por cobrar.
/// Es dueño de su controlador de texto: liberarlo justo después del
/// pop (con el campo enfocado aún montado durante la animación de
/// salida) provocaba la pantalla roja al guardar y al cancelar.
class _PaymentDialog extends StatefulWidget {
  final Ticket ticket;

  const _PaymentDialog({required this.ticket});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim()) ?? 0;
    if (v <= 0 || v > widget.ticket.balance + 0.009) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(t('admin_payment_invalid',
                {'max': formatMoney(widget.ticket.balance)}))),
      );
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t(
          'admin_payment_title', {'name': widget.ticket.customer.name})),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('admin_payment_owes',
                {'amount': formatMoney(widget.ticket.balance)}),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'))
            ],
            decoration: InputDecoration(
              labelText: t('admin_payment_amount_label'),
              prefixText: t('admin_currency_prefix'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('common_cancel')),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(t('admin_payment_register')),
        ),
      ],
    );
  }
}
