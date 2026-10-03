import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../controllers/cart_controller.dart';
import '../controllers/shift_controller.dart';
import '../../domain/cash_shift.dart';
import '../../data/pos_repository.dart';
import '../../../receipt/services/pdf_receipt_service.dart';
import '../../../auth/data/auth_repository.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  File? _proofImage;
  bool _isProcessing = false;
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) setState(() => _proofImage = File(picked.path));
    } catch (e) {
      _showSnack('No se pudo abrir la cámara/galería: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _completeCheckout() async {
    // Regla de negocio: comprobante obligatorio para medios electrónicos
    if (_selectedPaymentMethod != PaymentMethod.cash && _proofImage == null) {
      _showSnack('Comprobante obligatorio para Datáfono o Transferencia.', isError: true);
      return;
    }

    final shiftId = ref.read(cashShiftProvider).valueOrNull?.shift.id;
    if (shiftId == null) {
      _showSnack('No hay un turno de caja abierto.', isError: true);
      return;
    }

    setState(() => _isProcessing = true);
    final cart = ref.read(cartProvider);
    final total = ref.read(cartProvider.notifier).totalAmount;
    final cashier = ref.read(currentUserProfileProvider);

    try {
      // 1. Transacción atómica (locks + descuento de stock + registro)
      final saleId = await ref.read(posRepositoryProvider).processSaleTransaction(
            shiftId: shiftId,
            cashierId: cashier.id,
            paymentMethod: _selectedPaymentMethod.code,
            items: cart,
            paymentProofFile: _proofImage,
            notes: _notesController.text.trim(),
          );

      // 2. Ticket térmico en PDF
      final pdfFile = await PdfReceiptService.generateReceiptPdf(
        saleId: saleId,
        cashierName: cashier.fullName,
        paymentMethod: _selectedPaymentMethod.label,
        items: cart,
        total: total,
      );

      ref.read(cartProvider.notifier).clearCart();
      await ref.read(cashShiftProvider.notifier).refresh();

      if (!mounted) return;

      // 3. Confirmación con opción de compartir
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 52),
          title: const Text('¡Venta Exitosa!'),
          content: Text(
            'Transacción registrada con éxito.\nReferencia: ${saleId.substring(0, 8)}',
            textAlign: TextAlign.center,
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Finalizar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Compartir Recibo'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (!mounted) return;
                await PdfReceiptService.shareReceipt(
                  pdfFile,
                  sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
                );
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartProvider.notifier).totalAmount;
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Completar Cobro')),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Verificando stock y procesando venta transaccional...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total a Cobrar:',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          Text(currency.format(total),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cart.length,
                    itemBuilder: (_, i) {
                      final item = cart[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.variant.productName ?? item.variant.sku),
                        subtitle: Text(
                            '${item.quantity} x ${currency.format(item.unitPrice)}  (${item.variant.size})'),
                        trailing: Text(currency.format(item.subtotal),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                  const Divider(height: 28),
                  const Text('Método de Pago:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: PaymentMethod.values.map((m) {
                      final isSelected = m == _selectedPaymentMethod;
                      return ChoiceChip(
                        label: Text(m.label),
                        avatar: Icon(
                          switch (m) {
                            PaymentMethod.cash => Icons.money,
                            PaymentMethod.card => Icons.credit_card,
                            PaymentMethod.bankTransfer => Icons.account_balance,
                          },
                          size: 18,
                        ),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedPaymentMethod = m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Comprobante / Voucher ${_selectedPaymentMethod == PaymentMethod.cash ? '(Opcional)' : '(Obligatorio)'}:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  _proofImage == null
                      ? Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Tomar Foto'),
                                onPressed: () => _pickImage(ImageSource.camera),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Galería'),
                                onPressed: () => _pickImage(ImageSource.gallery),
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_proofImage!,
                                  height: 170, width: double.infinity, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                  onPressed: () => setState(() => _proofImage = null),
                                ),
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notas adicionales (Opcional)',
                      hintText: 'Ej. Últimos 4 dígitos de tarjeta, cliente habitual...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _completeCheckout,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Confirmar y Emitir Recibo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}