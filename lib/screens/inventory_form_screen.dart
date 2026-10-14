import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/inventory_item.dart';
import '../services/inventory_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../utils/money.dart';
import 'barcode_scanner_screen.dart';

/// Alta y edición de un producto del inventario.
/// El precio de venta se sugiere solo a partir del costo y el margen
/// configurado; se puede cambiar a mano.
class InventoryFormScreen extends StatefulWidget {
  final InventoryItem? item;

  const InventoryFormScreen({super.key, this.item});

  @override
  State<InventoryFormScreen> createState() =>
      _InventoryFormScreenState();
}

class _InventoryFormScreenState extends LocaleAwareState<InventoryFormScreen> {
  final _service = InventoryService();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _saleCtrl;
  double _margin = InventoryService.defaultMarginPct;
  bool _saleTouched = false; // el usuario cambió el precio a mano
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _nameCtrl = TextEditingController(text: it?.name ?? '');
    _barcodeCtrl = TextEditingController(text: it?.barcode ?? '');
    _qtyCtrl = TextEditingController(
        text: it == null ? '' : _num(it.quantity));
    _minCtrl = TextEditingController(
        text: it == null ? '' : _num(it.minStock));
    _costCtrl =
        TextEditingController(text: it == null ? '' : _num(it.cost));
    _saleCtrl = TextEditingController(
        text: it == null ? '' : _num(it.salePrice));
    _costCtrl.addListener(_onCostChanged);
    _loadMargin();
  }

  String _num(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  Future<void> _loadMargin() async {
    final m = await _service.marginPct();
    if (mounted) setState(() => _margin = m);
  }

  /// Al escribir el costo se sugiere el precio de venta (si el usuario
  /// no lo cambió a mano).
  void _onCostChanged() {
    if (_saleTouched) return;
    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0;
    final suggested = suggestSalePrice(cost, _margin);
    _saleCtrl.text = cost > 0 ? _num(suggested) : '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _qtyCtrl.dispose();
    _minCtrl.dispose();
    _costCtrl.dispose();
    _saleCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(),
      ),
    );
    if (code != null && mounted) {
      setState(() => _barcodeCtrl.text = code);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0;
    final sale = double.tryParse(_saleCtrl.text.trim()) ?? 0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_name_required'))),
      );
      return;
    }
    if (cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_cost_required'))),
      );
      return;
    }
    setState(() => _busy = true);
    final barcode = _barcodeCtrl.text.trim();
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final min = double.tryParse(_minCtrl.text.trim()) ?? 0;
    final existing = widget.item;
    if (existing == null) {
      await _service.add(InventoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        barcode: barcode.isEmpty ? null : barcode,
        quantity: qty,
        minStock: min,
        cost: cost,
        salePrice: sale,
        createdAt: DateTime.now(),
      ));
    } else {
      await _service.update(existing.copyWith(
        name: name,
        barcode: barcode.isEmpty ? null : barcode,
        clearBarcode: barcode.isEmpty,
        quantity: qty,
        minStock: min,
        cost: cost,
        salePrice: sale,
      ));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('inv_saved'))),
      );
      safePop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0;
    final suggested = suggestSalePrice(cost, _margin);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.item == null
            ? t('inv_add')
            : widget.item!.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label(t('inv_name_label')),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: _dec(),
          ),
          const SizedBox(height: 14),
          _label(t('inv_barcode_label')),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary),
                  decoration:
                      _dec(hint: t('inv_barcode_hint')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _scanBarcode,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _label(t('inv_qty_label')),
                    TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      style: const TextStyle(
                          color: AppTheme.textPrimary),
                      decoration: _dec(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _label(t('inv_min_label')),
                    TextField(
                      controller: _minCtrl,
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      style: const TextStyle(
                          color: AppTheme.textPrimary),
                      decoration: _dec(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label(t('inv_cost_label')),
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'))
            ],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: _dec(prefix: '\$ '),
          ),
          const SizedBox(height: 14),
          _label(t('inv_sale_label')),
          TextField(
            controller: _saleCtrl,
            onChanged: (_) => _saleTouched = true,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'))
            ],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: _dec(prefix: '\$ '),
          ),
          if (cost > 0 && !_saleTouched) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color:
                        Colors.green.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    '✨ ${t('inv_sale_suggested')}: ${formatMoney(suggested)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('inv_sale_hint', {
                      'cost': formatMoney(cost),
                      'pct': _margin.toStringAsFixed(0),
                    }),
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      );

  InputDecoration _dec({String? hint, String? prefix}) =>
      InputDecoration(
        hintText: hint,
        prefixText: prefix,
        hintStyle:
            const TextStyle(color: AppTheme.textSecondary),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: AppTheme.surface,
      );
}
