import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ticket.dart';

/// Guarda y lee los tickets cobrados. Cada ticket guarda vehículo, cliente,
/// fotos de condición, niveles, servicios y datos del cobro.
class TicketService {
  static const _key = 'tickets';

  Future<List<Ticket>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map(
            (e) => Ticket.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Guarda el ticket y devuelve el folio asignado ("0001", "0002", ...).
  Future<String> save(Ticket ticket) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    final folio = (items.length + 1).toString().padLeft(4, '0');
    items.add(ticket.copyWith(id: folio));
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
    return folio;
  }

  /// Reemplaza un ticket existente (p. ej. al registrar un abono).
  Future<void> update(Ticket ticket) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    final i = items.indexWhere((t) => t.id == ticket.id);
    if (i != -1) {
      items[i] = ticket;
      await prefs.setString(
          _key, jsonEncode(items.map((e) => e.toJson()).toList()));
    }
  }
}
