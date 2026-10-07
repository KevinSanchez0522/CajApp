import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import '../domain/cart_item.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/data/local_database.dart';

// Simulación local en memoria para modo demostración sin base de datos
// Mantenida por compatibilidad temporal, migrar a LocalDatabase
class LocalDatabaseSimulation {
  static final List<Map<String, dynamic>> categories = [
    {'id': 'cat-1', 'name': 'Camisas', 'description': 'Camisas de vestir y casuales'},
    {'id': 'cat-2', 'name': 'Pantalones', 'description': 'Jeans, pantalones chinos y bermudas'},
    {'id': 'cat-3', 'name': 'Ropa Interior', 'description': 'Calcetines y boxer shorts'},
    {'id': 'cat-4', 'name': 'Chaquetas', 'description': 'Abrigos y chaquetas impermeables'},
  ];

  static final List<Map<String, dynamic>> products = [
    {
      'id': 'p-1',
      'category_id': 'cat-1',
      'name': 'Camisa Oxford Classic Fit',
      'cost_price': 15.00,
      'retail_price': 35.00,
      'image_url': null,
      'is_active': true,
    },
    {
      'id': 'p-2',
      'category_id': 'cat-2',
      'name': 'Jeans Slim Fit Denim',
      'cost_price': 20.00,
      'retail_price': 49.99,
      'image_url': null,
      'is_active': true,
    },
  ];

  static final List<Map<String, dynamic>> productVariants = [
    {
      'id': 'v-1',
      'product_id': 'p-1',
      'sku': 'OXF-S-BLUE-1234',
      'size': 'S',
      'color': 'Azul Celeste',
      'current_stock': 12,
      'min_stock_alert': 3,
      'product_name': 'Camisa Oxford Classic Fit',
      'retail_price': 35.00,
    },
    {
      'id': 'v-2',
      'product_id': 'p-1',
      'sku': 'OXF-M-BLUE-1234',
      'size': 'M',
      'color': 'Azul Celeste',
      'current_stock': 8,
      'min_stock_alert': 3,
      'product_name': 'Camisa Oxford Classic Fit',
      'retail_price': 35.00,
    },
    {
      'id': 'v-3',
      'product_id': 'p-1',
      'sku': 'OXF-L-BLUE-1234',
      'size': 'L',
      'color': 'Azul Celeste',
      'current_stock': 2,
      'min_stock_alert': 3,
      'product_name': 'Camisa Oxford Classic Fit',
      'retail_price': 35.00,
    },
    {
      'id': 'v-4',
      'product_id': 'p-2',
      'sku': 'SLM-32-INDG-5678',
      'size': '32',
      'color': 'Indigo',
      'current_stock': 15,
      'min_stock_alert': 3,
      'product_name': 'Jeans Slim Fit Denim',
      'retail_price': 49.99,
    },
    {
      'id': 'v-5',
      'product_id': 'p-2',
      'sku': 'SLM-34-INDG-5678',
      'size': '34',
      'color': 'Indigo',
      'current_stock': 0, // Agotado para probar validaciones
      'min_stock_alert': 3,
      'product_name': 'Jeans Slim Fit Denim',
      'retail_price': 49.99,
    },
  ];

  static final List<Map<String, dynamic>> cashShifts = [
    {
      'id': 'shift-active-demo',
      'user_id': 'admin-001-uuid',
      'opening_balance': 150.00,
      'closing_balance': null,
      'calculated_cash': 0.00,
      'status': 'OPEN',
      'opened_at': DateTime.now().toIso8601String(),
    }
  ];

  static final List<Map<String, dynamic>> sales = [];
  static final List<Map<String, dynamic>> saleDetails = [];
}

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return PosRepository();
});

class PosRepository {
  final _localDb = LocalDatabase.instance;

