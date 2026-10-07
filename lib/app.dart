import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/supabase_config.dart';
import 'core/router/home_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/domain/user_profile.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/profile_screen.dart';
import 'features/auth/presentation/app_lock_wrapper.dart';
import 'features/settings/presentation/report_settings_screen.dart';

class ClothPosApp extends StatelessWidget {
  const ClothPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VERSATIL FRESH BOUTIQUE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const _AppEntry(),
    );
  }
}

class _AppEntry extends ConsumerWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    // while initializing we still render the shell in demo mode so the app
    // remains usable; with a real backend we show a splash screen.
    final showLogin =
        !SupabaseConfig.isDemoMode && session.status == AuthStatus.unauthenticated;

    // Evitar mostrar splash interno mientras carga
    if (session.status == AuthStatus.loading) {
      if (SupabaseConfig.isDemoMode) {
        return const AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: Scaffold(body: HomeShell()),
        );
      }
      if (SupabaseConfig.isInitialized) {
        return const ColoredBox(color: Colors.white);
      }
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: showLogin
            ? LoginScreen(initialError: session.error)
            : Column(
                children: [
                  const _BackendWarning(),
                  _AppHeader(profile: session.profile),
                  Expanded(
                    child: AppLockWrapper(
                      profile: session.profile,
                      child: const HomeShell(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Aviso no bloqueante cuando el backend no está disponible.
/// Antes la app caía a modo demo en silencio y el usuario no entendía por qué
/// no cargaban las categorías.
class _BackendWarning extends ConsumerStatefulWidget {
  const _BackendWarning();

  @override
  ConsumerState<_BackendWarning> createState() => _BackendWarningState();
}

class _BackendWarningState extends ConsumerState<_BackendWarning> {
  String? _message;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (!SupabaseConfig.isDemoMode) _verify();
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final error = await SupabaseConfig.verifyBackend();
    if (!mounted) return;
    setState(() {
      _message = error?.message;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (SupabaseConfig.isDemoMode) return const SizedBox.shrink();

    if (_message == null) {
      return _checking
          ? const LinearProgressIndicator(minHeight: 2)
          : const SizedBox.shrink();
    }

    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _message!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: _verify,
              child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}



class _AppHeader extends ConsumerWidget {
  const _AppHeader({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = profile ?? AuthRepository.demoAdminProfile;
    final isDemo = SupabaseConfig.isDemoMode;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primary,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 8,
        left: 16,
        right: 8,
      ),
      child: PopupMenuButton<_HeaderAction>(
        onSelected: (action) => _onMenuAction(context, ref, action, isDemo),
        tooltip: 'Menú',
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: _HeaderAction.perfil,
            child: Row(children: [
              Icon(Icons.person_outline, size: 20),
              SizedBox(width: 10),
              Text('Mi perfil'),
            ]),
          ),
          const PopupMenuItem(
            value: _HeaderAction.config,
            child: Row(children: [
              Icon(Icons.settings_outlined, size: 20),
              SizedBox(width: 10),
              Text('Configuración'),
            ]),
          ),
          const PopupMenuDivider(),
          if (!isDemo)
            const PopupMenuItem(
              value: _HeaderAction.cambiarUsuario,
              child: Row(children: [
                Icon(Icons.logout, size: 20),
                SizedBox(width: 10),
                Text('Cambiar de usuario'),
              ]),
            ),
          if (isDemo) ...[
            const PopupMenuItem(
              value: _HeaderAction.demoAdmin,
              child: Text('Entrar como ADMIN'),
            ),
            const PopupMenuItem(
              value: _HeaderAction.demoColab,
              child: Text('Entrar como COLABORADOR'),
            ),
          ],
        ],
        child: Row(
          children: [
            const Icon(Icons.storefront, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VERSATIL FRESH BOUTIQUE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${current.fullName} · ${current.role.name.toUpperCase()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenuAction(
    BuildContext context,
    WidgetRef ref,
    _HeaderAction action,
    bool isDemo,
  ) async {
    if (action == _HeaderAction.perfil) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    } else if (action == _HeaderAction.config) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReportSettingsScreen()),
      );
    } else if (action == _HeaderAction.cambiarUsuario) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cambiar de usuario'),
          content: const Text(
              'Se cerrará la sesión actual y volverás a la pantalla de acceso.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        ref.read(sessionProvider.notifier).signOut();
      }
    } else if (action == _HeaderAction.demoAdmin) {
      ref.read(sessionProvider.notifier).switchDemoRole(UserRole.admin);
    } else if (action == _HeaderAction.demoColab) {
      ref.read(sessionProvider.notifier).switchDemoRole(UserRole.colaborador);
    }
  }
}

enum _HeaderAction { perfil, config, cambiarUsuario, demoAdmin, demoColab }