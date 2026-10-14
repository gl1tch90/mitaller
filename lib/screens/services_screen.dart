import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/customer.dart';
import '../models/mechanic.dart';
import '../models/service_item.dart';
import '../models/quick_service.dart';
import '../models/work_order.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../services/service_catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../utils/money.dart';
import 'ticket_summary_screen.dart';

/// Paso 2 del punto de venta: catálogo de servicios y ticket.
/// Cada servicio se marca una sola vez por visita (palomita para
/// seleccionar/quitar). Solo el administrador ve los costos; los demás
/// solo eligen servicios. Al guardar se pasa a [TicketSummaryScreen].
class ServicesScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;
  final Vehicle vehicle;
  final Customer customer;
  final Map<String, String> photos;

  const ServicesScreen({
    super.key,
    required this.vehicleType,
    required this.mechanic,
    required this.vehicle,
    required this.customer,
    required this.photos,
  });

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends LocaleAwareState<ServicesScreen> {
  final _catalogService = ServiceCatalogService();
  List<ServiceItem> _catalog = [];
  bool _loading = true;
  final Map<String, ServiceItem> _lines = {};

  /// Servicio rápido: se describe con texto y su precio lo pone el
  /// administrador al revisar la orden.
  bool _quickSelected = false;
  final _quickNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final items = await _catalogService.load();
    if (!mounted) return;
    setState(() {
      _catalog =
          items.where((e) => e.appliesTo(widget.vehicleType)).toList();
      _loading = false;
    });
  }

  double get _total =>
      _lines.values.fold(0, (s, e) => s + e.price);

  /// Solo el administrador (jefe) puede ver los costos.
  bool get _isAdmin => widget.mechanic.isAdmin;

  int get _serviceCount => _lines.length + (_quickSelected ? 1 : 0);

  bool get _canContinue {
    if (_serviceCount == 0) return false;
    if (_quickSelected && _quickNoteCtrl.text.trim().isEmpty) return false;
    return true;
  }

  /// Palomita: tocar un servicio lo marca, tocarlo de nuevo lo quita.
  void _toggleItem(ServiceItem item) {
    setState(() {
      if (_lines.containsKey(item.id)) {
        _lines.remove(item.id);
      } else {
        _lines[item.id] = item;
      }
    });
  }

  Future<void> _newServiceDialog() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('services_new_service'),
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: t('services_name_label'),
                labelStyle:
                    const TextStyle(color: AppTheme.textSecondary),
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
                labelText: t('services_price_label'),
                labelStyle:
                    const TextStyle(color: AppTheme.textSecondary),
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
                      content: Text(
                          t('services_invalid_snackbar'))),
                );
                return;
              }
              safePop(ctx, true);
            },
            child: Text(t('common_add')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final item = ServiceItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: nameCtrl.text.trim(),
      price: double.parse(priceCtrl.text.trim()),
      types: {widget.vehicleType},
    );
    await _catalogService.add(item);
    if (!mounted) return;
    setState(() => _catalog.add(item));
    _toggleItem(item);
  }

  /// Palomita del servicio rápido.
  void _toggleQuick() {
    setState(() => _quickSelected = !_quickSelected);
  }

  void _goToSummary() {
    if (!_canContinue) return;
    final lines = _lines.values
        .map((e) => OrderLine(
              serviceId: e.id,
              name: e.name,
              price: e.price,
            ))
        .toList();
    if (_quickSelected) {
      lines.add(OrderLine(
        serviceId: quickServiceId,
        // Valor guardado: siempre en español (los registros históricos
        // usan 'Servicio rápido'; solo la vista se traduce).
        name: 'Servicio rápido',
        note: _quickNoteCtrl.text.trim(),
      ));
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TicketSummaryScreen(
          vehicleType: widget.vehicleType,
          mechanic: widget.mechanic,
          vehicle: widget.vehicle,
          customer: widget.customer,
          photos: widget.photos,
          lines: lines,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('services_title')),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoCard(),
                const SizedBox(height: 20),
                _header(t('services_catalog')),
                const SizedBox(height: 8),
                _quickServiceRow(),
                ..._catalog.map(_catalogRow),
                if (_isAdmin) _newServiceTile(),
                const SizedBox(height: 20),
                _header(t('services_order')),
                const SizedBox(height: 8),
                if (_serviceCount == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      t('services_empty_order_hint'),
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                else ...[
                  if (_quickSelected) _quickTicketRow(),
                  ..._lines.entries.map((e) => _ticketRow(e.key, e.value)),
                ],
                const SizedBox(height: 90),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(
                top: BorderSide(color: AppTheme.border, width: 1)),
          ),
          child: Row(
            children: [
              if (_isAdmin)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('services_total'),
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13)),
                    Text(
                      formatMoney(_total),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 24),
                    ),
                  ],
                )
              else
                Text(
                  t('services_service_count', {
                    'n': '$_serviceCount',
                    's': _serviceCount == 1 ? '' : 's',
                  }),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _canContinue ? _goToSummary : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(t('common_continue'),
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String text) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17),
      );

  Widget _infoCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.vehicleType.icon,
                    color: AppTheme.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.vehicle.label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('services_info_subtitle', {
                'customer': widget.customer.label,
                'photos': '${widget.photos.length}',
              }),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    _quickNoteCtrl.dispose();
    super.dispose();
  }

  /// Fila especial del "Servicio rápido": al marcarla aparece un cuadro
  /// de texto para describir qué se hizo. El precio lo pone el admin
  /// al revisar la orden.
  Widget _quickServiceRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _quickSelected
            ? AppTheme.accent.withValues(alpha: 0.08)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _quickSelected ? AppTheme.accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: _toggleQuick,
            title: Text(t('services_quick_service'),
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(
              t('services_quick_subtitle'),
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _quickSelected
                    ? AppTheme.accent
                    : Colors.transparent,
                border: Border.all(
                  color: _quickSelected
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                  width: 2,
                ),
              ),
              child: _quickSelected
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 20)
                  : null,
            ),
          ),
          if (_quickSelected)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: TextField(
                controller: _quickNoteCtrl,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                style:
                    const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: t('services_what_was_done_label'),
                  hintText: t('services_what_was_done_hint'),
                  labelStyle:
                      const TextStyle(color: AppTheme.textSecondary),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Renglón del servicio rápido dentro de la orden.
  Widget _quickTicketRow() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accent, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('services_quick_service'),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  Text(
                    _quickNoteCtrl.text.trim().isEmpty
                        ? t('services_no_description')
                        : _quickNoteCtrl.text.trim(),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  if (_isAdmin)
                    Text(t('services_price_at_review'),
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              onPressed: () => setState(() {
                _quickSelected = false;
                _quickNoteCtrl.clear();
              }),
            ),
          ],
        ),
      );

  Widget _catalogRow(ServiceItem item) {
    final selected = _lines.containsKey(item.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.accent.withValues(alpha: 0.08)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppTheme.accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        onTap: () => _toggleItem(item),
        title: Text(item.displayName,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600)),
        subtitle: _isAdmin
            ? Text(formatMoney(item.price),
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700))
            : null,
        trailing: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppTheme.accent : Colors.transparent,
            border: Border.all(
              color: selected
                  ? AppTheme.accent
                  : AppTheme.textSecondary,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }

  Widget _newServiceTile() => InkWell(
        onTap: _newServiceDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.textSecondary, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(t('services_new_service'),
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _ticketRow(String id, ServiceItem e) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accent, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.displayName,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  if (_isAdmin)
                    Text(formatMoney(e.price),
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              onPressed: () => setState(() => _lines.remove(id)),
            ),
          ],
        ),
      );
}
