import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shop_vehicle.dart';

/// Vehículos propios del taller: bitácora diaria, daños, aceite,
/// documentos con vencimiento y gastos. Todo en el dispositivo.
class ShopVehicleService {
  static const _vehiclesKey = 'shop_vehicles';
  static const _logKey = 'shop_vehicle_log';
  static const _issuesKey = 'shop_vehicle_issues';
  static const _docsKey = 'shop_vehicle_docs';
  static const _expensesKey = 'shop_vehicle_expenses';

  /// Cada cuántos km se cambia el aceite.
  static const int oilEveryKm = 5000;

  /// Días antes del vencimiento para avisar en ámbar.
  static const int docWarnDays = 30;

  // ---------------- Vehículos ----------------

  Future<List<ShopVehicle>> loadVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_vehiclesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            ShopVehicle.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _saveVehicles(
      SharedPreferences prefs, List<ShopVehicle> items) async {
    await prefs.setString(
        _vehiclesKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> addVehicle(ShopVehicle v) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadVehicles();
    items.add(v);
    await _saveVehicles(prefs, items);
  }

  Future<void> updateVehicle(ShopVehicle v) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadVehicles();
    final i = items.indexWhere((e) => e.id == v.id);
    if (i == -1) return;
    items[i] = v;
    await _saveVehicles(prefs, items);
  }

  Future<void> removeVehicle(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadVehicles();
    items.removeWhere((e) => e.id == id);
    await _saveVehicles(prefs, items);
    // Limpia sus datos asociados.
    final log = await loadLogEntries();
    log.removeWhere((e) => e.vehicleId == id);
    await _saveLog(prefs, log);
    final issues = await loadIssues();
    issues.removeWhere((e) => e.vehicleId == id);
    await _saveIssues(prefs, issues);
    final docs = await loadDocuments();
    docs.removeWhere((e) => e.vehicleId == id);
    await _saveDocs(prefs, docs);
    final expenses = await loadExpenses();
    expenses.removeWhere((e) => e.vehicleId == id);
    await _saveExpenses(prefs, expenses);
  }

  // ---------------- Bitácora diaria ----------------

