import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import 'pin_setup_screen.dart';

/// Pantalla de configuración de perfil y seguridad
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info del usuario
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.fullName, style: theme.textTheme.titleLarge),
                        Text(profile.email, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Chip(
                          label: Text(profile.role.name.toUpperCase()),
                          backgroundColor: profile.isAdmin
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.secondaryContainer,
                          labelStyle: TextStyle(
                            color: profile.isAdmin
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Seguridad
          Text('Seguridad', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                _SettingsTile(
                  leading: Icon(Icons.pin, color: theme.colorScheme.primary),
                  title: 'PIN de desbloqueo',
                  subtitle: profile.hasLocalPin
                      ? 'PIN configurado • Toca para cambiar'
                      : 'No configurado • Toca para crear',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PinSetupScreen(
                        profile: profile,
                        isChangePin: profile.hasLocalPin,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  leading: Icon(Icons.fingerprint, color: theme.colorScheme.primary),
                  title: 'Desbloqueo biométrico',
                  subtitle: 'Face ID / Huella dactilar',
                  trailing: Consumer(
                    builder: (context, ref, _) {
                      return FutureBuilder<bool>(
                        future: ref.read(authRepositoryProvider).isBiometricEnabled(profile.id),
                        builder: (context, snapshot) {
                          final enabled = snapshot.data ?? false;
                          return Switch(
                            value: enabled,
                            onChanged: (value) async {
                              final repo = ref.read(authRepositoryProvider);
                              if (value) {
                                final authenticated = await repo.authenticateWithBiometrics(
                                  reason: 'Confirma tu identidad para activar biometría',
                                );
                                if (authenticated) {
                                  await repo.setBiometricEnabled(profile.id, true);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Biometría activada'), behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                }
                              } else {
                                await repo.setBiometricEnabled(profile.id, false);
                              }
                              // Forzar rebuild (solo si el widget sigue vivo:
                              // esto va después de varios `await`).
                              if (context.mounted) {
                                ref.invalidate(currentUserProfileProvider);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Configuración de la app
          Text('Aplicación', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                _SettingsTile(
                  leading: Icon(Icons.lock_clock, color: theme.colorScheme.primary),
                  title: 'Bloqueo automático',
                  subtitle: '5 minutos de inactividad',
                  trailing: const Icon(Icons.info_outline),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Bloqueo automático'),
                        content: const Text(
                          'La app se bloquea automáticamente después de 5 minutos de inactividad. '
                          'Requiere PIN o biometría para desbloquear.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  leading: Icon(Icons.palette, color: theme.colorScheme.primary),
                  title: 'Tema de la app',
                  subtitle: 'Claro / Oscuro / Sistema',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Implementar selector de tema
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Próximamente'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Info de la app
          Text('Información', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                _SettingsTile(
                  leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  title: 'Versión de la app',
                  subtitle: '1.0.0+1',
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  leading: Icon(Icons.description, color: theme.colorScheme.primary),
                  title: 'Licencias de código abierto',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(context: context, applicationName: 'Cloth POS'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}