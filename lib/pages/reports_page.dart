import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

enum _Range { today, month, lastMonth, year, all }

String _rangeLabel(_Range r) {
  switch (r) {
    case _Range.today:
      return 'Today';
    case _Range.month:
      return 'This month';
    case _Range.lastMonth:
      return 'Last month';
    case _Range.year:
      return 'This year';
    case _Range.all:
      return 'All time';
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  _Range range = _Range.month;

  (DateTime, DateTime) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (range) {
      case _Range.today:
        return (today, today.add(const Duration(days: 1)));
      case _Range.month:
        return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case _Range.lastMonth:
        return (DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
      case _Range.year:
        return (DateTime(now.year), DateTime(now.year + 1));
      case _Range.all:
        return (DateTime(2000), DateTime(2200));
    }
  }

  bool _in(DateTime t, DateTime a, DateTime b) => !t.isBefore(a) && t.isBefore(b);

  Future<void> _copyCsv(List<SavedBill> list) async {
    final b = StringBuffer('Invoice,Date,Customer,Gross,Old metal exchange,Net total,Paid,Due\n');
    for (final s in list) {
      final name = s.customerName.replaceAll('"', '""');
      b.writeln('${s.invoiceNo},${fmtDate(s.createdAt)},"$name",${s.data.grossTotal.toStringAsFixed(2)},'
          '${s.data.exchangeTotal.toStringAsFixed(2)},${s.grandTotal.toStringAsFixed(2)},'
          '${s.totalPaid.toStringAsFixed(2)},${s.dueAmount.toStringAsFixed(2)}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Report copied. Paste it into Excel or Google Sheets.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final (from, to) = _bounds();
        final bills = store.bills.where((b) => _in(b.createdAt, from, to)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        var sales = 0.0, paidNow = 0.0, gst = 0.0, exchange = 0.0, goldG = 0.0, silverG = 0.0;
        var oldGoldG = 0.0, oldSilverG = 0.0;
        final byCustomer = <String, double>{};
        final names = <String, String>{};
        for (final b in bills) {
          final d = b.data;
          sales += b.grandTotal;
          paidNow += b.paidAtBilling;
          gst += d.gstAmount;
          exchange += d.exchangeTotal;
          for (final i in d.items) {
            if (i.type == ItemType.gold) goldG += i.weightValue;
            if (i.type == ItemType.silver) silverG += i.weightValue;
          }
          for (final e in d.exchanges) {
            if (e.isSilver) {
              oldSilverG += e.netWeight;
            } else {
              oldGoldG += e.netWeight;
            }
          }
          final key = b.customerName.toLowerCase();
          byCustomer[key] = (byCustomer[key] ?? 0) + b.grandTotal;
          names[key] = b.customerName;
        }
        var laterCollected = 0.0;
        for (final b in store.bills) {
          for (final p in b.payments) {
            if (_in(p.date, from, to)) laterCollected += p.amount;
          }
        }
        final top = byCustomer.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final avg = bills.isEmpty ? 0.0 : sales / bills.length;

        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final r in _Range.values)
                ChoiceChip(label: Text(_rangeLabel(r)), selected: range == r, onSelected: (_) => setState(() => range = r)),
            ]),
            const SizedBox(height: 12),
            _hero(sales, bills.length, avg),
            const SizedBox(height: 12),
            Row(children: [
              _tile('Collected', money(paidNow + laterCollected), Icons.payments_outlined, const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              _tile('Total due (now)', money(store.totalDue), Icons.hourglass_bottom, const Color(0xFFC62828)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _tile('GST billed', money(gst), Icons.receipt_long_outlined, maroon),
              const SizedBox(width: 8),
              _tile('Old metal taken', money(exchange), Icons.swap_horiz, const Color(0xFFB8860B)),
            ]),
            const SizedBox(height: 18),
            sectionTitle('Metal sold'),
            const SizedBox(height: 10),
            Row(children: [
              _tile('Gold sold', '${goldG.toStringAsFixed(2)} g', Icons.circle, const Color(0xFFB8860B)),
              const SizedBox(width: 8),
              _tile('Silver sold', '${silverG.toStringAsFixed(2)} g', Icons.circle, Colors.blueGrey),
            ]),
            if (oldGoldG > 0 || oldSilverG > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                _tile('Old gold in', '${oldGoldG.toStringAsFixed(2)} g', Icons.south_west, const Color(0xFFB8860B)),
                const SizedBox(width: 8),
                _tile('Old silver in', '${oldSilverG.toStringAsFixed(2)} g', Icons.south_west, Colors.blueGrey),
              ]),
            ],
            const SizedBox(height: 18),
            sectionTitle('Last 14 days', subtitle: 'Billed amount per day'),
            const SizedBox(height: 10),
            _chart(),
            const SizedBox(height: 18),
            sectionTitle('Top customers', subtitle: _rangeLabel(range)),
            const SizedBox(height: 8),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No bills in this period.', style: TextStyle(color: Colors.brown.shade400)),
              ),
            for (var i = 0; i < top.length && i < 5; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: maroon,
                    child: Text('${i + 1}', style: const TextStyle(color: goldLight, fontWeight: FontWeight.w900)),
                  ),
                  title: Text(names[top[i].key] ?? top[i].key, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text(money(top[i].value), style: const TextStyle(fontWeight: FontWeight.w800, color: maroon)),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: bills.isEmpty ? null : () => _copyCsv(bills),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text('Copy ${bills.length} bills as spreadsheet'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _hero(double sales, int count, double avg) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [maroonDark, maroon], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: gold, width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x40340A16), blurRadius: 12, offset: Offset(0, 5))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOTAL SALES  -  ${_rangeLabel(range).toUpperCase()}',
              style: const TextStyle(color: goldLight, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(sales), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('$count ${count == 1 ? 'bill' : 'bills'}', style: const TextStyle(color: Colors.white70))),
            Text('Average ${money(avg)}', style: const TextStyle(color: Colors.white70)),
          ]),
        ]),
      );

  Widget _tile(String label, String value, IconData icon, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 14, color: c),
                const SizedBox(width: 5),
                Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: Colors.brown.shade500))),
              ]),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c)),
              ),
            ]),
          ),
        ),
      );

  double _barHeight(double v, double maxV) {
    if (maxV <= 0) return 3;
    final h = v / maxV * 120;
    return h < 3 ? 3 : h;
  }

  Widget _chart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))];
    final totals = <double>[];
    for (final d in days) {
      final next = d.add(const Duration(days: 1));
      totals.add(store.bills.where((b) => _in(b.createdAt, d, next)).fold(0.0, (s, b) => s + b.grandTotal));
    }
    final maxV = totals.fold(0.0, (m, v) => v > m ? v : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(children: [
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: _barHeight(totals[i], maxV),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: totals[i] > 0 ? [maroon, gold] : [const Color(0xFFE9DFCF), const Color(0xFFE9DFCF)],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            for (final d in days)
              Expanded(
                child: Center(child: Text('${d.day}', style: TextStyle(fontSize: 9.5, color: Colors.brown.shade400))),
              ),
          ]),
          const SizedBox(height: 6),
          Text(maxV == 0 ? 'No bills in the last 14 days' : 'Best day: ${money(maxV)}',
              style: TextStyle(fontSize: 12, color: Colors.brown.shade500)),
        ]),
      ),
    );
  }
}
