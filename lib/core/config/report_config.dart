import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configuración persistente para envío automático de reportes
class ReportConfig {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const String _emailKey = 'report_email_recipient';
  static const String _whatsappKey = 'report_whatsapp_number';
  static const String _autoSendKey = 'report_auto_send';

  /// Email del destinatario (ej. gerente@tienda.com)
  static Future<String?> getReportEmail() async {
    return await _storage.read(key: _emailKey);
  }

  /// Guarda el email del destinatario
  static Future<void> setReportEmail(String email) async {
    if (email.trim().isEmpty) {
      await _storage.delete(key: _emailKey);
    } else {
      await _storage.write(key: _emailKey, value: email.trim());
    }
  }

  /// Número de WhatsApp con código de país (ej. 573001234567)
  static Future<String?> getReportWhatsApp() async {
    return await _storage.read(key: _whatsappKey);
  }

  /// Guarda el número de WhatsApp
  static Future<void> setReportWhatsApp(String phone) async {
    // Normalizar: solo dígitos
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      await _storage.delete(key: _whatsappKey);
    } else {
      await _storage.write(key: _whatsappKey, value: digits);
    }
  }

  /// Si está activado, envía automáticamente sin mostrar selector
  static Future<bool> getAutoSendEnabled() async {
    final value = await _storage.read(key: _autoSendKey);
    return value == 'true';
  }

  static Future<void> setAutoSendEnabled(bool enabled) async {
    await _storage.write(key: _autoSendKey, value: enabled.toString());
  }

  /// Limpia toda la configuración
  static Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _whatsappKey);
    await _storage.delete(key: _autoSendKey);
  }
}

/// Provider para Riverpod
final reportConfigProvider = Provider<ReportConfig>((ref) => ReportConfig());