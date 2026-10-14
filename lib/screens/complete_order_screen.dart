import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/inventory_item.dart';
import '../models/work_order.dart';
import '../services/inventory_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../utils/duration.dart';
import '../utils/money.dart';
import 'barcode_scanner_screen.dart';

/// "Completar información": el mecánico anota lo que usó antes de mandar
/// la orden a revisión.
/// - Materiales del inventario (colapsable): escaneados o manuales.
///   Pregunta si son del taller o los trajo el cliente.
/// - Comprado para este trabajo: descripción + monto + foto del ticket
///   (opcional).
/// Al mandar a revisión se descuenta del inventario lo del taller.
class CompleteOrderScreen extends StatefulWidget {
  final WorkOrder order;

  const CompleteOrderScreen({super.key, required this.order});

  @override
  State<CompleteOrderScreen> createState() =>
      _CompleteOrderScreenState();
}

class _CompleteOrderScreenState extends LocaleAwareState<CompleteOrderScreen> {
  final _invService = InventoryService();
  final _orderService = WorkOrderService();
  final _notesCtrl = TextEditingController();

  List<OrderMaterial> _materials = [];
  List<OrderPurchase> _purchases = [];
  bool _materialsOpen = false;
  bool _busy = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ---------------- Materiales ----------------

  Future<void> _scanMaterial() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(),
      ),
    );
    if (code == null || !mounted) return;
    final item = await _invService.findByBarcode(code);
    if (!mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_not_found'))),
      );
      return;
    }
    _askSource(item, 1, confirmItem: true);
  }

  /// Pregunta si el material es del taller o lo trajo el cliente,
  /// y lo agrega a la lista. La pregunta no se puede saltar tocando
  /// fuera: hay que elegir origen o cancelar explícitamente.
  /// [confirmItem] usa el título "¿Es este?" (flujo de escáner).
  Future<void> _askSource(InventoryItem item, double qty,
      {bool confirmItem = false}) async {
    if (!mounted) return;
    final source = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t(confirmItem
            ? 'inv_confirm_title'
            : 'complete_source_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              t('inv_pieces', {'n': '$qty'}),
              style: const TextStyle(
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(t('complete_ask_source'),
                style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx),
            child: Text(t('common_cancel')),
          ),
          TextButton(
            onPressed: () => safePop(ctx, 'cliente'),
            child: Text(t('complete_from_client')),
          ),
          FilledButton(
            onPressed: () => safePop(ctx, 'taller'),
            child: Text(t('complete_from_shop')),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    if (source == 'taller' && item.quantity < qty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                t('inv_no_stock', {'name': item.name}))),
      );
      return;
    }
    setState(() {
      _materialsOpen = true;
      final i = _materials.indexWhere(
          (m) => m.itemId == item.id && m.source == source);
      if (i == -1) {
        _materials.add(OrderMaterial(
          itemId: item.id,
          name: item.name,
          qty: qty,
          source: source,
          unitCost: item.cost,
          unitPrice: item.salePrice,
        ));
      } else {
        final m = _materials[i];
        _materials[i] = OrderMaterial(
          itemId: m.itemId,
          name: m.name,
          qty: m.qty + qty,
          source: m.source,
          unitCost: m.unitCost,
          unitPrice: m.unitPrice,
        );
      }
    });
  }

  /// Agregar manual: lista con - / + por producto (sin diálogos
  /// extra para la cantidad). Al aceptar, pregunta el origen
  /// (taller/cliente) de cada producto elegido, como antes.
  Future<void> _addManual() async {
    final items = await _invService.load();
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_empty'))),
      );
      return;
    }
    final qty = <String, int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('complete_add_materials')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                final q = qty[it.id] ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(it.name,
                      style: const TextStyle(
                          color: AppTheme.textPrimary)),
                  subtitle: Text(
                    t('inv_pieces',
                        {'n': '${it.quantity.round()}'}),
                    style: const TextStyle(
                        color: AppTheme.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: q == 0
                            ? null
                            : () => setD(() =>
                                qty[it.id] = q - 1),
                        icon: const Icon(
                            Icons.remove_circle_outline),
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(
                        width: 28,
                        child: Text('$q',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setD(() => qty[it.id] = q + 1),
                        icon: const Icon(
                            Icons.add_circle_outline),
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: qty.values.any((v) => v > 0)
                  ? () => safePop(ctx, true)
                  : null,
              child: Text(t('common_add')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    for (final it in items) {
      final q = qty[it.id] ?? 0;
      if (q > 0) await _askSource(it, q.toDouble());
    }
  }

  void _bumpMaterial(int i, double delta) {
    setState(() {
      final m = _materials[i];
      final next = m.qty + delta;
      if (next <= 0) {
        _materials.removeAt(i);
      } else {
        _materials[i] = OrderMaterial(
          itemId: m.itemId,
          name: m.name,
          qty: next,
          source: m.source,
          unitCost: m.unitCost,
          unitPrice: m.unitPrice,
        );
      }
    });
  }

  // ---------------- Compras ----------------

  Future<String?> _captureReceipt() async {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (xfile == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/orders/receipts');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(xfile.path).copy(dest.path);
    return dest.path;
  }

  Future<void> _addPurchase() async {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? photoPath;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('complete_add_purchase')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: t('complete_purchase_desc'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'))
                  ],
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: t('complete_purchase_amount'),
                    prefixText: '\$ ',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(photoPath == null
                      ? t('complete_purchase_photo')
                      : t('complete_with_ticket')),
                  onPressed: () async {
                    final p = await _captureReceipt();
                    if (p != null) setD(() => photoPath = p);
                  },
                ),
                if (photoPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(photoPath!),
                          height: 100),
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
            FilledButton(
              onPressed: () => safePop(ctx, true),
              child: Text(t('common_add')),
            ),
          ],
        ),
      ),
    );
    final desc = descCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    descCtrl.dispose();
    amountCtrl.dispose();
    if (ok != true || desc.isEmpty || amount <= 0 || !mounted) {
      return;
    }
    setState(() {
      _purchases.add(OrderPurchase(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        description: desc,
        amount: amount,
        photoPath: photoPath,
      ));
    });
  }

  void _removePurchase(int i) {
    setState(() => _purchases.removeAt(i));
  }

  // ---------------- Enviar ----------------

  Future<void> _sendToReview() async {
    setState(() => _busy = true);
    final ok = await _orderService.completeInfo(
      widget.order.id,
      _materials,
      _purchases,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_no_stock', {'name': ''}))),
      );
      return;
    }
    safePop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(t('complete_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Resumen de la orden
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o.folio} · ${o.vehicle.brand} ${o.vehicle.model}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  '${o.lines.map((l) => o.displayLineName(l)).join(', ')} · ⏱ ${formatWorkTime(o.elapsedSeconds)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Materiales (colapsable)
          _sectionTitle(t('complete_materials'),
              count: _materials.isEmpty
                  ? null
                  : '${_materials.length}'),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _materialsOpen = !_materialsOpen),
            icon: Icon(_materialsOpen
                ? Icons.expand_less
                : Icons.expand_more),
            label: Text(_materialsOpen
                ? t('complete_hide_materials')
                : t('complete_add_materials')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(
                  color: AppTheme.accent, width: 1.5),
              padding:
                  const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (_materialsOpen) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _materials.length; i++)
              _materialRow(i),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _scanMaterial,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(t('inv_scan')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _addManual,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent),
                    child: Text('+ ${t('common_manual')}'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          // Compras para el trabajo
          _sectionTitle(t('complete_purchases'),
              count: _purchases.isEmpty
                  ? null
                  : '${_purchases.length}'),
          for (var i = 0; i < _purchases.length; i++)
            _purchaseRow(i),
          OutlinedButton.icon(
            onPressed: _addPurchase,
            icon: const Icon(Icons.add),
            label: Text(t('complete_add_purchase')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(
                  color: AppTheme.accent, width: 1.5),
              padding:
                  const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle(t('common_notes')),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style:
                const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: AppTheme.surface,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _sendToReview,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(t('complete_send_review'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {String? count}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(count,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            ],
          ],
        ),
      );

  Widget _materialRow(int i) {
    final m = _materials[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: m.fromShop
                        ? AppTheme.accent
                            .withValues(alpha: 0.15)
                        : Colors.purple
                            .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    m.fromShop
                        ? t('complete_from_shop')
                        : t('complete_from_client'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: m.fromShop
                          ? AppTheme.accent
                          : Colors.purple.shade200,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _bumpMaterial(i, -1),
            icon: const Icon(Icons.remove_circle_outline),
            color: AppTheme.textSecondary,
          ),
          Text('${m.qty.round()}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16)),
          IconButton(
            onPressed: () => _bumpMaterial(i, 1),
            icon: const Icon(Icons.add_circle_outline),
            color: AppTheme.accent,
          ),
        ],
      ),
    );
  }

  Widget _purchaseRow(int i) {
    final p = _purchases[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (p.photoPath != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(p.photoPath!),
                    width: 48, height: 48, fit: BoxFit.cover),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.receipt_outlined,
                  color: AppTheme.textSecondary),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.description,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700)),
                Text(
                  '${formatMoney(p.amount)} · ${p.photoPath != null ? t('complete_with_ticket') : t('complete_no_ticket')}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removePurchase(i),
            icon: const Icon(Icons.delete_outline),
            color: AppTheme.danger,
          ),
        ],
      ),
    );
  }
}
