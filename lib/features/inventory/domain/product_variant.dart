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
  final String? productImageUrl;

  /// Estado de la prenda a la que pertenece (`products.is_active`).
  /// `false` = prenda desactivada: no debe aparecer en inventario ni en el POS.
  final bool productIsActive;

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
    this.productImageUrl,
    this.productIsActive = true,
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
    String? productImageUrl,
    bool? productIsActive,
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
      productImageUrl: productImageUrl ?? this.productImageUrl,
      productIsActive: productIsActive ?? this.productIsActive,
    );
  }

  /// Convierte 0/1, true/false o ausente a bool (Supabase devuelve bool y
  /// SQLite devuelve entero).
  static bool _asBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return fallback;
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
      productImageUrl: productMap != null
          ? (productMap['image_url'] as String?)
          : (json['product_image_url'] as String?),
      productIsActive: productMap != null
          ? _asBool(productMap['is_active'])
          : _asBool(json['product_is_active']),
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
