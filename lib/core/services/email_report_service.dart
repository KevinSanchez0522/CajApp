import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Servicio para envío automático de reportes vía Firebase Functions + SendGrid
class EmailReportService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Inicializa Firebase (llamar en main.dart antes de runApp)
  static Future<void> initialize() async {
    await Firebase.initializeApp();
    // Forzar región si no es us-central1
    // FirebaseFunctions.instanceFor(region: 'europe-west1');
  }

  /// Envía reporte de cierre por email automáticamente
  /// Retorna true si éxito, false si falla
  static Future<bool> sendClosingReport({
    required File pdfFile,
    required String fileName,
    required String toEmail,
    required String cashierName,
    required double openingBalance,
    required double cashSales,
    required double cardSales,
    required double transferSales,
    required double reportedCash,
    required double expectedCash,
    required double difference,
  }) async {
    try {
      // Leer PDF y convertir a base64
      final bytes = await pdfFile.readAsBytes();
      final pdfBase64 = base64Encode(bytes);

      // Llamar a Cloud Function
      final callable = _functions.httpsCallable('sendReportEmail');
      final result = await callable.call({
        'pdfBase64': pdfBase64,
        'fileName': fileName,
        'toEmail': toEmail,
        'subject': 'Reporte de Cierre de Caja - $fileName',
        'shiftData': {
          'cashierName': cashierName,
          'openingBalance': openingBalance,
          'cashSales': cashSales,
          'cardSales': cardSales,
          'transferSales': transferSales,
          'reportedCash': reportedCash,
          'expectedCash': expectedCash,
          'difference': difference,
        },
      });

      if (result.data['success'] == true) {
        debugPrint('✅ Email enviado via Firebase Function: $toEmail');
        return true;
      } else {
        debugPrint('❌ Error Function: ${result.data['message']}');
        return false;
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Firebase Functions error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Error enviando email automático: $e');
      return false;
    }
  }

  /// Envía reporte de apertura por email
  static Future<bool> sendOpeningReport({
    required File pdfFile,
    required String fileName,
    required String toEmail,
    required String cashierName,
    required double openingBalance,
  }) async {
    try {
      final bytes = await pdfFile.readAsBytes();
      final pdfBase64 = base64Encode(bytes);

      final callable = _functions.httpsCallable('sendReportEmail');
      final result = await callable.call({
        'pdfBase64': pdfBase64,
        'fileName': fileName,
        'toEmail': toEmail,
        'subject': 'Reporte de Apertura de Caja - $fileName',
        'shiftData': {
          'cashierName': cashierName,
          'openingBalance': openingBalance,
        },
      });

      return result.data['success'] == true;
    } catch (e) {
      debugPrint('❌ Error enviando email apertura: $e');
      return false;
    }
  }
}