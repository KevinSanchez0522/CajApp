import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../data/inventory_repository.dart';
import '../domain/category.dart';
import '../services/qr_label_printer.dart';
import '../../../core/errors/app_exception.dart';

class VariantDraft {
  final String size;
  final String color;
  int initialStock;
  String sku;

  VariantDraft({
    required this.size,
    required this.color,
    this.initialStock = 5,
    required this.sku,
  });
}

/// Opción de color predefinida: nombre (se usa para el SKU) + muestra visual.
class ColorOption {
  const ColorOption(this.name, this.value);

  final String name;
  final Color value;
}

class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _costController = TextEditingController();
  final _priceController = TextEditingController();
  final _colorController = TextEditingController(text: 'Negro');

  String? _selectedCategoryId;
  File? _productImage;
  bool _isSaving = false;

  final List<String> _availableSizes = ['Única', 'XS', 'S', 'M', 'L', 'XL', 'XXL'];

  /// Talla activa. Siempre hay UNA sola talla en el formulario y se cambia a
  /// mano tocando el chip de la talla deseada.
  String _selectedSize = 'Única';

  final List<VariantDraft> _matrix = [];

  /// Colores principales para elegir (el nombre alimenta el SKU).
  final List<ColorOption> _colorOptions = const [
    ColorOption('Negro', Color(0xFF000000)),
    ColorOption('Blanco', Color(0xFFFFFFFF)),
    ColorOption('Gris', Color(0xFF9E9E9E)),
    ColorOption('Azul', Color(0xFF1565C0)),
    ColorOption('Celeste', Color(0xFF4FC3F7)),
    ColorOption('Rojo', Color(0xFFC62828)),
    ColorOption('Naranja', Color(0xFFEF6C00)),
    ColorOption('Amarillo', Color(0xFFF9A825)),
    ColorOption('Verde', Color(0xFF2E7D32)),
    ColorOption('Morado', Color(0xFF6A1B9A)),
    ColorOption('Rosa', Color(0xFFEC407A)),
    ColorOption('Beige', Color(0xFFD7CCC8)),
    ColorOption('Burdeos', Color(0xFF880E4F)),
    ColorOption('Marfil', Color(0xFFF5F0E6)),
  ];

  /// Cantidad por defecto al elegir una talla.
  static const int _defaultQty = 1;

  /// Un controlador de cantidad, para conservar lo digitado aunque se
  /// regeneren los SKU al cambiar nombre/color.
  final Map<String, TextEditingController> _qtyControllers = {};

  /// Unidades totales que se están ingresando.
  int get _totalUnits =>
      _matrix.fold<int>(0, (sum, item) => sum + _readQty(item.size));

  /// Color efectivo (evita guardar vacío).
  String get _colorValue =>
      _colorController.text.trim().isEmpty ? 'Negro' : _colorController.text.trim();

  int _readQty(String size) =>
      int.tryParse(_qtyControllers[size]?.text ?? '') ?? 0;

  int _incrementQty(String size) {
    final next = _readQty(size) + 1;
    _qtyControllers[size]?.text = next.toString();
    return next;
  }

  int _decrementQty(String size) {
    final next = _readQty(size) > 0 ? _readQty(size) - 1 : 0;
    _qtyControllers[size]?.text = next.toString();
    return next;
  }

  @override
  void initState() {
    super.initState();
    _regenerateMatrix();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _colorController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Regenera la única fila de talla activa.
  ///
  /// Se conserva la cantidad digitada mientras no cambie de talla; al cambiar
  /// de talla la cantidad vuelve a 1. El SKU se genera de forma automática
  /// (no se muestra).
  void _regenerateMatrix() {
    final color = _colorValue;
    final productName = _nameController.text.trim();
    final size = _selectedSize;

    final keepQty = _matrix.isNotEmpty && _matrix.first.size == size;
    final qty = keepQty ? _matrix.first.initialStock : _defaultQty;

    // Libera el controlador de la talla anterior (tras el frame, para que no
    // se use un controlador ya destruido por el rebuild).
    final removedCtrl = <TextEditingController>[];
    _qtyControllers.removeWhere((k, ctrl) {
      if (k == size) return false;
      removedCtrl.add(ctrl);
      return true;
    });
    if (removedCtrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in removedCtrl) {
          c.dispose();
        }
      });
    }

    setState(() {
      _qtyControllers.putIfAbsent(
        size,
        () => TextEditingController(text: qty.toString()),
      );
      _matrix
        ..clear()
        ..add(VariantDraft(
          size: size,
          color: color,
          initialStock: qty,
          sku: InventoryRepository.generateSku(
            productName: productName,
            size: size,
            color: color,
          ),
        ));
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source);
      if (picked != null) setState(() => _productImage = File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar la imagen: $e')),
        );
      }
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona una categoría')),
      );
      return;
    }
    if (_matrix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una talla')),
      );
      return;
    }
    if (_totalUnits < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa al menos 1 unidad')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final variantsToSave = _matrix
          .map((v) => {
                'sku': v.sku,
                'size': v.size,
                'color': v.color,
                'current_stock': _readQty(v.size),
              })
          .toList();
      final totalUnits =
          variantsToSave.fold<int>(0, (s, v) => s + (v['current_stock'] as int));
      final savedSize = _matrix.first.size;

      await ref.read(inventoryRepositoryProvider).registerProduct(
            name: _nameController.text.trim(),
            categoryId: _selectedCategoryId!,
            costPrice: double.parse(_costController.text),
            retailPrice: double.parse(_priceController.text),
            color: _colorValue,
            variants: variantsToSave,
            image: _productImage,
          );

      if (!mounted) return;
      ref.invalidate(variantsProvider);
      ref.invalidate(productsProvider);

      final productName = _nameController.text.trim();
      final margin = double.parse(_priceController.text) -
          double.parse(_costController.text);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$totalUnits unidades de talla $savedSize ingresadas a bodega. Margen: ${NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(margin)}'),
          backgroundColor: Colors.green.shade700,
        ),
      );

      // Captura las variantes ANTES de limpiar el formulario para que la
      // impresión de etiquetas use los SKU correctos.
      final printedVariants = List<VariantDraft>.from(_matrix);
      _showPrintLabelsDialog(productName, printedVariants);

      _formKey.currentState!.reset();
      _nameController.clear();
      _costController.clear();
      _priceController.clear();
      setState(() {
        _productImage = null;
        // Vuelve a la talla única y reinicia la cantidad para el siguiente
        // ingreso.
        _selectedSize = 'Única';
        for (final c in _qtyControllers.values) {
          c.text = _defaultQty.toString();
        }
        _matrix.clear();
      });
      _regenerateMatrix();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showPrintLabelsDialog(String productName, List<VariantDraft> variants) {
    final sizes = variants.map((v) => v.size).join(', ');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiquetas generadas'),
        content: Text(
            'Se registró la talla $sizes con SKU único. ¿Deseas imprimir las etiquetas QR para el rotulado físico?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Imprimir etiquetas'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _printQrLabels(productName, variants);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _printQrLabels(String productName, List<VariantDraft> variants) async {
    try {
      await QrLabelPrinter.printLabels(
        productName: productName,
        labels: variants
            .map((v) => QrLabelData(sku: v.sku, size: v.size, color: v.color))
            .toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo imprimir: $e')),
        );
      }
    }
  }

  /// Campo de categoría con estados de carga / error recuperable / vacío.
  ///
  /// Antes mostraba el texto crudo de la excepción y un desplegable sin
  /// opciones, lo que dejaba al usuario sin forma de saber qué hacer.
  Widget _buildCategoryField(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ProductCategory>> categoriesAsync,
  ) {
    return categoriesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) {
        return _CategoryErrorBox(
          message: (e is AppException)
              ? e.message
              : 'Error al cargar categorías: $e',
          retryable: true,
          onRetry: () => ref.invalidate(categoriesProvider),
        );
      },
      data: (categories) {
        if (categories.isEmpty) {
          return const _CategoryErrorBox(
            message:
                'No hay categorías registradas. Crea al menos una en Supabase '
                'o revisa las políticas RLS de la tabla `categories`.',
            retryable: true,
          );
        }

        // Si el valor guardado ya no existe en la lista, lo descartamos para
        // evitar el assert de DropdownButtonFormField ("exactly one item").
        final ids = categories.map((c) => c.id).toSet();
        final valorActual =
            (_selectedCategoryId != null && ids.contains(_selectedCategoryId))
                ? _selectedCategoryId
                : null;

        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Categoría *',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          initialValue: valorActual,
          isExpanded: true,
          items: categories
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
              .toList(),
          onChanged: (v) => setState(() => _selectedCategoryId = v),
          validator: (v) => (v == null || v.isEmpty) ? 'Selecciona una categoría' : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Ingreso de Mercancía')),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Captura / carga de imagen
                  GestureDetector(
                    onTap: () => _showImageOptions(context),
                    child: Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _productImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(_productImage!, fit: BoxFit.cover),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, size: 42, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('Cargar imagen de la prenda'),
                              ],
                            ),
                    ),
                  ),
                  if (_productImage != null)
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Quitar imagen'),
                        onPressed: () => setState(() => _productImage = null),
                      ),
                    ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la prenda *',
                      prefixIcon: Icon(Icons.checkroom),
                    ),
                    onChanged: (_) => _regenerateMatrix(),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 14),
                  _buildCategoryField(context, ref, categoriesAsync),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _costController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Costo compra',
                            prefixIcon: Icon(Icons.trending_down),
                          ),
                          validator: (v) {
                            if (v == null || double.tryParse(v) == null) {
                              return 'Inválido';
                            }
                            final price = double.tryParse(_priceController.text);
                            if (price != null && double.parse(v) > price) {
                              return 'No supera el precio';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Precio venta',
                            prefixIcon: Icon(Icons.trending_up),
                          ),
                          validator: (v) {
                            if (v == null || double.tryParse(v) == null) {
                              return 'Inválido';
                            }
                            final cost = double.tryParse(_costController.text);
                            if (cost != null && double.parse(v) < cost) {
                              return 'Menor que el costo';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_costController.text.isNotEmpty && _priceController.text.isNotEmpty)
                    Builder(builder: (context) {
                      final cost = double.tryParse(_costController.text) ?? 0;
                      final price = double.tryParse(_priceController.text) ?? 0;
                      final margin = price - cost;
                      final pct = cost > 0 ? (margin / cost * 100) : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12, left: 4),
                        child: Text(
                          'Margen: ${currency.format(margin)} (${pct.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            color: margin > 0 ? Colors.green.shade700 : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _colorValue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Color principal',
                      prefixIcon: Icon(Icons.palette_outlined),
                    ),
                    items: _colorOptions.map((opt) {
                      return DropdownMenuItem(
                        value: opt.name,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: opt.value,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(opt.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _colorController.text = v);
                      _regenerateMatrix();
                    },
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Selecciona un color' : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.straighten, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Text('Talla',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800)),
                      const Spacer(),
                      Text('Se cambia a mano',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSizes.map((size) {
                      return ChoiceChip(
                        label: Text(size),
                        selected: _selectedSize == size,
                        onSelected: (_) {
                          if (_selectedSize == size) return;
                          setState(() => _selectedSize = size);
                          _regenerateMatrix();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Cantidad a ingresar',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Indica cuántas unidades llegan en talla $_selectedSize.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  ..._matrix.map((item) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Talla ${item.size}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _readQty(item.size) > 0
                                  ? () => setState(
                                        () => item.initialStock = _decrementQty(item.size))
                                  : null,
                            ),
                            SizedBox(
                              width: 56,
                              child: TextFormField(
                                key: ValueKey('qty_${item.size}'),
                                controller: _qtyControllers[item.size],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) => setState(
                                    () => item.initialStock = int.tryParse(v) ?? 0),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setState(
                                  () => item.initialStock = _incrementQty(item.size)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: $_totalUnits unidades',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.inventory_2),
                    label: const Text('Guardar e ingresar a bodega',
                        style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _saveProduct,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  void _showImageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de galería'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Caja de error accionable para el selector de categoría.
class _CategoryErrorBox extends StatelessWidget {
  const _CategoryErrorBox({
    required this.message,
    this.retryable = true,
    this.onRetry,
  });

  final String message;
  final bool retryable;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          if (retryable && onRetry != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
                onPressed: onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }
}