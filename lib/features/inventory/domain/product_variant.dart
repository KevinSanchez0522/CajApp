class ProductVariant {
  final String id;
  final String productId;
  final String sku;
  final String size;
  final String color;
  final int currentStock;
  final int minStockAlert;

  // Propiedades opcionales cargadas de joins
  final String? productName;
  final double? retailPrice;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.sku,
    required this.size,
    required this.color,
    required this.currentStock,
    this.minStockAlert = 3,
    this.productName,
    this.retailPrice,
  });

  bool get isOutOfStock => currentStock <= 0;
  bool get isLowStock => currentStock > 0 && currentStock <= minStockAlert;

  ProductVariant copyWith({
    String? id,
    String? productId,
    String? sku,
    String? size,
    String? color,
    int? currentStock,
    int? minStockAlert,
    String? productName,
    double? retailPrice,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      size: size ?? this.size,
      color: color ?? this.color,
      currentStock: currentStock ?? this.currentStock,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      productName: productName ?? this.productName,
      retailPrice: retailPrice ?? this.retailPrice,
    );
  }

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final productMap = json['products'] as Map<String, dynamic>?;
    return ProductVariant(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      sku: json['sku'] as String,
      size: json['size'] as String,
      color: json['color'] as String,
      currentStock: json['current_stock'] as int,
      minStockAlert: json['min_stock_alert'] as int? ?? 3,
      productName: productMap != null
          ? productMap['name'] as String?
          : json['product_name'] as String?,
      retailPrice: productMap != null
          ? (productMap['retail_price'] as num?)?.toDouble()
          : (json['retail_price'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'sku': sku,
        'size': size,
        'color': color,
        'current_stock': currentStock,
        'min_stock_alert': minStockAlert,
      };
}
