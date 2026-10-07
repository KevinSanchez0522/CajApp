import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/pos/presentation/screens/pos_scanner_screen.dart';
import '../../features/pos/presentation/screens/cash_shift_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/user_profile.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider);
    final isAdmin = profile.role == UserRole.admin;

    // COLABORADOR: POS, Caja (Perfil y Config. viven en el menú del logo)
    // ADMIN: POS, Caja, Inventario (Ingresar desde el FAB del inventario)
    final tabs = isAdmin
        ? <Widget>[
            const PosScannerScreen(),
            const CashShiftScreen(),
            const InventoryScreen(),
          ]
        : <Widget>[
            const PosScannerScreen(),
            const CashShiftScreen(),
          ];

    final icons = isAdmin
        ? <IconData>[
            Icons.qr_code_scanner,
            Icons.point_of_sale,
            Icons.inventory_2,
          ]
        : <IconData>[
            Icons.qr_code_scanner,
            Icons.point_of_sale,
          ];

    final labels = isAdmin
        ? <String>[
            'POS',
            'Caja',
            'Inventario',
          ]
        : <String>[
            'POS',
            'Caja',
          ];

    // Reset índice si cambió de rol y el índice actual no existe en el nuevo rol
    final maxIndex = tabs.length - 1;
    if (_currentIndex > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = maxIndex);
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex.clamp(0, maxIndex),
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex.clamp(0, maxIndex),
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          for (int i = 0; i < icons.length; i++)
            NavigationDestination(
              icon: Icon(icons[i]),
              label: labels[i],
            ),
        ],
      ),
    );
  }
}