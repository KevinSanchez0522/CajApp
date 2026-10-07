import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../data/inventory_repository.dart';
import '../domain/product.dart';
import '../domain/product_variant.dart';
import '../services/qr_label_printer.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/dialog_body.dart';
import '../../auth/data/admin_pin.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/user_profile.dart';

/// Ficha de detalle de un producto:
/// - Foto grande de la prenda
/// - Precios (costo/utilidad solo ADMIN)
/// - Variantes con stock, QR visible y reimpresión de etiquetas
///
/// Es `ConsumerStatefulWidget` (y no `ConsumerWidget`) a propósito: los
/// diálogos de "Eliminar unidades" y "Eliminar prenda" hacen `await` de red y,
/// para poder escribir `if (!mounted) return;` después de cada `await`, se
/// necesita estar dentro de una clase `State`.
class ProductDetailScreen extends ConsumerStatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final variantsAsync = ref.watch(variantsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final profile = ref.watch(currentUserProfileProvider);
    final isAdmin = profile.role == UserRole.admin;
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    var categoryName = 'Sin categoría';
    for (final c in (categoriesAsync.valueOrNull ?? [])) {
      if (c.id == product.categoryId) {
        categoryName = c.name;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Eliminar prenda',
            onPressed: () => _deleteProduct(ref),
          ),
        ],
      ),
      body: variantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error al cargar variantes: $e')),
        data: (allVariants) {
          final variants = allVariants
              .where((v) => v.productId == product.id)
              .toList();
          final totalUnits = variants.fold<int>(0, (s, v) => s + v.currentStock);
          final margin = product.retailPrice - product.costPrice;
          final marginPct =
              product.costPrice > 0 ? margin / product.costPrice * 100 : 0.0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---------- Foto de la prenda ----------
              _ProductPhoto(imageUrl: product.imageUrl),
              const SizedBox(height: 16),

              // ---------- Identidad ----------
              Text(
                product.name,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    avatar: const Icon(Icons.category, size: 16),
                    label: Text(categoryName),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    avatar: Icon(
                      totalUnits > 0 ? Icons.inventory_2 : Icons.remove_shopping_cart,
                      size: 16,
                      color: totalUnits > 0 ? Colors.teal : Colors.red,
                    ),
                    label: Text('$totalUnits unidades'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (product.description != null &&
                  product.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(product.description!,
                    style: TextStyle(color: Colors.grey.shade700)),
              ],
              const SizedBox(height: 16),

              // ---------- Precios ----------
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 22,
                    runSpacing: 10,
                    children: [
                      _InfoTile(
                        label: 'Precio venta',
                        value: currency.format(product.retailPrice),
                        color: Colors.blue.shade700,
                      ),
                      // Restricción RBAC: costo y utilidad solo para ADMIN
                      if (isAdmin) ...[
                        _InfoTile(
                          label: 'Costo',
                          value: currency.format(product.costPrice),
                          color: Colors.red.shade700,
                        ),
                        _InfoTile(
                          label: 'Utilidad unitaria',
                          value:
                              '${currency.format(margin)} (${marginPct.toStringAsFixed(0)}%)',
                          color:
                              margin > 0 ? Colors.green.shade700 : Colors.red,
                        ),
                      ],
                      _InfoTile(
                        label: 'Valor en bodega',
                        value: currency.format(product.retailPrice * totalUnits),
                        color: Colors.teal.shade700,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---------- Variantes + QR ----------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Variantes (${variants.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (variants.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Imprimir todas'),
                      onPressed: () => _printLabels(product.name, variants),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (variants.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Sin variantes registradas.')),
                )
              else
                ...variants.map((v) => _VariantCard(
                      variant: v,
                      productName: product.name,
                      isAdmin: isAdmin,
                      currency: currency,
                      onPrint: () => _printLabels(product.name, [v]),
                      onRemove: () => _removeUnits(ref, v),
                    )),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printLabels(String productName, List<ProductVariant> variants) async {
    try {
      await QrLabelPrinter.printLabels(
        productName: productName,
        labels: variants
            .map((v) => QrLabelData(sku: v.sku, size: v.size, color: v.color))
            .toList(),
      );
    } catch (e) {
      // El contexto puede haberse cerrado al volver del diálogo de impresión.
    }
  }

  /// Abre el diálogo para eliminar unidades: pide cantidad y PIN de
  /// administrador antes de tocar el stock.
  ///
  /// No recibe `BuildContext`: se usa el de la propia `State` para que el
  /// `if (!mounted) return;` de cada `await` sea realmente el guardia de ese
  /// contexto (si no, el linter lo marca como "guardia no relacionada").
  Future<void> _removeUnits(
    WidgetRef ref,
    ProductVariant variant,
  ) async {
    final qtyController = TextEditingController(text: '1');
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var errorText = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => DialogBody(
        controllers: [qtyController, pinController],
        builder: (dialogCtx, setDialogState) {
          Future<void> confirm() async {
            // try/catch en TODO el flujo: cualquier excepción no capturada
            // aquí se propaga como Future sin manejar y Flutter pinta una
            // pantalla roja en debug.
            try {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final qty = int.parse(qtyController.text);

              // Se captura todo ANTES del primer await: a partir de aquí el
              // widget o el diálogo podrían desmontarse mientras esperamos.
              final repo = ref.read(inventoryRepositoryProvider);

              setDialogState(() {
                loading = true;
                errorText = '';
              });

              final authorized =
                  await verifyAdminPin(ref, pinController.text);
              if (!authorized) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    loading = false;
                    errorText = 'PIN de administrador incorrecto.';
                  });
                }
                return;
              }

              await repo.removeUnits(
                variantId: variant.id,
                quantity: qty,
                currentStock: variant.currentStock,
              );

              // Nada de `context` / `ref` / `setDialogState` sin comprobar
              // antes que el widget siga montado.
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '$qty unidades de talla ${variant.size} eliminadas del inventario.'),
                  backgroundColor: Colors.red.shade700,
                ),
              );
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
              ref.invalidate(variantsProvider);
            } catch (e, st) {
              debugPrint('Fallo al eliminar unidades: $e\n$st');
              final msg =
                  e is AppException ? e.message : 'Error al eliminar: $e';
              if (dialogCtx.mounted) {
                setDialogState(() {
                  loading = false;
                  errorText = msg;
                });
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(msg),
                      backgroundColor: Colors.red.shade700),
                );
              }
            }
          }

          return AlertDialog(
            title: const Text('Eliminar unidades'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Talla ${variant.size} · ${variant.color}\n'
                    'Stock actual: ${variant.currentStock} unidades',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Unidades a eliminar *',
                      prefixIcon: Icon(Icons.remove_circle_outline),
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1) return 'Debe ser 1 o más';
                      if (n > variant.currentStock) {
                        return 'Solo hay ${variant.currentStock} en stock';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN de administrador *',
                      hintText: '4-6 dígitos',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => (v == null || v.trim().length < 4)
                        ? 'Ingresa el PIN de administrador'
                        : null,
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText,
                      style: TextStyle(
                          color: Colors.red.shade700, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    loading ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                label: const Text('Eliminar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: loading ? null : confirm,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Abre el diálogo para eliminar la prenda por completo.
  ///
  /// Pide el PIN de administrador. Si la prenda ya tiene ventas, en lugar de
  /// borrarse físicamente se desactiva (desaparece del inventario y del POS,
  /// pero se conserva el histórico).
  Future<void> _deleteProduct(WidgetRef ref) async {
    final product = widget.product;
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var errorText = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => DialogBody(
        controllers: [pinController],
        builder: (dialogCtx, setDialogState) {
          Future<void> confirm() async {
            // Igual que en eliminar unidades: toda la validación, la llamada
            // a red y la navegación van dentro del try para que ninguna
            // excepción escape como Future sin manejar (pantalla roja).
            try {
              if (!(formKey.currentState?.validate() ?? false)) return;

              // Capturado ANTES del primer await.
              final repo = ref.read(inventoryRepositoryProvider);
              final pin = pinController.text;

              setDialogState(() {
                loading = true;
                errorText = '';
              });

              final authorized = await verifyAdminPin(ref, pin);
              if (!authorized) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    loading = false;
                    errorText = 'PIN de administrador incorrecto.';
                  });
                }
                return;
              }

              final borradoFisico = await repo.deleteProduct(product.id);
              final nombre = product.name;

              if (!mounted) return;
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    borradoFisico
                        ? 'Prenda "$nombre" eliminada del inventario.'
                        : 'Prenda "$nombre" ocultada del inventario. Tiene '
                            'ventas registradas, así que el histórico se '
                            'conserva.',
                  ),
                  backgroundColor: Colors.red.shade700,
                ),
              );

              ref.invalidate(variantsProvider);
              ref.invalidate(productsProvider);
              ref.invalidate(categoriesProvider);

              // Volver al inventario: esta pantalla ya no tiene datos.
              if (mounted) {
                final nav = Navigator.of(context);
                if (nav.canPop()) nav.pop();
              }
            } catch (e, st) {
              debugPrint('Fallo al eliminar prenda: $e\n$st');
              final msg =
                  e is AppException ? e.message : 'Error al eliminar: $e';
              if (dialogCtx.mounted) {
                setDialogState(() {
                  loading = false;
                  errorText = msg;
                });
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(msg),
                      backgroundColor: Colors.red.shade700),
                );
              }
            }
          }

          return AlertDialog(
            title: const Text('Eliminar prenda'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Se eliminará "${product.name}" y todas sus variantes del '
                    'inventario.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Si nunca tuvo ventas, se borra por completo.\n'
                    '• Si ya tiene ventas, solo se oculta (el histórico de '
                    'ventas se conserva).\n'
                    'Esta acción no se puede deshacer.',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN de administrador *',
                      hintText: '4-6 dígitos',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => (v == null || v.trim().length < 4)
                        ? 'Ingresa el PIN de administrador'
                        : null,
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText,
                      style: TextStyle(
                          color: Colors.red.shade700, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    loading ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever, size: 18),
                label: const Text('Eliminar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: loading ? null : confirm,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Foto grande con estados de carga / error / ausencia.
class _ProductPhoto extends StatelessWidget {
  final String? imageUrl;

  const _ProductPhoto({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final isNetwork = imageUrl != null &&
        (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://'));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: 260,
        color: Colors.grey.shade100,
        child: isNetwork
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (ctx, err, st) => const _PhotoPlaceholder(),
              )
            : const _PhotoPlaceholder(),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.checkroom, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 8),
        Text(
          'Sin foto disponible',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      ],
    );
  }
}

/// Tarjeta de variante: QR visible, stock, reimpresión y borrado de unidades.
class _VariantCard extends StatelessWidget {
  final ProductVariant variant;
  final String productName;
  final bool isAdmin;
  final NumberFormat currency;
  final VoidCallback onPrint;
  final VoidCallback onRemove;

  const _VariantCard({
    required this.variant,
    required this.productName,
    required this.isAdmin,
    required this.currency,
    required this.onPrint,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR tappable → vista ampliada
            GestureDetector(
              onTap: () => _showQrFull(context),
              child: QrImageView(
                data: variant.sku,
                version: QrVersions.auto,
                size: 74,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Talla ${variant.size} · ${variant.color}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      StockStatusBadge(stock: variant.currentStock),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    variant.sku,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (isAdmin && variant.retailPrice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Precio: ${currency.format(variant.retailPrice)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.qr_code_2, size: 16),
                        label: const Text('Ver QR', style: TextStyle(fontSize: 12)),
                        onPressed: () => _showQrFull(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text('Reimprimir',
                            style: TextStyle(fontSize: 12)),
                        onPressed: onPrint,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton.icon(
                        icon: Icon(
                          Icons.remove_circle_outline,
                          size: 16,
                          color: variant.currentStock > 0
                              ? Colors.red.shade700
                              : Colors.grey.shade400,
                        ),
                        label: Text(
                          'Eliminar uds',
                          style: TextStyle(
                            fontSize: 12,
                            color: variant.currentStock > 0
                                ? Colors.red.shade700
                                : Colors.grey.shade400,
                          ),
                        ),
                        onPressed: variant.currentStock > 0 ? onRemove : null,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrFull(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiqueta QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: variant.sku, version: QrVersions.auto, size: 230),
            const SizedBox(height: 12),
            Text(productName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Talla ${variant.size} · ${variant.color}'),
            const SizedBox(height: 4),
            Text(variant.sku,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Imprimir'),
            onPressed: () {
              Navigator.pop(ctx);
              onPrint();
            },
          ),
        ],
      ),
    );
  }
}

class StockStatusBadge extends StatelessWidget {
  final int stock;

  const StockStatusBadge({super.key, required this.stock});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (stock <= 0) {
      color = Colors.red.shade700;
      label = 'Agotado';
    } else if (stock <= 3) {
      color = Colors.orange.shade700;
      label = '$stock pocos';
    } else {
      color = Colors.teal.shade700;
      label = '$stock uds';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoTile({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(
          value,
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: color),
        ),
      ],
    );
  }
}