  /// Sube la imagen comprimida
  Future<String> uploadPaymentProof(File originalFile) async {
    if (!SupabaseConfig.isInitialized) {
      // Simular retraso y retornar ruta local ficticia
      await Future.delayed(const Duration(milliseconds: 600));
      return 'demo-proofs/comprobante_${const Uuid().v4()}.jpg';
    }

    final supabase = Supabase.instance.client;
    final fileName = 'proof_${const Uuid().v4()}.jpg';
    final targetPath = '${originalFile.parent.path}/compressed_$fileName';

    final compressedXFile = await FlutterImageCompress.compressAndGetFile(
      originalFile.absolute.path,
      targetPath,
      quality: 75,
      minWidth: 1024,
      minHeight: 1024,
    );

    if (compressedXFile == null) {
      throw Exception('Fallo en compresión de comprobante');
    }

    final compressedFile = File(compressedXFile.path);
    final storageResponse = await supabase.storage
        .from('payment-receipts')
        .upload(fileName, compressedFile, fileOptions: const FileOptions(contentType: 'image/jpeg'));

    if (await compressedFile.exists()) {
      await compressedFile.delete();
    }

    return storageResponse;
  }

  /// Ejecución de Venta con ACID
  Future<String> processSaleTransaction({
    required String shiftId,
    required String cashierId,
    required String paymentMethod,
    required List<CartItem> items,
    File? paymentProofFile,
    String? notes,
  }) async {
    String? uploadedProofPath;

    if (paymentProofFile != null) {
      uploadedProofPath = await uploadPaymentProof(paymentProofFile);
    }

    if (!SupabaseConfig.isInitialized) {
      // Usar base de datos local SQLite
      final shift = await _localDb.getOpenShift(cashierId);
      if (shift == null || shift['id'] != shiftId) {
        throw Exception('El turno de caja especificado no existe o se encuentra cerrado.');
      }

      final saleId = const Uuid().v4();
      double total = 0;

      // Validar stock físico localmente (transacción)
      for (final item in items) {
        final variant = await _localDb.getVariantById(item.variant.id);
        if (variant == null) {
          throw Exception('La variante de producto no existe en el catálogo.');
        }

        final currentStock = variant['current_stock'] as int;
        if (currentStock < item.quantity) {
          throw Exception('Stock insuficiente para la variante: ${item.variant.sku}. Disponible: $currentStock, Solicitado: ${item.quantity}');
        }

        total += item.subtotal;
      }

      // Aplicar descuentos de stock físico
      for (final item in items) {
        await _localDb.decrementStock(item.variant.id, item.quantity);
      }

      // Registrar cabecera
      await _localDb.insertSale({
        'id': saleId,
        'shift_id': shiftId,
        'cashier_id': cashierId,
        'subtotal': total,
        'tax': 0.0,
        'total': total,
        'payment_method': paymentMethod,
        'notes': notes,
        'proof_path': uploadedProofPath,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Registrar detalles
      final details = items.map((item) => {
        'id': const Uuid().v4(),
        'sale_id': saleId,
        'variant_id': item.variant.id,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
      }).toList();
      await _localDb.insertSaleDetails(details);

      // Sumar al total del turno de caja si es efectivo
      if (paymentMethod == 'CASH') {
        final currentShiftCash = (shift['calculated_cash'] as num).toDouble();
        await _localDb.updateCashShift(shiftId, {
          'calculated_cash': currentShiftCash + total,
        });
      }

      return saleId;
    }

    final supabase = Supabase.instance.client;
    final formattedItems = items.map((item) => {
      'variant_id': item.variant.id,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
    }).toList();

    try {
      final response = await supabase.rpc('execute_sale', params: {
        'p_shift_id': shiftId,
        'p_cashier_id': cashierId,
        'p_payment_method': paymentMethod,
        'p_items': formattedItems,
        'p_proof_path': uploadedProofPath,
        'p_notes': notes,
      });

      return response as String;
    } on PostgrestException catch (e) {
      if (e.message.contains('Stock insuficiente')) {
        throw Exception('Alerta de Concurrencia: Uno de los productos ya fue vendido por otro colaborador.');
      }
      throw Exception('Error en transacción de venta: ${e.message}');
    } catch (e) {
      throw Exception('Error de comunicación POS: $e');
    }
  }
}
