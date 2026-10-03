import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import '../domain/product.dart';
import '../domain/product_variant.dart';
import '../domain/category.dart';
import '../../pos/data/pos_repository.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/app_exception.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository();
});

final categoriesProvider = FutureProvider<List<ProductCategory>>((ref) {
  return ref.watch(inventoryRepositoryProvider).fetchCategories();
});

final productsProvider = FutureProvider<List<Product>>((ref) {
  return ref.watch(inventoryRepositoryProvider).fetchProducts();
});

final variantsProvider = FutureProvider<List<ProductVariant>>((ref) {
  return ref.watch(inventoryRepositoryProvider).fetchVariants();
});

class InventoryRepository {
  /// Comprime localmente la imagen antes de subir (optimiza red y almacenamiento).
  Future<File> compressImage(File file, {int maxWidth = 1080}) async {
    final targetPath = '${file.path}_compressed.jpg';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 78,
      minWidth: maxWidth,
      minHeight: maxWidth,
    );
    if (compressed == null) return file;
    final compressedFile = File(compressed.path);
    if (await compressedFile.exists()) await compressedFile.delete();
    return compressedFile;
  }

  Future<List<ProductCategory>> fetchCategories() async {
    if (!SupabaseConfig.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 250));
      return LocalDatabaseSimulation.categories
          .map((c) => ProductCategory.fromJson(c))
          .toList();
    }

    try {
      final res = await Supabase.instance.client
          .from('categories')
          .select('id, name, description')
          .order('name');
      return res.map((c) => ProductCategory.fromJson(c)).toList();
    } catch (e) {
      throw mapErrorToAppException(e, contexto: 'Error al cargar categorías');
    }
  }

  Future<List<Product>> fetchProducts() async {
    if (!SupabaseConfig.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 250));
      return LocalDatabaseSimulation.products
          .map((p) => Product.fromJson(p))
          .toList();
    }

    try {
      final res = await Supabase.instance.client
          .from('products')
          .select()
          .eq('is_active', true)
          .order('name');
      return res.map((p) => Product.fromJson(p)).toList();
    } catch (e) {
      throw mapErrorToAppException(e, contexto: 'Error al cargar productos');
    }
  }

  Future<List<ProductVariant>> fetchVariants() async {
    if (!SupabaseConfig.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 250));
      return LocalDatabaseSimulation.productVariants.map((v) {
        final map = Map<String, dynamic>.from(v);
        map['products'] = {
          'name': v['product_name'],
          'retail_price': v['retail_price'],
        };
        return ProductVariant.fromJson(map);
      }).toList();
    }

    try {
      final res = await Supabase.instance.client
          .from('product_variants')
          .select('*, products(name, retail_price)')
          .order('sku');
      return res.map((v) => ProductVariant.fromJson(v)).toList();
    } catch (e) {
      throw mapErrorToAppException(e, contexto: 'Error al cargar variantes');
    }
  }

  /// Registra producto + variantes. En modo Supabase usa una RPC atómica.
  Future<String> registerProduct({
    required String name,
    required String categoryId,
    required double costPrice,
    required double retailPrice,
    required String color,
    required List<Map<String, dynamic>> variants,
    File? image,
  }) async {
    if (!SupabaseConfig.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 700));

      String? imageUrl;
      if (image != null) {
        imageUrl = 'local://compressed/${image.path}';
      }

      final productId = const Uuid().v4();
      LocalDatabaseSimulation.products.add({
        'id': productId,
        'category_id': categoryId,
        'name': name,
        'description': null,
        'cost_price': costPrice,
        'retail_price': retailPrice,
        'image_url': imageUrl,
        'is_active': true,
      });

      for (final v in variants) {
        LocalDatabaseSimulation.productVariants.add({
          'id': const Uuid().v4(),
          'product_id': productId,
          'sku': v['sku'],
          'size': v['size'],
          'color': v['color'],
          'current_stock': v['current_stock'],
          'min_stock_alert': 3,
          'product_name': name,
          'retail_price': retailPrice,
        });
      }

      return productId;
    }

    final supabase = Supabase.instance.client;
    String? imageUrl;

    if (image != null) {
      final compressed = await compressImage(image);
      final path = 'products/${const Uuid().v4()}.jpg';
      await supabase.storage.from('product-images').upload(path, compressed);
      imageUrl = supabase.storage.from('product-images').getPublicUrl(path);
      if (await compressed.exists()) await compressed.delete();
    }

    final productId = await supabase.rpc('register_product_with_variants', params: {
      'p_name': name,
      'p_category_id': categoryId,
      'p_cost_price': costPrice,
      'p_retail_price': retailPrice,
      'p_image_url': imageUrl,
      'p_variants': variants,
    });

    return productId as String;
  }

  /// Genera un SKU determinístico y único.
  static String generateSku({
    required String productName,
    required String size,
    required String color,
  }) {
    final prefix = productName
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final base = prefix.length >= 3 ? prefix.substring(0, 3) : prefix.padRight(3, 'X');
    final colorPart = color.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final colorCode = colorPart.isEmpty
        ? 'STD'
        : (colorPart.length >= 4 ? colorPart.substring(0, 4) : colorPart.padRight(4, 'X'));
    final hash = const Uuid().v4().substring(0, 4).toUpperCase();
    return '$base-$size-$colorCode-$hash';
  }
}