import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../data/inventory_repository.dart';
import '../domain/category.dart';
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

  final List<String> _availableSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'Única'];
  final Set<String> _selectedSizes = {'S', 'M', 'L'};
  final List<VariantDraft> _matrix = [];

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
    super.dispose();
  }

  void _regenerateMatrix() {
    final color = _colorController.text.trim().isEmpty
        ? 'Negro'
        : _colorController.text.trim();
    final productName = _nameController.text.trim();

    setState(() {
      _matrix.clear();
      for (final size in _selectedSizes) {
        _matrix.add(VariantDraft(
          size: size,
          color: color,
          initialStock: 5,
          sku: InventoryRepository.generateSku(
            productName: productName,
            size: size,
            color: color,
          ),
        ));
      }
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
        const SnackBar(content: Text('Selecciona al menos una talla')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ref.read(inventoryRepositoryProvider).registerProduct(
            name: _nameController.text.trim(),
            categoryId: _selectedCategoryId!,
            costPrice: double.parse(_costController.text),
            retailPrice: double.parse(_priceController.text),
            color: _colorController.text.trim(),
            variants: _matrix
                .map((v) => {
                      'sku': v.sku,
                      'size': v.size,
                      'color': v.color,
                      'current_stock': v.initialStock,
                    })
                .toList(),
            image: _productImage,
          );

      ref.invalidate(variantsProvider);
      ref.invalidate(productsProvider);

      if (!mounted) return;
      final productName = _nameController.text.trim();
      final margin = double.parse(_priceController.text) -
          double.parse(_costController.text);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${_matrix.length} variantes" ingresadas a bodega. Margen: ${NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(margin)}'),
          backgroundColor: Colors.green.shade700,
        ),
      );

      _showPrintLabelsDialog(productName);
      _formKey.currentState!.reset();
      _nameController.clear();
      _costController.clear();
      _priceController.clear();
      setState(() => _productImage = null);
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

  void _showPrintLabelsDialog(String productName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiquetas generadas'),
        content: Text(
            'Se registraron ${_matrix.length} variantes con SKU único. ¿Deseas imprimir las etiquetas QR para el rotulado físico?'),
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
              final labels = List<VariantDraft>.from(_matrix);
              await _printQrLabels(productName, labels);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _printQrLabels(String productName, List<VariantDraft> variants) async {
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (context) => [
            pw.Header(level: 1, child: pw.Text('Etiquetas: $productName')),
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: variants.map((v) {
                return pw.Container(
                  width: 170,
                  height: 195,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        productName,
                        maxLines: 2,
                        textAlign: pw.TextAlign.center,
                        style:
                            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                      pw.Text('Talla: ${v.size} | ${v.color}',
                          style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 6),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: v.sku,
                        width: 92,
                        height: 92,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(v.sku,
                          style: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (_) => pdf.save());
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
                  TextFormField(
                    controller: _colorController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Color principal',
                      prefixIcon: Icon(Icons.palette_outlined),
                    ),
                    onChanged: (_) => _regenerateMatrix(),
                  ),
                  const SizedBox(height: 20),
                  const Text('Tallas disponibles:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSizes.map((size) {
                      return FilterChip(
                        label: Text(size),
                        selected: _selectedSizes.contains(size),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedSizes.add(size);
                            } else if (_selectedSizes.length > 1) {
                              _selectedSizes.remove(size);
                            }
                          });
                          _regenerateMatrix();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Matriz de variantes y stock inicial',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.autorenew, size: 18),
                        label: const Text('Regenerar SKU'),
                        onPressed: _regenerateMatrix,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._matrix.map((item) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            QrImageView(data: item.sku, version: QrVersions.auto, size: 52),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Talla ${item.size} · ${item.color}',
                                      style:
                                          const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.sku,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 92,
                              child: TextFormField(
                                initialValue: item.initialStock.toString(),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  labelText: 'Cant.',
                                  isDense: true,
                                ),
                                onChanged: (v) => item.initialStock = int.tryParse(v) ?? 0,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_2, size: 20),
                              tooltip: 'Ver QR',
                              onPressed: () => _showQrPreview(
                                context,
                                item.sku,
                                'Talla ${item.size} · ${item.color}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
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

  void _showQrPreview(BuildContext context, String sku, String subtitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiqueta QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: sku, version: QrVersions.auto, size: 200),
            const SizedBox(height: 12),
            Text(subtitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(sku,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
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