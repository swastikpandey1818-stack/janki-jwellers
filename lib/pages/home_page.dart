import 'package:flutter/material.dart';

import '../backup_helper.dart';
import '../constants.dart';
import '../rates_card.dart';
import '../store.dart';
import '../widgets.dart';
import 'booking_form_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _banner() {
    return Container(
      height: 196,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gold, width: 1.6),
        boxShadow: const [BoxShadow(color: Color(0x40340A16), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.5),
        child: Stack(fit: StackFit.expand, children: [
          // Diamond + gold rings texture
          Image.asset(headerBannerAsset,
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              errorBuilder: (_, __, ___) => Container(color: maroon)),
          // Dark fade on the left so the text stays readable
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xE6340A16), Color(0x99340A16), Color(0x00340A16)],
                stops: [0.0, 0.55, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 96, 14),
            child: Row(children: [
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: gold, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: ClipOval(
                  child: Image.asset(logoAsset, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: maroon, size: 32)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(shopName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: goldLight, fontWeight: FontWeight.w800, fontSize: 19, height: 1.15, fontFamily: 'serif')),
                  const SizedBox(height: 6),
                  Container(
                    width: 36,
                    height: 2.5,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [gold, goldLight]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(shopAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 5),
                  const Text(shopPhone,
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECE4D8)),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [maroon, maroonDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    border: Border.all(color: gold, width: 1.5),
                  ),
                  child: Icon(icon, color: goldLight, size: 22),
                ),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: maroon, fontSize: 11.5, height: 1.15)),
              ]),
            ),
          ),
        ),
      );

  Future<void> _backupNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final err = await saveBackupFile();
    messenger.showSnackBar(SnackBar(
        content: Text(err == null ? 'Backup saved. Keep the file safe (Drive / WhatsApp to yourself).' : 'Could not save backup: $err')));
  }

  Widget _alertRow(IconData icon, String text, {VoidCallback? onTap, Widget? trailing}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, color: maroon, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            trailing ?? (onTap == null ? const SizedBox.shrink() : const Icon(Icons.chevron_right, color: Colors.black38)),
          ]),
        ),
      );

  /// Things that need attention today: backup, dues, deliveries, birthdays.
  Widget _attention(BuildContext context) {
    final rows = <Widget>[];
    if (store.backupDue) {
      rows.add(_alertRow(
        Icons.cloud_upload_outlined,
        store.lastBackupAt == null
            ? 'You have not made a backup yet.'
            : 'Backup is ${store.daysSinceBackup} days old, ${store.changesSinceBackup} change${store.changesSinceBackup == 1 ? '' : 's'} not saved.',
        trailing: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: maroon, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
          onPressed: () => _backupNow(context),
          child: const Text('Back up'),
        ),
      ));
    }
    if (store.dueBillCount > 0) {
      rows.add(_alertRow(
        Icons.account_balance_wallet_outlined,
        '${store.dueBillCount} bill${store.dueBillCount == 1 ? '' : 's'} with due: ${money(store.totalDue)}',
        onTap: () => navIndex.value = 7,
      ));
    }
    final soon = store.bookingsDueSoon();
    if (soon.isNotEmpty) {
      rows.add(_alertRow(
        Icons.event_available_outlined,
        '${soon.length} booking${soon.length == 1 ? '' : 's'} due for delivery within 3 days or overdue',
        onTap: () => navIndex.value = 6,
      ));
    }
    final today = store.upcomingOccasions(days: 0);
    if (today.isNotEmpty) {
      final names = today.map((o) => '${o.customer.name} (${o.birthday ? 'birthday' : 'anniversary'})').join(', ');
      rows.add(_alertRow(Icons.cake_outlined, 'Today: $names', onTap: () => navIndex.value = 7));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Card(
        color: const Color(0xFFFFF3E0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Needs your attention', style: TextStyle(fontWeight: FontWeight.w800, color: maroon, fontSize: 15)),
            const SizedBox(height: 2),
            ...rows,
          ]),
        ),
      ),
    );
  }

  Widget _category(String image, String label) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Image.asset(image, height: 56, errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: gold)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: maroon)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final recent = store.bills.take(5).toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _banner(),
              const SizedBox(height: 12),
              const RatesCard(),
              const SizedBox(height: 6),
              _attention(context),
              Row(children: [
                Expanded(child: StatCard(icon: Icons.receipt_long, label: 'Total Bills', value: '${store.totalBills}')),
                const SizedBox(width: 10),
                Expanded(child: StatCard(icon: Icons.today, label: 'Bills Today', value: '${store.todayCount}')),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: StatCard(icon: Icons.currency_rupee, label: 'Total Sales', value: money(store.totalSales))),
                const SizedBox(width: 10),
                Expanded(child: StatCard(icon: Icons.confirmation_number_outlined, label: 'Next Invoice', value: store.nextInvoiceNo)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: StatCard(icon: Icons.account_balance_wallet_outlined, label: 'Total Due', value: money(store.totalDue))),
                const SizedBox(width: 10),
                Expanded(child: StatCard(icon: Icons.bookmark_outline, label: 'Advance Held', value: money(store.advanceHeld))),
              ]),
              const SizedBox(height: 10),
              const SizedBox(height: 12),
              Row(children: [
                _action(Icons.add_circle_outline, 'New\nInvoice', () => navIndex.value = 1),
                _action(Icons.bookmark_add_outlined, 'New\nBooking',
                    () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookingFormPage()))),
                _action(Icons.people_outline, 'Customers', () => navIndex.value = 5),
                _action(Icons.history, 'All\nBills', () => navIndex.value = 2),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _action(Icons.insights_outlined, 'Reports', () => navIndex.value = 8),
                _action(Icons.inventory_2_outlined, 'Stock', () => navIndex.value = 9),
                _action(Icons.calendar_month_outlined, 'Day\nBook', () => navIndex.value = 3),
                _action(Icons.notifications_none, 'Reminders', () => navIndex.value = 7),
              ]),
              const SizedBox(height: 18),
              sectionTitle('We deal in'),
              const SizedBox(height: 6),
              Row(children: [
                _category(goldBarAsset, 'Gold'),
                _category(silverBarAsset, 'Silver'),
                _category(gemAsset, 'Gems & More'),
              ]),
              const SizedBox(height: 14),
              sectionTitle('Recent Bills', subtitle: 'Your latest generated invoices.'),
              const SizedBox(height: 10),
              if (recent.isEmpty)
                const EmptyState(
                  title: 'No bills yet',
                  subtitle: 'Generate your first invoice and it will appear here.',
                )
              else
                ...recent.map((b) => BillTile(bill: b)),
            ]),
          ),
        );
      },
    );
  }
}
