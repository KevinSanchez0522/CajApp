import '../../inventory/domain/product_variant.dart';

class CartItem {
  final ProductVariant variant;
  final int quantity;
  final double unitPrice;

  const CartItem({
    required this.variant,
    required this.quantity,
    required this.unitPrice,
  });

  double get subtotal => quantity * unitPrice;

  CartItem copyWith({
    ProductVariant? variant,
    int? quantity,
    double? unitPrice,
  }) {
    return CartItem(
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}
