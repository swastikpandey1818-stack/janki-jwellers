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
      height: 178,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [maroonDark, maroon],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(children: [
        Container(
          width: 128,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold, width: 1.5),
          ),
          child: Image.asset(logoFullAsset, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: maroon, size: 48)),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(shopName,
                style: TextStyle(
                    color: goldLight, fontWeight: FontWeight.w800, fontSize: 20, height: 1.15, fontFamily: 'serif')),
            SizedBox(height: 8),
            Text(shopAddress, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
            SizedBox(height: 6),
            Text(shopPhone, style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

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
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                  onPressed: () => navIndex.value = 1,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('CREATE NEW INVOICE'),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookingFormPage())),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('NEW BOOKING'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => navIndex.value = 5,
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: const Text('CUSTOMERS'),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => navIndex.value = 2,
                  icon: const Icon(Icons.history),
                  label: const Text('VIEW ALL BILLS'),
                ),
              ),
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
