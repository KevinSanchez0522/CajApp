import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio para envío de emails automáticos via EmailJS
class EmailJSService {
  // Credenciales EmailJS
  static const String _serviceId = 'service_sj039v8';
  static const String _templateId = 'template_h5zx7oy';
  static const String _publicKey = '4QPbZ9u13du2BxJnP';
  // TODO: Pon aquí tu Private Key de EmailJS (Account > Security > Private Key)
  // static const String _privateKey = 'TU_PRIVATE_KEY_AQUI';
  static const String _apiUrl = 'https://api.emailjs.com/api/v1.0/email/send';

  /// Envía email con PDF adjunto (base64) usando EmailJS
  /// Retorna true si éxito, false si falla
  static Future<bool> sendEmail({
    required String pdfBase64,
    required String fileName,
    required String toEmail,
    required String subject,
    required String htmlBody,
  }) async {
    try {
      // Parámetros que DEBEN coincidir exactamente con tu template_h5zx7oy
      // Verifica en EmailJS > Templates > template_h5zx7oy qué variables usa
      final templateParams = {
        'to_email': toEmail,
        'subject': subject,
        'message': htmlBody,  // Algunos templates usan 'message' en lugar de 'html_body'
        'html_body': htmlBody,
        'reply_to': 'nadabrayan@gmail.com',
        'from_name': 'cajApp',
      };
      
      final requestBody = {
        'service_id': _serviceId,
        'template_id': _templateId,
        'user_id': _publicKey,
        // 'accessToken': _privateKey,  // Descomenta si usas Private Key
        'template_params': templateParams,
        'attachments': [
          {
            'name': fileName,
            'content': pdfBase64,
            'encoding': 'base64',
            'mimeType': 'application/pdf',
          }
        ],
      };
      
      print('📧 EmailJS: Enviando a $toEmail...');
      print('📧 EmailJS: Service=$_serviceId, Template=$_templateId');
      print('📧 EmailJS: Params keys=${templateParams.keys.toList()}');
      
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('📧 EmailJS Response: ${response.statusCode}');
      print('📧 EmailJS Body: ${response.body}');
      
      if (response.statusCode == 200) {
        print('✅ EmailJS: Email enviado exitosamente');
        return true;
      } else {
        print('❌ EmailJS Error: ${response.statusCode} - ${response.body}');
        // Intentar sin adjunto como fallback
        print('🔄 EmailJS: Reintentando SIN adjunto...');
        return await _sendWithoutAttachment(toEmail, subject, htmlBody);
      }
    } catch (e) {
      print('❌ EmailJS Exception: $e');
      return false;
    }
  }

  /// Fallback: envía email sin adjunto
  static Future<bool> _sendWithoutAttachment(
    String toEmail,
    String subject,
    String htmlBody,
  ) async {
    try {
      final templateParams = {
        'to_email': toEmail,
        'subject': subject,
        'message': htmlBody,
        'html_body': htmlBody,
        'reply_to': 'nadabrayan@gmail.com',
        'from_name': 'cajApp',
      };
      
      final requestBody = {
        'service_id': _serviceId,
        'template_id': _templateId,
        'user_id': _publicKey,
        // 'accessToken': _privateKey,  // Descomenta si usas Private Key
        'template_params': templateParams,
      };
      
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('📧 EmailJS (sin adjunto) Response: ${response.statusCode}');
      print('📧 EmailJS (sin adjunto) Body: ${response.body}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ EmailJS Exception (sin adjunto): $e');
      return false;
    }
  }
}