import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/inventory_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/user_profile.dart';
import '../domain/product.dart';
import '../../pos/presentation/screens/pos_scanner_screen.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variantsAsync = ref.watch(variantsProvider);
    final productsAsync = ref.watch(productsProvider);
    final profile = ref.watch(currentUserProfileProvider);
    final isAdmin = profile.role == UserRole.admin;
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    final costByProduct = <String, double>{
      for (final p in (productsAsync.valueOrNull ?? <Product>[])) p.id: p.costPrice,
    };
    final nameByProduct = <String, String>{
      for (final p in (productsAsync.valueOrNull ?? <Product>[])) p.id: p.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario de Bodega'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: () {
                ref.invalidate(variantsProvider);
                ref.invalidate(productsProvider);
              },
            ),
        ],
      ),
      body: variantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (variants) {
          if (variants.isEmpty) {
            return const Center(child: Text('Sin variantes registradas.'));
          }

          final totalUnits = variants.fold<int>(0, (s, v) => s + v.currentStock);
          final lowStock = variants.where((v) => v.isLowStock).length;
          final outOfStock = variants.where((v) => v.isOutOfStock).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _KpiCard(
                    label: 'Unidades',
                    value: '$totalUnits',
                    color: Colors.teal,
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(width: 10),
                  _KpiCard(
                    label: 'Stock crítico',
                    value: '$lowStock',
                    color: Colors.orange.shade700,
                    icon: Icons.warning_amber,
                  ),
                  const SizedBox(width: 10),
                  _KpiCard(
                    label: 'Agotados',
                    value: '$outOfStock',
                    color: Colors.red.shade700,
                    icon: Icons.error_outline,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...variants.map((v) {
                final productId = v.productId;
                final cost = costByProduct[productId] ?? 0.0;
                final price = v.retailPrice ?? 0.0;
                final margin = isAdmin ? price - cost : 0.0;
                final marginPct = isAdmin && cost > 0 ? margin / cost * 100 : 0.0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                v.productName ?? nameByProduct[productId] ?? v.sku,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            StockBadge(stock: v.currentStock),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${v.size} · ${v.color} · SKU: ${v.sku}',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 18,
                          runSpacing: 6,
                          children: [
                            _PriceTag(
                              label: 'Precio',
                              value: currency.format(price),
                            ),
                            // Restricción RBAC: costo y utilidad solo para ADMIN
                            if (isAdmin) ...[
                              _PriceTag(
                                label: 'Costo',
                                value: currency.format(cost),
                                color: Colors.red.shade700,
                              ),
                              _PriceTag(
                                label: 'Utilidad',
                                value:
                                    '${currency.format(margin)} (${marginPct.toStringAsFixed(0)}%)',
                                color: margin > 0 ? Colors.green.shade700 : Colors.red,
                              ),
                            ],
                            _PriceTag(
                              label: 'Valor en bodega',
                              value: currency.format(price * v.currentStock),
                              color: Colors.blue.shade700,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold, color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _PriceTag({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13, color: color)),
      ],
    );
  }
}