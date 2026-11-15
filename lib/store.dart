import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'models.dart';

const _kBills = 'saved_bills_v1';
const _kPrefix = 'invoice_prefix_v1';
const _kNext = 'invoice_next_number_v1';
const _kDraft = 'bill_draft_v1';
const _kLastBackup = 'last_backup_v1';
const _kGoldRate = 'gold_rate_v2';
const _kSilverRate = 'silver_rate_v2';
const _kRateSource = 'rate_source_v2';
const _kRateUpdated = 'rate_updated_v2';

/// Which page of the app is showing (0 Home, 1 New Invoice, 2 History, 3 Day Book, 4 Settings).
final ValueNotifier<int> navIndex = ValueNotifier<int>(0);

/// Backup file format version. Bump only when the file layout changes.
const int kBackupVersion = 2;

enum PeriodKind { daily, weekly, monthly }

/// One payment that cleared (part of) a bill's due, with the bill it belongs to.
class DueClearance {
  final SavedBill bill;
  final Payment payment;
  DueClearance(this.bill, this.payment);
}

/// Money summary for one day, week or month in the Day Book.
class PeriodTotal {
  final DateTime start;
  final DateTime end;
  int bills = 0;
  double billed = 0;
  double paidAtBilling = 0;
  double dueCreated = 0;
  double collectedLater = 0;
  final List<DueClearance> clearances = [];
  final List<SavedBill> dueBills = [];
  PeriodTotal(this.start, this.end);

  /// All money that actually came in during this period.
  double get cashIn => paidAtBilling + collectedLater;
}

/// Outcome of restoring a backup.
class ImportResult {
  final String? error;
  final int added;
  final int skipped;
  final int unreadable;
  final bool draftRestored;
  const ImportResult({this.error, this.added = 0, this.skipped = 0, this.unreadable = 0, this.draftRestored = false});
}

/// Single place that keeps invoices, the invoice counter and the unfinished draft on the phone.
class BillStore extends ChangeNotifier {
  SharedPreferences? _prefs;

  List<SavedBill> bills = [];
  String prefix = 'SJJ';
  int nextNumber = 1;
  double goldRate = 70000; // INR per 10 grams
  double silverRate = 100; // INR per gram
  String rateSource = 'Default';
  DateTime? rateUpdatedAt;

  /// When the last backup was exported or copied (null = never).
  DateTime? lastBackupAt;

  /// Set by "Use as new bill"; the billing page picks it up and clears it.
  BillData? pendingTemplate;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      prefix = p.getString(_kPrefix) ?? 'SJJ';
      nextNumber = p.getInt(_kNext) ?? 1;
      goldRate = p.getDouble(_kGoldRate) ?? 70000;
      silverRate = p.getDouble(_kSilverRate) ?? 100;
      rateSource = p.getString(_kRateSource) ?? 'Default';
      rateUpdatedAt = DateTime.tryParse(p.getString(_kRateUpdated) ?? '');
      lastBackupAt = DateTime.tryParse(p.getString(_kLastBackup) ?? '');
      final raw = p.getString(_kBills);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        bills = list
            .map((e) => SavedBill.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (_) {
      // Unreadable storage: start with an empty history rather than crash.
    }
    notifyListeners();
  }

  String invoiceNoFor(int n) => '$prefix-${n.toString().padLeft(4, '0')}';

  int _freeNumber() {
    var n = nextNumber < 1 ? 1 : nextNumber;
    while (bills.any((b) => b.invoiceNo == invoiceNoFor(n))) {
      n++;
    }
    return n;
  }

  /// The number the next generated invoice will get.
  String get nextInvoiceNo => invoiceNoFor(_freeNumber());

  int get totalBills => bills.length;

  double get totalSales => bills.fold(0.0, (s, b) => s + b.grandTotal);

  /// Money still to be collected across all bills.
  double get totalDue => bills.fold(0.0, (s, b) => s + b.dueAmount);

  int get dueBillCount => bills.where((b) => b.hasDue).length;

  /// First day of the day / week (Monday) / month that [t] falls in.
  static DateTime periodStart(DateTime t, PeriodKind kind) {
    final day = DateTime(t.year, t.month, t.day);
    switch (kind) {
      case PeriodKind.daily:
        return day;
      case PeriodKind.weekly:
        return DateTime(day.year, day.month, day.day - (day.weekday - 1));
      case PeriodKind.monthly:
        return DateTime(day.year, day.month, 1);
    }
  }

