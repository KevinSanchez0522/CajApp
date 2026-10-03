enum ShiftStatus { open, closed }

enum PaymentMethod {
  cash('CASH', 'Efectivo'),
  card('CARD', 'Datáfono / Tarjeta'),
  bankTransfer('BANK_TRANSFER', 'Transferencia Bancaria');

  const PaymentMethod(this.code, this.label);

  final String code;
  final String label;

  static PaymentMethod fromCode(String code) {
    return PaymentMethod.values.firstWhere(
      (m) => m.code == code,
      orElse: () => PaymentMethod.cash,
    );
  }
}

class CashShift {
  final String id;
  final String userId;
  final double openingBalance;
  final double? closingBalance;
  final double calculatedCash;
  final ShiftStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;

  const CashShift({
    required this.id,
    required this.userId,
    required this.openingBalance,
    this.closingBalance,
    this.calculatedCash = 0.0,
    this.status = ShiftStatus.open,
    required this.openedAt,
    this.closedAt,
  });

  factory CashShift.fromJson(Map<String, dynamic> json) {
    return CashShift(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      openingBalance: (json['opening_balance'] as num).toDouble(),
      closingBalance: (json['closing_balance'] as num?)?.toDouble(),
      calculatedCash: (json['calculated_cash'] as num?)?.toDouble() ?? 0.0,
      status: (json['status'] as String) == 'CLOSED'
          ? ShiftStatus.closed
          : ShiftStatus.open,
      openedAt: DateTime.parse(json['opened_at'] as String),
      closedAt: json['closed_at'] == null
          ? null
          : DateTime.parse(json['closed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'opening_balance': openingBalance,
        'closing_balance': closingBalance,
        'calculated_cash': calculatedCash,
        'status': status == ShiftStatus.open ? 'OPEN' : 'CLOSED',
        'opened_at': openedAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
      };
}

/// Métricas agregadas en tiempo real del turno abierto.
class ShiftSummary {
  final CashShift shift;
  final double cashSales;
  final double cardSales;
  final double transferSales;

  const ShiftSummary({
    required this.shift,
    required this.cashSales,
    required this.cardSales,
    required this.transferSales,
  });

  double get expectedCashTotal => shift.openingBalance + cashSales;
  double get totalSales => cashSales + cardSales + transferSales;
  int get transactionCount => 0;
}