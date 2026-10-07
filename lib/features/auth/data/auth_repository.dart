import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/user_profile.dart';
import 'pin_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(const FlutterSecureStorage(), ref.watch(pinServiceProvider));
});

final pinServiceProvider = Provider<PinService>((ref) => PinService());

// --------------------------------------------------------------------------
// Estado de sesión
// --------------------------------------------------------------------------

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthSession {
  final AuthStatus status;
  final UserProfile? profile;
  final String? error;

  const AuthSession._(this.status, {this.profile, this.error});

  const AuthSession.loading() : this._(AuthStatus.loading);

  const AuthSession.authenticated(UserProfile profile)
      : this._(AuthStatus.authenticated, profile: profile);

  const AuthSession.unauthenticated({String? error})
      : this._(AuthStatus.unauthenticated, error: error);

  bool get isAuthenticated => status == AuthStatus.authenticated;

  UserProfile? get roleProfile => profile;
}

final sessionProvider =
    StateNotifierProvider<SessionController, AuthSession>((ref) {
  return SessionController(ref.watch(authRepositoryProvider));
});

/// Perfil del usuario actual. Mantiene compatibilidad con los widgets que
/// sólo necesitan el perfil (RBAC de UI) sin depender del estado completo
/// de la sesión.
final currentUserProfileProvider = Provider<UserProfile>((ref) {
  final session = ref.watch(sessionProvider);
  return session.profile ?? AuthRepository.demoAdminProfile;
});

// --------------------------------------------------------------------------
// Controlador de sesión
// --------------------------------------------------------------------------

class SessionController extends StateNotifier<AuthSession> {
  final AuthRepository _repo;
  StreamSubscription<AuthState>? _sub;

  SessionController(this._repo) : super(const AuthSession.loading()) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Modo demo: entro directamente con el perfil simulado (sin backend).
    if (SupabaseConfig.isDemoMode || !SupabaseConfig.isInitialized) {
      final persisted = await _repo.getPersistedProfile();
      state = AuthSession.authenticated(
        persisted ?? AuthRepository.demoAdminProfile,
      );
      return;
    }

