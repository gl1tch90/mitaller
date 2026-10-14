import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/attendance.dart';
import '../models/mechanic.dart';
import '../l10n/strings.dart';
import 'business_service.dart';

/// Genera y comparte un reporte en PDF con las horas trabajadas de un
/// mecánico en una semana (lunes a domingo). Sirve para mostrarlo
/// al empleado o guardarlo como evidencia.
class AttendanceReport {
  static Future<void> shareWeekPdf(Mechanic mechanic,
      DateTime weekStartDay, List<AttendanceRecord> records) async {
    final doc = pw.Document();
    final businessName = await BusinessService.getName();

    final days = List<AttendanceRecord>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));
    final totalMin = days.fold<double>(0,
        (s, r) => s + (r.clockOut != null ? r.hoursWorked : 0));
    final now = DateTime.now();
    final generated =
        '${formatDay(now)} ${formatClock(now)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(businessName,
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold)),
          pw.Text('Reporte de horas trabajadas',
              style: pw.TextStyle(
                  fontSize: 14, color: PdfColors.grey700)),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Empleado: ${mechanic.name}',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('Puesto: ${positionsLabel(mechanic.positions)}'),
                pw.Text(
                    'Semana: ${formatWeekRange(weekStartDay)}',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('Generado: $generated'),
                pw.Text(
                    'Total de la semana: ${formatHours(totalMin)}',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          if (days.isEmpty)
            pw.Text('Sin registros en esta semana.')
          else
            pw.Table(
              border:
                  pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2.4),
                2: const pw.FlexColumnWidth(1.6),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FlexColumnWidth(1.4),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200),
                  children: [
                    _Cell('Día', bold: true),
                    _Cell('Fecha', bold: true),
                    _Cell('Entrada', bold: true),
                    _Cell('Salida', bold: true),
                    _Cell('Horas', bold: true),
                  ],
                ),
                for (final r in days)
                  pw.TableRow(children: [
                    _Cell(formatWeekday(r.date)),
                    _Cell(formatDay(r.date)),
                    _Cell(formatClock(r.clockIn)),
                    _Cell(r.clockOut != null
                        ? formatClock(r.clockOut!)
                        : '—'),
                    _Cell(r.clockOut != null
                        ? formatHours(r.hoursWorked)
                        : '—'),
                  ]),
              ],
            ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceAround,
            children: [
              _signature('Firma del empleado'),
              _signature('Firma del encargado'),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text(
              'Documento generado por $businessName',
              style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    final ws =
        '${weekStartDay.year}-${weekStartDay.month.toString().padLeft(2, '0')}-${weekStartDay.day.toString().padLeft(2, '0')}';
    final name =
        'horas_${mechanic.name.replaceAll(' ', '_')}_semana_$ws.pdf';
    await Printing.sharePdf(
        bytes: await doc.save(), filename: name);
  }
}

class _Cell extends pw.StatelessWidget {
  final String text;
  final bool bold;
  _Cell(this.text, {this.bold = false});

  @override
  pw.Widget build(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal)),
    );
  }
}

pw.Widget _signature(String label) {
  return pw.Column(children: [
    pw.Container(
        width: 160,
        height: 40,
        decoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide()))),
    pw.SizedBox(height: 4),
    pw.Text(label,
        style: pw.TextStyle(
            fontSize: 11, color: PdfColors.grey700)),
  ]);
}
