import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import '../domain/product.dart';
import '../domain/product_variant.dart';
import '../domain/category.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/data/local_database.dart';

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
  final _localDb = LocalDatabase.instance;

  /// Comprime localmente la imagen antes de subir (optimiza red y almacenamiento).
  ///
  /// Devuelve el archivo comprimido SIN borrarlo: el borrado lo hace
  /// [registerProduct] DESPUÉS de subirlo a Storage. Antes se borraba aquí
  /// y el upload recibía una ruta inexistente (PathNotFoundException).
  Future<File> compressImage(File file, {int maxWidth = 1080}) async {
    final targetPath = '${file.path}_compressed.jpg';
    try {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 78,
        minWidth: maxWidth,
        minHeight: maxWidth,
      );
      if (compressed == null) return file;
      return File(compressed.path);
    } catch (_) {
      // Si la compresión falla, subimos el original en lugar de abortar.
      return file;
    }
  }

  Future<List<ProductCategory>> fetchCategories() async {
    if (!SupabaseConfig.isInitialized) {
      final res = await _localDb.getCategories();
      return res.map((c) => ProductCategory.fromJson(c)).toList();
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
      final res = await _localDb.getProducts();
      return res.map((p) => Product.fromJson(p)).toList();
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
      final res = await _localDb.getVariants();
      // Oculta las variantes de prendas desactivadas (borrado lógico).
      return res
          .map((v) => ProductVariant.fromJson(v))
          .where((v) => v.productIsActive)
          .toList();
    }

    try {
      final res = await Supabase.instance.client
          .from('product_variants')
          .select('*, products(name, retail_price, image_url, is_active)')
          .order('sku');
      return res
          .map((v) => ProductVariant.fromJson(v))
          .where((v) => v.productIsActive)
          .toList();
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
      String? imageUrl;
      if (image != null) {
        imageUrl = 'local://compressed/${image.path}';
      }

      final productId = const Uuid().v4();
      await _localDb.insertProduct({
        'id': productId,
        'category_id': categoryId,
        'name': name,
        'description': null,
        'cost_price': costPrice,
        'retail_price': retailPrice,
        'image_url': imageUrl,
        'is_active': 1,
      });

      final variantsData = variants.map((v) => {
        'id': const Uuid().v4(),
        'product_id': productId,
        'sku': v['sku'],
        'size': v['size'],
        'color': v['color'],
        'current_stock': v['current_stock'],
        'min_stock_alert': 3,
      }).toList();

      await _localDb.insertVariants(variantsData);

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

  /// Elimina unidades de una variante (ajuste manual: daños, extravíos, etc.).
  ///
  /// En Supabase usa la RPC `remove_variant_units`, que es atómica y deja
  /// registro en el kardex (`inventory_movements`). Si esa función aún no está
  /// aplicada en el proyecto, se degrada a un UPDATE directo, que solo el rol
  /// ADMIN puede hacer por las políticas RLS. En modo local solo decrementa.
  ///
  /// [currentStock] se usa para validar el límite y para el respaldo.
  /// Devuelve el stock resultante.
  Future<int> removeUnits({
    required String variantId,
    required int quantity,
    required int currentStock,
  }) async {
    if (quantity <= 0) {
      throw const AppException('La cantidad a eliminar debe ser mayor a cero.');
    }
    if (quantity > currentStock) {
      throw AppException(
          'Stock insuficiente. Disponible: $currentStock unidades.');
    }

    final remaining = currentStock - quantity;

    if (!SupabaseConfig.isInitialized) {
      await _localDb.decrementStock(variantId, quantity);
      return remaining;
    }

    final supabase = Supabase.instance.client;
    try {
      final res = await supabase.rpc('remove_variant_units', params: {
        'p_variant_id': variantId,
        'p_quantity': quantity,
      });
      return res is num ? res.toInt() : remaining;
    } on PostgrestException catch (e) {
      // 42883 = undefined_function (PostgreSQL), PGRST202 = función no
      // encontrada y PGRST204 = no está en la caché de esquema: en los tres
      // casos intentamos el respaldo con un UPDATE directo.
      final sinRpc = {'42883', 'PGRST202', 'PGRST204'}.contains(e.code);
      if (!sinRpc) rethrow;

      try {
        // Solo `current_stock`: si la caché de PostgREST está desactualizada,
        // menos columnas en el payload = menos puntos de fallo.
        final rows = await supabase
            .from('product_variants')
            .update({'current_stock': remaining})
            .eq('id', variantId)
            .select('id');

        if (rows.isEmpty) {
          throw const AppException(
            'Supabase no actualizó el stock. Suele deberse a que falta la '
            'función `remove_variant_units` (ejecútala desde supabase/schema.sql '
            'en el SQL Editor) o a que no iniciaste sesión como ADMIN.',
          );
        }
        return remaining;
      } on PostgrestException catch (e2) {
        if (e2.code == 'PGRST204') {
          throw const AppException(
            "Supabase no encuentra la tabla `product_variants` en su caché de "
            "esquema. Ejecuta \"NOTIFY pgrst, 'reload schema';\" en el SQL "
            'Editor y vuelve a intentarlo.',
            retryable: true,
          );
        }
        rethrow;
      }
    }
  }

  /// Elimina una prenda por completo (producto + todas sus variantes).
  ///
  /// Si la prenda ya tiene ventas registradas, el borrado físico está bloqueado
  /// por integridad referencial (`sale_details` → `product_variants`). En ese
  /// caso se desactiva (`is_active = false`), con lo que desaparece del
  /// inventario y del POS, pero se conserva el histórico de ventas.
  ///
  /// En Supabase solo el rol ADMIN puede hacerlo (políticas RLS).
  ///
  /// Devuelve `true` si se borró físicamente y `false` si solo se ocultó.
  Future<bool> deleteProduct(String productId) async {
    if (!SupabaseConfig.isInitialized) {
      if (await _localDb.productHasSales(productId)) {
        await _localDb.deactivateProduct(productId);
        return false;
      }
      await _localDb.deleteVariantsByProduct(productId);
      await _localDb.deleteProduct(productId);
      return true;
    }

    final supabase = Supabase.instance.client;
    try {
      final rows = await supabase
          .from('products')
          .delete()
          .eq('id', productId)
          .select('id');

      if (rows.isEmpty) {
        // RLS silencioso: la fila existe pero el rol no tiene permiso.
        throw const AppException(
          'Supabase no eliminó la prenda. Solo un usuario con rol ADMIN puede '
          'hacerlo (políticas RLS).',
        );
      }
      return true;
    } on PostgrestException catch (e) {
      // 23503 = foreign_key_violation: la prenda todavía tiene ventas.
      if (e.code != '23503') {
        throw mapErrorToAppException(e, contexto: 'Error al eliminar la prenda');
      }

      try {
        final rows = await supabase
            .from('products')
            .update({'is_active': false})
            .eq('id', productId)
            .select('id');
        if (rows.isEmpty) {
          throw const AppException(
            'Supabase no pudo ocultar la prenda. Solo un usuario con rol ADMIN '
            'puede hacerlo (políticas RLS).',
          );
        }
        return false;
      } on PostgrestException catch (e2) {
        throw mapErrorToAppException(
          e2,
          contexto: 'Error al desactivar la prenda',
        );
      }
    }
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