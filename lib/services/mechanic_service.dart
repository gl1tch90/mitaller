import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mechanic.dart';

/// Guarda y lee la lista de mecánicos en el almacenamiento local del dispositivo.
class MechanicService {
  static const _key = 'mechanics';

  Future<List<Mechanic>> loadMechanics() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final mechanics = list
        .map((e) => Mechanic.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    // Migración: si ya había mecánicos pero ninguno es admin,
    // el primero pasa a ser el administrador (el jefe).
    if (mechanics.isNotEmpty && !mechanics.any((m) => m.isAdmin)) {
      mechanics[0] = mechanics[0].copyWith(isAdmin: true);
      await _saveMechanics(mechanics);
    }
    // Migración: si ya había mecánicos pero ninguno es fundador,
    // el primero (que ya es admin) pasa a ser el fundador.
    if (mechanics.isNotEmpty && !mechanics.any((m) => m.isFounder)) {
      mechanics[0] = mechanics[0].copyWith(isFounder: true, isAdmin: true);
      await _saveMechanics(mechanics);
    }
    return mechanics;
  }

  Future<void> _saveMechanics(List<Mechanic> mechanics) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(mechanics.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> addMechanic(String name, String pin,
      {List<String>? positions,
      bool isAdmin = false,
      bool isFounder = false,
      String language = '',
      String avatar = MechanicAvatars.def}) async {
    final mechanics = await loadMechanics();
    mechanics.add(Mechanic(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      pin: pin,
      avatar: MechanicAvatars.sanitize(avatar),
      positions: positions ?? const [MechanicPositions.def],
      isAdmin: isAdmin,
      isFounder: isFounder,
      language: language,
    ));
    await _saveMechanics(mechanics);
  }

  Future<void> updateMechanic(Mechanic updated) async {
    final mechanics = await loadMechanics();
    final i = mechanics.indexWhere((m) => m.id == updated.id);
    if (i != -1) {
      mechanics[i] = updated;
      await _saveMechanics(mechanics);
    }
  }

  Future<void> deleteMechanic(String id) async {
    final mechanics = await loadMechanics();
    mechanics.removeWhere((m) => m.id == id);
    await _saveMechanics(mechanics);
  }
}
