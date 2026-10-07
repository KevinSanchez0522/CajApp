import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../pos/domain/cash_shift.dart';
import 'package:printing/printing.dart';
import '../../../../core/config/report_config.dart';
import '../../../../core/services/emailjs_service.dart';

/// Servicio para generar reportes PDF de apertura/cierre de caja
class ShiftReportService {
  static final NumberFormat _currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
  static final DateFormat _shortDateFormat = DateFormat('dd/MM/yyyy');

  /// Genera PDF de apertura de caja
  static Future<File> generateOpeningReportPdf({
    required CashShift shift,
    required String cashierName,
    required String cashierRole,
    required double openingBalance,
    String storeName = 'BOUTIQUE FASHION STORE',
    String storeNit = '900.543.210-9',
    String storeAddress = 'Calle Principal # 45 - 20',
    String storePhone = '+57 300 123 4567',
  }) async {
    final pdf = pw.Document();

    const roll80mm = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ENCABEZADO
              pw.Text(
                storeName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              pw.Text('NIT: $storeNit', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Tel: $storePhone', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),
              
              // TÍTULO
              pw.Text(
                'APERTURA DE CAJA',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 4),
              
              // INFO BÁSICA
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('APERTURA #: ${shift.id.substring(0, 8).toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(_dateFormat.format(shift.openedAt), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cajero: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Rol: $cashierRole', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // BASE INICIAL
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'BASE INICIAL EN EFECTIVO',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Monto base:', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(
                    _currency.format(openingBalance),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // OBSERVACIONES
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Observaciones:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                ),
              ),
              pw.Text('Caja abierta correctamente. Base verificada.', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 8),

              // FIRMA
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('________________________', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Firma Cajero', style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('________________________', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Firma Supervisor', style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text('¡Buena jornada laboral!', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
            ],
          );
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final fileName = 'apertura_caja_${shift.id.substring(0, 8)}_${_shortDateFormat.format(shift.openedAt).replaceAll('/', '')}.pdf';
    final file = File('${outputDir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Genera PDF de cierre de caja
  static Future<File> generateClosingReportPdf({
    required CashShift shift,
    required String cashierName,
    required String cashierRole,
    required double openingBalance,
    required double cashSales,
    required double cardSales,
    required double transferSales,
    required double reportedCash,
    required double expectedCash,
    required double difference,
    String storeName = 'BOUTIQUE FASHION STORE',
    String storeNit = '900.543.210-9',
    String storeAddress = 'Calle Principal # 45 - 20',
    String storePhone = '+57 300 123 4567',
  }) async {
    final pdf = pw.Document();

    const roll80mm = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final isExact = difference.abs() < 0.01;
    final isOver = difference > 0;
    final diffLabel = isExact ? 'CUADRE EXACTO' : (isOver ? 'SOBRANTE' : 'FALTANTE');

    pdf.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ENCABEZADO
              pw.Text(
                storeName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              pw.Text('NIT: $storeNit', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Tel: $storePhone', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // TÍTULO
              pw.Text(
                'CIERRE Y ARQUEO DE CAJA',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 4),

              // INFO BÁSICA
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CIERRE #: ${shift.id.substring(0, 8).toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(_dateFormat.format(shift.closedAt ?? DateTime.now()), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cajero: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Rol: $cashierRole', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // RESUMEN VENTAS
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'RESUMEN DE VENTAS DEL TURNO',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 4),
              _buildRow('Ventas Efectivo:', _currency.format(cashSales)),
              _buildRow('Ventas Datáfono:', _currency.format(cardSales)),
              _buildRow('Ventas Transferencias:', _currency.format(transferSales)),
              pw.Divider(thickness: 0.5),
              _buildRow('TOTAL VENDIDO:', _currency.format(cashSales + cardSales + transferSales), bold: true),
              pw.SizedBox(height: 8),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // ARQUEO DE CAJA
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'ARQUEO DE EFECTIVO',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 4),
              _buildRow('Base inicial:', _currency.format(openingBalance)),
              _buildRow('+ Ventas en efectivo:', _currency.format(cashSales)),
              pw.Divider(thickness: 0.5),
              _buildRow('Esperado en caja:', _currency.format(expectedCash), bold: true),
              _buildRow('Reportado físico:', _currency.format(reportedCash), bold: true),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Diferencia:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text(
                    '${difference >= 0 ? '+' : ''}${_currency.format(difference)} ($diffLabel)',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: isExact ? PdfColors.green800 : (isOver ? PdfColors.blue800 : PdfColors.red800),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // VENTAS POR MÉTODO (desglose)
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'DESGLOSE POR MÉTODO DE PAGO',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 4),
              _buildRow('Efectivo:', _currency.format(cashSales)),
              _buildRow('Datáfono/Tarjeta:', _currency.format(cardSales)),
              _buildRow('Transferencia:', _currency.format(transferSales)),
              pw.SizedBox(height: 8),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),

              // FIRMAS
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('________________________', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Firma Cajero', style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('________________________', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Firma Supervisor', style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text('Gracias por tu trabajo', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
            ],
          );
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final closedAt = shift.closedAt ?? DateTime.now();
    final fileName = 'cierre_caja_${shift.id.substring(0, 8)}_${_shortDateFormat.format(closedAt).replaceAll('/', '')}.pdf';
    final file = File('${outputDir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  /// Comparte el PDF por WhatsApp (usa share_plus para abrir selector)
  static Future<void> shareViaWhatsApp(File pdfFile, {String? phoneNumber, String? message}) async {
    final text = message ?? 'Reporte de caja - VERSATIL FRESH BOUTIQUE Store';
    
    // Si no se pasa número, intenta usar el configurado
    final targetPhone = phoneNumber ?? await ReportConfig.getReportWhatsApp();

    // share_plus comparte archivo; para WhatsApp específico con número usamos url_launcher
    if (targetPhone != null && targetPhone.isNotEmpty) {
      final url = 'https://wa.me/$targetPhone?text=${Uri.encodeComponent(text)}';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Fallback: selector nativo
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(pdfFile.path)],
        text: text,
        subject: 'Reporte de Caja',
      ),
    );
  }

  /// Abre el cliente de correo con el PDF adjunto (mailto:)
  static Future<void> shareViaEmail(File pdfFile, {
    String? to,
    String subject = 'Reporte de Caja - VERSATIL FRESH BOUTIQUE Store',
    String body = 'Adjunto reporte de apertura/cierre de caja.',
  }) async {
    // Si no se pasa email, intenta usar el configurado
    final targetEmail = to ?? await ReportConfig.getReportEmail();

    // share_plus maneja el envío por email con adjunto
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(pdfFile.path)],
        text: body,
        subject: subject,
        // Nota: share_plus no soporta 'to' directo en todos los clientes,
        // pero algunos (Gmail, Outlook) lo leen del subject/body
      ),
    );

