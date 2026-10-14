import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../models/ticket.dart';
import '../theme/app_theme.dart';
import 'business_service.dart';

/// Genera y comparte el ticket para entregar al cliente:
/// solo los servicios y el total (sin costos internos ni fotos).
/// Dos formatos: PDF (descargar/imprimir) e imagen PNG (WhatsApp).
class TicketShareService {
  /// Canal nativo (MainActivity): guarda directo en Descargas/galería
  /// en Android moderno, donde Dart no puede escribir a carpetas
  /// compartidas por el almacenamiento por alcance.
  static const MethodChannel _mediaChannel =
      MethodChannel('georges_garage/media');
  static String _money(double v) => '\$${v
      .toStringAsFixed(2)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Nombre único por guardado (con fecha y hora): en Android cada
  /// guardado crea un archivo nuevo en la galería/Descargas (el sistema
  /// no sobrescribe), así el archivo más reciente siempre es fácil
  /// de identificar y no se confunde con versiones anteriores.
  static String _fileName(String ticketId, String ext) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'ticket-$ticketId-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.$ext';
  }

  static Future<Uint8List> build(Ticket ticket) async {
    final workshopName = await BusinessService.getName();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
                child: pw.Text(workshopName,
                    style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800))),
            pw.SizedBox(height: 4),
            pw.Text(t('ticket_share_title'),
                style: pw.TextStyle(
                    fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(t('ticket_share_folio', {'id': ticket.id}),
                style: const pw.TextStyle(fontSize: 14)),
            pw.Text(
                t('ticket_share_date',
                    {'date': _date(ticket.dateTime)}),
                style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder(
                  bottom: pw.BorderSide(color: PdfColors.grey400)),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(t('ticket_share_col_service'),
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(t('ticket_share_col_price'),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ...ticket.lines.map((l) => pw.TableRow(children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(l.name +
                              (l.quantity > 1
                                  ? t('ticket_share_qty_suffix',
                                      {'qty': '${l.quantity}'})
                                  : ''))),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(_money(l.price * l.quantity),
                              textAlign: pw.TextAlign.right)),
                    ])),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                    t('ticket_share_total',
                        {'total': _money(ticket.total)}),
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Spacer(),
            pw.Center(
                child: pw.Text(t('ticket_share_thanks'),
                    style: const pw.TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// PDF: en Android se guarda directo en Descargas;
  /// en iPhone abre el menú del sistema; en computadora se guarda
  /// en la carpeta de Descargas.
  static Future<void> sharePdf(
      BuildContext context, Ticket ticket) async {
    try {
      final bytes = await build(ticket);
      final name = _fileName(ticket.id, 'pdf');
      if (Platform.isAndroid) {
        await _mediaChannel
            .invokeMethod('savePdf', {'name': name, 'bytes': bytes});
        _saved(context,
            t('ticket_share_saved_pdf', {'name': name}));
      } else if (Platform.isIOS) {
        await Printing.sharePdf(bytes: bytes, filename: name);
      } else {
        await _saveToDownloads(context, bytes, name);
      }
    } catch (e) {
      _showError(context,
          t('ticket_share_pdf_error', {'e': '$e'}));
    }
  }

  /// Imagen PNG del ticket: se dibuja directo como widget de Flutter
  /// (sin pasar por el rasterizado del PDF, que en algunos teléfonos
  /// recorta la imagen). En Android se guarda directo en la galería
  /// (desde ahí se puede mandar por WhatsApp); en iPhone abre el menú
  /// del sistema; en computadora se guarda en Descargas.
  static Future<void> shareImage(
      BuildContext context, Ticket ticket) async {
    try {
      final png = await _renderTicketPng(context, ticket);
      final name = _fileName(ticket.id, 'png');
      // Diagnóstico: qué escala de letra reporta el teléfono.
      final scale =
          MediaQuery.textScalerOf(context).scale(1.0).toStringAsFixed(2);
      if (Platform.isAndroid) {
        await _mediaChannel
            .invokeMethod('saveImage', {'name': name, 'bytes': png});
        _saved(context,
            t('ticket_share_saved_image', {'name': name, 'scale': scale}));
      } else if (Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(png);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: t('ticket_share_share_text', {'id': ticket.id}),
          ),
        );
      } else {
        await _saveToDownloads(context, png, name);
      }
    } catch (e) {
      _showError(context,
          t('ticket_share_image_error', {'e': '$e'}));
    }
  }

  /// Dibuja el ticket como widget fuera de la pantalla y lo captura
  /// como PNG. Así la imagen sale completa y nítida sin depender
  /// del convertidor nativo del PDF.
  static Future<Uint8List> _renderTicketPng(
      BuildContext context, Ticket ticket) async {
    final key = GlobalKey();
    final workshopName = await BusinessService.getName();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned(
            left: -10000,
            top: 0,
            child: RepaintBoundary(
              key: key,
              child: TicketImageView(
                  ticket: ticket, workshopName: workshopName),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(entry);
    try {
      // Dejar que el widget se dibuje antes de capturarlo.
      await Future.delayed(const Duration(milliseconds: 400));
      final boundary = key.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      entry.remove();
    }
  }

  /// Guarda el archivo en la carpeta de Descargas y avisa dónde quedó.
  static Future<void> _saveToDownloads(
      BuildContext context, Uint8List bytes, String name) async {
    final dir =
        await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              t('ticket_share_saved_downloads', {'name': name})),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  static void _showError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  static void _saved(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Hoja con las dos opciones: PDF o imagen para WhatsApp.
  static Future<void> showSheet(
      BuildContext context, Ticket ticket) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(t('ticket_share_sheet_title'),
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 4),
            ListTile(
              leading:
                  const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text(t('ticket_share_download_pdf'),
                  style: const TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text(t('ticket_share_pdf_sub'),
                  style: const TextStyle(color: AppTheme.textSecondary)),
              onTap: () {
                Navigator.of(ctx).pop();
                sharePdf(context, ticket);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.green),
              title: Text(t('ticket_share_save_image'),
                  style: const TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text(t('ticket_share_gallery_sub'),
                  style: const TextStyle(color: AppTheme.textSecondary)),
              onTap: () {
                Navigator.of(ctx).pop();
                shareImage(context, ticket);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// El ticket dibujado como widget de Flutter: es lo que se captura
/// como imagen PNG para WhatsApp. Mismo contenido que el PDF
/// (servicios + total), con aspecto de ticket de caja.
class TicketImageView extends StatelessWidget {
  final Ticket ticket;
  final String workshopName;
  const TicketImageView(
      {super.key, required this.ticket, required this.workshopName});

  static const _ink = Color(0xFF212121);
  static const _muted = Color(0xFF757575);
  static const _line = Color(0xFFBDBDBD);

  @override
  Widget build(BuildContext context) {
    // La imagen debe verse idéntica en todos los teléfonos: ignoramos
    // el tamaño de letra de accesibilidad del sistema.
    return MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        width: 420,
        color: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(workshopName,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      color: _muted)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(t('ticket_share_title'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _ink)),
            ),
            const SizedBox(height: 10),
            Text(t('ticket_share_folio', {'id': ticket.id}),
                style: const TextStyle(fontSize: 13, color: _muted)),
            Text(
                t('ticket_share_date',
                    {'date': TicketShareService._date(ticket.dateTime)}),
                style: const TextStyle(fontSize: 13, color: _muted)),
            const SizedBox(height: 12),
            const _DashedLine(),
            const SizedBox(height: 6),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1.4),
              },
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(t('ticket_share_col_service'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _ink)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(t('ticket_share_col_price'),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _ink)),
                    ),
                  ],
                ),
                for (final l in ticket.lines)
                  TableRow(
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                            l.name +
                                (l.quantity > 1
                                    ? t('ticket_share_qty_suffix',
                                        {'qty': '${l.quantity}'})
                                    : ''),
                            style: const TextStyle(
                                fontSize: 14, color: _ink)),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                              TicketShareService._money(
                                  l.price * l.quantity),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 14, color: _ink)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const _DashedLine(),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    t('ticket_share_total',
                        {'total': TicketShareService._money(ticket.total)}),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _ink)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(t('ticket_share_thanks'),
                  style: const TextStyle(fontSize: 12, color: _muted)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Línea punteada estilo ticket de caja.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 14).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => const SizedBox(
              width: 7,
              height: 1.5,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: TicketImageView._line),
              ),
            ),
          ),
        );
      },
    );
  }
}