  Future<List<VehicleLogEntry>> loadLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_logKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            VehicleLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _saveLog(
      SharedPreferences prefs, List<VehicleLogEntry> items) async {
    await prefs.setString(
        _logKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// Entrada de hoy para un vehículo, o null si aún no se llena.
  Future<VehicleLogEntry?> todayEntry(String vehicleId) async {
    final key = VehicleLogEntry.dayKey(DateTime.now());
    final items = await loadLogEntries();
    for (final e in items) {
      if (e.vehicleId == vehicleId &&
          VehicleLogEntry.dayKey(e.date) == key) {
        return e;
      }
    }
    return null;
  }

  /// Guarda la entrada del día (una por vehículo por día).
  Future<void> saveTodayEntry(VehicleLogEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadLogEntries();
    final key = VehicleLogEntry.dayKey(entry.date);
    items.removeWhere((e) =>
        e.vehicleId == entry.vehicleId &&
        VehicleLogEntry.dayKey(e.date) == key);
    items.add(entry);
    await _saveLog(prefs, items);
    // Actualiza el km actual del vehículo.
    final vehicles = await loadVehicles();
    final i = vehicles.indexWhere((e) => e.id == entry.vehicleId);
    if (i != -1) {
      final v = vehicles[i];
      await updateVehicle(ShopVehicle(
        id: v.id,
        name: v.name,
        kind: v.kind,
        plates: v.plates,
        photoPath: v.photoPath,
        currentKm: entry.km,
        oilChangeKm: v.oilChangeKm,
        oilChangeDate: v.oilChangeDate,
        createdAt: v.createdAt,
      ));
    }
  }

  Future<List<VehicleLogEntry>> logFor(String vehicleId) async {
    final items = await loadLogEntries();
    final mine =
        items.where((e) => e.vehicleId == vehicleId).toList();
    mine.sort((a, b) => b.date.compareTo(a.date));
    return mine;
  }

  // ---------------- Daños ----------------

  Future<List<VehicleIssue>> loadIssues() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_issuesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            VehicleIssue.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _saveIssues(
      SharedPreferences prefs, List<VehicleIssue> items) async {
    await prefs.setString(
        _issuesKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> addIssue(VehicleIssue issue) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadIssues();
    items.add(issue);
    await _saveIssues(prefs, items);
  }

  Future<void> resolveIssue(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadIssues();
    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final old = items[i];
    items[i] = VehicleIssue(
      id: old.id,
      vehicleId: old.vehicleId,
      reportedById: old.reportedById,
      reportedByName: old.reportedByName,
      date: old.date,
      description: old.description,
      photoPath: old.photoPath,
      notes: old.notes,
      resolved: true,
      resolvedAt: DateTime.now(),
    );
    await _saveIssues(prefs, items);
  }

  Future<List<VehicleIssue>> issuesFor(String vehicleId,
      {bool? resolved}) async {
    final items = await loadIssues();
    final mine =
        items.where((e) => e.vehicleId == vehicleId).toList();
    final filtered = resolved == null
        ? mine
        : mine.where((e) => e.resolved == resolved).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  /// Cuántos daños sin resolver hay en total (para aviso del admin).
  Future<int> openIssueCount() async {
    final items = await loadIssues();
    return items.where((e) => !e.resolved).length;
  }

  // ---------------- Documentos ----------------

  Future<List<VehicleDocument>> loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_docsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            VehicleDocument.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _saveDocs(
      SharedPreferences prefs, List<VehicleDocument> items) async {
    await prefs.setString(
        _docsKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> addDocument(VehicleDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadDocuments();
    // Un documento por tipo por vehículo: reemplaza si ya existe.
    items.removeWhere((e) =>
        e.vehicleId == doc.vehicleId && e.kind == doc.kind);
    items.add(doc);
    await _saveDocs(prefs, items);
  }

  Future<void> removeDocument(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadDocuments();
    items.removeWhere((e) => e.id == id);
    await _saveDocs(prefs, items);
  }

  Future<List<VehicleDocument>> docsFor(String vehicleId) async {
    final items = await loadDocuments();
    final mine =
        items.where((e) => e.vehicleId == vehicleId).toList();
    mine.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return mine;
  }

  // ---------------- Gastos ----------------

  Future<List<VehicleExpense>> loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_expensesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            VehicleExpense.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _saveExpenses(
      SharedPreferences prefs, List<VehicleExpense> items) async {
    await prefs.setString(
        _expensesKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> addExpense(VehicleExpense expense) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadExpenses();
    items.add(expense);
    await _saveExpenses(prefs, items);
  }

  Future<void> removeExpense(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadExpenses();
    items.removeWhere((e) => e.id == id);
    await _saveExpenses(prefs, items);
  }

  Future<void> updateExpense(VehicleExpense expense) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadExpenses();
    final i = items.indexWhere((e) => e.id == expense.id);
    if (i == -1) return;
    items[i] = expense;
    await _saveExpenses(prefs, items);
  }

  Future<List<VehicleExpense>> expensesFor(String vehicleId) async {
    final items = await loadExpenses();
    final mine =
        items.where((e) => e.vehicleId == vehicleId).toList();
    mine.sort((a, b) => b.date.compareTo(a.date));
    return mine;
  }

  // ---------------- Aceite ----------------

  Future<void> logOilChange(
      String vehicleId, int km, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadVehicles();
    final i = items.indexWhere((e) => e.id == vehicleId);
    if (i == -1) return;
    final v = items[i];
    items[i] = ShopVehicle(
      id: v.id,
      name: v.name,
      kind: v.kind,
      plates: v.plates,
      photoPath: v.photoPath,
      currentKm: km > v.currentKm ? km : v.currentKm,
      oilChangeKm: km,
      oilChangeDate: date,
      createdAt: v.createdAt,
    );
    await _saveVehicles(prefs, items);
  }
}