    // Alternativa nativa mailto (sin adjunto, solo texto)
    if (targetEmail != null && targetEmail.isNotEmpty) {
      final mailtoUri = Uri(
        scheme: 'mailto',
        path: targetEmail,
        queryParameters: {
          'subject': subject,
          'body': body,
        },
      );
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Muestra el selector nativo de compartir (incluye WhatsApp, Email, etc.)
  static Future<void> shareNative(File pdfFile, {
    String text = 'Reporte de caja - VERSATIL FRESH BOUTIQUE Store',
    String subject = 'Reporte de Caja',
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(pdfFile.path)],
        text: text,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Genera y comparte reporte de apertura
  static Future<void> generateAndShareOpeningReport({
    required CashShift shift,
    required String cashierName,
    required String cashierRole,
    required double openingBalance,
    required BuildContext context,
  }) async {
    try {
      final file = await generateOpeningReportPdf(
        shift: shift,
        cashierName: cashierName,
        cashierRole: cashierRole,
        openingBalance: openingBalance,
      );
    
    // Verificar si envío automático está activado
    final autoSend = await ReportConfig.getAutoSendEnabled();
    if (!context.mounted) return;
    if (autoSend) {
      await _sendReportAutomatically(
        file, 
        context,
        cashierName: cashierName,
        openingBalance: openingBalance,
        cashSales: 0,
        cardSales: 0,
        transferSales: 0,
        reportedCash: 0,
        expectedCash: 0,
        difference: 0,
        isClosingReport: false,
      );
    } else if (context.mounted) {
      await _showShareOptions(context, file, 'Reporte de Apertura de Caja');
    }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando reporte: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  /// Genera y comparte reporte de cierre
  static Future<void> generateAndShareClosingReport({
    required CashShift shift,
    required String cashierName,
    required String cashierRole,
    required double openingBalance,
    required double cashSales,
    required double cardSales,
    required double transferSales,
    required double reportedCash,
    required double expectedCash,
    required double difference,
    required BuildContext context,
  }) async {
    try {
      final file = await generateClosingReportPdf(
        shift: shift,
        cashierName: cashierName,
        cashierRole: cashierRole,
        openingBalance: openingBalance,
        cashSales: cashSales,
        cardSales: cardSales,
        transferSales: transferSales,
        reportedCash: reportedCash,
        expectedCash: expectedCash,
        difference: difference,
      );

      // Verificar si envío automático está activado
      final autoSend = await ReportConfig.getAutoSendEnabled();
      if (!context.mounted) return;
      if (autoSend) {
        await _sendReportAutomatically(
          file, 
          context,
          cashierName: cashierName,
          openingBalance: openingBalance,
          cashSales: cashSales,
          cardSales: cardSales,
          transferSales: transferSales,
          reportedCash: reportedCash,
          expectedCash: expectedCash,
          difference: difference,
          isClosingReport: true,
        );
      } else if (context.mounted) {
        await _showShareOptions(context, file, 'Reporte de Cierre de Caja');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando reporte: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  /// Envía reporte automáticamente: Email (auto via EmailJS) + WhatsApp (manual via share)
  static Future<void> _sendReportAutomatically(File file, BuildContext context, {
    required String cashierName,
    required double openingBalance,
    required double cashSales,
    required double cardSales,
    required double transferSales,
    required double reportedCash,
    required double expectedCash,
    required double difference,
    required bool isClosingReport, // true = cierre, false = apertura
  }) async {
    try {
      // 1. EMAIL AUTOMÁTICO via EmailJS
      final email = await ReportConfig.getReportEmail();
      bool emailSent = false;

      if (email != null && email.isNotEmpty) {
        final fileName = file.path.split('/').last;
        
        // Leer PDF y convertir a base64
        final bytes = await file.readAsBytes();
        final pdfBase64 = base64Encode(bytes);
        
        // Construir HTML body
        String htmlBody;
        if (isClosingReport) {
          htmlBody = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #2c3e50;">📊 Reporte de Cierre de Caja</h2>
            <p><strong>Cajero:</strong> $cashierName</p>
            <p><strong>Fecha:</strong> ${DateTime.now().toString().substring(0, 19)}</p>
            <hr style="border: 1px solid #eee;">
            <p><strong>Base inicial:</strong> \$${openingBalance.toStringAsFixed(2)}</p>
            <p><strong>Ventas efectivo:</strong> \$${cashSales.toStringAsFixed(2)}</p>
            <p><strong>Ventas datáfono:</strong> \$${cardSales.toStringAsFixed(2)}</p>
            <p><strong>Ventas transferencias:</strong> \$${transferSales.toStringAsFixed(2)}</p>
            <hr style="border: 1px solid #eee;">
            <p><strong>Esperado en caja:</strong> \$${expectedCash.toStringAsFixed(2)}</p>
            <p><strong>Reportado físico:</strong> \$${reportedCash.toStringAsFixed(2)}</p>
            <p><strong>Diferencia:</strong> \$${difference.toStringAsFixed(2)}</p>
            <hr style="border: 1px solid #eee;">
            <p style="color: #7f8c8d;">Adjunto PDF con el detalle completo.</p>
            <p style="color: #7f8c8d; font-size: 12px;">Enviado automáticamente desde VERSATIL FRESH BOUTIQUE</p>
          </div>
          ''';
        } else {
          htmlBody = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #2c3e50;">📊 Reporte de Apertura de Caja</h2>
            <p><strong>Cajero:</strong> $cashierName</p>
            <p><strong>Fecha:</strong> ${DateTime.now().toString().substring(0, 19)}</p>
            <hr style="border: 1px solid #eee;">
            <p><strong>Base inicial:</strong> \$${openingBalance.toStringAsFixed(2)}</p>
            <hr style="border: 1px solid #eee;">
            <p style="color: #7f8c8d;">Adjunto PDF con el detalle completo.</p>
            <p style="color: #7f8c8d; font-size: 12px;">Enviado automáticamente desde VERSATIL FRESH BOUTIQUE</p>
          </div>
          ''';
        }

        emailSent = await EmailJSService.sendEmail(
          pdfBase64: pdfBase64,
          fileName: fileName,
          toEmail: email,
          subject: '${isClosingReport ? "Cierre" : "Apertura"} de Caja - $fileName',
          htmlBody: htmlBody,
        );
      }

      // 2. WHATSAPP MANUAL - abrir selector para que usuario envíe
      // (No se puede automatizar WhatsApp sin WhatsApp Business API de pago)
      if (!context.mounted) return;
      final whatsappSent = await _sendWhatsAppManually(file, context);

      // 3. Mostrar resultado
      if (context.mounted) {
        String message = '';
        Color color = Colors.green.shade700;
        
        if (emailSent && whatsappSent) {
          message = '✅ Email automático enviado + WhatsApp listo para enviar';
        } else if (emailSent) {
          message = '✅ Email automático enviado (WhatsApp: abre manual)';
        } else if (whatsappSent) {
          message = '📱 WhatsApp abierto (Email: configurar en ajustes)';
          color = Colors.orange.shade700;
        } else {
          message = '⚠️ Configura email en Ajustes > Config. Reportes';
          color = Colors.red.shade700;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: color,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en envío automático: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Abre WhatsApp para que el usuario envíe manualmente
  static Future<bool> _sendWhatsAppManually(File file, BuildContext context) async {
    try {
      final phone = await ReportConfig.getReportWhatsApp();
      if (phone != null && phone.isNotEmpty) {
        final url = 'https://wa.me/$phone?text=${Uri.encodeComponent('Reporte de caja - VERSATIL FRESH BOUTIQUE Store')}';
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return true;
        }
      }
      // Fallback: share_plus selector
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Reporte de caja - VERSATIL FRESH BOUTIQUE Store',
          subject: 'Reporte de Caja',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Error abriendo WhatsApp: $e');
      return false;
    }
  }

  static Future<void> _showShareOptions(BuildContext context, File file, String title) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Compartir (WhatsApp, Email, etc.)'),
                onTap: () {
                  Navigator.pop(ctx);
                  shareNative(file);
                },
              ),
              ListTile(
                leading: Icon(Icons.chat_bubble, color: Colors.green.shade700),
                title: const Text('Enviar por WhatsApp'),
                onTap: () {
                  Navigator.pop(ctx);
                  shareViaWhatsApp(file);
                },
              ),
              ListTile(
                leading: Icon(Icons.email, color: Colors.blue.shade700),
                title: const Text('Enviar por Email'),
                onTap: () {
                  Navigator.pop(ctx);
                  shareViaEmail(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Imprimir'),
                onTap: () {
                  Navigator.pop(ctx);
                  _printPdf(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('Guardar en archivos'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveToDownloads(file);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _printPdf(File file) async {
    // Usar printing package para imprimir
    try {
      await Printing.layoutPdf(onLayout: (_) => file.readAsBytesSync());
    } catch (e) {
      debugPrint('Error imprimiendo: $e');
    }
  }

  static Future<void> _saveToDownloads(File file) async {
    // En Android/iOS, share_plus con "Guardar en archivos" ya lo hace
    await shareNative(file);
  }
}

