import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloth_inventory_pos/app.dart';
import 'package:cloth_inventory_pos/features/inventory/data/inventory_repository.dart';
import 'package:cloth_inventory_pos/core/config/supabase_config.dart';

void main() {
  testWidgets('A: Ingreso de mercancía sin overflow ni error de categorías',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2160); // pantalla de móvil real
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: ClothPosApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final err = find.textContaining('Error al cargar categorías');
    // ignore: avoid_print
    print('A) errorUI=${err.evaluate().isNotEmpty}');
    expect(err, findsNothing);
  });

  testWidgets('B: Dropdown de categorías con tamaño de móvil', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: ClothPosApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final dropdown = find.byType(DropdownButtonFormField<String>);
    // ignore: avoid_print
    print('B) dropdownes=${dropdown.evaluate().length}');
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('B) Camisas=${find.text('Camisas').evaluate().isNotEmpty}');
  });

  test('C: modo demo activo', () {
    // ignore: avoid_print
    print('C) isDemoMode=${SupabaseConfig.isDemoMode} initialized=${SupabaseConfig.isInitialized}');
  });

  test('D: categorías del repositorio', () async {
    final cats = await InventoryRepository().fetchCategories();
    // ignore: avoid_print
    print('D) ${cats.map((c) => '${c.id}/${c.name}').toList()}');
  });
}