import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../constants.dart';
import '../models.dart';
import '../pdf_service.dart';
import '../store.dart';
import '../widgets.dart';

class BillDetailPage extends StatefulWidget {
  final SavedBill bill;
  final bool justCreated;
  const BillDetailPage({super.key, required this.bill, this.justCreated = false});

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  bool busy = false;

  SavedBill get bill => widget.bill;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String errorPrefix) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      _message('$errorPrefix: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sharePdf() => _run(() async {
        final bytes = await PdfService.build(bill);
        await Printing.sharePdf(bytes: bytes, filename: PdfService.fileName(bill));
      }, 'Could not open PDF sharing');

  Future<void> downloadPdf() => _run(() async {
        final bytes = await PdfService.build(bill);
        await FileSaver.instance.saveFile(
          name: PdfService.fileName(bill).replaceAll('.pdf', ''),
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
        _message('PDF saved successfully.');
      }, 'Could not save PDF');

  Future<void> printPdf() => _run(() async {
        final bytes = await PdfService.build(bill);
        await Printing.layoutPdf(onLayout: (format) async => bytes, name: PdfService.fileName(bill));
      }, 'Could not open print preview');

  String _describe(ItemData item, BillData d) {
    switch (item.type) {
      case ItemType.gold:
        return 'Gold ${item.goldPurity}K  •  ${item.weightValue.toStringAsFixed(2)} g  •  ${money(d.metalRateFor(item))}/g';
      case ItemType.silver:
        return 'Silver  •  ${item.weightValue.toStringAsFixed(2)} g  •  ${money(d.silverRatePerGram)}/g';
      case ItemType.other:
        final w = item.weight.trim();
        return w.isEmpty ? 'Others' : 'Others  •  $w';
    }
  }

  Widget _row(String label, double value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 16 : 14)),
          Text(money(value),
              style: TextStyle(
                color: color ?? (bold ? maroon : Colors.black87),
                fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
                fontSize: bold ? 19 : 14,
              )),
        ]),
      );

  static const _red = Color(0xFFC62828);
  static const _green = Color(0xFF2E7D32);

  double _qrAmountFor(QrMode m) {
    switch (m) {
      case QrMode.due:
        return bill.dueAmount;
      case QrMode.paid:
        return bill.paidAtBilling;
      case QrMode.total:
        return bill.grandTotal;
    }
  }

  Future<void> _receivePayment() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceivePaymentDialog(bill: bill),
    );
    if (saved == true && mounted) {
      setState(() {});
      _message(bill.hasDue
          ? 'Payment saved. Balance due is now ${money(bill.dueAmount)}.'
          : 'Payment saved. This bill is now fully paid.');
    }
  }

  Future<void> _removePayment(Payment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this payment?'),
        content: Text('${money(p.amount)} received on ${fmtDate(p.date)} will be removed and the due will go up again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.removePayment(bill.invoiceNo, p);
      if (mounted) setState(() {});
    }
  }

  Widget _paymentRow(Payment p) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Received ${fmtDate(p.date)}'),
              if (p.note.trim().isNotEmpty)
                Text(p.note.trim(), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ]),
          ),
          Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w500)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove payment',
            onPressed: () => _removePayment(p),
            icon: const Icon(Icons.close, size: 18, color: Colors.black45),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = bill.data;
    return Scaffold(
      appBar: AppBar(
        title: Text(bill.invoiceNo, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reuse') {
                useAsNewBill(context, bill);
              } else if (value == 'delete') {
                final deleted = await confirmDeleteBill(context, bill);
                if (deleted && context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reuse', child: Text('Use as new bill')),
              PopupMenuItem(value: 'delete', child: Text('Delete bill')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (widget.justCreated)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF81C784)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Invoice ${bill.invoiceNo} generated and saved to Bill History.',
                        style: const TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [maroon, Color(0xFF812C3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('INVOICE NO', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
                    Text(bill.invoiceNo,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
                    const SizedBox(height: 6),
                    Text(fmtDateTime(bill.createdAt), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                Image.asset(gemAsset, width: 58, height: 58,
                    errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Colors.white, size: 40)),
              ]),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle('Customer'),
                  const SizedBox(height: 8),
                  Text(bill.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(d.customerPhone.trim().isEmpty ? 'Mobile not provided' : d.customerPhone.trim(),
                      style: const TextStyle(color: Colors.black54)),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle('Items'),
                  const SizedBox(height: 8),
                  ...d.items.asMap().entries.map((e) {
                    final item = e.value;
                    final amount = d.amountFor(item);
                    final making = d.makingFor(item);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Image.asset(typeImage(item.type), width: 38, height: 38,
                            errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: gold)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${e.key + 1}. ${item.name.trim().isEmpty ? 'Item' : item.name.trim()}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(_describe(item, d), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                            if (making > 0)
                              Text('Making ${money(making)}',
                                  style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                          ]),
                        ),
                        Text(money(amount + making),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: maroon)),
                      ]),
                    );
                  }),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Card(
              color: const Color(0xFFFFF8E9),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _row('Items Amount', d.jewelleryTotal),
                  _row('Making Charges', d.makingTotal),
                  const Divider(),
                  _row('Subtotal', d.subtotal),
                  _row('GST (${d.applyGst ? d.gstPercentage : 0}%)', d.gstAmount),
                  const Divider(),
                  _row('GRAND TOTAL', d.grandTotal, bold: true),
                  if (d.hasPaymentEntry) ...[
                    const Divider(),
                    _row('Paid at billing', bill.paidAtBilling),
                    ...bill.payments.map(_paymentRow),
                    _row(bill.hasDue ? 'BALANCE DUE' : 'PAID IN FULL', bill.dueAmount,
                        bold: true, color: bill.hasDue ? _red : _green),
                  ],
                ]),
              ),
            ),
            if (d.hasPaymentEntry) ...[
              const SizedBox(height: 4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    sectionTitle('Amount on QR code', subtitle: 'Choose what the customer pays by scanning the QR on the PDF.'),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final mode in QrMode.values)
                        ChoiceChip(
                          label: Text('${qrModeLabel(mode)}  ${money(_qrAmountFor(mode))}'),
                          selected: d.effectiveQrMode == mode,
                          onSelected: (_) async {
                            await store.setQrMode(bill.invoiceNo, mode);
                            if (mounted) setState(() {});
                          },
                        ),
                    ]),
                  ]),
                ),
              ),
              if (bill.hasDue) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                    onPressed: _receivePayment,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('RECEIVE PAYMENT / CLEAR DUE'),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                onPressed: busy ? null : sharePdf,
                icon: const Icon(Icons.share),
                label: Text(busy ? 'PLEASE WAIT...' : 'SHARE PDF / WHATSAPP'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: busy ? null : downloadPdf,
                icon: const Icon(Icons.download),
                label: const Text('DOWNLOAD PDF'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: busy ? null : printPdf,
                icon: const Icon(Icons.print),
                label: const Text('PRINT / PREVIEW BILL'),
              ),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

/// Asks how much money was received against a bill's due.
class _ReceivePaymentDialog extends StatefulWidget {
  final SavedBill bill;
  const _ReceivePaymentDialog({required this.bill});

  @override
  State<_ReceivePaymentDialog> createState() => _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends State<_ReceivePaymentDialog> {
  final amount = TextEditingController();
  final note = TextEditingController();
  String? error;
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    final err = await store.addPayment(widget.bill.invoiceNo, parseNum(amount.text), note: note.text.trim());
    if (!mounted) return;
    if (err != null) {
      setState(() {
        error = err;
        saving = false;
      });
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = widget.bill.dueAmount;
    return AlertDialog(
      title: const Text('Receive payment'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Balance due: ${money(due)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFC62828))),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount received (Rs.)', errorText: error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                amount.text = due.toStringAsFixed(2);
                error = null;
              }),
              child: const Text('Fill full due'),
            ),
          ),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional, e.g. cash / UPI)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: const Text('Save payment')),
      ],
    );
  }
}
