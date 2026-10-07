import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../data/auth_repository.dart';
import '../domain/user_profile.dart';

/// Pantalla de desbloqueo con PIN o biometría
class PinLockScreen extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onUnlocked;
  final String? reason;

  const PinLockScreen({
    super.key,
    required this.profile,
    required this.onUnlocked,
    this.reason,
  });

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  final _pinCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePin = true;
  bool _isLoading = false;
  String? _error;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  List<BiometricType> _availableBiometrics = [];
  bool _triedBiometric = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
    // Intentar biometría automáticamente si está habilitada
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final repo = ref.read(authRepositoryProvider);
    final available = await repo.isBiometricAvailable;
    final enabled = await repo.isBiometricEnabled(widget.profile.id);
    final types = await repo.getAvailableBiometrics();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _availableBiometrics = types;
      });
    }
  }

  Future<void> _tryBiometric() async {
    if (!_biometricAvailable || !_biometricEnabled || _triedBiometric) return;
    _triedBiometric = true;

    final repo = ref.read(authRepositoryProvider);
    final authenticated = await repo.authenticateWithBiometrics(
      reason: widget.reason ?? 'Autentícate para acceder a la app',
    );

    if (authenticated && mounted) {
      widget.onUnlocked();
    }
  }

  Future<void> _verifyPin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      final ok = await repo.verifyLocalPin(widget.profile.id, _pinCtrl.text);

      if (ok) {
        if (mounted) widget.onUnlocked();
      } else {
        setState(() => _error = 'PIN incorrecto');
      }
    } catch (e) {
      setState(() => _error = 'Error al verificar PIN');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _retryBiometric() async {
    final repo = ref.read(authRepositoryProvider);
    final authenticated = await repo.authenticateWithBiometrics(
      reason: widget.reason ?? 'Autentícate para acceder a la app',
    );

    if (authenticated && mounted) {
      widget.onUnlocked();
    }
  }

  String _getBiometricLabel() {
    if (_availableBiometrics.contains(BiometricType.face)) return 'Face ID';
    if (_availableBiometrics.contains(BiometricType.fingerprint)) return 'Huella dactilar';
    if (_availableBiometrics.contains(BiometricType.strong)) return 'Biometría';
    if (_availableBiometrics.contains(BiometricType.weak)) return 'Biometría';
    if (_availableBiometrics.contains(BiometricType.iris)) return 'Iris';
    return 'Biometría';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _getBiometricLabel();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'App bloqueada',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bienvenido, ${widget.profile.fullName}',
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (widget.reason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.reason!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Biometría
                    if (_biometricAvailable && _biometricEnabled) ...[
                      FilledButton.icon(
                        icon: Icon(_availableBiometrics.contains(BiometricType.face)
                            ? Icons.face
                            : Icons.fingerprint),
                        label: Text('Desbloquear con $label'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor: theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: _isLoading ? null : _retryBiometric,
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                    ],

                    // PIN
                    Text('O ingresa tu PIN', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 18, color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _pinCtrl,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 8),
                      decoration: InputDecoration(
                        hintText: '• • • •',
                        counterText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePin = !_obscurePin),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ingresa tu PIN';
                        if (!RegExp(r'^\d{4,6}$').hasMatch(v)) return 'PIN inválido';
                        return null;
                      },
                      onFieldSubmitted: (_) => _verifyPin(),
                    ),

                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isLoading ? null : _verifyPin,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Desbloquear', style: TextStyle(fontSize: 18)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}