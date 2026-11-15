import 'package:flutter/material.dart';

import '../constants.dart';
import '../crm_models.dart';
import '../messages.dart';
import '../models.dart';
import '../store.dart';
import '../whatsapp.dart';
import '../widgets.dart';
import 'booking_form_page.dart';
import 'bookings_page.dart';

const _red = Color(0xFFC62828);
const _green = Color(0xFF2E7D32);

class BookingDetailPage extends StatefulWidget {
  final String bookingId;
  final bool justCreated;
  const BookingDetailPage({super.key, required this.bookingId, this.justCreated = false});

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage> {
  void _message(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action));
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

  // ---------- actions ----------

  Future<void> _receiveAdvance(Booking k) async {
    final before = k.advances.length;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AdvanceDialog(booking: k),
    );
    if (saved == true && mounted) {
      setState(() {});
      final latest = k.advances.length > before ? k.advances.last : null;
      _message(
        'Advance saved. Total advance ${money(k.advanceTotal)}.',
        action: latest == null
            ? null
            : SnackBarAction(
                label: 'WHATSAPP RECEIPT',
                onPressed: () => sendWhatsAppDialog(context,
                    phone: k.customerPhone, text: advanceReceiptText(k, latest), title: 'Advance receipt'),
              ),
      );
    }
  }

  Future<void> _removeAdvance(Booking k, Payment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this advance?'),
        content: Text('${money(p.amount)} received on ${fmtDate(p.date)} will be removed from this booking.'),
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
      await store.removeAdvance(k.id, p);
      if (mounted) setState(() {});
    }
  }

  Future<void> _markReady(Booking k) async {
    await store.setBookingStatus(k.id, BookingStatus.ready);
    if (!mounted) return;
    _message(
      'Marked as ready.',
      action: SnackBarAction(
        label: 'TELL CUSTOMER',
        onPressed: () async {
          final sent = await sendWhatsAppDialog(context,
              phone: k.customerPhone, text: bookingReadyText(k), title: 'Order ready message');
          if (sent) await store.logBookingReminder(k.id);
        },
      ),
    );
  }

  void _makeBill(Booking k) {
    store.startBillFromBooking(k);
    Navigator.of(context).popUntil((route) => route.isFirst);
    navIndex.value = 1;
  }

  Future<void> _cancel(Booking k) async {
    final result = await showDialog<(bool, String)>(
      context: context,
      builder: (_) => _CancelDialog(booking: k),
    );
    if (result == null) return;
    await store.cancelBooking(k.id, refund: result.$1, note: result.$2);
    if (mounted) setState(() {});
  }

  Future<void> _delete(Booking k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this booking?'),
        content: const Text('The booking and its advance records will be removed. '
            'This also removes its advance from the Day Book. This cannot be undone.'),
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
      await store.deleteBooking(k.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _whatsAppChoices(Booking k) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Send on WhatsApp', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: maroon)),
            ),
          ),
          if (k.advances.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.receipt_outlined, color: maroon),
              title: const Text('Advance receipt'),
              subtitle: const Text('Latest advance and total paid'),
              onTap: () {
                Navigator.pop(ctx);
                sendWhatsAppDialog(context,
                    phone: k.customerPhone, text: advanceReceiptText(k, k.advances.last), title: 'Advance receipt');
              },
            ),
          if (k.isOpen)
            ListTile(
              leading: const Icon(Icons.event_available_outlined, color: maroon),
              title: const Text('Delivery reminder'),
              subtitle: const Text('Remind about the booking and delivery date'),
              onTap: () async {
                Navigator.pop(ctx);
                final sent = await sendWhatsAppDialog(context,
                    phone: k.customerPhone, text: bookingReminderText(k), title: 'Booking reminder');
                if (sent) await store.logBookingReminder(k.id);
              },
            ),
          if (k.isOpen)
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: maroon),
              title: const Text('Order is ready'),
              subtitle: const Text('Ask the customer to collect it'),
              onTap: () async {
                Navigator.pop(ctx);
                final sent = await sendWhatsAppDialog(context,
                    phone: k.customerPhone, text: bookingReadyText(k), title: 'Order ready message');
                if (sent) await store.logBookingReminder(k.id);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _advanceRow(Booking k, Payment p) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Advance ${fmtDate(p.date)}'),
              if (p.note.trim().isNotEmpty)
                Text(p.note.trim(), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ]),
          ),
          Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w500)),
          if (k.isOpen)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove advance',
              onPressed: () => _removeAdvance(k, p),
              icon: const Icon(Icons.close, size: 18, color: Colors.black45),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final k = store.bookingById(widget.bookingId);
        if (k == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Booking')),
            body: const Center(child: Text('This booking was deleted.')),
          );
        }
        final info = deliveryInfo(k);
        final bill = k.billInvoiceNo.isEmpty ? null : store.billByInvoice(k.billInvoiceNo);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Booking', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingFormPage(editing: k)));
                  } else if (value == 'pending') {
                    await store.setBookingStatus(k.id, BookingStatus.pending);
                  } else if (value == 'delete') {
                    await _delete(k);
                  }
                },
                itemBuilder: (_) => [
                  if (k.isOpen) const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                  if (k.status == BookingStatus.ready) const PopupMenuItem(value: 'pending', child: Text('Mark as pending again')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete booking')),
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
                    child: const Row(children: [
                      Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Booking saved. You can send the advance receipt on WhatsApp below.',
                            style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.w600)),
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
                        const Text('BOOKING FOR', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
                        Text(k.customerName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(k.customerPhone.trim().isEmpty ? 'No mobile number' : k.customerPhone.trim(),
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Text('Booked on ${fmtDate(k.createdAt)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    bookingStatusChip(k.status),
                  ]),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      sectionTitle('Item'),
                      const SizedBox(height: 8),
                      Text(k.description.trim().isEmpty ? 'Advance only (no item)' : k.description.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(bookingItemLine(k), style: const TextStyle(color: Colors.black54)),
                      if (k.metal == ItemType.gold && k.lockedRateValue > 0) ...[
                        const SizedBox(height: 6),
                        Text('Booked rate: ${money(k.lockedRateValue)} per 10 g (24K)',
                            style: const TextStyle(color: maroon, fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                      if (info != null) ...[
                        const SizedBox(height: 6),
                        Text(info.text, style: TextStyle(color: info.color, fontWeight: FontWeight.w700)),
                      ],
                      if (k.note.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(k.note.trim(), style: TextStyle(color: Colors.brown.shade500)),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
                Card(
                  color: const Color(0xFFFFF8E9),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      if (k.estimateValue > 0) _row('Estimated total', k.estimateValue),
                      ...k.advances.map((p) => _advanceRow(k, p)),
                      if (k.advances.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Align(alignment: Alignment.centerLeft, child: Text('No advance received yet.')),
                        ),
                      const Divider(),
                      _row('TOTAL ADVANCE', k.advanceTotal, bold: true, color: _green),
                      if (k.estimateValue > 0) _row('Estimated balance', k.balance, color: k.balance > 0 ? _red : _green),
                      if (k.refundAmount > 0.005) ...[
                        const Divider(),
                        _row('Advance returned on ${fmtDate(k.refundDate ?? k.createdAt)}', k.refundAmount, color: _red),
                      ],
                    ]),
                  ),
                ),
                if (k.remindedAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Reminded ${k.remindedAt.length} time${k.remindedAt.length == 1 ? '' : 's'}, last on ${fmtDate(k.remindedAt.last)}.',
                      style: TextStyle(color: Colors.brown.shade400, fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                if (k.status == BookingStatus.delivered) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long, color: maroon),
                      title: Text('Delivered  •  Invoice ${k.billInvoiceNo}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(bill == null ? 'This bill was deleted.' : 'Tap to open the bill'),
                      onTap: bill == null ? null : () => openBill(context, bill),
                    ),
                  ),
                ],
                if (k.isOpen) ...[
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                      onPressed: () => _receiveAdvance(k),
                      icon: const Icon(Icons.add_card),
                      label: const Text('RECEIVE ADVANCE'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                      onPressed: () => _makeBill(k),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('MAKE BILL / DELIVER'),
                    ),
                  ),
                  if (k.status == BookingStatus.pending) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _markReady(k),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('MARK AS READY'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _whatsAppChoices(k),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('WHATSAPP'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => callWithMessage(context, k.customerPhone),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('CALL'),
                      ),
                    ),
                  ),
                ]),
                if (k.isOpen) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _cancel(k),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('CANCEL BOOKING'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _AdvanceDialog extends StatefulWidget {
  final Booking booking;
  const _AdvanceDialog({required this.booking});

  @override
  State<_AdvanceDialog> createState() => _AdvanceDialogState();
}

class _AdvanceDialogState extends State<_AdvanceDialog> {
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
    final err = await store.addAdvance(widget.booking.id, parseNum(amount.text), note: note.text.trim());
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
    final k = widget.booking;
    return AlertDialog(
      title: const Text('Receive advance'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Advance so far: ${money(k.advanceTotal)}', style: const TextStyle(fontWeight: FontWeight.w700, color: maroon)),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount received (Rs.)', errorText: error),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional, e.g. cash / UPI)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: const Text('Save advance')),
      ],
    );
  }
}

class _CancelDialog extends StatefulWidget {
  final Booking booking;
  const _CancelDialog({required this.booking});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final note = TextEditingController();
  late bool refund = widget.booking.advanceTotal > 0.005;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final advance = widget.booking.advanceTotal;
    return AlertDialog(
      title: const Text('Cancel this booking?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (advance > 0.005)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Advance ${money(advance)} returned to customer'),
              subtitle: const Text('Turn off if you are keeping it.'),
              value: refund,
              onChanged: (v) => setState(() => refund = v),
            )
          else
            const Text('No advance was received for this booking.'),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep booking')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, (refund, note.text)),
          child: const Text('Cancel booking'),
        ),
      ],
    );
  }
}
