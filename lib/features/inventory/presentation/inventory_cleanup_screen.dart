import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/dialog_body.dart';
import '../../auth/data/admin_pin.dart';
import '../data/inventory_repository.dart';
import '../domain/category.dart';
import '../domain/product.dart';
import '../domain/product_variant.dart';

/// Limpieza masiva de inventario.
///
/// Saca la lista de prendas candidatas (agotadas y/o sin ventas en los últimos
/// N días), deja marcar cuáles a mano y las elimina de una sola pasada
/// exigiendo el PIN de administrador.
///
/// El borrado es el mismo que el de la ficha de prenda: si la prenda no tiene
/// ventas se borra de verdad; si las tiene, la restricción `ON DELETE RESTRICT`
/// obliga a pasar a borrado lógico (`is_active = false`), con lo que
/// desaparece del inventario y del POS sin romper el histórico de ventas.
class InventoryCleanupScreen extends ConsumerStatefulWidget {
  const InventoryCleanupScreen({super.key});

  @override
  ConsumerState<InventoryCleanupScreen> createState() =>
      _InventoryCleanupScreenState();
}

class _InventoryCleanupScreenState
    extends ConsumerState<InventoryCleanupScreen> {
  /// Solo prendas cuyo stock total es 0.
  bool _onlyOutOfStock = false;

  /// Solo prendas sin ventas en la ventana elegida.
  bool _withoutRecentSales = false;

  /// Ventana de "sin ventas", en días.
  int _days = 90;

  /// Prendas marcadas por el usuario (se conservan aunque cambien los filtros).
  final Set<String> _selected = {};

  static const _dayOptions = [30, 60, 90, 180];

  /// Clave para [recentSaleVariantIdsProvider]: 0 = no consultar ventas.
  int get _saleWindowDays => _withoutRecentSales ? _days : 0;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final variantsAsync = ref.watch(variantsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final soldAsync = ref.watch(recentSaleVariantIdsProvider(_saleWindowDays));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Limpiar inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBox(
          message: 'No se pudo cargar el inventario: $e',
          onRetry: _refresh,
        ),
        data: (products) {
          // Sin variantes todavía no se puede calcular el stock: mejor no
          // mostrar la lista con todo en "agotada".
          if (variantsAsync.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Con el filtro de ventas activo, no se filtra nada hasta tener la
          // respuesta: filtrar sobre un conjunto vacío haría creer que nada
          // se vendió y podría llevar a borrar prendas que sí se vendieron.
          if (_withoutRecentSales && soldAsync.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_withoutRecentSales && soldAsync.hasError) {
            return _ErrorBox(
              message:
                  'No se pudieron consultar las ventas recientes:\n'
                  '${soldAsync.error}',
              onRetry: _refresh,
            );
          }

          final variants =
              variantsAsync.valueOrNull ?? const <ProductVariant>[];
          final categories =
              categoriesAsync.valueOrNull ?? const <ProductCategory>[];
          final soldIds = soldAsync.valueOrNull ?? const <String>{};

          final rows = _filterRows(products, variants, categories, soldIds);
          final visibleSelected =
              rows.where((r) => _selected.contains(r.product.id)).length;

          return Column(
            children: [
              _filtersCard(),
              _statusLine(
                total: rows.length,
                selected: visibleSelected,
                salesChecked: !_withoutRecentSales,
              ),
              Expanded(
                child: rows.isEmpty
                    ? const _EmptyBox(
                        text: 'Ninguna prenda coincide con los filtros.',
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _tile(rows[i]),
                      ),
              ),
              _deleteBar(visibleSelected),
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Datos
  // --------------------------------------------------------------------------

  void _refresh() {
    ref.invalidate(productsProvider);
    ref.invalidate(variantsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(recentSaleVariantIdsProvider);
  }

  void _toggle(String productId) {
    setState(() {
      if (!_selected.remove(productId)) _selected.add(productId);
    });
  }

  /// Aplica los filtros activos sobre el inventario cargado.
  ///
  /// Los filtros se combinan en **Y**: si ambos están activos solo pasan las
  /// prendas agotadas que tampoco se vendieron en la ventana. Con los dos
  /// apagados se devuelve el inventario completo para selección manual.
  List<_CleanupRow> _filterRows(
    List<Product> products,
    List<ProductVariant> variants,
    List<ProductCategory> categories,
    Set<String> soldIds,
  ) {
    final variantsByProduct = <String, List<ProductVariant>>{};
    for (final v in variants) {
      variantsByProduct
          .putIfAbsent(v.productId, () => <ProductVariant>[])
          .add(v);
    }
    final categoryNameById = {for (final c in categories) c.id: c.name};

    final rows = <_CleanupRow>[];
    for (final p in products) {
      final vs = variantsByProduct[p.id] ?? const <ProductVariant>[];
      final stock = vs.fold<int>(0, (s, v) => s + v.currentStock);
      final soldRecently = vs.any((v) => soldIds.contains(v.id));

      if (_onlyOutOfStock && stock > 0) continue;
      if (_withoutRecentSales && soldRecently) continue;

      rows.add(_CleanupRow(
        product: p,
        stock: stock,
        soldRecently: soldRecently,
        variantCount: vs.length,
        categoryName: categoryNameById[p.categoryId] ?? '',
      ));
    }

    rows.sort((a, b) => a.product.name
        .toLowerCase()
        .compareTo(b.product.name.toLowerCase()));
    return rows;
  }

  // --------------------------------------------------------------------------
  // UI: filtros y estado
  // --------------------------------------------------------------------------

  Widget _filtersCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filtros', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    avatar: const Icon(Icons.remove_shopping_cart, size: 16),
                    label: const Text('Agotadas (stock 0)'),
                    selected: _onlyOutOfStock,
                    onSelected: (v) => setState(() => _onlyOutOfStock = v),
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.timelapse, size: 16),
                    label: Text('Sin ventas en $_days días'),
                    selected: _withoutRecentSales,
                    onSelected: (v) =>
                        setState(() => _withoutRecentSales = v),
                  ),
                  if (_withoutRecentSales)
                    DropdownButton<int>(
                      value: _days,
                      isDense: true,
                      items: [
                        for (final d in _dayOptions)
                          DropdownMenuItem(value: d, child: Text('$d días')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _days = v);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Los filtros se combinan en Y. Con los dos apagados ves todo '
                'el inventario y seleccionas a mano.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine({
    required int total,
    required int selected,
    required bool salesChecked,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$total ${total == 1 ? 'prenda' : 'prendas'} en la lista'
              '${salesChecked ? '' : ' · sin verificar ventas'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (selected > 0)
            Text(
              '$selected seleccionada${selected == 1 ? '' : 's'}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI: lista
  // --------------------------------------------------------------------------

  Widget _tile(_CleanupRow row) {
    final checked = _selected.contains(row.product.id);
    final tags = <Widget>[
      if (row.stock <= 0)
        const _Tag(text: 'Agotada', color: Color(0xFFC62828)),
      if (_withoutRecentSales && !row.soldRecently)
        _Tag(text: 'Sin ventas $_days d', color: Color(0xFFEF6C00)),
    ];

    return CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      onChanged: (_) => _toggle(row.product.id),
      title: Row(
        children: [
          _thumb(row.product.imageUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            [
              if (row.categoryName.isNotEmpty) row.categoryName,
              '${row.variantCount} ${row.variantCount == 1 ? 'variante' : 'variantes'}',
              'Stock: ${row.stock}',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: tags),
          ],
        ],
      ),
    );
  }

  Widget _thumb(String? imageUrl) {
    final isNetwork = imageUrl != null &&
        (imageUrl.startsWith('http://') || imageUrl.startsWith('https://'));

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: isNetwork
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.checkroom, size: 20, color: Colors.grey),
            )
          : const Icon(Icons.checkroom, size: 20, color: Colors.grey),
    );
  }

  // --------------------------------------------------------------------------
  // UI: barra de borrado
  // --------------------------------------------------------------------------

  Widget _deleteBar(int selected) {
    final enabled = selected > 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
          onPressed: enabled ? _confirmDelete : null,
          icon: const Icon(Icons.delete_sweep),
          label: Text(
            enabled
                ? 'Eliminar $selected seleccionada${selected == 1 ? '' : 's'}'
                : 'Selecciona las prendas a eliminar',
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Borrado
  // --------------------------------------------------------------------------

  Future<void> _confirmDelete() async {
    // Se releen con ref.read: el diálogo se abre una sola vez y no debe
    // reconstruirse si cambian los filtros por debajo.
    final products =
        ref.read(productsProvider).valueOrNull ?? const <Product>[];
    final variants =
        ref.read(variantsProvider).valueOrNull ?? const <ProductVariant>[];
    final categories =
        ref.read(categoriesProvider).valueOrNull ?? const <ProductCategory>[];
    final soldIds =
        ref.read(recentSaleVariantIdsProvider(_saleWindowDays)).valueOrNull ??
            const <String>{};

    final targets = _filterRows(products, variants, categories, soldIds)
        .where((r) => _selected.contains(r.product.id))
        .toList();
    if (targets.isEmpty) return;

    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var errorText = '';

    await showDialog<void>(
      context: context,
      builder: (_) => DialogBody(
        controllers: [pinController],
        builder: (dialogCtx, setDialogState) {
          Future<void> confirm() async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            setDialogState(() {
              loading = true;
              errorText = '';
            });

            try {
              final authorized = await verifyAdminPin(ref, pinController.text);
              if (!mounted) return;
              if (!authorized) {
                setDialogState(() {
                  loading = false;
                  errorText = 'PIN incorrecto.';
                });
                return;
              }

              final repo = ref.read(inventoryRepositoryProvider);
              var deleted = 0;
              var hidden = 0;
              final failed = <String>[];
              String? abortReason;

              for (final row in targets) {
                if (!mounted) return;
                try {
                  final hardDeleted = await repo.deleteProduct(row.product.id);
                  if (hardDeleted) {
                    deleted++;
                  } else {
                    hidden++;
                  }
                } on AppException catch (e) {
                  // RLS u otra restricción de base de datos: repetirlo con el
                  // resto de prendas solo alarga el mismo error.
                  failed.add(row.product.name);
                  abortReason = e.message;
                  break;
                } catch (e) {
                  debugPrint('No se pudo eliminar ${row.product.name}: $e');
                  failed.add(row.product.name);
                }
              }

              if (!mounted) return;
              ref.invalidate(productsProvider);
              ref.invalidate(variantsProvider);
              setState(() {
                for (final row in targets) {
                  _selected.remove(row.product.id);
                }
              });

              if (!mounted) return;
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();

              if (!mounted) return;
              _showResult(
                deleted: deleted,
                hidden: hidden,
                failed: failed,
                reason: abortReason,
              );
            } catch (e) {
              // Nada de esto debe escapar como Future sin capturar: provocaría
              // la pantalla roja.
              debugPrint('Error en la limpieza de inventario: $e');
              if (!mounted) return;
              setDialogState(() {
                loading = false;
                errorText = 'No se pudo completar: $e';
              });
            }
          }

          return AlertDialog(
            title: Text('Eliminar ${targets.length} prendas'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se quitarán ${targets.length} prendas del inventario. '
                      'Las que ya tengan ventas no se borran: se ocultan para '
                      'conservar el histórico.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'PIN de administrador',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingresa el PIN' : null,
                      onFieldSubmitted: (_) => confirm(),
                    ),
                    if (errorText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText,
                        style: TextStyle(
                          color: Theme.of(dialogCtx).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
                onPressed: loading ? null : confirm,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Eliminar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showResult({
    required int deleted,
    required int hidden,
    required List<String> failed,
    String? reason,
  }) {
    if (!mounted) return;

    final ok = deleted + hidden;
    final partes = <String>[
      if (deleted > 0) '$deleted borrada${deleted == 1 ? '' : 's'}',
      if (hidden > 0) '$hidden oculta${hidden == 1 ? '' : 's'}',
    ];

    final messenger = ScaffoldMessenger.of(context);
    if (ok == 0) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(reason ?? 'No se pudo eliminar ninguna prenda.'),
      ));
      return;
    }

    final detalle = <String>[
      'Se procesaron $ok prendas: ${partes.join(' y ')}.',
      if (failed.isNotEmpty)
        reason ?? 'No se pudo con: ${failed.take(3).join(', ')}.',
    ];

    messenger.showSnackBar(SnackBar(content: Text(detalle.join(' '))));
  }
}

/// Fila de la lista de limpieza: prenda + datos agregados de sus variantes.
class _CleanupRow {
  final Product product;
  final int stock;
  final bool soldRecently;
  final int variantCount;
  final String categoryName;

  const _CleanupRow({
    required this.product,
    required this.stock,
    required this.soldRecently,
    required this.variantCount,
    required this.categoryName,
  });
}

/// Etiqueta pequeña de estado (Agotada / Sin ventas).
class _Tag extends StatelessWidget {
  final String text;
  final Color color;

  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final String text;

  const _EmptyBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
