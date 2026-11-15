import 'package:flutter/material.dart';

import 'constants.dart';
import 'models.dart';
import 'pages/bill_detail_page.dart';
import 'store.dart';

String typeImage(ItemType type) {
  switch (type) {
    case ItemType.gold:
      return goldBarAsset;
    case ItemType.silver:
      return silverBarAsset;
    case ItemType.other:
      return gemAsset;
  }
}

Widget sectionTitle(String title, {String? subtitle}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: maroon)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: Colors.brown.shade500, fontSize: 12)),
        ],
      ],
    );

void openBill(BuildContext context, SavedBill bill) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BillDetailPage(bill: bill)));
}

/// Loads the bill's customer + items into the billing page and switches to it.
void useAsNewBill(BuildContext context, SavedBill bill) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  store.useAsTemplate(bill.data);
  navIndex.value = 1;
}

Future<bool> confirmDeleteBill(BuildContext context, SavedBill bill) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this bill?'),
      content: Text('${bill.invoiceNo} (${bill.customerName}) will be removed from history. '
          'Its invoice number will not be reused.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await store.deleteBill(bill.invoiceNo);
    return true;
  }
  return false;
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const StatCard({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: maroon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.brown.shade500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: maroon)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const EmptyState({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(children: [
        Image.asset(emptyBillsAsset, height: 170, errorBuilder: (_, __, ___) =>
            const Icon(Icons.receipt_long, size: 80, color: gold)),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: maroon)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.brown.shade500)),
      ]),
    );
  }
}

class BillTile extends StatelessWidget {
  final SavedBill bill;
  const BillTile({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    final itemCount = bill.data.items.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openBill(context, bill),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.receipt_long, color: maroon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bill.invoiceNo,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: maroon, fontSize: 15)),
                const SizedBox(height: 2),
                Text(bill.customerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${fmtDateTime(bill.createdAt)}  •  $itemCount item${itemCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 11.5, color: Colors.brown.shade400)),
              ]),
            ),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(bill.grandTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              if (bill.hasDue)
                Text('Due ${money(bill.dueAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: Color(0xFFC62828))),
            ]),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'view') {
                  openBill(context, bill);
                } else if (value == 'reuse') {
                  useAsNewBill(context, bill);
                } else if (value == 'delete') {
                  await confirmDeleteBill(context, bill);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'view', child: Text('View / Share / Print')),
                PopupMenuItem(value: 'reuse', child: Text('Use as new bill')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
