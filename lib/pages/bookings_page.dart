import 'package:flutter/material.dart';

import '../constants.dart';
import '../crm_models.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'booking_detail_page.dart';
import 'booking_form_page.dart';

const _red = Color(0xFFC62828);
const _green = Color(0xFF2E7D32);
const _amber = Color(0xFFB26A00);

void openBooking(BuildContext context, Booking booking) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingDetailPage(bookingId: booking.id)));
}

/// "Gold 22K  •  12.5 g" style line describing what was booked.
String bookingItemLine(Booking k) {
  final buf = StringBuffer(itemTypeName(k.metal));
  if (k.metal == ItemType.gold) buf.write(' ${k.goldPurity}K');
  final w = k.weight.trim();
  if (w.isNotEmpty) {
    buf.write('  •  $w');
    if (k.metal != ItemType.other) buf.write(' g');
  }
  return buf.toString();
}

Color bookingStatusColor(BookingStatus s) {
  switch (s) {
    case BookingStatus.pending:
      return _amber;
    case BookingStatus.ready:
      return _green;
    case BookingStatus.delivered:
      return const Color(0xFF00695C);
    case BookingStatus.cancelled:
      return Colors.black45;
  }
}

Widget bookingStatusChip(BookingStatus s) {
  final color = bookingStatusColor(s);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withAlpha(120)),
    ),
    child: Text(bookingStatusLabel(s), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
  );
}

/// Delivery date text for an open booking, with a colour (red = overdue, amber = within 3 days).
({String text, Color color})? deliveryInfo(Booking k) {
  final d = k.deliveryDate;
  if (d == null) return null;
  final left = k.daysToDelivery(DateTime.now());
  if (left == null) return null;
  if (!k.isOpen) return (text: 'Delivery date ${fmtDate(d)}', color: Colors.black54);
  if (left < 0) return (text: 'Overdue: was ${fmtDate(d)} (${relativeDays(left)})', color: _red);
  return (text: 'Delivery ${fmtDate(d)}  (${relativeDays(left)})', color: left <= 3 ? _amber : Colors.black54);
}

class BookingTile extends StatelessWidget {
  final Booking booking;
  const BookingTile({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final k = booking;
    final info = deliveryInfo(k);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openBooking(context, k),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.bookmark_outline, color: maroon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.customerName.trim().isEmpty ? 'Customer' : k.customerName.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(k.description.trim().isEmpty ? bookingItemLine(k) : '${k.description.trim()}  •  ${bookingItemLine(k)}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.brown.shade500, fontSize: 12.5)),
                if (info != null) ...[
                  const SizedBox(height: 3),
                  Text(info.text, style: TextStyle(color: info.color, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 4),
                Text('Advance ${money(k.advanceTotal)}${k.estimateValue > 0 ? '  •  Balance ${money(k.balance)}' : ''}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 8),
            bookingStatusChip(k.status),
          ]),
        ),
      ),
    );
  }
}

enum _Filter { open, delivered, cancelled, all }

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  final search = TextEditingController();
  String query = '';
  _Filter filter = _Filter.open;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String _filterLabel(_Filter f) {
    switch (f) {
      case _Filter.open:
        return 'Open (${store.openBookings.length})';
      case _Filter.delivered:
        return 'Delivered';
      case _Filter.cancelled:
        return 'Cancelled';
      case _Filter.all:
        return 'All';
    }
  }

  bool _passes(Booking k) {
    switch (filter) {
      case _Filter.open:
        return k.isOpen;
      case _Filter.delivered:
        return k.status == BookingStatus.delivered;
      case _Filter.cancelled:
        return k.status == BookingStatus.cancelled;
      case _Filter.all:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = query.trim().toLowerCase();
        var list = store.bookings.where(_passes).toList();
        if (filter == _Filter.open) {
          // Soonest delivery first; no date goes last.
          list.sort((a, b) {
            final da = a.deliveryDate;
            final db = b.deliveryDate;
            if (da == null && db == null) return b.createdAt.compareTo(a.createdAt);
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });
        }
        if (q.isNotEmpty) {
          list = list
              .where((k) =>
                  k.customerName.toLowerCase().contains(q) ||
                  k.customerPhone.contains(q) ||
                  k.description.toLowerCase().contains(q))
              .toList();
        }
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
                      Image.asset(gemAsset, width: 54, height: 54,
                          errorBuilder: (_, __, ___) => const Icon(Icons.bookmark, color: Colors.white, size: 40)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${store.openBookings.length} open booking${store.openBookings.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 3),
                          Text('Advance held ${money(store.advanceHeld)}',
                              style: const TextStyle(color: Color(0xFFF0D080), fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookingFormPage())),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('NEW BOOKING / ADVANCE'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: search,
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'Search customer, mobile or item',
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
                      for (final f in _Filter.values)
                        ChoiceChip(
                          label: Text(_filterLabel(f)),
                          selected: filter == f,
                          onSelected: (_) => setState(() => filter = f),
                        ),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? ListView(children: [
                        EmptyState(
                          title: store.bookings.isEmpty ? 'No bookings yet' : 'Nothing here',
                          subtitle: store.bookings.isEmpty
                              ? 'Take an advance for a jewellery order and track it until delivery.'
                              : 'No bookings match this filter.',
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (context, i) => BookingTile(booking: list[i]),
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
