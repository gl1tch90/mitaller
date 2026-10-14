import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/inventory_item.dart';
import '../models/mechanic.dart';
import '../services/inventory_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../utils/money.dart';
import 'barcode_scanner_screen.dart';
import 'inventory_form_screen.dart';

/// Inventario del taller: insumos que rotan (aceites, filtros, bujías).
/// Inventario de insumos del taller.
/// [readOnly]: el mecánico solo consulta existencias (sin agregar,
/// editar, eliminar ni resurtir). El descuento de lo usado pasa por
/// "Completar información" de la orden, no por aquí.
class InventoryScreen extends StatefulWidget {
  final Mechanic mechanic;
  final bool readOnly;

  const InventoryScreen(
      {super.key, required this.mechanic, this.readOnly = false});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends LocaleAwareState<InventoryScreen> {
  final _service = InventoryService();
  List<InventoryItem> _items = [];

  /// Modo borrado múltiple: casillas en cada fila.
  bool _selecting = false;
  final Set<String> _selected = {};
  double _margin = InventoryService.defaultMarginPct;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.load();
    final margin = await _service.marginPct();
    if (mounted) {
      setState(() {
        _items = items;
        _margin = margin;
        _loading = false;
      });
    }
  }

  /// Carga de insumos comunes: el usuario elige cuáles agregar.
  Future<void> _seedCatalog() async {
    final existing = _items.map((e) => e.name.toLowerCase()).toSet();
    final candidates = InventoryService.seedNames
        .where((n) => !existing.contains(n.toLowerCase()))
        .toList();
    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('inv_seed_none'))),
        );
      }
      return;
    }
    // Las casillas empiezan deseleccionadas: el usuario escoge cuáles quiere.
    final picked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('inv_seed_pick_title')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final n in candidates)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(n, style: const TextStyle(fontSize: 14)),
                      value: picked.contains(n),
                      activeColor: AppTheme.accent,
                      onChanged: (v) => setD(() {
                        if (v == true) {
                          picked.add(n);
                        } else {
                          picked.remove(n);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed:
                  picked.isEmpty ? null : () => Navigator.of(ctx).pop(true),
              child: Text(t('inv_seed_add')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    final added = await _service.seedSelected(picked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_seed_done', {'n': '$added'}))),
      );
      _load();
    }
  }

  /// Borrado múltiple con confirmación.
  Future<void> _deleteSelected() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('inv_delete_multi_title')),
        content: Text(t('inv_delete_multi_body', {'n': '$n'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: Text(t('common_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _selected) {
      await _service.delete(id);
    }
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _load();
  }

  Future<void> _openForm([InventoryItem? item]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InventoryFormScreen(item: item),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _scanToFind() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(),
      ),
    );
    if (code == null || !mounted) return;
    final found = await _service.findByBarcode(code);
    if (!mounted) return;
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_not_found'))),
      );
      return;
    }
    _showItemSheet(found);
  }

  Future<void> _showItemSheet(InventoryItem item) async {
    // La hoja devuelve QUÉ acción se eligió; el diálogo/pantalla
    // siguiente se abre SOLO después de que la hoja ya se cerró.
    // (safePop retrasa el pop 100 ms; abrir el siguiente diálogo antes
    // hacía que el pop pendiente lo cerrara de inmediato.)
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${t('inv_pieces', {
                      'n': '${item.quantity.round()}'
                    })} · ${formatMoney(item.salePrice)} c/u',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => safePop(ctx, 'restock'),
                icon: const Icon(Icons.add_box_outlined),
                label: Text(t('inv_restock')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => safePop(ctx, 'edit'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(t('common_edit')),
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppTheme.accent),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => safePop(ctx, 'delete'),
                icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                label: Text(t('common_delete')),
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'restock':
        _restockDialog(item);
        break;
      case 'edit':
        _openForm(item);
        break;
      case 'delete':
        _deleteDialog(item);
        break;
    }
  }

  Future<void> _restockDialog(InventoryItem item) async {
    final qtyCtrl = TextEditingController(text: '1');
    // Si ya tiene precio, se muestra para confirmar; si es 0 (insumos
    // precargados), queda vacío y hay que escribirlo: el precio es obligatorio.
    final costCtrl = TextEditingController(
      text: item.cost > 0
          ? (item.cost == item.cost.roundToDouble()
              ? item.cost.toInt().toString()
              : item.cost.toString())
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String? costError;
          // Contador: botones -/+ y campo editable para cantidad manual.
          void bump(double delta) {
            final cur = double.tryParse(qtyCtrl.text.trim()) ?? 0;
            var next = cur + delta;
            if (next < 0) next = 0;
            qtyCtrl.text = next == next.roundToDouble()
                ? next.toInt().toString()
                : next.toStringAsFixed(2);
            setD(() {});
          }

          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text(t('inv_restock_title', {'name': item.name})),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('inv_restock_qty'),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => bump(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => bump(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: costCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (costError != null) setD(() => costError = null);
                  },
                  decoration: InputDecoration(
                    labelText: t('inv_restock_cost'),
                    prefixText: '\$ ',
                    border: const OutlineInputBorder(),
                    errorText: costError,
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
                  // El precio es obligatorio: sin precio válido no se guarda.
                  final c = double.tryParse(costCtrl.text.trim());
                  if (c == null || c <= 0) {
                    setD(() => costError = t('inv_cost_required'));
                    return;
                  }
                  safePop(ctx, true);
                },
                child: Text(t('common_save')),
              ),
            ],
          );
        },
      ),
    );
    // Leer ANTES de liberar (leer después de dispose = pantalla roja).
    final qtyText = qtyCtrl.text.trim();
    final costText = costCtrl.text.trim();
    qtyCtrl.dispose();
    costCtrl.dispose();
    if (ok != true || !mounted) return;
    final qty = double.tryParse(qtyText) ?? 0;
    if (qty <= 0) return;
    final cost = double.tryParse(costText);
    await _service.restock(item.id, qty, newCost: cost);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_restocked'))),
      );
      _load();
    }
  }

  Future<void> _deleteDialog(InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('inv_delete_title')),
        content: Text(t('inv_delete_body', {'name': item.name})),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            onPressed: () => safePop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(t('common_delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('inv_deleted'))),
        );
        _load();
      }
    }
  }

  Future<void> _marginDialog() async {
    final ctrl = TextEditingController(text: _margin.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('inv_margin_label')),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: '%',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            onPressed: () => safePop(ctx, true),
            child: Text(t('common_save')),
          ),
        ],
      ),
    );
    final pct = double.tryParse(ctrl.text.trim());
    ctrl.dispose();
    if (ok == true && pct != null && mounted) {
      await _service.setMarginPct(pct);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_margin_saved'))),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowCount = _items.where((e) => e.isLow).length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_selecting
            ? t('inv_selected', {'n': '${_selected.length}'})
            : t('inv_title')),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
              )
            : null,
        actions: [
          if (_selecting)
            IconButton(
              tooltip: t('common_delete'),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            )
          else if (!widget.readOnly) ...[
            IconButton(
              tooltip: t('inv_seed_btn'),
              icon: const Icon(Icons.list_alt),
              onPressed: _seedCatalog,
            ),
            IconButton(
              tooltip: t('inv_delete_multi_title'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => setState(() => _selecting = true),
            ),
            IconButton(
              tooltip: t('inv_margin_label'),
              icon: const Icon(Icons.percent),
              onPressed: _marginDialog,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 64, color: AppTheme.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          t('inv_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        if (!widget.readOnly) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _seedCatalog,
                            icon: const Icon(Icons.list_alt),
                            label: Text(t('inv_seed_btn')),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (lowCount > 0)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            t('inv_low_alert', {'n': '$lowCount'}),
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      for (final item in _items) _itemCard(item),
                    ],
                  ),
                ),
      floatingActionButton: widget.readOnly || _selecting
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'inv_scan',
                  onPressed: _scanToFind,
                  backgroundColor: AppTheme.surfaceLight,
                  child:
                      const Icon(Icons.qr_code_scanner, color: AppTheme.accent),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'inv_add',
                  onPressed: () => _openForm(),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
    );
  }

  Widget _itemCard(InventoryItem item) => Card(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: item.isLow
              ? BorderSide(color: Colors.orange.withValues(alpha: 0.6))
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.readOnly
              ? null
              : _selecting
                  ? () => setState(() {
                        if (_selected.contains(item.id)) {
                          _selected.remove(item.id);
                        } else {
                          _selected.add(item.id);
                        }
                      })
                  : () => _showItemSheet(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (_selecting)
                  Checkbox(
                    value: _selected.contains(item.id),
                    activeColor: AppTheme.accent,
                    onChanged: (_) => setState(() {
                      if (_selected.contains(item.id)) {
                        _selected.remove(item.id);
                      } else {
                        _selected.add(item.id);
                      }
                    }),
                  ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: AppTheme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        '${formatMoney(item.salePrice)} c/u',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      if (item.isLow)
                        Text(
                          t('inv_low_badge'),
                          style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${item.quantity.round()}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: item.isLow ? Colors.orange : AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