    // Backend real: escucho cambios de sesión de Supabase.
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        state = const AuthSession.unauthenticated();
      } else {
        _hydrateProfile();
      }
    });

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      state = const AuthSession.unauthenticated();
      return;
    }
    await _hydrateProfile();
  }

  Future<void> _hydrateProfile() async {
    try {
      final profile = await _repo.fetchProfileFromBackend();
      state = AuthSession.authenticated(profile);
    } on AppException catch (e) {
      state = AuthSession.unauthenticated(error: e.message);
    } catch (e) {
      state = AuthSession.unauthenticated(
        error: mapErrorToAppException(e, contexto: 'No se pudo leer el perfil')
            .message,
      );
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = const AuthSession.loading();
    try {
      await _repo.signIn(email, password);
      await _hydrateProfile();
      return true;
    } catch (e) {
      final ex = mapErrorToAppException(e, contexto: 'Inicio de sesión');
      state = AuthSession.unauthenticated(error: ex.message);
      return false;
    }
  }

  Future<bool> signUp(String email, String password, String fullName) async {
    state = const AuthSession.loading();
    try {
      await _repo.signUp(email, password, fullName);
      return true;
    } catch (e) {
      final ex = mapErrorToAppException(e, contexto: 'Registro');
      state = AuthSession.unauthenticated(error: ex.message);
      return false;
    }
  }

  Future<void> signOut() async {
    if (!SupabaseConfig.isDemoMode && SupabaseConfig.isInitialized) {
      try {
        await _repo.signOutRemote();
      } catch (_) {
        // Ignoramos: la sesión local se limpia igualmente.
      }
    }
    await _repo.clearPersistedProfile();
    if (SupabaseConfig.isDemoMode || !SupabaseConfig.isInitialized) {
      state = AuthSession.authenticated(AuthRepository.demoAdminProfile);
    } else {
      state = const AuthSession.unauthenticated();
    }
  }

  /// Cambio de rol rápido, sólo disponible en modo demo.
  Future<void> switchDemoRole(UserRole role) async {
    if (!SupabaseConfig.isDemoMode) return;
    final profile = role == UserRole.admin
        ? AuthRepository.demoAdminProfile
        : AuthRepository.demoColaboradorProfile;
    await _repo.persistProfile(profile);
    state = AuthSession.authenticated(profile);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// --------------------------------------------------------------------------
// Repositorio
// --------------------------------------------------------------------------

class AuthRepository {
  final FlutterSecureStorage _storage;
  final PinService _pinService;

  AuthRepository(this._storage, this._pinService);

  static const UserProfile demoAdminProfile = UserProfile(
    id: 'admin-001-uuid',
    email: 'admin@boutique.com',
    fullName: 'Administrador de Tienda',
    role: UserRole.admin,
    isActive: true,
  );

  static const UserProfile demoColaboradorProfile = UserProfile(
    id: 'colab-002-uuid',
    email: 'cajero@boutique.com',
    fullName: 'Carlos Cajero',
    role: UserRole.colaborador,
    isActive: true,
  );

  // ---------- Gestión de PIN local ----------

  /// Configura el PIN local para el usuario actual
  Future<void> setLocalPin(String userId, String pin) async {
    await _pinService.setPin(userId, pin);
  }

  /// Verifica el PIN local
  Future<bool> verifyLocalPin(String userId, String pin) async {
    return await _pinService.verifyPin(userId, pin);
  }

  /// Elimina el PIN local
  Future<void> clearLocalPin(String userId) async {
    await _pinService.clearPin(userId);
  }

  /// Comprueba si el usuario tiene PIN configurado
  Future<bool> hasLocalPin(String userId) async {
    return await _pinService.hasPin(userId);
  }

  /// Obtiene el PIN almacenado (solo para admin o el propio usuario)
  Future<String?> getLocalPin(String userId) async {
    return await _pinService.getPin(userId);
  }

  /// Habilita/deshabilita biometría
  Future<void> setBiometricEnabled(String userId, bool enabled) async {
    await _pinService.setBiometricEnabled(userId, enabled);
  }

  Future<bool> isBiometricEnabled(String userId) async {
    return await _pinService.isBiometricEnabled(userId);
  }

  Future<bool> get isBiometricAvailable async {
    return await _pinService.isBiometricAvailable;
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    return await _pinService.getAvailableBiometrics();
  }

  Future<bool> authenticateWithBiometrics({
    required String reason,
  }) async {
    return await _pinService.authenticateWithBiometrics(reason: reason);
  }

  // ---------- Sesión remota ----------

  Future<void> signIn(String email, String password) async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp(String email, String password, String fullName) async {
    final res = await Supabase.instance.client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: null,
      data: {'full_name': fullName.trim()},
    );
    if (res.user == null) {
      throw const AppException('No se pudo crear la cuenta. Intenta de nuevo.');
    }
  }

  Future<void> signOutRemote() async {
    await Supabase.instance.client.auth.signOut();
  }

  /// Lee el perfil del usuario autenticado desde `public.profiles`.
  Future<UserProfile> fetchProfileFromBackend() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AppException('No hay sesión activa.');
    }

    final res = await Supabase.instance.client
        .from('profiles')
        .select('id, email, full_name, role, is_active')
        .eq('id', userId)
        .maybeSingle();

    if (res == null) {
      // El usuario existe en auth.users pero no tiene fila en profiles:
      // creamos una perfil COLABORADOR para que la app sea utilizable.
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      final fullName = (Supabase.instance.client.auth.currentUser
                  ?.userMetadata?['full_name'] as String?) ??
              email.split('@').first;
      final nuevo = <String, dynamic>{
        'id': userId,
        'email': email,
        'full_name': fullName,
        'role': 'COLABORADOR',
        'is_active': true,
      };
      final creado = await Supabase.instance.client
          .from('profiles')
          .insert(nuevo)
          .select('id, email, full_name, role, is_active')
          .single();
      return UserProfile.fromJson(creado);
    }

    return UserProfile.fromJson(res);
  }

  // ---------- Persistencia local (modo demo) ----------

  Future<UserProfile?> getPersistedProfile() async {
    try {
      final roleStr = await _storage.read(key: 'current_user_role');
      final profile = roleStr == 'colaborador' ? demoColaboradorProfile : demoAdminProfile;
      // En modo demo, intentamos cargar el PIN si existe
      final pin = await _pinService.getPin(profile.id);
      return profile.copyWith(localPin: pin);
    } catch (_) {
      return null;
    }
  }

  Future<void> persistProfile(UserProfile profile) async {
    try {
      await _storage.write(
        key: 'current_user_role',
        value: profile.role.name,
      );
    } catch (_) {}
  }

  Future<void> clearPersistedProfile() async {
    try {
      await _storage.delete(key: 'current_user_role');
    } catch (_) {}
  }
}