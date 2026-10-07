import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/auth/data/pin_service.dart';
import 'report_config.dart';

/// Configuración por defecto de la aplicación (PINs, reportes, etc.)
/// Se ejecuta una sola vez al primer arranque.
class AppDefaults {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const String _initializedKey = 'app_defaults_initialized_v1';

  // ──────────────────────────────────────────────────────────────────────
  // CREDENCIALES POR DEFECTO - CAMBIA ESTOS VALORES AQUÍ
  // ──────────────────────────────────────────────────────────────────────

  /// PIN por defecto para Administrador (4-6 dígitos)
  static const String defaultAdminPin = '1234';

  /// PIN por defecto para Colaborador/Cajero (4-6 dígitos)
  static const String defaultColaboradorPin = '4321';

  /// Email donde llegarán los reportes de cierre de caja
  static const String defaultReportEmail = 'nadabrayan@gmail.com';

  /// WhatsApp Business para reportes (código país + número, solo dígitos)
  /// España (+34): 34675010781
  static const String defaultReportWhatsApp = '34675010781';

  /// Enviar reportes automáticamente sin mostrar selector
  static const bool defaultAutoSendReports = true;

  // ──────────────────────────────────────────────────────────────────────

  /// IDs de usuario (deben coincidir con AuthRepository.demoAdminProfile y demoColaboradorProfile)
  static const String adminUserId = 'admin-001-uuid';
  static const String colaboradorUserId = 'colab-002-uuid';

  /// Inicializa valores por defecto si es la primera vez
  static Future<void> initialize() async {
    final alreadyInitialized = await _storage.read(key: _initializedKey);
    if (alreadyInitialized == 'true') return;

    final pinService = PinService();

    // 1. Configurar PINs por defecto
    await pinService.setPin(adminUserId, defaultAdminPin);
    await pinService.setPin(colaboradorUserId, defaultColaboradorPin);

    // 2. Configurar destinatarios de reportes
    await ReportConfig.setReportEmail(defaultReportEmail);
    await ReportConfig.setReportWhatsApp(defaultReportWhatsApp);
    await ReportConfig.setAutoSendEnabled(defaultAutoSendReports);

    // 3. Marcar como inicializado
    await _storage.write(key: _initializedKey, value: 'true');

    // Log para debug (se ve en `flutter run` o logcat)
    // ignore: avoid_print
    print('✅ AppDefaults initialized:');
    // ignore: avoid_print
    print('   Admin PIN: $defaultAdminPin');
    // ignore: avoid_print
    print('   Colaborador PIN: $defaultColaboradorPin');
    // ignore: avoid_print
    print('   Report Email: $defaultReportEmail');
    // ignore: avoid_print
    print('   Report WhatsApp: $defaultReportWhatsApp');
    // ignore: avoid_print
    print('   Auto-send: $defaultAutoSendReports');
  }

  /// Fuerza reinicialización (útil para testing o reset)
  static Future<void> forceReinitialize() async {
    await _storage.delete(key: _initializedKey);
    await initialize();
  }

  /// Verifica si ya se inicializó
  static Future<bool> isInitialized() async {
    return await _storage.read(key: _initializedKey) == 'true';
  }
}

/// Provider para Riverpod
final appDefaultsProvider = Provider<AppDefaults>((ref) => AppDefaults());