  static DateTime periodEnd(DateTime start, PeriodKind kind) {
    switch (kind) {
      case PeriodKind.daily:
        return start;
      case PeriodKind.weekly:
        return DateTime(start.year, start.month, start.day + 6);
      case PeriodKind.monthly:
        return DateTime(start.year, start.month + 1, 0);
    }
  }

  /// Totals per day, week or month, newest first. A later payment counts in the
  /// period it was received, with the bill it cleared listed under it.
  List<PeriodTotal> totalsFor(PeriodKind kind) {
    final map = <DateTime, PeriodTotal>{};
    PeriodTotal at(DateTime t) {
      final start = periodStart(t, kind);
      return map.putIfAbsent(start, () => PeriodTotal(start, periodEnd(start, kind)));
    }

    for (final b in bills) {
      final t = at(b.createdAt);
      t.bills++;
      t.billed += b.grandTotal;
      t.paidAtBilling += b.paidAtBilling;
      final due = b.grandTotal - b.paidAtBilling;
      if (due > 0.005) {
        t.dueCreated += due;
        t.dueBills.add(b);
      }
      for (final p in b.payments) {
        final pt = at(p.date);
        pt.collectedLater += p.amount;
        pt.clearances.add(DueClearance(b, p));
      }
    }
    for (final t in map.values) {
      t.clearances.sort((a, b) => b.payment.date.compareTo(a.payment.date));
      t.dueBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final list = map.values.toList()..sort((a, b) => b.start.compareTo(a.start));
    return list;
  }

  int get todayCount {
    final now = DateTime.now();
    return bills
        .where((b) =>
            b.createdAt.year == now.year &&
            b.createdAt.month == now.month &&
            b.createdAt.day == now.day)
        .length;
  }

  Future<void> setRates({required double gold, required double silver, required String source}) async {
    if (gold <= 0 || silver <= 0) return;
    goldRate = gold;
    silverRate = silver;
    rateSource = source;
    rateUpdatedAt = DateTime.now();
    notifyListeners();
    await _prefs?.setDouble(_kGoldRate, goldRate);
    await _prefs?.setDouble(_kSilverRate, silverRate);
    await _prefs?.setString(_kRateSource, rateSource);
    await _prefs?.setString(_kRateUpdated, rateUpdatedAt!.toIso8601String());
  }

  Future<void> _persistBills() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_kBills, jsonEncode(bills.map((b) => b.toJson()).toList()));
    await p.setInt(_kNext, nextNumber);
    await p.setString(_kPrefix, prefix);
  }

  /// Gives the bill the next invoice number, stores it, and moves the counter on.
  Future<SavedBill> saveBill(BillData data) async {
    final n = _freeNumber();
    final bill = SavedBill(
      invoiceNo: invoiceNoFor(n),
      serial: n,
      createdAt: DateTime.now(),
      data: BillData.fromJson(data.toJson()), // deep copy
    );
    bills.insert(0, bill);
    nextNumber = n + 1;
    notifyListeners();
    await _persistBills();
    return bill;
  }

  SavedBill? _find(String invoiceNo) {
    for (final b in bills) {
      if (b.invoiceNo == invoiceNo) return b;
    }
    return null;
  }

  /// Records money received against a bill's due. Returns an error message, or null on success.
  Future<String?> addPayment(String invoiceNo, double amount, {String note = ''}) async {
    final bill = _find(invoiceNo);
    if (bill == null) return 'Bill not found.';
    if (amount <= 0) return 'Enter an amount greater than 0.';
    if (amount > bill.dueAmount + 0.005) {
      return 'That is more than the balance due (${money(bill.dueAmount)}).';
    }
    bill.payments.add(Payment(date: DateTime.now(), amount: amount, note: note));
    notifyListeners();
    await _persistBills();
    return null;
  }

  Future<void> removePayment(String invoiceNo, Payment payment) async {
    _find(invoiceNo)?.payments.remove(payment);
    notifyListeners();
    await _persistBills();
  }

  Future<void> setQrMode(String invoiceNo, QrMode mode) async {
    final bill = _find(invoiceNo);
    if (bill == null) return;
    bill.data.qrMode = mode;
    notifyListeners();
    await _persistBills();
  }

  /// Copies a past bill's customer and items into the billing page as a fresh bill.
  void useAsTemplate(BillData data) {
    pendingTemplate = BillData.fromJson(data.toJson());
    notifyListeners();
  }

  Future<void> deleteBill(String invoiceNo) async {
    bills.removeWhere((b) => b.invoiceNo == invoiceNo);
    notifyListeners();
    await _persistBills();
  }

  Future<void> deleteAllBills() async {
    bills = [];
    notifyListeners();
    await _persistBills();
  }

  Future<void> updateSettings({required String newPrefix, required int newNext}) async {
    prefix = newPrefix;
    nextNumber = newNext < 1 ? 1 : newNext;
    notifyListeners();
    await _persistBills();
  }

  // ---- backup & restore ----

  /// Everything needed to rebuild this app's data: bills (with payments), invoice counter and saved rates.
  String exportJson() {
    final draft = loadDraft();
    final map = <String, dynamic>{
      'app': 'janki_jwellers',
      'backupVersion': kBackupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'invoicePrefix': prefix,
      'nextNumber': nextNumber,
      'rates': {'goldPer10g': goldRate, 'silverPerGram': silverRate, 'source': rateSource, 'updatedAt': rateUpdatedAt?.toIso8601String()},
      'bills': bills.map((b) => b.toJson()).toList(),
      if (draft != null) 'draft': draft,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  String exportFileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Shree_Janki_Backup_${n.year}-${two(n.month)}-${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  Future<void> markBackedUp() async {
    lastBackupAt = DateTime.now();
    notifyListeners();
    try {
      await _prefs?.setString(_kLastBackup, lastBackupAt!.toIso8601String());
    } catch (_) {
      // Best effort only.
    }
  }

  /// Restores a backup. [replace] = wipe current bills first; otherwise only bills whose
  /// invoice number is not already saved are added. The file is fully checked before anything changes.
  Future<ImportResult> importJson(String text, {required bool replace}) async {
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is! Map) return const ImportResult(error: 'This is not a Shree Janki backup file.');
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const ImportResult(error: 'Could not read this. Is it a backup (.json) made by this app?');
    }
    if (map['bills'] is! List) return const ImportResult(error: 'No bills found in this backup.');
    final version = map['backupVersion'];
    if (version is int && version > kBackupVersion) {
      return const ImportResult(error: 'This backup is from a newer version of the app. Update the app first.');
    }

    final incoming = <SavedBill>[];
    var unreadable = 0;
    for (final e in map['bills'] as List) {
      try {
        incoming.add(SavedBill.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {
        unreadable++;
      }
    }
    if (incoming.isEmpty) return const ImportResult(error: 'No readable bills in this backup. Nothing was changed.');

    if (replace) bills = [];
    var added = 0;
    var skipped = 0;
    for (final b in incoming) {
      if (bills.any((x) => x.invoiceNo == b.invoiceNo)) {
        skipped++;
      } else {
        bills.add(b);
        added++;
      }
    }
    bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Never reuse an invoice number: keep the highest counter seen anywhere.
    var next = nextNumber;
    final backupNext = map['nextNumber'];
    if (backupNext is int && backupNext > next) next = backupNext;
    for (final b in bills) {
      if (b.serial >= next) next = b.serial + 1;
    }
    nextNumber = next;
    final backupPrefix = (map['invoicePrefix'] ?? '').toString().trim();
    if (replace && backupPrefix.isNotEmpty) prefix = backupPrefix;
    final rates = map['rates'];
    if (replace && rates is Map) {
      final g = rates['goldPer10g']; final si = rates['silverPerGram'];
      if (g is num && g > 0) goldRate = g.toDouble();
      if (si is num && si > 0) silverRate = si.toDouble();
      rateSource = (rates['source'] ?? 'Restored').toString();
      rateUpdatedAt = DateTime.tryParse((rates['updatedAt'] ?? '').toString());
      await _prefs?.setDouble(_kGoldRate, goldRate);
      await _prefs?.setDouble(_kSilverRate, silverRate);
      await _prefs?.setString(_kRateSource, rateSource);
      if (rateUpdatedAt != null) await _prefs?.setString(_kRateUpdated, rateUpdatedAt!.toIso8601String());
    }

    var draftRestored = false;
    final draft = map['draft'];
    if (replace && draft is Map) {
      await saveDraft(Map<String, dynamic>.from(draft));
      draftRestored = true;
    }

    notifyListeners();
    await _persistBills();
    return ImportResult(added: added, skipped: skipped, unreadable: unreadable, draftRestored: draftRestored);
  }

  // ---- unfinished bill (draft) ----

  Map<String, dynamic>? loadDraft() {
    try {
      final text = _prefs?.getString(_kDraft);
      if (text == null) return null;
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(Map<String, dynamic> json) async {
    try {
      await _prefs?.setString(_kDraft, jsonEncode(json));
    } catch (_) {
      // Best effort only.
    }
  }
}

final BillStore store = BillStore();
