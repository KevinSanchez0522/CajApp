import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../controllers/cart_controller.dart';
import '../controllers/shift_controller.dart';
import 'checkout_screen.dart';

/// Terminal POS: la cámara de escaneo ocupa toda la pantalla.
/// El carrito NO está a la vista: aparece como botón flotante
/// cuando ya hay artículos y se quiere culminar la venta.
class PosScannerScreen extends ConsumerStatefulWidget {
  const PosScannerScreen({super.key});

  @override
  ConsumerState<PosScannerScreen> createState() => _PosScannerScreenState();
}

class _PosScannerScreenState extends ConsumerState<PosScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _isProcessingCode = false;
  bool _cameraFailed = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: isError ? 2500 : 1300),
      ),
    );
  }

  Future<void> _processCode(String rawCode) async {
    if (_isProcessingCode || rawCode.trim().isEmpty) return;

    setState(() => _isProcessingCode = true);
    HapticFeedback.mediumImpact();

    try {
      await ref.read(cartProvider.notifier).scanVariantCode(
            rawCode,
            onError: (errMsg) => _showSnack(errMsg, isError: true),
            onSuccess: (variant) => _showSnack(
                'Agregado: ${variant.productName ?? variant.sku} (${variant.size})'),
          );
    } catch (e) {
      _showSnack('Error al escanear: $e', isError: true);
    } finally {
      // Pausa anti-rebote y libera siempre el bloqueo, incluso si hubo error.
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _isProcessingCode = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final value = barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _processCode(value);
  }

  Future<void> _openCartSheet() async {
    // Pausa el escáner mientras se revisa el carrito / se cobra. Así se evitan
    // escaneos "fantasma" en segundo plano y, al volver, se rearma la cámara
    // para poder escanear una prenda nueva.
    await _stopScanner();
    if (!mounted) return;

    final startCheckout = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CartSheet(),
    );

    if (!mounted) return;

    if (startCheckout == true) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CheckoutScreen()),
      );
    }

    if (!mounted) return;
    // Rearma la detección (reinicia el estado noDuplicates del controlador).
    setState(() => _isProcessingCode = false);
    await _startScanner();
  }

  Future<void> _stopScanner() async {
    if (_cameraFailed) return;
    try {
      await _scannerController.stop();
    } catch (_) {
      // El controlador puede no estar iniciado todavía; se ignora.
    }
  }

  Future<void> _startScanner() async {
    if (_cameraFailed) return;
    try {
      await _scannerController.start();
    } catch (_) {
      // Si la cámara no puede reiniciarse, el fallback manual sigue disponible.
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
    final units = cart.fold<int>(0, (s, item) => s + item.quantity);

    return Scaffold(
      body: Stack(
        children: [
          // 1. Escáner a pantalla completa (con fallback si la cámara falla)
          Positioned.fill(
            child: _cameraFailed
                ? _CameraUnavailable(onManualEntry: _processCode)
                : MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) {
                      // Se marca el fallo para evitar re-construcciones infinitas
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _cameraFailed = true);
                      });
                      return const _CameraUnavailable();
                    },
                  ),
          ),

          // 2. Retícula guía
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isProcessingCode ? Colors.orange : Colors.greenAccent,
                    width: 3.0,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          // 3. Pista visual de escaneo
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 96),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Enfoca el código QR de la prenda',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ),

          // 4. Controles de cámara: linterna (izquierda) / cambiar cámara (derecha)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _scannerController,
                    builder: (context, state, child) {
                      final isOn = state.torchState == TorchState.on;
                      return _CameraButton(
                        icon: isOn ? Icons.flash_on : Icons.flash_off,
                        onPressed: () => _scannerController.toggleTorch(),
                        tooltip: 'Linterna',
                      );
                    },
                  ),
                  _CameraButton(
                    icon: Icons.flip_camera_ios,
                    onPressed: () => _scannerController.switchCamera(),
                    tooltip: 'Cambiar cámara',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // 4. Botón flotante del carrito: aparece solo con artículos
      floatingActionButton: cart.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCartSheet,
              tooltip: 'Ver carrito',
              icon: Badge(
                label: Text('$units'),
                child: const Icon(Icons.shopping_cart),
              ),
              label: Text(
                currency.format(cartNotifier.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
    );
  }
}

