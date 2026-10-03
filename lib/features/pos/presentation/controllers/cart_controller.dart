import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/cart_item.dart';
import '../../../inventory/domain/product_variant.dart';
import '../../data/pos_repository.dart';
import '../../../../core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final cartProvider = StateNotifierProvider<CartController, List<CartItem>>((ref) {
  return CartController();
});

class CartController extends StateNotifier<List<CartItem>> {
  CartController() : super([]);

  double get totalAmount => state.fold(0, (sum, item) => sum + item.subtotal);
  int get totalItemCount => state.fold(0, (sum, item) => sum + item.quantity);

  /// Escanea y procesa SKU o UUID
  Future<void> scanVariantCode(
    String rawCode, {
    required Function(String error) onError,
    required Function(ProductVariant variant) onSuccess,
  }) async {
    final cleanCode = rawCode.trim();

    if (!SupabaseConfig.isInitialized) {
      // Simulación en memoria
      await Future.delayed(const Duration(milliseconds: 300));

      final matchIdx = LocalDatabaseSimulation.productVariants.indexWhere(
        (v) => v['sku'].toString().toLowerCase() == cleanCode.toLowerCase(),
      );

      if (matchIdx == -1) {
        onError('El código "$rawCode" no está registrado en la base de datos local.');
        return;
      }

      final variantData = LocalDatabaseSimulation.productVariants[matchIdx];
      final variant = ProductVariant(
        id: variantData['id'] as String,
        productId: variantData['product_id'] as String,
        sku: variantData['sku'] as String,
        size: variantData['size'] as String,
        color: variantData['color'] as String,
        currentStock: variantData['current_stock'] as int,
        minStockAlert: variantData['min_stock_alert'] as int? ?? 3,
        productName: variantData['product_name'] as String?,
        retailPrice: variantData['retail_price'] as double?,
      );

      if (variant.isOutOfStock) {
        onError('¡Stock agotado! No quedan unidades disponibles de este producto.');
        return;
      }

      addItem(variant, onError: onError);
      onSuccess(variant);
      return;
    }

    final supabase = Supabase.instance.client;
    try {
      final response = await supabase
          .from('product_variants')
          .select('*, products(name, retail_price)')
          .eq('sku', cleanCode)
          .maybeSingle();

      if (response == null) {
        onError('El código $rawCode no está registrado en el sistema.');
        return;
      }

      final variant = ProductVariant.fromJson(response);

      if (variant.isOutOfStock) {
        onError('¡Stock agotado! No quedan unidades disponibles de este producto.');
        return;
      }

      addItem(variant, onError: onError);
      onSuccess(variant);
    } catch (e) {
      onError('Error al consultar stock: $e');
    }
  }

  void addItem(ProductVariant variant, {required Function(String error) onError}) {
    final existingIndex = state.indexWhere((item) => item.variant.id == variant.id);

    if (existingIndex >= 0) {
      final currentItem = state[existingIndex];
      if (currentItem.quantity + 1 > variant.currentStock) {
        onError('Límite de stock alcanzado (${variant.currentStock} unidades disponibles).');
        return;
      }
      final updated = List<CartItem>.from(state);
      updated[existingIndex] = currentItem.copyWith(quantity: currentItem.quantity + 1);
      state = updated;
    } else {
      state = [
        ...state,
        CartItem(
          variant: variant,
          quantity: 1,
          unitPrice: variant.retailPrice ?? 0.0,
        ),
      ];
    }
  }

  void decrementItem(String variantId) {
    final index = state.indexWhere((item) => item.variant.id == variantId);
    if (index >= 0) {
      final current = state[index];
      if (current.quantity > 1) {
        final updated = List<CartItem>.from(state);
        updated[index] = current.copyWith(quantity: current.quantity - 1);
        state = updated;
      } else {
        removeItem(variantId);
      }
    }
  }

  void removeItem(String variantId) {
    state = state.where((item) => item.variant.id != variantId).toList();
  }

  void clearCart() {
    state = [];
  }
}
