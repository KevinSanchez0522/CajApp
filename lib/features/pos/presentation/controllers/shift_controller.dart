import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/cash_shift.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/data/local_database.dart';

final cashShiftProvider =
    StateNotifierProvider<CashShiftController, AsyncValue<ShiftSummary?>>(
  (ref) => CashShiftController(),
);

class CashShiftController extends StateNotifier<AsyncValue<ShiftSummary?>> {
  final _localDb = LocalDatabase.instance;

  CashShiftController() : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final summary = await _fetchActiveShift();
      state = AsyncValue.data(summary);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<ShiftSummary?> _fetchActiveShift() async {
    if (!SupabaseConfig.isInitialized) {
      final shifts = await _localDb.getCashShifts(status: 'OPEN');
      if (shifts.isEmpty) return null;

      final shiftJson = shifts.first;
      final shift = CashShift.fromJson({
        ...shiftJson,
        'opened_at': shiftJson['opened_at'] ?? DateTime.now().toIso8601String(),
      });

      final sales = await _localDb.getSalesByShift(shift.id);

      double cash = 0, card = 0, transfer = 0;
      for (final sale in sales) {
        final amount = (sale['total'] as num).toDouble();
        final method = sale['payment_method'] as String;
        if (method == 'CASH') {
          cash += amount;
        } else if (method == 'CARD') {
          card += amount;
        } else {
          transfer += amount;
        }
      }

      return ShiftSummary(
        shift: shift,
        cashSales: cash,
        cardSales: card,
        transferSales: transfer,
      );
    }

    final supabase = Supabase.instance.client;
    final shiftData = await supabase
        .from('cash_shifts')
        .select()
        .eq('status', 'OPEN')
        .order('opened_at', ascending: false)
        .limit(1);

    if (shiftData.isEmpty) return null;

    final shift = CashShift.fromJson(shiftData.first);
    final sales = await supabase
        .from('sales')
        .select('total, payment_method')
        .eq('shift_id', shift.id);

    double cash = 0, card = 0, transfer = 0;
    for (final sale in sales) {
      final amount = (sale['total'] as num).toDouble();
      final method = sale['payment_method'] as String;
      if (method == 'CASH') {
        cash += amount;
      } else if (method == 'CARD') {
        card += amount;
      } else {
        transfer += amount;
      }
    }

    return ShiftSummary(
      shift: shift,
      cashSales: cash,
      cardSales: card,
      transferSales: transfer,
    );
  }

  Future<void> openShift({required String userId, required double baseAmount}) async {
    try {
      if (!SupabaseConfig.isInitialized) {
        await _localDb.insertCashShift({
          'id': 'shift-${DateTime.now().millisecondsSinceEpoch}',
          'user_id': userId,
          'opening_balance': baseAmount,
          'closing_balance': null,
          'calculated_cash': 0.0,
          'status': 'OPEN',
          'opened_at': DateTime.now().toIso8601String(),
          'closed_at': null,
        });
      } else {
        await Supabase.instance.client.from('cash_shifts').insert({
          'user_id': userId,
          'opening_balance': baseAmount,
          'status': 'OPEN',
        });
      }
      await refresh();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> closeShift({required double reportedCash}) async {
    final current = state.valueOrNull;
    if (current == null) throw Exception('No hay un turno abierto para cerrar.');

    try {
      if (!SupabaseConfig.isInitialized) {
        await _localDb.updateCashShift(current.shift.id, {
          'closing_balance': reportedCash,
          'calculated_cash': current.cashSales,
          'status': 'CLOSED',
          'closed_at': DateTime.now().toIso8601String(),
        });
      } else {
        await Supabase.instance.client
            .from('cash_shifts')
            .update({
              'closing_balance': reportedCash,
              'calculated_cash': current.cashSales,
              'status': 'CLOSED',
              'closed_at': DateTime.now().toIso8601String(),
            })
            .eq('id', current.shift.id);
      }
      await refresh();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  /// Identificador del turno activo, usado por el checkout.
  String? get activeShiftId => state.valueOrNull?.shift.id;
}