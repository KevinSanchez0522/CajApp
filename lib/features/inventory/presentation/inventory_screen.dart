import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/inventory_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/user_profile.dart';
import '../domain/product.dart';
import '../domain/product_variant.dart';
import 'add_product_screen.dart';
import 'inventory_cleanup_screen.dart';
import 'product_detail_screen.dart';

/// Inventario con búsqueda en vivo, filtros por estado, miniaturas de foto
/// y navegación a la ficha de detalle de cada prenda (foto + QR + reimpresión).
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _StockFilter _filter = _StockFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variantsAsync = ref.watch(variantsProvider);
    final productsAsync = ref.watch(productsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final profile = ref.watch(currentUserProfileProvider);
    final isAdmin = profile.role == UserRole.admin;
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    final products = productsAsync.valueOrNull ?? <Product>[];
    final costByProduct = <String, double>{for (final p in products) p.id: p.costPrice};
    final nameByProduct = <String, String>{for (final p in products) p.id: p.name};
    final categoryIdByProduct = <String, String>{for (final p in products) p.id: p.categoryId};
    final categoryNameById = <String, String>{
      for (final c in (categoriesAsync.valueOrNull ?? [])) c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: 'Limpiar inventario',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InventoryCleanupScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(variantsProvider);
              ref.invalidate(productsProvider);
              ref.invalidate(categoriesProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Añadir prenda'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddProductScreen()),
          );
        },
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

          // ---------- Búsqueda + filtro por estado ----------
          final q = _query.trim().toLowerCase();
          final filtered = variants.where((v) {
            // Filtro de estado
            switch (_filter) {
              case _StockFilter.all:
                break;
              case _StockFilter.low:
                if (!v.isLowStock) return false;
              case _StockFilter.out:
                if (!v.isOutOfStock) return false;
            }
            // Búsqueda: nombre, categoría, SKU, talla, color
            if (q.isEmpty) return true;
            final name = v.productName ?? nameByProduct[v.productId] ?? '';
            final catName = categoryNameById[
                    categoryIdByProduct[v.productId] ?? ''] ??
                '';
            final haystack =
                '$name $catName ${v.sku} ${v.size} ${v.color}'.toLowerCase();
            return haystack.contains(q);
          }).toList();

          return Column(
            children: [
              // ---------- KPIs ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
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
              ),
              const SizedBox(height: 12),

              // ---------- Búsqueda ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, talla, color o SKU…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Limpiar',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 8),

              // ---------- Chips de filtro ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Todos',
                      selected: _filter == _StockFilter.all,
                      color: Colors.teal,
                      onTap: () =>
                          setState(() => _filter = _StockFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Stock crítico',
                      selected: _filter == _StockFilter.low,
                      color: Colors.orange.shade700,
                      onTap: () =>
                          setState(() => _filter = _StockFilter.low),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Agotados',
                      selected: _filter == _StockFilter.out,
                      color: Colors.red.shade700,
                      onTap: () =>
                          setState(() => _filter = _StockFilter.out),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // ---------- Resultados ----------
              Expanded(
                child: filtered.isEmpty
                    ? _EmptySearch(query: _query)
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(variantsProvider);
                          ref.invalidate(productsProvider);
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 88),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) =>
                              _buildVariantCard(
                            context,
                            filtered[i],
                            isAdmin,
                            costByProduct,
                            nameByProduct,
                            products,
                            currency,
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVariantCard(
    BuildContext context,
    ProductVariant v,
    bool isAdmin,
    Map<String, double> costByProduct,
    Map<String, String> nameByProduct,
    List<Product> products,
    NumberFormat currency,
  ) {
    final name = v.productName ?? nameByProduct[v.productId] ?? v.sku;
    final cost = costByProduct[v.productId] ?? 0.0;
    final price = v.retailPrice ?? 0.0;
    final margin = price - cost;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Product? product;
          for (final p in products) {
            if (p.id == v.productId) {
              product = p;
              break;
            }
          }
          if (product == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Producto no encontrado')),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Miniatura de la prenda
              _Thumb(imageUrl: v.productImageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        StockStatusBadge(stock: v.currentStock),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${v.size} · ${v.color}',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                    Text(
                      v.sku,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _PriceTag(
                          label: 'Precio',
                          value: currency.format(price),
                        ),
                        _PriceTag(
                          label: 'Valor stock',
                          value: currency.format(price * v.currentStock),
                          color: Colors.blue.shade700,
                        ),
                        // Restricción RBAC: costo/utilidad solo ADMIN
                        if (isAdmin)
                          _PriceTag(
                            label: 'Utilidad',
                            value: currency.format(margin),
                            color:
                                margin > 0 ? Colors.green.shade700 : Colors.red,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StockFilter { all, low, out }

/// Miniatura de la foto de la prenda (fallback a icono si no hay foto/red).
class _Thumb extends StatelessWidget {
  final String? imageUrl;

  const _Thumb({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final isNetwork = imageUrl != null &&
        (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://'));

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: isNetwork
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) =>
                  const Icon(Icons.checkroom, color: Colors.grey),
            )
          : const Icon(Icons.checkroom, color: Colors.grey),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? color : Colors.grey.shade700,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12.5,
      ),
      side: BorderSide(
        color: selected ? color : Colors.grey.shade400,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final String query;

  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            query.isEmpty
                ? 'No hay prendas con este filtro.'
                : 'Sin resultados para "$query"',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
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
