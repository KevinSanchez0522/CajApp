import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/supabase_config.dart';
import 'core/router/home_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/domain/user_profile.dart';
import 'features/auth/presentation/login_screen.dart';

class ClothPosApp extends StatelessWidget {
  const ClothPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloth POS',
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

    if (session.status == AuthStatus.loading &&
        SupabaseConfig.isInitialized &&
        !SupabaseConfig.isDemoMode) {
      return const _SplashScreen();
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
                  const Expanded(child: HomeShell()),
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

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Conectando con el servidor…'),
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
      child: Row(
        children: [
          const Icon(Icons.storefront, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BOUTIQUE FASHION',
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
          if (isDemo)
            PopupMenuButton<UserRole>(
              icon: const Icon(Icons.switch_account, color: Colors.white),
              tooltip: 'Cambiar rol (demo)',
              onSelected: (role) =>
                  ref.read(sessionProvider.notifier).switchDemoRole(role),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: UserRole.admin,
                  child: Text('Entrar como ADMIN'),
                ),
                PopupMenuItem(
                  value: UserRole.colaborador,
                  child: Text('Entrar como COLABORADOR'),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              tooltip: 'Cerrar sesión',
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            ),
        ],
      ),
    );
  }
}