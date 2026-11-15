import 'package:flutter/material.dart';

import '../constants.dart';
import '../store.dart';
import '../widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _banner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 190,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset(headerBannerAsset, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: maroon)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xCC340A16), Color(0x00340A16)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 0,
            bottom: 0,
            right: 130,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(logoAsset, width: 52, height: 52, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Colors.white, size: 40)),
              ),
              const SizedBox(height: 10),
              const Text(shopName,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, height: 1.15)),
              const SizedBox(height: 4),
              const Text(shopAddress, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ]),
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
