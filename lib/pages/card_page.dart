import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/learning.dart';
import '../core/links.dart';
import '../core/platform_style.dart';

class CardPage extends StatefulWidget {
  const CardPage({super.key});
  @override
  State<CardPage> createState() => _CardPageState();
}

class _CardPageState extends State<CardPage> {
  late DateTime _month;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    _month = DateTime(now.year, now.month);
  }

  String get _monthKey => '${_month.year}-${'${_month.month}'.padLeft(2, '0')}';

  Future<void> _sync(AppState state) async {
    state.cardQueryMonth = _monthKey;
    await AppLinks.open(
      context,
      'http://ecard.neu.edu.cn/selflogin/login.aspx',
      title: '校园卡',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final balance = state.cardBalance;
    final month = state.cardMonths[_monthKey];
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final current = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: PageAppBar(
        title: '校园卡',
        actions: [
          IconButton(
            tooltip: '打开卡务网页',
            onPressed: () => _sync(state),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主钱包余额'),
                  const SizedBox(height: 8),
                  Text(
                    balance == null
                        ? '尚未读取'
                        : '¥ ${balance.balance.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (balance?.subsidy != null)
                    Text('补助 ¥ ${balance!.subsidy!.toStringAsFixed(2)}'),
                  if (balance?.status.isNotEmpty == true) Text(balance!.status),
                  if (state.cardUpdatedAt != null)
                    Text('更新于 ${learningDateText(state.cardUpdatedAt)}'),
                  const SizedBox(height: 12),
                  Text(
                    AppLinks.supportsDataSync
                        ? '完成卡务网页认证后，点击“同步”读取余额和所选月份流水。'
                        : '当前平台可打开卡务网页，应用内同步支持 Android 和 iOS 客户端。',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _sync(state),
                    icon: const Icon(Icons.sync),
                    label: Text(
                      AppLinks.supportsDataSync ? '打开网页并同步' : '打开卡务网页',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: _month.year <= 2000 && _month.month == 1
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _monthKey,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: current
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          for (final warning in state.cardWarnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                warning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (month == null)
            const Padding(padding: EdgeInsets.all(24), child: Text('该月流水尚未读取'))
          else ...[
            if (month.truncated) const Text('已读取前 10 页，更多流水请在卡务网页查看。'),
            if (month.bills.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('该月没有流水记录'),
              ),
            for (final bill in month.bills)
              Card(
                child: ListTile(
                  title: Text(bill.subject.isEmpty ? '校园卡交易' : bill.subject),
                  subtitle: Text(
                    [
                      bill.timeText,
                      if (bill.station.isNotEmpty) bill.station,
                      if (bill.balanceAfter != null)
                        '余额 ¥ ${bill.balanceAfter!.toStringAsFixed(2)}',
                      if (bill.fee != null && bill.fee != 0)
                        '手续费 ¥ ${bill.fee!.toStringAsFixed(2)}',
                    ].join('\n'),
                  ),
                  trailing: Text(
                    '${bill.amount > 0 ? '+' : ''}${bill.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: bill.amount > 0
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
