import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../models/shop_vehicle.dart';
import 'business_service.dart';
import 'shop_vehicle_service.dart';

/// Reporte del historial de un vehículo del taller (PDF).
/// Se genera antes de borrar el vehículo para conservar el registro:
/// datos, cambios de aceite, bitácora, daños, documentos y gastos.
class VehicleReportService {
  static String _money(double v) => '\$${v
      .toStringAsFixed(2)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _statusLabel(String status) {
    switch (status) {
      case 'taller':
        return t('shop_vehicle_status_taller');
      case 'vendido':
        return t('shop_vehicle_status_vendido');
      default:
        return t('shop_vehicle_status_activo');
    }
  }

  static pw.Widget _sectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
                width: 150,
                child: pw.Text(label,
                    style: const pw.TextStyle(fontSize: 10))),
            pw.Expanded(
                child: pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold))),
          ],
        ),
      );

  static Future<Uint8List> build(ShopVehicle v) async {
    final workshopName = await BusinessService.getName();
    final svc = ShopVehicleService();
    final log = await svc.logFor(v.id);
    final issues = await svc.issuesFor(v.id);
    final docs = await svc.docsFor(v.id);
    final expenses = await svc.expensesFor(v.id);
    final totalExpenses =
        expenses.fold(0.0, (s, e) => s + e.amount);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Center(
              child: pw.Text(workshopName,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold))),
          pw.Center(
              child: pw.Padding(
                  padding:
                      const pw.EdgeInsets.only(top: 4, bottom: 12),
                  child: pw.Text(
                      t('vehicle_report_title',
                          {'date': _date(DateTime.now())}),
                      style:
                          const pw.TextStyle(fontSize: 12)))),
          _sectionTitle(t('vehicle_report_vehicle')),
          _row(t('vehicle_report_name'), v.name),
          _row(
              t('vehicle_report_kind'),
              v.kind == 'moto'
                  ? t('shop_vehicles_moto')
                  : t('shop_vehicles_carro')),
          _row(t('vehicle_report_plates'),
              v.plates.isEmpty ? '—' : v.plates),
          _row(t('vehicle_report_km'), '${v.currentKm} km'),
          _row(t('vehicle_report_status'),
              _statusLabel(v.status)),
          if (v.oilChangeDate != null)
            _row(
                t('vehicle_report_last_oil'),
                '${_date(v.oilChangeDate!)}'
                '${v.oilChangeKm != null ? ' · ${v.oilChangeKm} km' : ''}'),
          _sectionTitle(
              t('vehicle_report_log', {'n': '${log.length}'})),
          if (log.isEmpty)
            pw.Text(t('vehicle_report_empty'),
                style: const pw.TextStyle(fontSize: 10))
          else
            ...log.map((e) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                      '• ${_date(e.date)} — ${e.km} km · '
                      '${e.mechanicName}'
                      '${e.notes.isNotEmpty ? ' · ${e.notes}' : ''}',
                      style:
                          const pw.TextStyle(fontSize: 10)),
                )),
          _sectionTitle(
              t('vehicle_report_issues', {'n': '${issues.length}'})),
          if (issues.isEmpty)
            pw.Text(t('vehicle_report_empty'),
                style: const pw.TextStyle(fontSize: 10))
          else
            ...issues.map((i) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                      '• ${_date(i.date)} — ${i.description} '
                      '(${i.resolved ? t('vehicle_report_resolved') : t('vehicle_report_open')})',
                      style:
                          const pw.TextStyle(fontSize: 10)),
                )),
          _sectionTitle(
              t('vehicle_report_docs', {'n': '${docs.length}'})),
          if (docs.isEmpty)
            pw.Text(t('vehicle_report_empty'),
                style: const pw.TextStyle(fontSize: 10))
          else
            ...docs.map((d) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                      '• ${d.label} — ${t('vehicle_report_expiry')}: ${_date(d.expiryDate)}',
                      style:
                          const pw.TextStyle(fontSize: 10)),
                )),
          _sectionTitle(t('vehicle_report_expenses',
              {'n': '${expenses.length}'})),
          if (expenses.isEmpty)
            pw.Text(t('vehicle_report_empty'),
                style: const pw.TextStyle(fontSize: 10))
          else ...[
            ...expenses.map((e) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                      '• ${_date(e.date)} — ${e.kind} — ${_money(e.amount)}'
                      '${e.notes.isNotEmpty ? ' · ${e.notes}' : ''}',
                      style:
                          const pw.TextStyle(fontSize: 10)),
                )),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                  '${t('vehicle_report_total')}: ${_money(totalExpenses)}',
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  /// Genera el PDF y lo guarda en Descargas. Devuelve el nombre del archivo.
  static Future<String> saveToDownloads(ShopVehicle v) async {
    final bytes = await build(v);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final safeName = v.name
        .replaceAll(RegExp(r'[^\w\- ]'), '')
        .trim()
        .replaceAll(' ', '-');
    final name =
        'reporte-vehiculo-$safeName-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.pdf';
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return name;
  }

  /// Comparte el PDF (ej. por WhatsApp).
  static Future<void> share(ShopVehicle v) async {
    final bytes = await build(v);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/reporte-vehiculo.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)],
        text: t('vehicle_report_share_text',
            {'name': v.name}));
  }
}
