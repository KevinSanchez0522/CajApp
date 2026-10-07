import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Provider para Riverpod
final pinServiceProvider = Provider<PinService>((ref) => PinService());

/// Servicio para gestionar PIN local y autenticación biométrica
class PinService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const String _pinPrefix = 'user_pin_';
  static const String _biometricEnabledKey = 'biometric_enabled_';
  static const int _minPinLength = 4;
  static const int _maxPinLength = 6;

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Guarda el PIN del usuario (hasheado básicamente para ofuscación simple)
  Future<void> setPin(String userId, String pin) async {
    if (!_isValidPin(pin)) {
      throw ArgumentError('El PIN debe tener entre $_minPinLength y $_maxPinLength dígitos');
    }
    // Ofuscación simple: no es hash criptográfico, solo para no guardar en claro
    final obfuscated = _obfuscatePin(pin);
    await _storage.write(key: '$_pinPrefix$userId', value: obfuscated);
  }

  /// Verifica si el PIN coincide
  Future<bool> verifyPin(String userId, String pin) async {
    final stored = await _storage.read(key: '$_pinPrefix$userId');
    if (stored == null) return false;
    return _deobfuscatePin(stored) == pin;
  }

  /// Elimina el PIN del usuario
  Future<void> clearPin(String userId) async {
    await _storage.delete(key: '$_pinPrefix$userId');
    await _storage.delete(key: '$_biometricEnabledKey$userId');
  }

  /// Comprueba si el usuario tiene PIN configurado
  Future<bool> hasPin(String userId) async {
    final stored = await _storage.read(key: '$_pinPrefix$userId');
    return stored != null && stored.isNotEmpty;
  }

  /// Obtiene el PIN almacenado (para mostrar en config, solo admin o el propio usuario)
  Future<String?> getPin(String userId) async {
    final stored = await _storage.read(key: '$_pinPrefix$userId');
    if (stored == null) return null;
    return _deobfuscatePin(stored);
  }

  /// Habilita/deshabilita autenticación biométrica para el usuario
  Future<void> setBiometricEnabled(String userId, bool enabled) async {
    await _storage.write(
      key: '$_biometricEnabledKey$userId',
      value: enabled.toString(),
    );
  }

  /// Comprueba si la biometría está habilitada para el usuario
  Future<bool> isBiometricEnabled(String userId) async {
    final value = await _storage.read(key: '$_biometricEnabledKey$userId');
    return value == 'true';
  }

  /// Comprueba si el dispositivo soporta autenticación biométrica
  Future<bool> get isBiometricAvailable async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Obtiene los tipos de biometría disponibles
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Autentica con biometría
  Future<bool> authenticateWithBiometrics({
    required String reason,
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  bool _isValidPin(String pin) {
    final digitsOnly = RegExp(r'^\d+$');
    return digitsOnly.hasMatch(pin) &&
        pin.length >= _minPinLength &&
        pin.length <= _maxPinLength;
  }

  /// Ofuscación simple XOR con clave fija (no es seguridad criptográfica, solo ofuscación)
  String _obfuscatePin(String pin) {
    const key = 0x5A;
    final bytes = pin.codeUnits.map((b) => b ^ key).toList();
    return String.fromCharCodes(bytes);
  }

  String _deobfuscatePin(String obfuscated) {
    const key = 0x5A;
    final bytes = obfuscated.codeUnits.map((b) => b ^ key).toList();
    return String.fromCharCodes(bytes);
  }
}