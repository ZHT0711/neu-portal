import 'learning.dart';
import 'portal_client.dart';

class CardBalance {
  const CardBalance(this.balance, {this.subsidy, this.status = ''});
  final double balance;
  final double? subsidy;
  final String status;
  factory CardBalance.fromJson(Map row) {
    final value = row['balance'];
    if (value is! num || !value.isFinite) throw PortalException('主钱包余额未读取');
    return CardBalance(
      value.toDouble(),
      subsidy: (row['subsidy'] as num?)?.toDouble(),
      status: '${row['status'] ?? ''}',
    );
  }
}

class CardBill {
  CardBill(Map row)
    : timeText = '${row['timeText'] ?? ''}',
      time = learningDate(row['timeText']),
      subject = '${row['subject'] ?? ''}',
      amount = (row['amount'] as num).toDouble(),
      fee = (row['fee'] as num?)?.toDouble(),
      balanceAfter = (row['balanceAfter'] as num?)?.toDouble(),
      station = '${row['station'] ?? ''}';
  final String timeText, subject, station;
  final DateTime? time;
  final double amount;
  final double? fee, balanceAfter;
}

class CardMonth {
  const CardMonth(this.month, this.bills, {this.truncated = false});
  final String month;
  final List<CardBill> bills;
  final bool truncated;
}
