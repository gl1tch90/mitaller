import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/shop_vehicle.dart';
import '../theme/app_theme.dart';
import '../utils/photo_picker.dart';

/// Alta/edición de un vehículo del taller.
class ShopVehicleFormScreen extends StatefulWidget {
  final ShopVehicle? existing;

  const ShopVehicleFormScreen({super.key, this.existing});

  @override
  State<ShopVehicleFormScreen> createState() =>
      _ShopVehicleFormScreenState();
}

class _ShopVehicleFormScreenState
    extends LocaleAwareState<ShopVehicleFormScreen> {
  final _nameCtrl = TextEditingController();
  final _platesCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  String _kind = 'carro';
  int? _year;
  String? _photoPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _platesCtrl.text = e.plates;
      _vinCtrl.text = e.vin ?? '';
      _modelCtrl.text = e.model ?? '';
      _year = e.year;
      _kmCtrl.text = '${e.currentKm}';
      _kind = e.kind;
      _photoPath = e.photoPath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _platesCtrl.dispose();
    _vinCtrl.dispose();
    _modelCtrl.dispose();
    _kmCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final xfile = await pickPhotoChoice(context);
    if (xfile == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/shop_vehicles');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(xfile.path).copy(dest.path);
    setState(() => _photoPath = dest.path);
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final km = int.tryParse(_kmCtrl.text.trim());
    if (name.isEmpty) {
      setState(() => _error = t('shop_vehicle_name_required'));
      return;
    }
    if (km == null || km < 0) {
      setState(() => _error = t('shop_vehicle_km_invalid'));
      return;
    }
    final e = widget.existing;
    final v = ShopVehicle(
      id: e?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      kind: _kind,
      plates: _platesCtrl.text.trim(),
      vin: _vinCtrl.text.trim().toUpperCase().isEmpty
          ? null
          : _vinCtrl.text.trim().toUpperCase(),
      year: _year,
      model: _modelCtrl.text.trim().isEmpty
          ? null
          : _modelCtrl.text.trim(),
      photoPath: _photoPath,
      currentKm: km,
      oilChangeKm: e?.oilChangeKm,
      oilChangeDate: e?.oilChangeDate,
      createdAt: e?.createdAt ?? DateTime.now(),
    );
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(widget.existing == null
            ? t('shop_vehicles_add')
            : t('shop_vehicle_edit')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Foto
            GestureDetector(
              onTap: _takePhoto,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppTheme.surfaceLight),
                ),
                child: _photoPath != null &&
                        File(_photoPath!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_photoPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo,
                              size: 40,
                              color: AppTheme.textSecondary),
                          const SizedBox(height: 8),
                          Text(
                            t('shop_vehicle_photo_optional'),
                            style: const TextStyle(
                                color:
                                    AppTheme.textSecondary),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              style:
                  const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: t('shop_vehicle_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Text(t('shop_vehicles_carro')),
                    selected: _kind == 'carro',
                    selectedColor: AppTheme.accent,
                    onSelected: (_) =>
                        setState(() => _kind = 'carro'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Text(t('shop_vehicles_moto')),
                    selected: _kind == 'moto',
                    selectedColor: AppTheme.accent,
                    onSelected: (_) =>
                        setState(() => _kind = 'moto'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(
                        color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: t('shop_vehicle_year'),
                      border:
                          const OutlineInputBorder(),
                    ),
                    items: [
                      for (var y = DateTime.now().year + 1;
                          y >= 1980;
                          y--)
                        DropdownMenuItem(
                          value: y,
                          child: Text('$y'),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _year = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _modelCtrl,
                    textCapitalization:
                        TextCapitalization.words,
                    style: const TextStyle(
                        color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText:
                          t('shop_vehicle_model'),
                      border:
                          const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _platesCtrl,
              maxLength: 10,
              style:
                  const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: t('shop_vehicle_plates'),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
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
                labelText: t('shop_vehicle_vin'),
                hintText: t('vehicle_data_vin_hint'),
                border: const OutlineInputBorder(),
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
            const SizedBox(height: 12),
            TextField(
              controller: _kmCtrl,
              keyboardType: TextInputType.number,
              style:
                  const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: t('shop_vehicle_km'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );
  }
}
