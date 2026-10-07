import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../data/auth_repository.dart';
import '../domain/user_profile.dart';

/// Pantalla para configurar o cambiar el PIN local
class PinSetupScreen extends ConsumerStatefulWidget {
  final UserProfile profile;
  final bool isChangePin; // true si es cambio, false si es configuración inicial

  const PinSetupScreen({
    super.key,
    required this.profile,
    this.isChangePin = false,
  });

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePin = true;
  bool _obscureConfirm = true;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pinCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Los PINs no coinciden');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.setLocalPin(widget.profile.id, _pinCtrl.text);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isChangePin
              ? 'PIN actualizado correctamente'
              : 'PIN configurado correctamente'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removePin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar PIN'),
        content: const Text('¿Estás seguro de querer eliminar el PIN local?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.clearLocalPin(widget.profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN eliminado'), behavior: SnackBarBehavior.floating),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangePin ? 'Cambiar PIN' : 'Configurar PIN'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.isChangePin
                      ? 'Ingresa tu nuevo PIN de 4-6 dígitos'
                      : 'Crea un PIN de 4-6 dígitos para desbloqueo rápido',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),

                if (_error != null) ...[
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _pinCtrl,
                  obscureText: _obscurePin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Nuevo PIN',
                    hintText: '4-6 dígitos',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePin = !_obscurePin),
                    ),
                    counterText: '',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Ingresa un PIN';
                    if (!RegExp(r'^\d{4,6}$').hasMatch(v)) return 'El PIN debe tener 4-6 dígitos';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Confirmar PIN',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    counterText: '',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirma el PIN';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _isLoading ? null : _savePin,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.isChangePin ? 'Actualizar PIN' : 'Guardar PIN'),
                ),

                if (widget.isChangePin) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar PIN'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _isLoading ? null : _removePin,
                  ),
                ],

                const SizedBox(height: 24),
                _BiometricSection(profile: widget.profile),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sección de configuración biométrica
class _BiometricSection extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _BiometricSection({required this.profile});

  @override
  ConsumerState<_BiometricSection> createState() => _BiometricSectionState();
}

class _BiometricSectionState extends ConsumerState<_BiometricSection> {
  bool _biometricEnabled = false;
  bool _isLoading = true;
  bool _biometricAvailable = false;
  List<BiometricType> _availableBiometrics = [];

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
  }

  Future<void> _loadBiometricSettings() async {
    final repo = ref.read(authRepositoryProvider);
    final available = await repo.isBiometricAvailable;
    final enabled = await repo.isBiometricEnabled(widget.profile.id);
    final types = await repo.getAvailableBiometrics();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _availableBiometrics = types;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!value) {
      // Deshabilitar directamente
      await ref.read(authRepositoryProvider).setBiometricEnabled(widget.profile.id, false);
      setState(() => _biometricEnabled = false);
      return;
    }

    // Habilitar: probar autenticación primero
    final repo = ref.read(authRepositoryProvider);
    final authenticated = await repo.authenticateWithBiometrics(
      reason: 'Confirma tu identidad para activar el desbloqueo biométrico',
    );

    if (authenticated) {
      await repo.setBiometricEnabled(widget.profile.id, true);
      setState(() => _biometricEnabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometría activada'), behavior: SnackBarBehavior.floating),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Autenticación biométrica fallida'), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  String _getBiometricLabel() {
    if (_availableBiometrics.contains(BiometricType.face)) return 'Face ID';
    if (_availableBiometrics.contains(BiometricType.fingerprint)) return 'Huella dactilar';
    if (_availableBiometrics.contains(BiometricType.strong)) return 'Biometría fuerte';
    if (_availableBiometrics.contains(BiometricType.weak)) return 'Biometría básica';
    if (_availableBiometrics.contains(BiometricType.iris)) return 'Iris';
    return 'Biometría';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    if (!_biometricAvailable) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final label = _getBiometricLabel();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Desbloqueo biométrico', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Usa $label para desbloquear la app rápidamente',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text('Activar $label'),
              subtitle: Text(_biometricEnabled ? 'Activo' : 'Inactivo'),
              value: _biometricEnabled,
              onChanged: _toggleBiometric,
            ),
          ],
        ),
      ),
    );
  }
}