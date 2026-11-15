import 'package:flutter/material.dart';

import '../constants.dart';
import '../store.dart';
import '../widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final search = TextEditingController();
  String query = '';
  bool dueOnly = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = query.trim().toLowerCase();
        final base = dueOnly ? store.bills.where((b) => b.hasDue).toList() : store.bills;
        final list = q.isEmpty
            ? base
            : base
                .where((b) =>
                    b.invoiceNo.toLowerCase().contains(q) ||
                    b.customerName.toLowerCase().contains(q) ||
                    b.data.customerPhone.contains(q))
                .toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [maroon, Color(0xFF812C3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(children: [
                      Image.asset(goldBarAsset, width: 54, height: 54,
                          errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long, color: Colors.white, size: 40)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${store.totalBills} bill${store.totalBills == 1 ? '' : 's'} generated',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 3),
                          Text('Total sales ${money(store.totalSales)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                          if (store.totalDue > 0)
                            Text('Total due ${money(store.totalDue)}  (${store.dueBillCount} bill${store.dueBillCount == 1 ? '' : 's'})',
                                style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 12.5, fontWeight: FontWeight.w700)),
                          Text('Next invoice: ${store.nextInvoiceNo}',
                              style: const TextStyle(color: Color(0xFFF0D080), fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: search,
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'Search invoice no, customer or mobile',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                search.clear();
                                setState(() => query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, children: [
                      ChoiceChip(
                        label: const Text('All bills'),
                        selected: !dueOnly,
                        onSelected: (_) => setState(() => dueOnly = false),
                      ),
                      ChoiceChip(
                        label: Text('Due only (${store.dueBillCount})'),
                        selected: dueOnly,
                        onSelected: (_) => setState(() => dueOnly = true),
                      ),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? ListView(children: [
                        EmptyState(
                          title: store.bills.isEmpty ? 'No bills yet' : 'No matching bills',
                          subtitle: store.bills.isEmpty
                              ? 'Generated invoices are saved here automatically.'
                              : 'Try a different invoice number, name or mobile.',
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (context, i) => BillTile(bill: list[i]),
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
