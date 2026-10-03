import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloth_inventory_pos/app.dart';

/// Regresión de layout: ninguna pantalla debe desbordar (RenderFlex overflow)
/// en los anchos de móvil más comunes, incluidos los más estrechos.
void main() {
  const tamanos = <Size>[
    Size(800, 600), // viewport por defecto de flutter_test
    Size(412, 915), // Android típico
    Size(393, 852), // Pixel
    Size(375, 812), // iPhone X
    Size(360, 800),
    Size(360, 640),
    Size(320, 568), // iPhone SE 1ra gen (el que fallaba)
  ];

  for (final size in tamanos) {
    testWidgets(
        'Sin overflow en todas las pestañas @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final captured = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = captured.add;

      await tester.pumpWidget(const ProviderScope(child: ClothPosApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      for (final tab in ['POS', 'Caja', 'Inventario', 'Ingresar']) {
        final f = find.text(tab);
        if (f.evaluate().isEmpty) continue;
        await tester.tap(f);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
      }

      // Restaura el handler antes de assertar para no enmascarar el resultado.
      FlutterError.onError = original;
      addTearDown(() => FlutterError.onError = original);

      final mensajes = captured
          .map((d) {
            final m = RegExp(r'lib[\\/][\w\\/]+\.dart:\d+:\d+')
                .firstMatch(d.toString());
            return '${d.exceptionAsString().split('\n').first} ${m?.group(0) ?? ''}';
          })
          .toList();

      // ignore: avoid_print
      print('SIZE=${size.width.toInt()} ERRORES=${mensajes.length}');
      for (final m in mensajes) {
        // ignore: avoid_print
        print('  $m');
      }

      expect(mensajes, isEmpty, reason: 'Sin RenderFlex overflow esperado');
    });
  }

  testWidgets('Las categorías cargan y son seleccionables', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: ClothPosApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    // Nunca debe mostrarse el error crudo de categorías en modo demo.
    expect(find.textContaining('Error al cargar categorías'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Camisas'), findsOneWidget);
    expect(find.text('Pantalones'), findsOneWidget);
  });
}