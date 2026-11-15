import 'package:flutter/material.dart';

import 'constants.dart';
import 'pages/billing_page.dart';
import 'pages/daybook_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(const ShreeJankiJewellersApp());
}

class ShreeJankiJewellersApp extends StatelessWidget {
  const ShreeJankiJewellersApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: maroon, primary: maroon, secondary: gold);
    return MaterialApp(
      title: 'Shree Janki Jewellers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        appBarTheme: const AppBarTheme(
          backgroundColor: maroon,
          foregroundColor: Colors.white,
          shape: Border(bottom: BorderSide(color: gold, width: 2.5)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE4DCCF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: gold, width: 1.8),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFECE4D8)),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}

/// App frame: AppBar + navigation drawer + the five main pages.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const titles = ['Dashboard', 'New Invoice', 'Bill History', 'Day Book', 'Settings'];

  void _go(BuildContext context, int index) {
    Navigator.of(context).pop(); // close drawer
    navIndex.value = index;
  }

  Widget _drawerItem(BuildContext context, int current, int index, IconData icon, String label, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing,
      selected: current == index,
      selectedColor: maroon,
      selectedTileColor: const Color(0xFFFFF1D6),
      onTap: () => _go(context, index),
    );
  }

  Widget _drawer(BuildContext context, int current) {
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [maroonDark, maroon],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(bottom: BorderSide(color: gold, width: 3)),
          ),
          child: Row(children: [
            Container(
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: gold, width: 1.5),
              ),
              child: Image.asset(logoAsset, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: maroon, size: 36)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(shopName,
                    style: TextStyle(
                        color: goldLight, fontWeight: FontWeight.w800, fontSize: 18, height: 1.15, fontFamily: 'serif')),
                SizedBox(height: 4),
                Text(shopPhone, style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        _drawerItem(context, current, 0, Icons.dashboard_outlined, 'Dashboard'),
        _drawerItem(context, current, 1, Icons.add_circle_outline, 'New Invoice'),
        _drawerItem(
          context,
          current,
          2,
          Icons.history,
          'Bill History',
          trailing: ListenableBuilder(
            listenable: store,
            builder: (context, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: maroon, borderRadius: BorderRadius.circular(20)),
              child: Text('${store.totalBills}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ),
        _drawerItem(context, current, 3, Icons.calendar_month_outlined, 'Day Book'),
        _drawerItem(context, current, 4, Icons.settings_outlined, 'Settings'),
        const Divider(height: 24),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Text('Next invoice: ${store.nextInvoiceNo}',
                style: TextStyle(color: Colors.brown.shade400, fontSize: 12.5)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Text('Version $appVersion', style: TextStyle(color: Colors.brown.shade300, fontSize: 12)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: navIndex,
      builder: (context, index, _) => PopScope(
        canPop: index == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) navIndex.value = 0;
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(titles[index], style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          drawer: _drawer(context, index),
          body: IndexedStack(
            index: index,
            children: const [HomePage(), BillingPage(), HistoryPage(), DayBookPage(), SettingsPage()],
          ),
        ),
      ),
    );
  }
}
