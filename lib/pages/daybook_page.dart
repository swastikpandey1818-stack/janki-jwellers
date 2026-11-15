import 'package:flutter/material.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'bookings_page.dart';

/// Daily / weekly / monthly totals: billed, received, dues cleared and dues still open.
class DayBookPage extends StatefulWidget {
  const DayBookPage({super.key});

  @override
  State<DayBookPage> createState() => _DayBookPageState();
}

class _DayBookPageState extends State<DayBookPage> {
  static const _red = Color(0xFFC62828);
  static const _green = Color(0xFF2E7D32);
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  PeriodKind kind = PeriodKind.daily;

  String _label(PeriodTotal t) {
    final isCurrent = BillStore.periodStart(DateTime.now(), kind) == t.start;
    switch (kind) {
      case PeriodKind.daily:
        final today = BillStore.periodStart(DateTime.now(), kind);
        final yesterday = DateTime(today.year, today.month, today.day - 1);
        if (isCurrent) return 'Today  •  ${fmtDate(t.start)}';
        if (t.start == yesterday) return 'Yesterday  •  ${fmtDate(t.start)}';
        return fmtDate(t.start);
      case PeriodKind.weekly:
        final range = '${fmtDate(t.start).substring(0, 5)} - ${fmtDate(t.end)}';
        return isCurrent ? 'This week  •  $range' : 'Week  •  $range';
      case PeriodKind.monthly:
        final name = '${_months[t.start.month - 1]} ${t.start.year}';
        return isCurrent ? 'This month  •  $name' : name;
    }
  }

  String get _periodWord => kind == PeriodKind.daily ? 'day' : kind == PeriodKind.weekly ? 'week' : 'month';

  Widget _row(String label, double value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Text(money(value),
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w500, color: color ?? (bold ? maroon : Colors.black87))),
        ]),
      );

  Widget _headerRow(String label, double value, {bool highlight = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(money(value),
              style: TextStyle(
                  color: highlight ? const Color(0xFFFFB4AB) : Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      );

  /// Collapsible list (closed by default) so each card stays short.
  Widget _expander(BuildContext context, String title, Color color, List<Widget> children) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
          children: children,
        ),
      );

  Widget _clearanceTile(BuildContext context, DueClearance c) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        onTap: () => openBill(context, c.bill),
        title: Text('${c.bill.customerName}  •  ${c.bill.invoiceNo}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${fmtDateTime(c.payment.date)}${c.payment.note.trim().isEmpty ? '' : '  •  ${c.payment.note.trim()}'}'),
        trailing: Text(money(c.payment.amount), style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
      );

  Widget _advanceTile(BuildContext context, AdvanceEntry a) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        onTap: () => openBooking(context, a.booking),
        title: Text(a.booking.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${fmtDateTime(a.payment.date)}${a.payment.note.trim().isEmpty ? '' : '  •  ${a.payment.note.trim()}'}'),
        trailing: Text(money(a.payment.amount), style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
      );

  Widget _dueBillTile(BuildContext context, SavedBill b) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        onTap: () => openBill(context, b),
        title: Text('${b.customerName}  •  ${b.invoiceNo}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Billed ${money(b.grandTotal)}  •  paid at billing ${money(b.paidAtBilling)}'),
        trailing: b.hasDue
            ? Text('Due ${money(b.dueAmount)}', style: const TextStyle(fontWeight: FontWeight.w800, color: _red))
            : const Text('Cleared', style: TextStyle(fontWeight: FontWeight.w800, color: _green)),
      );

  Widget _periodCard(BuildContext context, PeriodTotal t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_label(t), style: const TextStyle(fontWeight: FontWeight.w900, color: maroon, fontSize: 16)),
          const SizedBox(height: 4),
          Text('${t.bills} bill${t.bills == 1 ? '' : 's'} made',
              style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
          const Divider(height: 16),
          _row('Total billed', t.billed),
          _row('Received at billing', t.paidAtBilling),
          _row('Due cleared (received later)', t.collectedLater),
          if (t.advances > 0) _row('Advance received (bookings)', t.advances),
          if (t.refunds > 0) _row('Advance returned to customers', -t.refunds, color: _red),
          const Divider(height: 16),
          _row('TOTAL RECEIVED', t.cashIn, bold: true, color: _green),
          if (t.dueCreated > 0) _row('New due from this $_periodWord\'s bills', t.dueCreated, color: _red),
          if (t.clearances.isNotEmpty)
            _expander(context, 'Dues cleared this $_periodWord  (${t.clearances.length})', _green,
                t.clearances.map((c) => _clearanceTile(context, c)).toList()),
          if (t.advanceAdjusted > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Bills this $_periodWord also used ${money(t.advanceAdjusted)} of advance received earlier (not counted again).',
                  style: TextStyle(color: Colors.brown.shade400, fontSize: 11.5)),
            ),
          if (t.advanceEntries.isNotEmpty)
            _expander(context, 'Advances received this $_periodWord  (${t.advanceEntries.length})', _green,
                t.advanceEntries.map((a) => _advanceTile(context, a)).toList()),
          if (t.dueBills.isNotEmpty)
            _expander(context, 'Bills with due from this $_periodWord  (${t.dueBills.length})', _red,
                t.dueBills.map((b) => _dueBillTile(context, b)).toList()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final periods = store.totalsFor(kind);
        final allDays = store.totalsFor(PeriodKind.daily);
        final totalCashIn = allDays.fold(0.0, (s, d) => s + d.cashIn);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [maroon, Color(0xFF812C3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ALL TIME', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  _headerRow('Total billed', store.totalSales),
                  _headerRow('Total money received', totalCashIn),
                  _headerRow('Total still due', store.totalDue, highlight: store.totalDue > 0),
                ]),
              ),
              const SizedBox(height: 16),
              sectionTitle('Day Book',
                  subtitle: 'A payment counts in the period it was received. Open a card to see which dues were cleared.'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final k in PeriodKind.values)
                  ChoiceChip(
                    label: Text(k == PeriodKind.daily ? 'Daily' : k == PeriodKind.weekly ? 'Weekly' : 'Monthly'),
                    selected: kind == k,
                    onSelected: (_) => setState(() => kind = k),
                  ),
              ]),
              const SizedBox(height: 12),
              if (periods.isEmpty)
                const EmptyState(title: 'No bills yet', subtitle: 'Totals will appear here once you generate invoices.')
              else
                ...periods.map((t) => _periodCard(context, t)),
            ]),
          ),
        );
      },
    );
  }
}
