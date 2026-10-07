import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Datos mínimos de una etiqueta QR (una por variante de producto).
class QrLabelData {
  final String sku;
  final String size;
  final String color;

  const QrLabelData({
    required this.sku,
    required this.size,
    required this.color,
  });

  String get subtitle => 'Talla: $size | $color';
}

/// Impresión de etiquetas QR para rotulado físico.
///
/// Usado por el alta de productos y por la ficha de detalle de inventario
/// (reimpresión de etiquetas), para no duplicar la lógica del PDF.
class QrLabelPrinter {
  const QrLabelPrinter._();

  static Future<void> printLabels({
    required String productName,
    required List<QrLabelData> labels,
  }) async {
    if (labels.isEmpty) return;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => [
          pw.Header(level: 1, child: pw.Text('Etiquetas: $productName')),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: labels.map((v) {
              return pw.Container(
                width: 170,
                height: 195,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 1),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      productName,
                      maxLines: 2,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10),
                    ),
                    pw.Text(v.subtitle, style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 6),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: v.sku,
                      width: 92,
                      height: 92,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(v.sku,
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }
}
