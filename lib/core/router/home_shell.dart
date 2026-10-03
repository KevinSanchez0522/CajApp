import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/pos/presentation/screens/pos_scanner_screen.dart';
import '../../features/pos/presentation/screens/cash_shift_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/add_product_screen.dart';
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

    // Un COLABORADOR no tiene acceso a la pestaña de inventario ni a ingreso de mercancía.
    final tabs = <Widget>[
      const PosScannerScreen(),
      const CashShiftScreen(),
      const InventoryScreen(),
      if (isAdmin) const AddProductScreen(),
    ];

    final icons = <IconData>[
      Icons.qr_code_scanner,
      Icons.point_of_sale,
      Icons.inventory_2,
      if (isAdmin) Icons.add_box,
    ];

    final labels = <String>[
      'POS',
      'Caja',
      'Inventario',
      if (isAdmin) 'Ingresar',
    ];

    // Garantía extra: si el rol cambia a colaborador, se resetea el índice.
    if (!isAdmin && _currentIndex > 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 0);
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex.clamp(0, tabs.length - 1),
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex.clamp(0, tabs.length - 1),
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