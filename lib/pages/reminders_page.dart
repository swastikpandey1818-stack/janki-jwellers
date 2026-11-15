import 'package:flutter/material.dart';

import '../backup_helper.dart';
import '../constants.dart';
import '../crm_models.dart';
import '../messages.dart';
import '../models.dart';
import '../store.dart';
import '../whatsapp.dart';
import '../widgets.dart';
import 'bookings_page.dart';

const _red = Color(0xFFC62828);
const _green = Color(0xFF1FA855);

/// One place for everything that needs a call or a WhatsApp today:
/// pending dues, deliveries, birthdays / anniversaries and the backup reminder.
class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  String _remindedText(List<DateTime> log) {
    if (log.isEmpty) return 'Not reminded yet';
    final days = DateTime.now().difference(log.last).inDays;
    final when = days <= 0 ? 'today' : (days == 1 ? 'yesterday' : '$days days ago');
    return 'Reminded ${log.length}x, last $when';
  }

  Widget _sectionHeader(String title, int count, {String? subtitle}) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: sectionTitle(title, subtitle: subtitle)),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: maroon, borderRadius: BorderRadius.circular(20)),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
        ]),
      );

  Widget _actionButtons(BuildContext context, {required String phone, required VoidCallback onWhatsApp}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'WhatsApp',
        onPressed: onWhatsApp,
        icon: const Icon(Icons.chat, color: _green),
      ),
      IconButton(
        tooltip: 'Call',
        onPressed: () => callWithMessage(context, phone),
        icon: const Icon(Icons.call, color: maroon),
      ),
    ]);
  }

  Widget _dueTile(BuildContext context, SavedBill b) {
    final age = DateTime.now().difference(b.createdAt).inDays;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openBill(context, b),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.customerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text('${b.invoiceNo}  •  ${fmtDate(b.createdAt)}  •  ${age <= 0 ? 'today' : '$age day${age == 1 ? '' : 's'} old'}',
                    style: TextStyle(color: Colors.brown.shade500, fontSize: 12)),
                const SizedBox(height: 2),
                Text(_remindedText(b.remindedAt), style: TextStyle(color: Colors.brown.shade400, fontSize: 11.5)),
              ]),
            ),
            Text(money(b.dueAmount), style: const TextStyle(color: _red, fontWeight: FontWeight.w900, fontSize: 14.5)),
            _actionButtons(
              context,
              phone: b.data.customerPhone,
              onWhatsApp: () async {
                final sent = await sendWhatsAppDialog(context,
                    phone: b.data.customerPhone, text: dueReminderText(b), title: 'Due reminder');
                if (sent) await store.logBillReminder(b.invoiceNo);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bookingTile(BuildContext context, Booking k) {
    final info = deliveryInfo(k);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openBooking(context, k),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.customerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(k.description.trim().isEmpty ? bookingItemLine(k) : k.description.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.brown.shade500, fontSize: 12)),
                if (info != null)
                  Text(info.text, style: TextStyle(color: info.color, fontSize: 12, fontWeight: FontWeight.w700)),
                Text(_remindedText(k.remindedAt), style: TextStyle(color: Colors.brown.shade400, fontSize: 11.5)),
              ]),
            ),
            bookingStatusChip(k.status),
            _actionButtons(
              context,
              phone: k.customerPhone,
              onWhatsApp: () async {
                final text = k.status == BookingStatus.ready ? bookingReadyText(k) : bookingReminderText(k);
                final sent = await sendWhatsAppDialog(context, phone: k.customerPhone, text: text, title: 'Booking message');
                if (sent) await store.logBookingReminder(k.id);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _occasionTile(BuildContext context, Customer c, bool birthday, int days) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(children: [
          Icon(birthday ? Icons.cake_outlined : Icons.favorite_border, color: maroon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text('${birthday ? 'Birthday' : 'Anniversary'} ${relativeDays(days)}',
                  style: TextStyle(color: days == 0 ? _red : Colors.brown.shade500, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          _actionButtons(
            context,
            phone: c.phone,
            onWhatsApp: () => sendWhatsAppDialog(context,
                phone: c.phone,
                text: birthday ? birthdayText(c) : anniversaryText(c),
                title: birthday ? 'Birthday wish' : 'Anniversary wish'),
          ),
        ]),
      ),
    );
  }

  Future<void> _backupNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final err = await saveBackupFile();
    messenger.showSnackBar(SnackBar(
        content: Text(err == null ? 'Backup saved. Keep the file safe (Drive / WhatsApp to yourself).' : 'Could not save backup: $err')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final dues = store.dueBills;
        final deliveries = store.bookingsDueSoon(days: 7);
        final occasions = store.upcomingOccasions(days: 7);
        final nothing = dues.isEmpty && deliveries.isEmpty && occasions.isEmpty && !store.backupDue;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              sectionTitle('Reminders', subtitle: 'Tap the WhatsApp icon to send a ready-made message. You can edit it first.'),
              if (nothing)
                const EmptyState(title: 'All clear', subtitle: 'No dues, deliveries or special days to remind about right now.'),
              if (store.backupDue) ...[
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xFFFFF3E0),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.cloud_upload_outlined, color: maroon),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Backup needed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                      ]),
                      const SizedBox(height: 6),
                      Text(store.lastBackupAt == null
                          ? 'You have not made a backup yet.'
                          : 'Last backup was ${store.daysSinceBackup} days ago. ${store.changesSinceBackup} change${store.changesSinceBackup == 1 ? '' : 's'} are not backed up.'),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                          onPressed: () => _backupNow(context),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('BACK UP NOW'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
              if (dues.isNotEmpty) ...[
                _sectionHeader('Pending dues', dues.length, subtitle: 'Oldest first. Total ${money(store.totalDue)}.'),
                ...dues.map((b) => _dueTile(context, b)),
              ],
              if (deliveries.isNotEmpty) ...[
                _sectionHeader('Deliveries', deliveries.length, subtitle: 'Overdue and due in the next 7 days.'),
                ...deliveries.map((k) => _bookingTile(context, k)),
              ],
              if (occasions.isNotEmpty) ...[
                _sectionHeader('Birthdays & anniversaries', occasions.length, subtitle: 'Today and the next 7 days.'),
                ...occasions.map((o) => _occasionTile(context, o.customer, o.birthday, o.days)),
              ],
              const SizedBox(height: 20),
            ]),
          ),
        );
      },
    );
  }
}
