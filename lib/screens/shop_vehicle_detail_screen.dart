import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/customer.dart';
import '../models/mechanic.dart';
import '../models/quick_service.dart';
import '../models/shop_vehicle.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../services/mechanic_service.dart';
import '../services/shop_vehicle_service.dart';
import '../services/vehicle_report_service.dart';
import '../services/work_order_service.dart';
import '../utils/dialog.dart';
import '../theme/app_theme.dart';
import 'shop_vehicle_form_screen.dart';
import '../utils/photo_picker.dart';

/// Detalle del vehículo del taller: bitácora diaria, daños,
/// documentos, gastos y aceite.
class ShopVehicleDetailScreen extends StatefulWidget {
  final Mechanic mechanic;
  final ShopVehicle vehicle;

  const ShopVehicleDetailScreen(
      {super.key, required this.mechanic, required this.vehicle});

  @override
  State<ShopVehicleDetailScreen> createState() =>
      _ShopVehicleDetailScreenState();
}

class _ShopVehicleDetailScreenState
    extends LocaleAwareState<ShopVehicleDetailScreen> {
  final _service = ShopVehicleService();
  late ShopVehicle _v;
  VehicleLogEntry? _today;
  List<VehicleLogEntry> _history = [];
  List<VehicleIssue> _issues = [];
  List<VehicleDocument> _docs = [];
  List<VehicleExpense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _v = widget.vehicle;
    _load();
  }

  Future<void> _load() async {
    final vehicles = await _service.loadVehicles();
    final v = vehicles.firstWhere((e) => e.id == _v.id,
        orElse: () => _v);
    final today = await _service.todayEntry(_v.id);
    final history = await _service.logFor(_v.id);
    final issues = await _service.issuesFor(_v.id);
    final docs = await _service.docsFor(_v.id);
    final expenses = await _service.expensesFor(_v.id);
    if (mounted) {
      setState(() {
        _v = v;
        _today = today;
        _history = history;
        _issues = issues;
        _docs = docs;
        _expenses = expenses;
        _loading = false;
      });
    }
  }

  // ---------------- Bitácora del día ----------------

  /// Aviso previo: qué revisar antes de usar el vehículo.
  /// Devuelve true si el mecánico quiere continuar.
  Future<bool> _showPreCheckNotice() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('shop_log_notice_title')),
        content: Text(
          t('shop_log_notice_body'),
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('shop_log_notice_later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('shop_log_notice_checked')),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _fillTodayLog() async {
    // Primero el aviso de qué revisar.
    if (!await _showPreCheckNotice()) return;
    if (!mounted) return;

    final kmCtrl =
        TextEditingController(text: '${_v.currentKm}');
    ConditionLevel oil = ConditionLevel.bien;
    ConditionLevel coolant = ConditionLevel.bien;
    ConditionLevel tires = ConditionLevel.bien;
    bool lightsOk = true;
    final notesCtrl = TextEditingController();
    String? error;

    /// Cuántos km se pasó del cambio de aceite con el km escrito.
    int oilOverdue(int km) {
      final base = _v.oilChangeKm ?? 0;
      return km - (base + ShopVehicleService.oilEveryKm);
    }

    Widget triButtons(
        String label,
        ConditionLevel value,
        ValueChanged<ConditionLevel> onPick,
        List<String> labels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (int i = 0;
                  i < ConditionLevel.values.length;
                  i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: i < 2 ? 8 : 0),
                    child: ChoiceChip(
                      label: Text(labels[i],
                          style:
                              const TextStyle(fontSize: 13)),
                      selected:
                          value == ConditionLevel.values[i],
                      selectedColor: _levelColor(
                          ConditionLevel.values[i]),
                      onSelected: (_) => onPick(
                          ConditionLevel.values[i]),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final km =
              int.tryParse(kmCtrl.text.trim()) ?? 0;
          final overdue =
              km > 0 ? oilOverdue(km) : 0;
          return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('shop_log_today_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: kmCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: t('shop_log_km'),
                    border:
                        const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setD(() {}),
                ),
                // Alerta en rojo si con ese km ya se pasó el aceite.
                if (overdue > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent
                          .withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.redAccent
                              .withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      t('shop_log_oil_overdue',
                          {'km': '$overdue'}),
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                triButtons(
                    t('shop_log_oil_level'),
                    oil,
                    (v) => setD(() => oil = v),
                    [
                      t('shop_level_bad'),
                      t('shop_level_regular'),
                      t('shop_level_good')
                    ]),
                const SizedBox(height: 12),
                triButtons(
                    t('shop_log_coolant_level'),
                    coolant,
                    (v) =>
                        setD(() => coolant = v),
                    [
                      t('shop_level_bad'),
                      t('shop_level_regular'),
                      t('shop_level_good')
                    ]),
                const SizedBox(height: 12),
                triButtons(
                    t('shop_log_tires_state'),
                    tires,
                    (v) => setD(() => tires = v),
                    [
                      t('shop_level_bad_f'),
                      t('shop_level_regular_f'),
                      t('shop_level_good_f')
                    ]),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(t('shop_log_lights_ok')),
                  value: lightsOk,
                  activeColor: AppTheme.accent,
                  onChanged: (v) =>
                      setD(() => lightsOk = v ?? true),
                ),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText:
                        t('shop_log_notes_optional'),
                    border:
                        const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                final km =
                    int.tryParse(kmCtrl.text.trim());
                if (km == null || km < _v.currentKm) {
                  setD(() => error =
                      t('shop_log_km_invalid',
                          {'km': '${_v.currentKm}'}));
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(t('common_save')),
            ),
          ],
        );
        },
      ),
    );

    if (ok == true && mounted) {
      final entry = VehicleLogEntry(
        id: DateTime.now()
            .millisecondsSinceEpoch
            .toString(),
        vehicleId: _v.id,
        date: DateTime.now(),
        mechanicId: widget.mechanic.id,
        mechanicName: widget.mechanic.name,
        km: int.parse(kmCtrl.text.trim()),
        oil: oil,
        coolant: coolant,
        tires: tires,
        lightsOk: lightsOk,
        notes: notesCtrl.text.trim(),
      );
      await _service.saveTodayEntry(entry);
      _load();
    }
    kmCtrl.dispose();
    notesCtrl.dispose();
  }

  /// Color del nivel: malo rojo, regular naranja, bien verde.
  Color _levelColor(ConditionLevel l) {
    switch (l) {
      case ConditionLevel.malo:
        return Colors.redAccent;
      case ConditionLevel.regular:
        return Colors.orange;
      case ConditionLevel.bien:
        return Colors.green;
    }
  }
  // ---------------- Daños ----------------

  Future<String?> _capturePhoto(String sub) async {
    final xfile = await pickPhotoChoice(context);
    if (xfile == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/shop_vehicles/$sub');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(xfile.path).copy(dest.path);
    return dest.path;
  }

  Future<void> _reportIssue() async {
    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? photoPath;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('shop_issue_report_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText:
                        t('shop_issue_description'),
                    border:
                        const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(photoPath == null
                      ? t('shop_issue_photo_optional')
                      : t('shop_issue_photo_added')),
                  onPressed: () async {
                    final p = await _capturePhoto(
                        'issues');
                    if (p != null) {
                      setD(() => photoPath = p);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText:
                        t('shop_log_notes_optional'),
                    border:
                        const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (descCtrl.text.trim().isEmpty) {
                  setD(() => error =
                      t('shop_issue_desc_required'));
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      await _service.addIssue(VehicleIssue(
        id: DateTime.now()
            .millisecondsSinceEpoch
            .toString(),
        vehicleId: _v.id,
        reportedById: widget.mechanic.id,
        reportedByName: widget.mechanic.name,
        date: DateTime.now(),
        description: descCtrl.text.trim(),
        photoPath: photoPath,
        notes: notesCtrl.text.trim(),
      ));
      _load();
    }
    descCtrl.dispose();
    notesCtrl.dispose();
  }

  // ---------------- Documentos ----------------

  Future<void> _addDocument() async {
    String kind = 'seguro';
    DateTime expiry = DateTime.now().add(
        const Duration(days: 365));
    final notesCtrl = TextEditingController();
    String? photoPath;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('shop_doc_add_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: kind,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(
                    color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: t('shop_doc_kind'),
                  border:
                      const OutlineInputBorder(),
                ),
                items: [
                  'seguro',
                  'placas',
                  'verificacion',
                  'otro'
                ]
                    .map((k) => DropdownMenuItem(
                          value: k,
                          child: Text(
                              t('shop_doc_kind_$k')),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setD(() => kind = v ?? 'seguro'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('shop_doc_expiry')),
                trailing: Text(
                  _shortDate(expiry),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  final picked =
                      await showDatePicker(
                    context: ctx,
                    initialDate: expiry,
                    firstDate: DateTime.now().subtract(
                        const Duration(days: 365)),
                    lastDate: DateTime.now().add(
                        const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    setD(() => expiry = picked);
                  }
                },
              ),
              TextField(
                controller: notesCtrl,
                style: const TextStyle(
                    color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText:
                      t('shop_log_notes_optional'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Foto del documento (póliza, tarjeta...).
              InkWell(
                onTap: () async {
                  final p =
                      await _capturePhoto('documents');
                  if (p != null) {
                    setD(() => photoPath = p);
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color:
                            AppTheme.surfaceLight),
                  ),
                  child: photoPath != null
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(
                                  10),
                          child: Image.file(
                            File(photoPath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            const Icon(
                                Icons.add_a_photo,
                                color: AppTheme
                                    .textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              t('shop_doc_photo'),
                              style: const TextStyle(
                                  color: AppTheme
                                      .textSecondary),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(true),
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      await _service.addDocument(VehicleDocument(
        id: DateTime.now()
            .millisecondsSinceEpoch
            .toString(),
        vehicleId: _v.id,
        kind: kind,
        label: t('shop_doc_kind_$kind'),
        expiryDate: expiry,
        notes: notesCtrl.text.trim(),
        photoPath: photoPath,
      ));
      _load();
    }
    notesCtrl.dispose();
  }

  // ---------------- Gastos ----------------

  Future<void> _addExpense() async {
    String kind = 'reparacion';
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? photoPath;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('shop_expense_add_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in [
                      'reparacion',
                      'servicio',
                      'gasolina',
                      'otro'
                    ])
                      ChoiceChip(
                        label: Text(
                            t('shop_expense_kind_$k')),
                        selected: kind == k,
                        selectedColor:
                            AppTheme.accent,
                        onSelected: (_) =>
                            setD(() => kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: t('shop_expense_amount'),
                    prefixText: '\$ ',
                    border:
                        const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText:
                        t('shop_log_notes_optional'),
                    border:
                        const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: Text(photoPath == null
                      ? t('shop_expense_photo')
                      : t('shop_expense_photo_added')),
                  onPressed: () async {
                    final p = await _capturePhoto(
                        'expenses');
                    if (p != null) {
                      setD(() => photoPath = p);
                    }
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(
                    amountCtrl.text
                        .trim()
                        .replaceAll(',', '.'));
                if (amount == null ||
                    amount <= 0) {
                  setD(() => error =
                      t('shop_expense_amount_invalid'));
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

    final amount = double.tryParse(amountCtrl.text
        .trim()
        .replaceAll(',', '.'));
    final notes = notesCtrl.text.trim();
    disposeDialogControllers([amountCtrl, notesCtrl]);

    if (ok == true && mounted && amount != null && amount > 0) {
      final isAdmin = widget.mechanic.isAdmin;
      await _service.addExpense(VehicleExpense(
        id: DateTime.now()
            .millisecondsSinceEpoch
            .toString(),
        vehicleId: _v.id,
        date: DateTime.now(),
        kind: kind,
        amount: amount,
        notes: notes,
        photoPath: photoPath,
        createdById: widget.mechanic.id,
        createdByName: widget.mechanic.name,
        // Lo del mecánico queda pendiente de revisión del admin.
        approved: isAdmin,
      ));
      _load();
      if (!isAdmin && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(t('shop_expense_sent_for_review'))),
        );
      }
    }
  }

  // ---------------- Aceite ----------------

  Future<void> _logOilChange() async {
    final kmCtrl =
        TextEditingController(text: '${_v.currentKm}');
    DateTime date = DateTime.now();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('shop_oil_change_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: kmCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: t('shop_log_km'),
                  border:
                      const OutlineInputBorder(),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('shop_oil_date')),
                trailing: Text(
                  _shortDate(date),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  final picked =
                      await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(
                        const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setD(() => date = picked);
                  }
                },
              ),
              if (error != null)
                Text(error!,
                    style: const TextStyle(
                        color: Colors.redAccent)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                final km =
                    int.tryParse(kmCtrl.text.trim());
                if (km == null || km < 0) {
                  setD(() => error =
                      t('shop_vehicle_km_invalid'));
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      await _service.logOilChange(
          _v.id, int.parse(kmCtrl.text.trim()), date);
      _load();
    }
    kmCtrl.dispose();
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(_v.name),
        actions: [
          if (widget.mechanic.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: t('shop_vehicle_edit'),
              onPressed: _editVehicle,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'status') {
                  _changeStatus();
                } else if (value == 'delete') {
                  _deleteVehicle();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'status',
                  child: Text(t('shop_vehicle_change_status')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    t('shop_vehicle_delete'),
                    style:
                        const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),
                  _todayLogCard(),
                  const SizedBox(height: 12),
                  // Trabajar en este vehículo: crea una orden interna.
                  FilledButton.icon(
                    icon: const Icon(Icons.build),
                    label:
                        Text(t('shop_vehicle_work_on')),
                    onPressed: _workOnVehicle,
                  ),
                  const SizedBox(height: 12),
                  _oilCard(),
                  const SizedBox(height: 12),
                  _issuesCard(),
                  const SizedBox(height: 12),
                  _docsCard(),
                  const SizedBox(height: 12),
                  _expensesCard(),
                  const SizedBox(height: 12),
                  _historyCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Future<void> _editVehicle() async {
    final updated =
        await Navigator.of(context).push<ShopVehicle>(
      MaterialPageRoute(
        builder: (_) =>
            ShopVehicleFormScreen(existing: _v),
      ),
    );
    if (updated != null) {
      await _service.updateVehicle(updated);
      _load();
    }
  }

  /// Cambia el estado del vehículo (solo admin).
  Future<void> _changeStatus() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('shop_vehicle_change_status')),
        children: [
          _statusOption(ctx, 'activo', Colors.green,
              t('shop_vehicle_status_activo')),
          _statusOption(ctx, 'taller', Colors.orange,
              t('shop_vehicle_status_taller')),
          _statusOption(ctx, 'vendido', Colors.grey,
              t('shop_vehicle_status_vendido')),
        ],
      ),
    );
    if (picked == null || picked == _v.status || !mounted) return;
    await _service.updateVehicle(_v.copyWith(status: picked));
    _load();
  }

  SimpleDialogOption _statusOption(
      BuildContext ctx, String value, Color color, String label) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(ctx).pop(value),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textPrimary)),
          if (_v.status == value) ...[
            const Spacer(),
            const Icon(Icons.check, color: Colors.green),
          ],
        ],
      ),
    );
  }

  /// Borra el vehículo y todos sus datos (solo admin).
  /// Primero ofrece generar un reporte PDF con el historial.
  Future<void> _deleteVehicle() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('shop_vehicle_delete_title')),
        content: Text(t('shop_vehicle_delete_desc',
            {'name': _v.name})),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, 'cancel'),
            child: Text(t('common_cancel')),
          ),
          TextButton(
            onPressed: () => safePop(ctx, 'delete'),
            child: Text(
              t('shop_vehicle_delete_no_report'),
              style:
                  const TextStyle(color: Colors.redAccent),
            ),
          ),
          FilledButton(
            onPressed: () => safePop(ctx, 'report'),
            child: Text(t('shop_vehicle_delete_with_report')),
          ),
        ],
      ),
    );
    if (choice == null ||
        choice == 'cancel' ||
        !mounted) return;

    if (choice == 'report') {
      try {
        final name =
            await VehicleReportService.saveToDownloads(_v);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t(
                  'shop_vehicle_report_saved',
                  {'name': name})),
              duration: const Duration(seconds: 4)),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(t('shop_vehicle_report_error')),
              backgroundColor: Colors.red.shade700),
        );
        return;
      }
    }

    if (!mounted) return;
    await _service.removeVehicle(_v.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// "Trabajar en este vehículo": crea una orden de servicio interna
  /// (no de cliente) para este vehículo del taller.
  Future<void> _workOnVehicle() async {
    final descCtrl = TextEditingController();
    String? error;
    // El admin elige a quién se la asigna; el mecánico se auto-asigna.
    final isAdmin = widget.mechanic.isAdmin;
    String assigneeId = widget.mechanic.id;
    List<Mechanic> mechanics = [];
    if (isAdmin) {
      mechanics = await MechanicService().loadMechanics();
      if (mechanics.any((m) => m.id == assigneeId)) {
        // se queda el admin por defecto
      } else if (mechanics.isNotEmpty) {
        assigneeId = mechanics.first.id;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('shop_vehicle_work_on_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('shop_vehicle_work_on_desc'),
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  autofocus: true,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText:
                        t('shop_vehicle_work_on_what'),
                    border:
                        const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  Text(
                    t('shop_vehicle_work_on_who'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: assigneeId,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(
                        color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: mechanics
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setD(() => assigneeId = v);
                      }
                    },
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (descCtrl.text.trim().isEmpty) {
                  setD(() => error = t(
                      'shop_vehicle_work_on_required'));
                  return;
                }
                safePop(ctx, true);
              },
              child: Text(t('shop_vehicle_work_on_create')),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      disposeDialogControllers([descCtrl]);
      return;
    }
    final desc = descCtrl.text.trim();
    disposeDialogControllers([descCtrl]);

    final orderService = WorkOrderService();
    final now = DateTime.now();
    final order = WorkOrder(
      id: now.millisecondsSinceEpoch.toString(),
      folio: '', // lo asigna el servicio
      vehicleType: _v.kind == 'moto'
          ? VehicleType.moto
          : VehicleType.carro,
      vehicle: Vehicle(
        id: 'shop-${_v.id}',
        type: _v.kind == 'moto'
            ? VehicleType.moto
            : VehicleType.carro,
        year: 0,
        brand: _v.name,
        model: '',
        plate: _v.plates,
      ),
      customer: Customer(
          name: t('shop_vehicle_work_on_customer'),
          phone: ''),
      photos: const {},
      lines: [
        OrderLine(
            serviceId: quickServiceId,
            name: t('shop_vehicle_service_name'),
            note: desc),
      ],
      mechanicId: assigneeId,
      createdById: widget.mechanic.id,
      status: OrderStatus.pending,
      createdAt: now,
      shopVehicleId: _v.id,
    );
    final folio = await orderService.create(order);
    // El vehículo entra al taller: su estado pasa a naranja.
    await _service.updateVehicle(_v.copyWith(status: 'taller'));
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(t(
              'shop_vehicle_work_on_created',
              {'folio': folio}))),
    );
  }

  /// Círculo de color + etiqueta con el estado del vehículo.
  /// El admin lo puede tocar para cambiarlo.
  Widget _statusBadge() {
    Color color;
    String label;
    switch (_v.status) {
      case 'taller':
        color = Colors.orange;
        label = t('shop_vehicle_status_taller');
        break;
      case 'vendido':
        color = Colors.grey;
        label = t('shop_vehicle_status_vendido');
        break;
      default:
        color = Colors.green;
        label = t('shop_vehicle_status_activo');
    }
    final badge = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    if (!widget.mechanic.isAdmin) return badge;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _changeStatus,
      child: badge,
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (_v.photoPath != null &&
              File(_v.photoPath!).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(_v.photoPath!),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius:
                    BorderRadius.circular(10),
              ),
              child: Icon(
                _v.kind == 'moto'
                    ? Icons.two_wheeler
                    : Icons.directions_car,
                color: AppTheme.accent,
                size: 36,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_v.name,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                    _statusBadge(),
                  ],
                ),
                Text(
                  '${_v.kind == 'moto' ? t('shop_vehicles_moto') : t('shop_vehicles_carro')}'
                  '${_v.plates.isNotEmpty ? ' · ${_v.plates}' : ''}',
                  style: const TextStyle(
                      color:
                          AppTheme.textSecondary),
                ),
                if ((_v.vin ?? '').isNotEmpty)
                  Text(
                    'VIN: ${_v.vin}',
                    style: const TextStyle(
                        color:
                            AppTheme.textSecondary,
                        letterSpacing: 1),
                  ),
                if (_v.year != null ||
                    (_v.model ?? '').isNotEmpty)
                  Text(
                    [
                      if (_v.year != null) '${_v.year}',
                      if ((_v.model ?? '').isNotEmpty)
                        _v.model!,
                    ].join(' '),
                    style: const TextStyle(
                        color:
                            AppTheme.textSecondary),
                  ),
                const SizedBox(height: 4),
                Text(
                  t('shop_vehicle_km_current',
                      {'km': '${_v.currentKm}'}),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayLogCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.today,
                  color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(t('shop_log_today'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          // Un vehículo vendido ya no usa bitácora.
          if (_v.status != 'vendido') ...[
            if (_today == null)
              FilledButton.icon(
                icon: const Icon(Icons.checklist),
                label:
                    Text(t('shop_log_fill_today')),
                onPressed: _fillTodayLog,
              )
            else
              _logTile(_today!, showDate: false),
          ],
        ],
      ),
    );
  }

  Widget _logTile(VehicleLogEntry e,
      {bool showDate = true}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  showDate
                      ? '${_shortDate(e.date)} · ${e.mechanicName}'
                      : e.mechanicName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text('${e.km} km',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _miniLevel(e.oil,
                  t('shop_log_oil_short')),
              _miniLevel(e.coolant,
                  t('shop_log_coolant_short')),
              _miniLevel(e.tires,
                  t('shop_log_tires_short')),
              _miniCheck(e.lightsOk,
                  t('shop_log_lights_short')),
            ],
          ),
          if (e.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(e.notes,
                style: const TextStyle(
                    fontSize: 13,
                    color:
                        AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _miniLevel(ConditionLevel l, String label) {
    final color = _levelColor(l);
    final text = l == ConditionLevel.malo
        ? t('shop_level_bad')
        : l == ConditionLevel.regular
            ? t('shop_level_regular')
            : t('shop_level_good');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text('$label: $text',
            style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _miniCheck(bool ok, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: ok
                ? Colors.green
                : Colors.redAccent),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _oilCard() {
    final left =
        _v.kmToNextOil(ShopVehicleService.oilEveryKm);
    final lastDate = _v.oilChangeDate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: left < 0
            ? Border.all(
                color: Colors.redAccent
                    .withValues(alpha: 0.5))
            : null,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.oil_barrel,
                  color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('shop_oil_title'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight:
                            FontWeight.w700)),
              ),
              TextButton(
                onPressed: widget.mechanic.isAdmin
                    ? _logOilChange
                    : null,
                child:
                    Text(t('shop_oil_register')),
              ),
            ],
          ),
          Text(
            lastDate == null
                ? t('shop_oil_never')
                : t('shop_oil_last', {
                    'date': _shortDate(lastDate),
                    'km': '${_v.oilChangeKm ?? 0}'
                  }),
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            left < 0
                ? t('shop_oil_overdue_by',
                    {'km': '${-left}'})
                : t('shop_oil_left',
                    {'km': '$left'}),
            style: TextStyle(
                color: left < 0
                    ? Colors.redAccent
                    : AppTheme.textPrimary,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _issuesCard() {
    final open =
        _issues.where((e) => !e.resolved).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.report_problem,
                  color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    t('shop_issues_title',
                        {'n': '${open.length}'}),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight:
                            FontWeight.w700)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label:
                    Text(t('shop_issue_report')),
                onPressed: _reportIssue,
              ),
            ],
          ),
          if (_issues.isEmpty)
            Text(t('shop_issues_empty'),
                style: const TextStyle(
                    color:
                        AppTheme.textSecondary,
                    fontSize: 13))
          else
            ..._issues.map(_issueTile),
        ],
      ),
    );
  }

  Widget _issueTile(VehicleIssue i) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_shortDate(i.date)} · ${i.reportedByName}',
                  style: const TextStyle(
                      fontSize: 12,
                      color:
                          AppTheme.textSecondary),
                ),
              ),
              if (i.resolved)
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 18)
              else if (widget.mechanic.isAdmin)
                TextButton(
                  child:
                      Text(t('shop_issue_resolve')),
                  onPressed: () async {
                    await _service
                        .resolveIssue(i.id);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(i.description,
              style: const TextStyle(fontSize: 14)),
          if (i.photoPath != null &&
              File(i.photoPath!).existsSync()) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(8),
              child: Image.file(
                File(i.photoPath!),
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (i.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(i.notes,
                style: const TextStyle(
                    fontSize: 13,
                    color:
                        AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _docsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.description,
                  color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('shop_docs_title'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight:
                            FontWeight.w700)),
              ),
              if (widget.mechanic.isAdmin)
                TextButton.icon(
                  icon:
                      const Icon(Icons.add, size: 18),
                  label:
                      Text(t('shop_doc_add')),
                  onPressed: _addDocument,
                ),
            ],
          ),
          if (_docs.isEmpty)
            Text(t('shop_docs_empty'),
                style: const TextStyle(
                    color:
                        AppTheme.textSecondary,
                    fontSize: 13))
          else
            ..._docs.map(_docTile),
        ],
      ),
    );
  }

  Widget _docTile(VehicleDocument d) {
    final days = d.daysToExpiry();
    final Color color;
    final String status;
    if (days < 0) {
      color = Colors.redAccent;
      status = t('shop_doc_expired');
    } else if (days <=
        ShopVehicleService.docWarnDays) {
      color = Colors.amber;
      status = t('shop_doc_days_left',
          {'n': '$days'});
    } else {
      color = Colors.green;
      status = t('shop_doc_days_left',
          {'n': '$days'});
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: days <=
                ShopVehicleService.docWarnDays
            ? Border.all(
                color:
                    color.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          if (d.photoPath != null)
            GestureDetector(
              onTap: () => _viewPhoto(d.photoPath!),
              child: Container(
                width: 52,
                height: 52,
                margin:
                    const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          AppTheme.surfaceLight),
                ),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(8),
                  child: Image.file(
                    File(d.photoPath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(d.label,
                    style: const TextStyle(
                        fontWeight:
                            FontWeight.w600)),
                Text(
                  '${t('shop_doc_expiry')}: ${_shortDate(d.expiryDate)}',
                  style: const TextStyle(
                      fontSize: 12,
                      color:
                          AppTheme.textSecondary),
                ),
                Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight:
                            FontWeight.w700)),
              ],
            ),
          ),
          if (widget.mechanic.isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20),
              color: AppTheme.textSecondary,
              onPressed: () async {
                await _service
                    .removeDocument(d.id);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _expensesCard() {
    final isAdmin = widget.mechanic.isAdmin;
    final approved =
        _expenses.where((e) => e.approved).toList();
    final pending = _expenses
        .where((e) => !e.approved && !e.rejected)
        .toList();
    final rejected = _expenses
        .where((e) =>
            e.rejected &&
            e.createdById == widget.mechanic.id)
        .toList();
    // El total solo suma lo aprobado.
    final total =
        approved.fold<double>(0, (s, e) => s + e.amount);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_money,
                  color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: isAdmin
                    ? Text(
                        t('shop_expenses_title',
                            {
                              'total':
                                  '\$${total.toStringAsFixed(0)}'
                            }),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w700))
                    : Text(
                        t('shop_expenses_title_mechanic'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w700)),
              ),
              TextButton.icon(
                icon:
                    const Icon(Icons.add, size: 18),
                label:
                    Text(t('shop_expense_add')),
                onPressed: _addExpense,
              ),
            ],
          ),
          // Pendientes de revisión (solo el admin los aprueba).
          if (isAdmin && pending.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...pending.map(_pendingExpenseTile),
            const SizedBox(height: 4),
          ],
          if (isAdmin) ...[
            if (approved.isEmpty && pending.isEmpty)
              Text(t('shop_expenses_empty'),
                  style: const TextStyle(
                      color:
                          AppTheme.textSecondary,
                      fontSize: 13))
            else
              ...approved
                  .take(10)
                  .map(_expenseTile),
          ] else ...[
            // El mecánico ya no ve lo "en revisión": solo le aparecen
            // los que el admin rechazó, para volver a reportarlos.
            if (rejected.isEmpty)
              Text(t('shop_expenses_empty_mechanic'),
                  style: const TextStyle(
                      color:
                          AppTheme.textSecondary,
                      fontSize: 13))
            else
              ...rejected.map(_rejectedExpenseTile),
          ],
        ],
      ),
    );
  }

  /// Muestra una foto en grande.
  void _viewPhoto(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _expenseTile(VehicleExpense e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Foto del ticket/recibo (si tiene).
          if (e.photoPath != null &&
              File(e.photoPath!).existsSync()) ...[
            GestureDetector(
              onTap: () => _viewPhoto(e.photoPath!),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(8),
                child: Image.file(
                  File(e.photoPath!),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  t('shop_expense_kind_${e.kind}'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                Text(
                  '${_shortDate(e.date)}${e.notes.isNotEmpty ? ' · ${e.notes}' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      color:
                          AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text('\$${e.amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700)),
          if (widget.mechanic.isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18),
              color: AppTheme.textSecondary,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(),
              onPressed: () async {
                await _service
                    .removeExpense(e.id);
                _load();
              },
            ),
        ],
      ),
    );
  }

  /// Gasto pendiente de revisión (vista del admin): aprobar o rechazar.
  Widget _pendingExpenseTile(VehicleExpense e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (e.photoPath != null &&
              File(e.photoPath!).existsSync()) ...[
            GestureDetector(
              onTap: () => _viewPhoto(e.photoPath!),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(8),
                child: Image.file(
                  File(e.photoPath!),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '${t('shop_expense_kind_${e.kind}')} · \$${e.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                Text(
                  '${_shortDate(e.date)}'
                  '${e.createdByName.isNotEmpty ? ' · ${e.createdByName}' : ''}'
                  '${e.notes.isNotEmpty ? ' · ${e.notes}' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      color:
                          AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: Colors.redAccent),
            tooltip: t('shop_expense_reject'),
            onPressed: () => _rejectExpense(e),
          ),
          IconButton(
            icon: const Icon(Icons.check,
                color: Colors.green),
            tooltip: t('shop_expense_approve'),
            onPressed: () async {
              await _service.updateExpense(
                  e.copyWith(approved: true));
              _load();
            },
          ),
        ],
      ),
    );
  }

  /// Rechaza un gasto: pide el motivo y le avisa al mecánico
  /// para que lo vuelva a reportar corregido.
  Future<void> _rejectExpense(VehicleExpense e) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('shop_expense_reject_title')),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          style: const TextStyle(
              color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: t('shop_expense_reject_hint'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () => safePop(ctx, true),
            child: Text(t('shop_expense_reject_confirm')),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    disposeDialogControllers([reasonCtrl]);
    if (ok != true || !mounted) return;
    await _service.updateExpense(
        e.copyAsRejected(reason));
    _load();
  }

  /// Gasto rechazado por el admin (vista del mecánico): muestra el
  /// motivo y permite descartarlo al volver a reportarlo.
  Widget _rejectedExpenseTile(VehicleExpense e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '${t('shop_expense_kind_${e.kind}')} · ${_shortDate(e.date)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                if (e.rejectReason.isNotEmpty)
                  Text(
                    e.rejectReason,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent),
                  ),
                Text(
                  t('shop_expense_rejected_hint'),
                  style: const TextStyle(
                      fontSize: 12,
                      color:
                          AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await _service.removeExpense(e.id);
              _load();
            },
            child: Text(t('shop_expense_rejected_ok')),
          ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    final older =
        _history.where((e) => _today == null ||
            e.id != _today!.id).toList();
    if (older.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history,
                  color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(t('shop_history_title'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ...older.take(15).map((e) =>
              _logTile(e, showDate: true)),
        ],
      ),
    );
  }

  String _shortDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
