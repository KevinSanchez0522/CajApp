import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:ui' show Rect;
import '../../pos/domain/cart_item.dart';

class PdfReceiptService {
  static final NumberFormat _currency =
      NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

  /// Genera un documento PDF adaptado a tirilla de punto de venta (80mm)
  static Future<File> generateReceiptPdf({
    required String saleId,
    required String cashierName,
    required String paymentMethod,
    required List<CartItem> items,
    required double total,
    String storeName = 'BOUTIQUE FASHION STORE',
  }) async {
    final pdf = pw.Document();

    // Formato de papel continuo tipo ticket (Ancho: 80mm)
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
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              pw.Text('NIT: 900.543.210-9',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Calle Principal # 45 - 20',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Tel: +57 300 123 4567',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text('--------------------------------',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'VENTA #: ${saleId.substring(0, 8).toUpperCase()}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    _dateFormat.format(DateTime.now()),
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cajero: $cashierName',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Pago: $paymentMethod',
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Text('--------------------------------',
                  style: const pw.TextStyle(fontSize: 8)),

              // DETALLE DE PRENDAS
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'CANT  DESCRIPCION      TALLA   TOTAL',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 8),
                ),
              ),
              pw.Divider(thickness: 0.5),
              ...items.map((item) {
                final name = (item.variant.productName ?? item.variant.sku);
                final shortName =
                    name.length > 14 ? '${name.substring(0, 14)}.' : name;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('${item.quantity}x',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Expanded(
                        child: pw.Text(' $shortName (${item.variant.size})',
                            style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Text(_currency.format(item.subtotal),
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                );
              }),
              pw.Text('--------------------------------',
                  style: const pw.TextStyle(fontSize: 8)),

              // TOTALES
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL A PAGAR:',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text(_currency.format(total),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ],
              ),
              pw.SizedBox(height: 8),

              // CODIGO QR PARA VALIDACION DE RECIBO
              pw.BarcodeWidget(
                data: 'https://tienda.com/validar-recibo?id=$saleId',
                barcode: pw.Barcode.qrCode(),
                width: 55,
                height: 55,
              ),
              pw.SizedBox(height: 4),
              pw.Text('!Gracias por tu compra!',
                  style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic, fontSize: 8)),
              pw.Text('Garantia de cambio: 15 dias con recibo',
                  style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/recibo_${saleId.substring(0, 8)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Despliega el selector de compartir nativo de iOS / Android
  static Future<void> shareReceipt(File pdfFile, {Rect? sharePositionOrigin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(pdfFile.path)],
        text:
            'Adjunto comprobante de compra en VERSATIL FRESH BOUTIQUE Store. Gracias por preferirnos!',
        subject: 'Recibo Digital de Compra',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}