import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Servicio singleton para la base de datos local SQLite (sqflite).
/// Reemplaza a [LocalDatabaseSimulation] para modo APK offline.
class LocalDatabase {
  LocalDatabase._internal();
  static final LocalDatabase instance = LocalDatabase._internal();

  Database? _db;
  bool _isInitialized = false;

  /// Inicializa la base de datos. Debe llamarse al arrancar la app.
  Future<void> initialize() async {
    if (_isInitialized) return;

    final Directory docsDir = await getApplicationDocumentsDirectory();
    final String dbPath = join(docsDir.path, 'cloth_pos.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Poblar datos semilla si está vacía
    await _seedIfEmpty();

    _isInitialized = true;
  }

  Database get database {
    if (_db == null) {
      throw StateError('LocalDatabase no inicializado. Llama a initialize() primero.');
    }
    return _db!;
  }

  bool get isInitialized => _isInitialized;

  /// Cierra la conexión (útil en tests o al cerrar la app).
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _isInitialized = false;
  }

  // --------------------------------------------------------------------------
  // Esquema SQL
  // --------------------------------------------------------------------------

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        cost_price REAL NOT NULL,
        retail_price REAL NOT NULL,
        image_url TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (category_id) REFERENCES categories (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE product_variants (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        sku TEXT NOT NULL UNIQUE,
        size TEXT NOT NULL,
        color TEXT NOT NULL,
        current_stock INTEGER NOT NULL DEFAULT 0,
        min_stock_alert INTEGER NOT NULL DEFAULT 3,
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE cash_shifts (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        opening_balance REAL NOT NULL,
        closing_balance REAL,
        calculated_cash REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL CHECK (status IN ('OPEN', 'CLOSED')),
        opened_at TEXT NOT NULL,
        closed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        shift_id TEXT NOT NULL,
        cashier_id TEXT NOT NULL,
        subtotal REAL NOT NULL,
        tax REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL CHECK (payment_method IN ('CASH', 'CARD', 'TRANSFER', 'MIXED')),
        notes TEXT,
        proof_path TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (shift_id) REFERENCES cash_shifts (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_details (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        variant_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales (id),
        FOREIGN KEY (variant_id) REFERENCES product_variants (id)
      )
    ''');

    // Índices para consultas frecuentes
    await db.execute('CREATE INDEX idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX idx_variants_product ON product_variants(product_id)');
    await db.execute('CREATE INDEX idx_sales_shift ON sales(shift_id)');
    await db.execute('CREATE INDEX idx_sale_details_sale ON sale_details(sale_id)');
    await db.execute('CREATE INDEX idx_cash_shifts_user ON cash_shifts(user_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migraciones futuras aquí
    // Ejemplo: if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  // --------------------------------------------------------------------------
  // Datos semilla (equivalentes a LocalDatabaseSimulation)
  // --------------------------------------------------------------------------

  Future<void> _seedIfEmpty() async {
    final categoriesCount = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM categories'),
    ) ?? 0;

    if (categoriesCount > 0) return; // Ya hay datos

    await _db!.transaction((txn) async {
      // Categorías
      final categories = [
        {'id': 'cat-1', 'name': 'Camisas', 'description': 'Camisas de vestir y casuales'},
        {'id': 'cat-2', 'name': 'Pantalones', 'description': 'Jeans, pantalones chinos y bermudas'},
        {'id': 'cat-3', 'name': 'Ropa Interior', 'description': 'Calcetines y boxer shorts'},
        {'id': 'cat-4', 'name': 'Chaquetas', 'description': 'Abrigos y chaquetas impermeables'},
      ];
      for (final c in categories) {
        await txn.insert('categories', c);
      }

      // Productos
      final products = [
        {
          'id': 'p-1',
          'category_id': 'cat-1',
          'name': 'Camisa Oxford Classic Fit',
          'description': null,
          'cost_price': 15.00,
          'retail_price': 35.00,
          'image_url': null,
          'is_active': 1,
        },
        {
          'id': 'p-2',
          'category_id': 'cat-2',
          'name': 'Jeans Slim Fit Denim',
          'description': null,
          'cost_price': 20.00,
          'retail_price': 49.99,
          'image_url': null,
          'is_active': 1,
        },
      ];
      for (final p in products) {
        await txn.insert('products', p);
      }

      // Variantes
      final variants = [
        {
          'id': 'v-1',
          'product_id': 'p-1',
          'sku': 'OXF-S-BLUE-1234',
          'size': 'S',
          'color': 'Azul Celeste',
          'current_stock': 12,
          'min_stock_alert': 3,
        },
        {
          'id': 'v-2',
          'product_id': 'p-1',
          'sku': 'OXF-M-BLUE-1234',
          'size': 'M',
          'color': 'Azul Celeste',
          'current_stock': 8,
          'min_stock_alert': 3,
        },
        {
          'id': 'v-3',
          'product_id': 'p-1',
          'sku': 'OXF-L-BLUE-1234',
          'size': 'L',
          'color': 'Azul Celeste',
          'current_stock': 2,
          'min_stock_alert': 3,
        },
        {
          'id': 'v-4',
          'product_id': 'p-2',
          'sku': 'SLM-32-INDG-5678',
          'size': '32',
          'color': 'Indigo',
          'current_stock': 15,
          'min_stock_alert': 3,
        },
        {
          'id': 'v-5',
          'product_id': 'p-2',
          'sku': 'SLM-34-INDG-5678',
          'size': '34',
          'color': 'Indigo',
          'current_stock': 0,
          'min_stock_alert': 3,
        },
      ];
      for (final v in variants) {
        await txn.insert('product_variants', v);
      }

      // Turno de caja demo (abierto)
      await txn.insert('cash_shifts', {
        'id': 'shift-active-demo',
        'user_id': 'admin-001-uuid',
        'opening_balance': 150.00,
        'closing_balance': null,
        'calculated_cash': 0.00,
        'status': 'OPEN',
        'opened_at': DateTime.now().toIso8601String(),
        'closed_at': null,
      });
    });
  }

  // --------------------------------------------------------------------------
  // Helpers de consulta (para compatibilidad con código existente)
  // --------------------------------------------------------------------------

  /// Devuelve todas las categorías como lista de mapas (compatibilidad).
  Future<List<Map<String, dynamic>>> getCategories() async {
    return await _db!.query('categories', orderBy: 'name');
  }

  /// Devuelve productos activos con su categoría.
  Future<List<Map<String, dynamic>>> getProducts() async {
    return await _db!.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      JOIN categories c ON p.category_id = c.id
      WHERE p.is_active = 1
      ORDER BY p.name
    ''');
  }

  /// Devuelve variantes con info del producto (name, retail_price, image_url).
  /// Incluye `product_is_active` para poder ocultar prendas desactivadas.
  Future<List<Map<String, dynamic>>> getVariants() async {
    return await _db!.rawQuery('''
      SELECT v.*, p.name as product_name, p.retail_price,
             p.image_url as product_image_url, p.is_active as product_is_active
      FROM product_variants v
      JOIN products p ON v.product_id = p.id
      ORDER BY v.sku
    ''');
  }

  /// Busca variante por ID (para validar stock en carrito).
  Future<Map<String, dynamic>?> getVariantById(String variantId) async {
    final res = await _db!.query(
      'product_variants',
      where: 'id = ?',
      whereArgs: [variantId],
      limit: 1,
    );
    return res.isEmpty ? null : res.first;
  }

  /// Actualiza stock de una variante (decrementa).
  Future<void> decrementStock(String variantId, int quantity) async {
    await _db!.rawUpdate(
      'UPDATE product_variants SET current_stock = current_stock - ? WHERE id = ?',
      [quantity, variantId],
    );
  }

  // --------------------------------------------------------------------------
  // Borrado de prendas
  // --------------------------------------------------------------------------

  /// ¿La prenda tiene ventas registradas?
  ///
  /// Si es así no se puede borrar físicamente: `sale_details` mantiene la
  /// referencia a sus variantes y se debe conservar el histórico.
  Future<bool> productHasSales(String productId) async {
    final res = await _db!.rawQuery('''
      SELECT COUNT(*) AS total
      FROM sale_details sd
      JOIN product_variants v ON sd.variant_id = v.id
      WHERE v.product_id = ?
    ''', [productId]);
    return ((res.first['total'] as num?)?.toInt() ?? 0) > 0;
  }

  /// Desactiva la prenda (borrado lógico): desaparece del inventario y del
  /// POS, pero se conserva el histórico de ventas.
  Future<void> deactivateProduct(String productId) async {
    await _db!.update(
      'products',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  /// Borra todas las variantes de una prenda.
  Future<void> deleteVariantsByProduct(String productId) async {
    await _db!.delete(
      'product_variants',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  /// Borra la prenda (físicamente).
  Future<void> deleteProduct(String productId) async {
    await _db!.delete('products', where: 'id = ?', whereArgs: [productId]);
  }

  /// Inserta una nueva categoría.
  Future<void> insertCategory(Map<String, dynamic> category) async {
    await _db!.insert('categories', category);
  }

  /// Inserta un nuevo producto.
  Future<void> insertProduct(Map<String, dynamic> product) async {
    await _db!.insert('products', product);
  }

  /// Inserta variantes en lote.
  Future<void> insertVariants(List<Map<String, dynamic>> variants) async {
    final batch = _db!.batch();
    for (final v in variants) {
      batch.insert('product_variants', v);
    }
    await batch.commit(noResult: true);
  }

  // --------------------------------------------------------------------------
  // POS: Turnos de caja
  // --------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getCashShifts({String? userId, String? status}) async {
    String where = '';
    final args = <Object>[];
    if (userId != null) {
      where += 'user_id = ?';
      args.add(userId);
    }
    if (status != null) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'status = ?';
      args.add(status);
    }
    return await _db!.query(
      'cash_shifts',
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'opened_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getOpenShift(String userId) async {
    final res = await _db!.query(
      'cash_shifts',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'OPEN'],
      limit: 1,
    );
    return res.isEmpty ? null : res.first;
  }

  Future<void> insertCashShift(Map<String, dynamic> shift) async {
    await _db!.insert('cash_shifts', shift);
  }

  Future<void> updateCashShift(String id, Map<String, dynamic> data) async {
    await _db!.update('cash_shifts', data, where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------------------------
  // POS: Ventas
  // --------------------------------------------------------------------------

  Future<void> insertSale(Map<String, dynamic> sale) async {
    await _db!.insert('sales', sale);
  }

  Future<void> insertSaleDetails(List<Map<String, dynamic>> details) async {
    final batch = _db!.batch();
    for (final d in details) {
      batch.insert('sale_details', d);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getSalesByShift(String shiftId) async {
    return await _db!.query(
      'sales',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getSaleDetails(String saleId) async {
    return await _db!.query(
      'sale_details',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
  }

  // --------------------------------------------------------------------------
  // Utilidades
  // --------------------------------------------------------------------------

  /// Limpia toda la base de datos (para tests o reset).
  Future<void> clearAll() async {
    await _db!.transaction((txn) async {
      await txn.delete('sale_details');
      await txn.delete('sales');
      await txn.delete('cash_shifts');
      await txn.delete('product_variants');
      await txn.delete('products');
      await txn.delete('categories');
    });
    await _seedIfEmpty();
  }
}