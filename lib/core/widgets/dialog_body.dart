import 'package:flutter/material.dart';

/// Contenido de un diálogo que es dueño de sus [TextEditingController].
///
/// Tiene la misma forma que `StatefulBuilder`, pero libera los controllers en
/// su propio `dispose()`, es decir, exactamente cuando el `AlertDialog` deja
/// de existir.
///
/// Esto es importante porque `showDialog` se resuelve en el momento del `pop`
/// de la ruta, ANTES de que termine la animación de salida y el diálogo se
/// desmonte. Si se dispusieran los controllers justo ahí, el `TextFormField`
/// seguiría montado y, al reconstruirse, recibiría un controller ya destruido
/// ("A TextEditingController was used after being disposed"), lo que corrompe el
/// árbol y provoca la pantalla roja con `_dependents.isEmpty`.
class DialogBody extends StatefulWidget {
  const DialogBody({
    super.key,
    required this.controllers,
    required this.builder,
  });

  /// Controllers que debe liberar este widget al desmontarse.
  final List<TextEditingController> controllers;

  /// Mismo contrato que el `builder` de `StatefulBuilder`.
  final Widget Function(BuildContext, void Function(void Function())) builder;

  @override
  State<DialogBody> createState() => _DialogBodyState();
}

class _DialogBodyState extends State<DialogBody> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}
