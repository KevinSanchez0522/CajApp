import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../controllers/shift_controller.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../receipt/services/shift_report_service.dart';

class CashShiftScreen extends ConsumerStatefulWidget {
  const CashShiftScreen({super.key});

  @override
  ConsumerState<CashShiftScreen> createState() => _CashShiftScreenState();
}

class _CashShiftScreenState extends ConsumerState<CashShiftScreen> {
  final _currency = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  final _closingCashController = TextEditingController();

  @override
  void dispose() {
    _closingCashController.dispose();
    super.dispose();
  }

  Future<void> _openShiftDialog() async {
    final baseController = TextEditingController(text: '150.00');
    final notifier = ref.read(cashShiftProvider.notifier);
    final profile = ref.read(currentUserProfileProvider);

    final base = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apertura de Caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa la base inicial en efectivo presente en la gaveta física:'),
            const SizedBox(height: 14),
            TextField(
              controller: baseController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: r'Monto Base ($) *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(baseController.text) ?? 0.0,
            ),
            child: const Text('Iniciar Turno'),
          ),
        ],
      ),
    );

    if (base == null) return;
    try {
      await notifier.openShift(userId: profile.id, baseAmount: base);
      if (!mounted) return;

      // Recargar para obtener el turno recién creado
      await notifier.refresh();
      if (!mounted) return;
      final newSummary = ref.read(cashShiftProvider).valueOrNull;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Turno abierto con base de ${_currency.format(base)}'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Ver Reporte',
              onPressed: () {
                if (newSummary != null) {
                  ShiftReportService.generateAndShareOpeningReport(
                    shift: newSummary.shift,
                    cashierName: profile.fullName,
                    cashierRole: profile.role.name.toUpperCase(),
                    openingBalance: base,
                    context: context,
                  );
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  Future<void> _closeShiftDialog() async {
    final summary = ref.read(cashShiftProvider).valueOrNull;
    if (summary == null) return;

    _closingCashController.text = summary.expectedCashTotal.toStringAsFixed(2);
    final notifier = ref.read(cashShiftProvider.notifier);
    final profile = ref.read(currentUserProfileProvider);

    final reported = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cierre y Arqueo de Turno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Efectivo esperado en gaveta: ${_currency.format(summary.expectedCashTotal)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text('Ingresa el efectivo físico contado en caja:'),
            const SizedBox(height: 8),
            TextField(
              controller: _closingCashController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: r'Efectivo Real Contado ($) *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(_closingCashController.text) ?? 0.0,
            ),
            child: const Text('Cerrar Caja'),
          ),
        ],
      ),
    );

    if (reported == null) return;

    try {
      await notifier.closeShift(reportedCash: reported);
      if (!mounted) return;
      
      // Mostrar resumen y luego ofrecer compartir reporte
      final expected = summary.shift.openingBalance + summary.cashSales;
      final diff = reported - expected;
      
      await _showArqueoSummary(summary.cashSales, summary.cardSales,
          summary.transferSales, summary.shift.openingBalance, reported);
      
      if (!mounted) return;
      
      // Generar y ofrecer compartir reporte de cierre
      await ShiftReportService.generateAndShareClosingReport(
        shift: summary.shift,
        cashierName: profile.fullName,
        cashierRole: profile.role.name.toUpperCase(),
        openingBalance: summary.shift.openingBalance,
        cashSales: summary.cashSales,
        cardSales: summary.cardSales,
        transferSales: summary.transferSales,
        reportedCash: reported,
        expectedCash: expected,
        difference: diff,
        context: context,
      );
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  Future<void> _showArqueoSummary(
    double cash,
    double card,
    double transfer,
    double opening,
    double reported,
  ) async {
    final expected = opening + cash;
    final diff = reported - expected;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          diff.abs() < 0.01
              ? Icons.check_circle
              : (diff > 0 ? Icons.info : Icons.warning),
          color: diff.abs() < 0.01
              ? Colors.green
              : (diff > 0 ? Colors.blue : Colors.red),
          size: 48,
        ),
        title: const Text('Resumen del Arqueo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Base inicial: ${_currency.format(opening)}'),
            Text('Ventas efectivo: ${_currency.format(cash)}'),
            Text('Ventas datáfono: ${_currency.format(card)}'),
            Text('Ventas transferencias: ${_currency.format(transfer)}'),
            const Divider(),
            Text('Esperado en caja: ${_currency.format(expected)}'),
            Text('Reportado físico: ${_currency.format(reported)}'),
            Text(
              'Diferencia: ${_currency.format(diff)} '
              '(${diff.abs() < 0.01 ? "Cuadre exacto" : (diff > 0 ? "Sobrante" : "Faltante")})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: diff.abs() < 0.01
                    ? Colors.green
                    : (diff > 0 ? Colors.blue : Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiftAsync = ref.watch(cashShiftProvider);
    final profile = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Caja'),
        actions: [
          IconButton(
            tooltip: 'Cambiar rol (demo)',
            icon: const Icon(Icons.switch_account),
            onPressed: () {
              final newRole = profile.role == UserRole.admin
                  ? UserRole.colaborador
                  : UserRole.admin;
              ref.read(sessionProvider.notifier).switchDemoRole(newRole);
              ref.read(cashShiftProvider.notifier).refresh();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sesión cambiada a ${newRole.name.toUpperCase()}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(cashShiftProvider.notifier).refresh(),
        child: shiftAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Error: $e')),
            ],
          ),
          data: (summary) {
            if (summary == null) {
              return ListView(
                padding: const EdgeInsets.all(28),
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.point_of_sale, size: 90, color: Colors.grey),
                  const SizedBox(height: 18),
                  const Text(
                    'No hay un turno de caja abierto',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Registra una base en efectivo para habilitar las ventas en el POS.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Abrir Turno de Caja'),
                    style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                    onPressed: _openShiftDialog,
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text(
                                'Estado del turno:',
                                style: TextStyle(fontSize: 15),
                              ),
                            ),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text('ABIERTO',
                                  style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                        const Divider(height: 26),
                        _MetricRow(label: 'Cajero:', value: profile.fullName),
                        _MetricRow(
                            label: 'Rol:', value: profile.role.name.toUpperCase()),
                        const SizedBox(height: 6),
                        _MetricRow(
                          label: 'Base inicial:',
                          value: _currency.format(summary.shift.openingBalance),
                        ),
                        const SizedBox(height: 6),
                        _MetricRow(
                          label: 'Ventas efectivo:',
                          value: _currency.format(summary.cashSales),
                          valueColor: Colors.green.shade700,
                        ),
                        _MetricRow(
                          label: 'Ventas datáfono:',
                          value: _currency.format(summary.cardSales),
                          valueColor: Colors.blue.shade700,
                        ),
                        _MetricRow(
                          label: 'Ventas transferencias:',
                          value: _currency.format(summary.transferSales),
                          valueColor: Colors.purple.shade700,
                        ),
                        _MetricRow(
                          label: 'Total vendido (todos los medios):',
                          value: _currency.format(summary.totalSales),
                        ),
                        const Divider(height: 26),
                        _MetricRow(
                          label: 'Efectivo físico esperado:',
                          value: _currency.format(summary.expectedCashTotal),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_clock),
                  label: const Text('Realizar Cierre y Arqueo de Caja',
                      style: TextStyle(fontSize: 16)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _closeShiftDialog,
                ),
                const SizedBox(height: 12),
                // Botones de reportes
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Reporte Apertura'),
                        onPressed: () => ShiftReportService.generateAndShareOpeningReport(
                          shift: summary.shift,
                          cashierName: profile.fullName,
                          cashierRole: profile.role.name.toUpperCase(),
                          openingBalance: summary.shift.openingBalance,
                          context: context,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.assessment),
                        label: const Text('Reporte Parcial'),
                        onPressed: () => ShiftReportService.generateAndShareClosingReport(
                          shift: summary.shift,
                          cashierName: profile.fullName,
                          cashierRole: profile.role.name.toUpperCase(),
                          openingBalance: summary.shift.openingBalance,
                          cashSales: summary.cashSales,
                          cardSales: summary.cardSales,
                          transferSales: summary.transferSales,
                          reportedCash: summary.expectedCashTotal, // Parcial: esperado = reportado
                          expectedCash: summary.expectedCashTotal,
                          difference: 0.0,
                          context: context,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _MetricRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: isBold ? 17 : 15.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}