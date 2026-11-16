import 'dart:async';

import 'package:flutter/material.dart';

import 'backup_helper.dart';
import 'constants.dart';
import 'pages/billing_page.dart';
import 'pages/bookings_page.dart';
import 'pages/customers_page.dart';
import 'pages/daybook_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/reminders_page.dart';
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
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          shape: Border(bottom: BorderSide(color: gold, width: 2.5)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: maroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: maroon,
            side: const BorderSide(color: maroon, width: 1.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: maroon, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: gold, width: 1),
          ),
          titleTextStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: maroon),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: maroonDark,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE9DFCF)),
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

/// App frame: AppBar + navigation drawer + the main pages.
/// Page numbers: 0 Dashboard, 1 New Invoice, 2 Bill History, 3 Day Book, 4 Settings,
/// 5 Customers, 6 Advance & Booking, 7 Reminders.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const titles = [
    'Dashboard',
    'New Invoice',
    'Bill History',
    'Day Book',
    'Settings',
    'Customers',
    'Advance & Booking',
    'Reminders',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  Future<void> _startup() async {
    unawaited(store.refreshOnlineIfStale());
    if (!store.shouldPromptBackupToday) return;
    await store.markBackupPromptShown();
    if (!mounted) return;
    final days = store.daysSinceBackup;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Time for a backup'),
        content: Text(days == null
            ? 'You have not made a backup yet. Save one now so your bills, customers and bookings are safe if the phone is lost or the app is reinstalled.'
            : 'Your last backup was $days days ago and ${store.changesSinceBackup} change${store.changesSinceBackup == 1 ? '' : 's'} since then are not saved in it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Back up now')),
        ],
      ),
    );
    if (go != true) return;
    final err = await saveBackupFile();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err == null ? 'Backup saved. Keep the file safe (Drive / WhatsApp to yourself).' : 'Could not save backup: $err')));
  }

  void _go(BuildContext context, int index) {
    Navigator.of(context).pop(); // close drawer
    navIndex.value = index;
  }

  Widget _drawerItem(BuildContext context, int current, int index, IconData icon, String label, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: trailing,
        selected: current == index,
        selectedColor: maroon,
        selectedTileColor: const Color(0xFFFFF1D6),
        onTap: () => _go(context, index),
      ),
    );
  }

  Widget _drawer(BuildContext context, int current) {
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
          decoration: const BoxDecoration(
            color: maroonDark,
            image: DecorationImage(
              image: AssetImage(drawerHeaderAsset),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Color(0x66340A16), BlendMode.darken),
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
        _drawerItem(context, current, 5, Icons.people_outline, 'Customers'),
        _drawerItem(
          context,
          current,
          6,
          Icons.bookmark_outline,
          'Advance & Booking',
          trailing: ListenableBuilder(
            listenable: store,
            builder: (context, _) => store.openBookings.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: maroon, borderRadius: BorderRadius.circular(20)),
                    child: Text('${store.openBookings.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
          ),
        ),
        _drawerItem(
          context,
          current,
          7,
          Icons.notifications_active_outlined,
          'Reminders',
          trailing: ListenableBuilder(
            listenable: store,
            builder: (context, _) => store.reminderCount == 0
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(20)),
                    child: Text('${store.reminderCount}',
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
            title: Text(titles[index], style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [maroonDark, maroon], begin: Alignment.centerLeft, end: Alignment.centerRight),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: gold, width: 1.5),
                  ),
                  child: ClipOval(
                    child: Image.asset(logoAsset, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: maroon, size: 18)),
                  ),
                ),
              ),
            ],
          ),
          drawer: _drawer(context, index),
          body: IndexedStack(
            index: index,
            children: const [
              HomePage(),
              BillingPage(),
              HistoryPage(),
              DayBookPage(),
              SettingsPage(),
              CustomersPage(),
              BookingsPage(),
              RemindersPage(),
            ],
          ),
        ),
      ),
    );
  }
}
