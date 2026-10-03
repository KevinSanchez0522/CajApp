import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloth_inventory_pos/app.dart';

void main() {
  testWidgets('Qué pestaña desborda a 320dp', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
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
      captured.clear();
      await tester.tap(f);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      // ignore: avoid_print
      print('TAB=$tab ERRORES=${captured.length}');
      for (final d in captured) {
        final m = RegExp(r'lib[\\/][\w\\/]+\.dart:\d+:\d+').firstMatch(d.toString());
        // ignore: avoid_print
        print('   ${d.exceptionAsString().split('\n').first} @ ${m?.group(0) ?? '?'}');
      }
    }

    FlutterError.onError = original;
    addTearDown(() => FlutterError.onError = original);
  });
}