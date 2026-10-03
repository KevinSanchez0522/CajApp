class Product {
  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final double costPrice;
  final double retailPrice;
  final String? imageUrl;
  final bool isActive;

  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    required this.costPrice,
    required this.retailPrice,
    this.imageUrl,
    this.isActive = true,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      costPrice: (json['cost_price'] as num).toDouble(),
      retailPrice: (json['retail_price'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'cost_price': costPrice,
        'retail_price': retailPrice,
        'image_url': imageUrl,
        'is_active': isActive,
      };

  Product copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? description,
    double? costPrice,
    double? retailPrice,
    String? imageUrl,
    bool? isActive,
  }) {
    return Product(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      costPrice: costPrice ?? this.costPrice,
      retailPrice: retailPrice ?? this.retailPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
    );
  }
}
