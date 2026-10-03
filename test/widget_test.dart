// Smoke test: valida que el shell principal de la app se monta correctamente.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloth_inventory_pos/app.dart';

void main() {
  testWidgets('La app renderiza el shell principal', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ClothPosApp()));
    await tester.pump();
    // Deja completar las latencias simuladas de los repositorios en modo demo
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('BOUTIQUE FASHION'), findsOneWidget);
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Caja'), findsOneWidget);
    expect(find.text('Inventario'), findsOneWidget);
    // El ingreso de mercancía solo existe para el rol ADMIN
    expect(find.text('Ingresar'), findsOneWidget);
  });
}