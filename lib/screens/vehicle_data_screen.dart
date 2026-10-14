import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/customer.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../services/photo_service.dart';
import '../services/vehicle_catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';

/// Paso 1 del punto de venta: captura datos del vehículo, fotos de
/// condición (opcional) y datos del cliente.
///
/// El título se adapta a la sección: "Datos del vehículo" (carros)
/// o "Datos de la moto" (motos).
class VehicleDataScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final void Function(
      Vehicle vehicle, Customer customer, Map<String, String> photos)
      onContinue;

  const VehicleDataScreen({
    super.key,
    required this.vehicleType,
    required this.onContinue,
  });

  @override
  State<VehicleDataScreen> createState() => _VehicleDataScreenState();
}

class _VehicleDataScreenState extends LocaleAwareState<VehicleDataScreen> {
  static const _addNew = '__add_new__';

  final _catalog = VehicleCatalogService();
  final _photos = PhotoService();
  final _plateCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  /// Identificador del ticket en curso; también nombra la carpeta de fotos.
  late final String _ticketId =
      DateTime.now().millisecondsSinceEpoch.toString();

  /// slot ('front', 'rear', 'left', 'right') -> ruta local de la foto.
  final Map<String, String> _photoPaths = {};
  bool _takingPhoto = false;

  /// Aceite y anticongelante: malo/regular/bien (null = sin registrar).
  /// Gasolina: 0-100 en el tablero de aguja (null = sin registrar).
  ConditionLevel? _oilCondition;
  int? _fuelLevel;

  ConditionLevel? _coolantCondition;

  bool _loading = true;
  int? _year;
  String? _brand;
  String? _model;

  late final List<int> _years = List.generate(
    DateTime.now().year - 1990 + 1,
    (i) => DateTime.now().year - i,
  );

