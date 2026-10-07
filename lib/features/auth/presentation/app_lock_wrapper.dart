import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'pin_lock_screen.dart';
import '../data/auth_repository.dart';
import '../domain/user_profile.dart';

/// Estado del bloqueo de la app
class AppLockState {
  final bool isLocked;
  final String? lockReason;

  const AppLockState({this.isLocked = false, this.lockReason});

  AppLockState copyWith({bool? isLocked, String? lockReason}) {
    return AppLockState(
      isLocked: isLocked ?? this.isLocked,
      lockReason: lockReason ?? this.lockReason,
    );
  }
}

/// Controlador del bloqueo de la app
class AppLockController extends StateNotifier<AppLockState> {
  final AuthRepository _authRepo;
  UserProfile? _currentProfile;
  DateTime? _lastActivity;
  static const Duration _lockTimeout = Duration(minutes: 5); // 5 min de inactividad

  AppLockController(this._authRepo) : super(const AppLockState()) {
    _setupLifecycleListener();
  }

  void _setupLifecycleListener() {
    // Escuchar cambios de ciclo de vida de la app
    SystemChannels.lifecycle.setMessageHandler((message) async {
      switch (message) {
        case 'AppLifecycleState.paused':
        case 'AppLifecycleState.inactive':
        case 'AppLifecycleState.detached':
          _lastActivity = DateTime.now();
          break;
        case 'AppLifecycleState.resumed':
          _checkAutoLock();
          break;
      }
      return null;
    });
  }

  void setCurrentProfile(UserProfile? profile) {
    _currentProfile = profile;
  }

  void recordActivity() {
    _lastActivity = DateTime.now();
  }

  Future<void> _checkAutoLock() async {
    if (_currentProfile == null) return;
    if (!state.isLocked) return;

    final hasPin = await _authRepo.hasLocalPin(_currentProfile!.id);
    if (!hasPin) return;

    // Si ya está bloqueada, mostrar pantalla de desbloqueo
    // La lógica de mostrar la pantalla se maneja en el widget
  }

  /// Verifica si debe bloquearse por inactividad
  bool shouldAutoLock() {
    if (_currentProfile == null) return false;
    if (_lastActivity == null) return false;
    return DateTime.now().difference(_lastActivity!) > _lockTimeout;
  }

  /// Bloquea la app manualmente
  void lockApp({String? reason}) {
    state = state.copyWith(isLocked: true, lockReason: reason);
  }

  /// Desbloquea la app
  void unlockApp() {
    _lastActivity = DateTime.now();
    state = const AppLockState();
  }

  /// Comprueba y bloquea si corresponde (llamar en resume)
  Future<bool> checkAndLock() async {
    if (_currentProfile == null) return false;
    final hasPin = await _authRepo.hasLocalPin(_currentProfile!.id);
    if (!hasPin) return false;

    if (shouldAutoLock()) {
      lockApp(reason: 'Sesión bloqueada por inactividad');
      return true;
    }
    return false;
  }
}

final appLockControllerProvider = StateNotifierProvider<AppLockController, AppLockState>((ref) {
  return AppLockController(ref.watch(authRepositoryProvider));
});

/// Widget que envuelve la app y maneja el bloqueo automático
class AppLockWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final UserProfile? profile;

  const AppLockWrapper({super.key, required this.child, this.profile});

  @override
  ConsumerState<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends ConsumerState<AppLockWrapper> with WidgetsBindingObserver {
  bool _showingLockScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncProfile();
  }

  @override
  void didUpdateWidget(covariant AppLockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = ref.read(appLockControllerProvider.notifier);

    switch (state) {
      case AppLifecycleState.resumed:
        controller.recordActivity();
        _checkLock();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        controller.recordActivity();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _syncProfile() {
    ref.read(appLockControllerProvider.notifier).setCurrentProfile(widget.profile);
  }

  Future<void> _checkLock() async {
    final shouldLock = await ref.read(appLockControllerProvider.notifier).checkAndLock();
    if (shouldLock && mounted && !_showingLockScreen) {
      _showLockScreen();
    }
  }

  void _showLockScreen() {
    if (_showingLockScreen) return;
    _showingLockScreen = true;

    final lockState = ref.read(appLockControllerProvider);
    final profile = widget.profile;

    if (profile == null) {
      _showingLockScreen = false;
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: PinLockScreen(
          profile: profile,
          reason: lockState.lockReason,
          onUnlocked: () {
            ref.read(appLockControllerProvider.notifier).unlockApp();
            _showingLockScreen = false;
            Navigator.of(ctx).pop();
          },
        ),
      ),
    ).then((_) {
      _showingLockScreen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escuchar actividad del usuario
    return Listener(
      onPointerDown: (_) => ref.read(appLockControllerProvider.notifier).recordActivity(),
      onPointerMove: (_) => ref.read(appLockControllerProvider.notifier).recordActivity(),
      child: widget.child,
    );
  }
}