import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../store.dart';
import '../widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _editRates(BuildContext context) async {
    final gold = TextEditingController(text: store.goldRate.toStringAsFixed(2));
    final silver = TextEditingController(text: store.silverRate.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Set Gold & Silver Rates'),
      content: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: gold, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gold per 10 grams (Rs.)'), validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter a valid rate'),
        const SizedBox(height: 12),
        TextFormField(controller: silver, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Silver per gram (Rs.)'), validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter a valid rate'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save rates'))],
    ));
    if (save == true) await store.setRates(gold: double.parse(gold.text), silver: double.parse(silver.text), source: 'Manual');
    gold.dispose(); silver.dispose();
  }

  Future<void> _fetchRates(BuildContext context) async {
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Fetching live market rates…'))])));
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      Future<Map<String, dynamic>> getJson(String url) async {
        final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
        request.headers.set(HttpHeaders.userAgentHeader, 'ShreeJankiJewellers/1.6');
        final response = await request.close().timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) throw Exception('Rate service returned HTTP ${response.statusCode}');
        return jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      }
      final results = await Future.wait([getJson('https://api.gold-api.com/price/XAU'), getJson('https://api.gold-api.com/price/XAG'), getJson('https://open.er-api.com/v6/latest/USD')]);
      client.close();
      final goldUsd = (results[0]['price'] as num).toDouble();
      final silverUsd = (results[1]['price'] as num).toDouble();
      final inr = ((results[2]['rates'] as Map)['INR'] as num).toDouble();
      final goldInr = goldUsd * inr * 10 / 31.1034768;
      final silverInr = silverUsd * inr / 31.1034768;
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await store.setRates(gold: goldInr, silver: silverInr, source: 'Online (USD/INR converted)');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Online market rates updated. Verify local jeweller premiums before billing.')));
    } catch (e) {
      if (context.mounted) { Navigator.of(context, rootNavigator: true).pop(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not fetch rates. Your saved rates are unchanged. Details: $e'))); }
    }
  }

  Widget _rateCards(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: _rateCard(context, icon: Icons.edit, title: 'Set Rates Manually', subtitle: 'Enter shop rates', button: 'SET RATES', onTap: () => _editRates(context))),
      const SizedBox(width: 10),
      Expanded(child: _rateCard(context, icon: Icons.public, title: 'Fetch Rates Online', subtitle: 'Market reference rates', button: 'FETCH NOW', onTap: () => _fetchRates(context))),
    ]);
  }

  Widget _rateCard(BuildContext context, {required IconData icon, required String title, required String subtitle, required String button, required VoidCallback onTap}) => Card(
    color: const Color(0xFFFFF5DF), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: const BorderSide(color: gold, width: 1.3)),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: maroon, size: 30), const SizedBox(height: 7), Text(title, style: const TextStyle(color: maroon, fontWeight: FontWeight.bold, fontSize: 14)), Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.brown)), const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 4)), child: Text(button, style: const TextStyle(fontSize: 11)))),
    ])),
  );

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
              const SizedBox(height: 12),
              _rateCards(context),
              const SizedBox(height: 6),
              Card(color: maroonDark, child: Padding(padding: const EdgeInsets.all(12), child: ListenableBuilder(listenable: store, builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CURRENT METAL RATES', style: TextStyle(color: goldLight, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(children: [Expanded(child: Text('Gold  ₹${store.goldRate.toStringAsFixed(0)} / 10g', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))), Expanded(child: Text('Silver  ₹${store.silverRate.toStringAsFixed(2)} / g', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))]),
                Text('Source: ${store.rateSource}  •  ${store.rateUpdatedAt == null ? 'Not updated yet' : fmtDateTime(store.rateUpdatedAt!)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])))),
              const SizedBox(height: 10),
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