  @override
  void initState() {
    super.initState();
    _catalog.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _vinCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _askNew({
    required String title,
    required String hint,
    required Future<void> Function(String value) onSave,
  }) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            onPressed: () => safePop(ctx, ctrl.text.trim()),
            child: Text(t('common_add')),
          ),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      await onSave(value);
    }
  }

  void _onBrandChanged(String? value) async {
    if (value == _addNew) {
      await _askNew(
        title: t('vehicle_data_new_brand'),
        hint: t('vehicle_data_new_brand_hint'),
        onSave: (v) async {
          await _catalog.addBrand(widget.vehicleType, v);
          setState(() {
            _brand = v;
            _model = null;
          });
        },
      );
      return;
    }
    setState(() {
      _brand = value;
      _model = null;
    });
  }

  void _onModelChanged(String? value) async {
    if (value == _addNew) {
      await _askNew(
        title: t('vehicle_data_new_model'),
        hint: t('vehicle_data_new_model_hint'),
        onSave: (v) async {
          await _catalog.addModel(widget.vehicleType, _brand!, v);
          setState(() => _model = v);
        },
      );
      return;
    }
    setState(() => _model = value);
  }

  void _continue() {
    final plate = _plateCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (_year == null ||
        _brand == null ||
        _model == null ||
        plate.length < 3 ||
        name.isEmpty ||
        phoneDigits.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('vehicle_data_incomplete_data_snackbar')),
        ),
      );
      return;
    }
    if (PhotoService.slots.any((s) => !_photoPaths.containsKey(s))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('vehicle_data_photos_required_snackbar')),
        ),
      );
      return;
    }
    if (_oilCondition == null ||
        _fuelLevel == null ||
        _coolantCondition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('vehicle_data_levels_required_snackbar')),
        ),
      );
      return;
    }
    widget.onContinue(
      Vehicle(
        id: _ticketId,
        type: widget.vehicleType,
        year: _year!,
        brand: _brand!,
        model: _model!,
        plate: plate,
        vin: _vinCtrl.text.trim().toUpperCase().isEmpty
            ? null
            : _vinCtrl.text.trim().toUpperCase(),
        conditionNotes: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        oilCondition: _oilCondition,
        fuelLevel: _fuelLevel,
        coolantCondition: _coolantCondition,
      ),
      Customer(name: name, phone: phone),
      Map<String, String>.from(_photoPaths),
    );
  }

  Future<void> _takePhoto(String slot) async {
    setState(() => _takingPhoto = true);
    try {
      final path = await _photos.capture(_ticketId, slot);
      if (path != null && mounted) {
        setState(() => _photoPaths[slot] = path);
      }
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Future<void> _removePhoto(String slot) async {
    final path = _photoPaths[slot];
    if (path != null) await _photos.remove(path);
    setState(() => _photoPaths.remove(slot));
  }

  @override
  Widget build(BuildContext context) {
    // Sin Scaffold ni AppBar propios: esta pantalla vive dentro de la
    // pestaña "Vender" del Punto de venta, que ya trae los suyos.
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _fieldLabel(t('vehicle_data_year')),
                DropdownButtonFormField<int>(
                  value: _year,
                  hint: Text(t('vehicle_data_year_hint')),
                  items: _years
                      .map((y) => DropdownMenuItem(
                            value: y,
                            child: Text('$y'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _year = v),
                ),
                const SizedBox(height: 18),
                _fieldLabel(t('vehicle_data_brand')),
                DropdownButtonFormField<String>(
                  value: _brand,
                  hint: Text(t('vehicle_data_brand_hint')),
                  items: [
                    ..._catalog.brands(widget.vehicleType).map(
                          (b) => DropdownMenuItem(
                            value: b,
                            child: Text(b),
                          ),
                        ),
                    DropdownMenuItem(
                      value: _addNew,
                      child: Text(
                        t('vehicle_data_new_brand_item'),
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  onChanged: _onBrandChanged,
                ),
                const SizedBox(height: 18),
                _fieldLabel(t('vehicle_data_model')),
                DropdownButtonFormField<String>(
                  value: _model,
                  hint: Text(_brand == null
                      ? t('vehicle_data_model_hint_first_brand')
                      : t('vehicle_data_model_hint')),
                  items: _brand == null
                      ? []
                      : [
                          ..._catalog
                              .models(widget.vehicleType, _brand!)
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m),
                                ),
                              ),
                          DropdownMenuItem(
                            value: _addNew,
                            child: Text(
                              t('vehicle_data_new_model_item'),
                              style: TextStyle(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                  onChanged: _brand == null ? null : _onModelChanged,
                ),
                const SizedBox(height: 18),
                _fieldLabel(t('vehicle_data_plate')),
                TextField(
                  controller: _plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 10,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: t('vehicle_data_plate_hint'),
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary),
                    counterText: '',
                  ),
                  onChanged: (v) {
                    final upper = v.toUpperCase();
                    if (v != upper) {
                      _plateCtrl.value = _plateCtrl.value.copyWith(
                        text: upper,
                        selection: TextSelection.collapsed(
                            offset: upper.length),
                      );
                    }
                  },
                ),
                const SizedBox(height: 18),
                _fieldLabel(t('vehicle_data_vin')),
                TextField(
                  controller: _vinCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 17,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: t('vehicle_data_vin_hint'),
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary),
                    counterText: '',
                  ),
                  onChanged: (v) {
                    final upper = v.toUpperCase();
                    if (v != upper) {
                      _vinCtrl.value = _vinCtrl.value.copyWith(
                        text: upper,
                        selection: TextSelection.collapsed(
                            offset: upper.length),
                      );
                    }
                  },
                ),
                const SizedBox(height: 32),
                _sectionHeader(t('vehicle_data_photos_title')),
                const SizedBox(height: 6),
                Text(
                  t('vehicle_data_photos_subtitle'),
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 4 / 3,
                  children: PhotoService.slots
                      .map((slot) => _photoSlot(slot))
                      .toList(),
                ),
                const SizedBox(height: 18),
                _fieldLabel(t('vehicle_data_notes_label')),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: t('vehicle_data_notes_hint'),
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 18),
                _sectionHeader(t('vehicle_data_levels_title')),
                const SizedBox(height: 14),
                _conditionButtons(
                  title: t('vehicle_data_oil'),
                  icon: Icons.oil_barrel,
                  value: _oilCondition,
                  onChanged: (v) =>
                      setState(() => _oilCondition = v),
                ),
                const SizedBox(height: 18),
                _conditionButtons(
                  title: t('vehicle_data_coolant'),
                  icon: Icons.water_drop,
                  value: _coolantCondition,
                  onChanged: (v) =>
                      setState(() => _coolantCondition = v),
                ),
                const SizedBox(height: 18),
                _fuelNeedleGauge(),
                const SizedBox(height: 32),
                _sectionHeader(t('vehicle_data_client_title')),
                const SizedBox(height: 14),
                _fieldLabel(t('vehicle_data_name_label')),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 60,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: t('vehicle_data_name_hint'),
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 18),
                _fieldLabel(t('vehicle_data_phone_label')),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: t('vehicle_data_phone_hint'),
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _continue,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 17),
                  ),
                  child: Text(t('common_continue')),
                ),
              ],
            );
  }

  /// Selector de condición: tres botones (Malo rojo, Regular naranja,
  /// Bien verde). Tocar el botón activo lo desmarca ("Sin registrar").
  Widget _conditionButtons({
    required String title,
    required IconData icon,
    required ConditionLevel? value,
    required ValueChanged<ConditionLevel?> onChanged,
  }) {
    const colors = {
      ConditionLevel.malo: Colors.red,
      ConditionLevel.regular: Colors.orange,
      ConditionLevel.bien: Colors.green,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
            const Spacer(),
            if (value == null)
              Text(
                t('vehicle_data_not_registered'),
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            if (value != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.close,
                      size: 18, color: AppTheme.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: ConditionLevel.values.map((c) {
            final color = colors[c]!;
            final selected = value == c;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: c == ConditionLevel.values.last ? 0 : 8),
                child: GestureDetector(
                  onTap: () => onChanged(selected ? null : c),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? color
                          : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? color
                            : color.withValues(alpha: 0.55),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _conditionLabel(c),
                        style: TextStyle(
                          color: selected ? Colors.white : color,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Etiqueta visible de cada nivel de condición.
  String _conditionLabel(ConditionLevel c) {
    switch (c) {
      case ConditionLevel.malo:
        return t('vehicle_data_malo');
      case ConditionLevel.regular:
        return t('vehicle_data_regular');
      case ConditionLevel.bien:
        return t('vehicle_data_bien');
    }
  }

  String _fuelQualifier(int v) {
    if (v == 0) return t('vehicle_data_fuel_empty');
    if (v <= 25) return '1/4';
    if (v <= 50) return '1/2';
    if (v <= 75) return '3/4';
    return t('vehicle_data_fuel_full');
  }

  /// Medidor de gasolina estilo tablero: aguja que se arrastra con el dedo.
  Widget _fuelNeedleGauge() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_gas_station,
                size: 20, color: AppTheme.accent),
            const SizedBox(width: 8),
            Text(
              t('vehicle_data_fuel'),
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
            const Spacer(),
            if (_fuelLevel != null)
              Text(
                _fuelQualifier(_fuelLevel!),
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              )
            else
              Text(
                t('vehicle_data_not_registered'),
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            if (_fuelLevel != null)
              GestureDetector(
                onTap: () => setState(() => _fuelLevel = null),
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.close,
                      size: 18, color: AppTheme.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final size = Size(constraints.maxWidth, 170);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Toque: pone la aguja donde cae el dedo (por ángulo).
              onTapDown: (d) =>
                  _setFuelFromOffset(d.localPosition, size),
              // Arrastre horizontal: no compite con el scroll vertical
              // de la pantalla, así la aguja siempre responde.
              onHorizontalDragUpdate: (d) =>
                  _setFuelFromX(d.localPosition.dx, size),
              child: CustomPaint(
                size: size,
                painter: _FuelDialPainter(
                  value: _fuelLevel,
                  hint: t('vehicle_data_fuel_tap_hint'),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Convierte el punto tocado/arrastrado en nivel 0-100 según el ángulo
  /// desde el pivote de la aguja.
  void _setFuelFromOffset(Offset local, Size size) {
    final pivot = Offset(size.width / 2, size.height - 18);
    var a = atan2(local.dy - pivot.dy, local.dx - pivot.dx);
    if (a < 0) a += 2 * pi;
    if (a < pi) a = a < pi / 2 ? 2 * pi : pi;
    setState(
        () => _fuelLevel = ((a - pi) / pi * 100).round().clamp(0, 100));
  }

  /// Convierte la posición horizontal del dedo en nivel 0-100 a lo
  /// ancho del dial (para el arrastre sin pelear con el scroll).
  void _setFuelFromX(double x, Size size) {
    final pivot = Offset(size.width / 2, size.height - 18);
    final r = min(size.width / 2 - 30, size.height - 44);
    final v = ((x - (pivot.dx - r)) / (2 * r) * 100).round();
    setState(() => _fuelLevel = v.clamp(0, 100));
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 17,
      ),
    );
  }

  /// Recuadro de foto por ángulo: toca para tomar/retomar, ✕ para quitar.
  Widget _photoSlot(String slot) {
    final path = _photoPaths[slot];
    // Etiquetas localizadas de cada ángulo; los valores de
    // PhotoService.slotLabels están en español fijo (archivo ajeno).
    final label = {
      'front': t('vehicle_data_slot_front'),
      'rear': t('vehicle_data_slot_rear'),
      'left': t('vehicle_data_slot_left'),
      'right': t('vehicle_data_slot_right'),
    }[slot]!;
    return GestureDetector(
      onTap: _takingPhoto ? null : () => _takePhoto(slot),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: path == null ? AppTheme.textSecondary : AppTheme.accent,
            width: path == null ? 1 : 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: path == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_takingPhoto)
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    else
                      const Icon(Icons.photo_camera_outlined,
                          size: 34, color: AppTheme.textSecondary),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(path), fit: BoxFit.cover),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 5),
                        color: Colors.black54,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removePhoto(slot),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(5),
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Dibuja el tablero de gasolina: arco, marcas E–F, aguja y pivote.
class _FuelDialPainter extends CustomPainter {
  final int? value;
  final String hint;

  const _FuelDialPainter({this.value, required this.hint});

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height - 18);
    final r = min(size.width / 2 - 30, size.height - 44);
    final rect = Rect.fromCircle(center: pivot, radius: r);

    final trackPaint = Paint()
      ..color = AppTheme.textSecondary.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, pi, pi, false, trackPaint);

    // Marcas del arco.
    final tickPaint = Paint()
      ..color = AppTheme.textSecondary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final t in [0, 25, 50, 75, 100]) {
      final a = pi + pi * t / 100;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(
          pivot + dir * (r - 12), pivot + dir * (r + 12), tickPaint);
    }

    // Etiquetas E, 1/2, F.
    for (final entry in {0: 'E', 50: '1/2', 100: 'F'}.entries) {
      final a = pi + pi * entry.key / 100;
      final p = pivot + Offset(cos(a), sin(a)) * (r + 24);
      final tp = TextPainter(
        text: TextSpan(
          text: entry.value,
          style:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    if (value == null) {
      final tp = TextPainter(
        text: TextSpan(
          text: hint,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(pivot.dx - tp.width / 2,
            pivot.dy - r / 2 - tp.height / 2),
      );
      return;
    }

    // Arco de llenado.
    if (value! > 0) {
      final fillPaint = Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, pi, pi * value! / 100, false, fillPaint);
    }

    // Aguja.
    final a = pi + pi * value! / 100;
    final tip = pivot + Offset(cos(a), sin(a)) * (r - 18);
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 9, Paint()..color = AppTheme.accent);
  }

  @override
  bool shouldRepaint(covariant _FuelDialPainter old) =>
      old.value != value || old.hint != hint;
}