/// Botón flotante circular para los controles de cámara (linterna / flip).
class _CameraButton extends StatelessWidget {
  const _CameraButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}

/// Hoja modal con el panel del carrito (mismo diseño que el panel inferior
/// anterior: arrastre, lista con cantidades, vaciar y cobrar).
class _CartSheet extends StatelessWidget {
  const _CartSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) =>
          _CartPanel(scrollController: scrollController),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  final ScrollController scrollController;

  const _CartPanel({required this.scrollController});

  void _showSnack(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: isError ? 2500 : 1300),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final totalAmount = cartNotifier.totalAmount;
    final currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxHeight < 320;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 12, spreadRadius: 2),
            ],
          ),
          child: Column(
            children: [
              // Tirador táctil
              Container(
                margin: EdgeInsets.symmetric(vertical: compacto ? 4 : 8),
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: compacto ? 0 : 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Carrito (${cart.length})',
                      style: compacto
                          ? Theme.of(context).textTheme.titleSmall
                          : Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      currency.format(totalAmount),
                      style: (compacto
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: compacto ? 4 : 12),
              Expanded(
                child: cart.isEmpty
                    ? Center(
                        child: Text(
                          compacto
                              ? 'Carrito vacío'
                              : 'Enfoca el código QR de la prenda.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: compacto ? 12 : null),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: cart.length,
                        itemBuilder: (context, index) {
                          final item = cart[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              item.variant.productName ?? item.variant.sku,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                    '${item.variant.size} | ${item.variant.color}'),
                                const SizedBox(width: 8),
                                StockBadge(
                                    stock: item.variant.currentStock),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 20),
                                  onPressed: () => cartNotifier
                                      .decrementItem(item.variant.id),
                                ),
                                Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  onPressed: () => cartNotifier.addItem(
                                    item.variant,
                                    onError: (err) => _showSnack(context,
                                        err,
                                        isError: true),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding:
                      EdgeInsets.fromLTRB(16, 4, 16, compacto ? 6 : 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : () {
                                  cartNotifier.clearCart();
                                  _showSnack(context, 'Carrito vaciado');
                                  Navigator.pop(context);
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Vaciar'),
                          style: OutlinedButton.styleFrom(
                            minimumSize:
                                Size.fromHeight(compacto ? 44 : 52),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: FilledButton(
                          onPressed: cart.isEmpty
                              ? null
                              : () => _requestCheckout(context, ref),
                          style: FilledButton.styleFrom(
                            minimumSize:
                                Size.fromHeight(compacto ? 44 : 52),
                          ),
                          child:
                              Text('Cobrar ${currency.format(totalAmount)}'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Valida el turno y cierra la hoja pidiendo al POS abrir el checkout.
  /// Devolver `true` permite que el escáner se rearme al volver del cobro.
  void _requestCheckout(BuildContext context, WidgetRef ref) {
    final shift = ref.read(cashShiftProvider).valueOrNull;
    if (shift == null) {
      _showSnack(context, 'Debes abrir tu turno de caja antes de cobrar.',
          isError: true);
      return;
    }
    Navigator.pop(context, true); // cierra la hoja del carrito
  }
}

class _CameraUnavailable extends StatelessWidget {
  final void Function(String code)? onManualEntry;

  const _CameraUnavailable({this.onManualEntry});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Cámara no disponible',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Puedes digitar el SKU manualmente. Prueba con: OXF-S-BLUE-1234',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white12,
                hintText: 'Ej: OXF-S-BLUE-1234',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (v) {
                onManualEntry?.call(v);
                controller.clear();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador visual de nivel de stock (Rojo / Naranja / Verde).
class StockBadge extends StatelessWidget {
  final int stock;
  const StockBadge({super.key, required this.stock});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    String label;

    if (stock <= 0) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      label = 'Agotado';
    } else if (stock <= 3) {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
      label = 'Últimas $stock';
    } else {
      bg = Colors.green.shade100;
      fg = Colors.green.shade900;
      label = '$stock disp.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
