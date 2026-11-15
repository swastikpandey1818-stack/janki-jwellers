import 'package:flutter/material.dart';

import '../constants.dart';
import '../store.dart';
import '../widgets.dart';

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
              const SizedBox(height: 14),
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
              StatCard(icon: Icons.account_balance_wallet_outlined, label: 'Total Due (to collect)', value: money(store.totalDue)),
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
