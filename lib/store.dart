import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'crm_models.dart';
import 'models.dart';
import 'rate_service.dart';
import 'stock.dart';

const _kBills = 'saved_bills_v1';
const _kPrefix = 'invoice_prefix_v1';
const _kNext = 'invoice_next_number_v1';
const _kDraft = 'bill_draft_v1';
const _kLastBackup = 'last_backup_v1';
const _kBookings = 'bookings_v1';
const _kCustomers = 'customers_v1';
const _kChanges = 'changes_since_backup_v1';
const _kBackupEvery = 'backup_every_days_v1';
const _kBackupPromptDay = 'backup_prompt_day_v1';
const _kDueTemplate = 'due_template_v1';
const _kGoldRate = 'rate_gold_v1';
const _kSilverRate = 'rate_silver_v1';
const _kRateSource = 'rate_source_v1';
const _kRateAdjust = 'rate_adjust_v1';
const _kRateTime = 'rate_time_v1';
const _kRateName = 'rate_source_name_v1';

/// Default WhatsApp text for a pending due. {name} {amount} {invoice} {date} {total} {shop} {phone} {upi}
const defaultDueTemplate = 'Namaste {name} ji,\n\n'
    'This is a gentle reminder from {shop}. A balance of {amount} is pending on invoice {invoice} '
    'dated {date} (bill total {total}).\n\n'
    'You can pay by UPI: {upi}\n\n'
    'Thank you for your support.\n{shop}\n{phone}';

enum RateSource { manual, online }

/// Which page of the app is showing (0 Home, 1 New Invoice, 2 History, 3 Day Book, 4 Settings).
final ValueNotifier<int> navIndex = ValueNotifier<int>(0);

/// Backup file format version. Bump only when the file layout changes.
/// 1 = bills only (app 1.1 - 1.6).  2 = bills + customers + bookings + rates + settings (app 1.7).
/// 3 = also the stock register (app 1.9).
const int kBackupVersion = 3;

enum PeriodKind { daily, weekly, monthly }

/// One payment that cleared (part of) a bill's due, with the bill it belongs to.
class DueClearance {
  final SavedBill bill;
  final Payment payment;
  DueClearance(this.bill, this.payment);
}

/// One advance payment received for a booking.
class AdvanceEntry {
  final Booking booking;
  final Payment payment;
  AdvanceEntry(this.booking, this.payment);
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
  /// Advance money received for bookings during this period.
  double advances = 0;
  /// Advance money given back to customers during this period.
  double refunds = 0;
  /// Part of this period's bills that was paid from an advance received earlier (not new money).
  double advanceAdjusted = 0;
  final List<DueClearance> clearances = [];
  final List<SavedBill> dueBills = [];
  final List<AdvanceEntry> advanceEntries = [];
  final List<Booking> refundedBookings = [];
  PeriodTotal(this.start, this.end);

  /// All money that actually came in during this period (advances in, refunds out).
  double get cashIn => paidAtBilling + collectedLater + advances - refunds;
}

/// Outcome of restoring a backup.
class ImportResult {
  final String? error;
  final int added;
  final int skipped;
  final int unreadable;
  final bool draftRestored;
  final int bookingsAdded;
  final int customersAdded;
  const ImportResult({
    this.error,
    this.added = 0,
    this.skipped = 0,
    this.unreadable = 0,
    this.draftRestored = false,
    this.bookingsAdded = 0,
    this.customersAdded = 0,
  });
}

/// Single place that keeps invoices, customers, bookings, rates and the unfinished draft on the phone.
class BillStore extends ChangeNotifier {
  SharedPreferences? _prefs;

  List<SavedBill> bills = [];
  List<Booking> bookings = [];
  List<Customer> customers = [];
  String prefix = 'SJJ';
  int nextNumber = 1;

  /// When the last backup was exported or copied (null = never).
  DateTime? lastBackupAt;

  /// How many things were saved or changed since the last backup.
  int changesSinceBackup = 0;

  /// Remind to back up every this many days (0 = never remind).
  int backupEveryDays = 7;
  String lastBackupPromptDay = '';

  /// WhatsApp text used for due reminders.
  String dueTemplate = defaultDueTemplate;

  // ---- gold & silver rates (one set for the whole app) ----
  /// 24K gold, Rs. per 10 grams.
  double goldRate = 70000;

  /// Silver, Rs. per gram.
  double silverRate = 100;
  RateSource rateSource = RateSource.manual;

  /// Percent added on top of the fetched international rate (to match the local market).
  double onlineAdjustPercent = 0;
  DateTime? ratesUpdatedAt;

  /// Name of the website the online rates came from (e.g. IBJA).
  String onlineSourceName = '';

  /// Goes up whenever the rates are changed from outside the billing page, so the billing page reloads them.
  int ratesVersion = 0;

  /// Set by "Use as new bill"; the billing page picks it up and clears it.
  BillData? pendingTemplate;

  /// Set by "Make bill" on a booking; the billing page picks it up and clears it.
  Booking? pendingBooking;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      prefix = p.getString(_kPrefix) ?? 'SJJ';
      nextNumber = p.getInt(_kNext) ?? 1;
      lastBackupAt = DateTime.tryParse(p.getString(_kLastBackup) ?? '');
      changesSinceBackup = p.getInt(_kChanges) ?? 0;
      backupEveryDays = p.getInt(_kBackupEvery) ?? 7;
      lastBackupPromptDay = p.getString(_kBackupPromptDay) ?? '';
      final tpl = p.getString(_kDueTemplate);
      if (tpl != null && tpl.trim().isNotEmpty) dueTemplate = tpl;

      final raw = p.getString(_kBills);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        bills = list
            .map((e) => SavedBill.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      bookings = _decodeList(p.getString(_kBookings), (m) => Booking.fromJson(m));
      bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      customers = _decodeList(p.getString(_kCustomers), (m) => Customer.fromJson(m));

      _loadRates(p);
      // Customers from bills made before the customer list existed.
      final before = customers.length;
      _ensureCustomersFromRecords();
      if (customers.length != before) await _saveAll();
    } catch (_) {
      // Unreadable storage: start with an empty history rather than crash.
    }
    notifyListeners();
  }

  List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) build) {
    if (raw == null) return <T>[];
    final out = <T>[];
    try {
      for (final e in jsonDecode(raw) as List) {
        try {
          out.add(build(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          // Skip one unreadable record, keep the rest.
        }
      }
    } catch (_) {
      // Unreadable list: start empty.
    }
    return out;
  }

  void _loadRates(SharedPreferences p) {
    final g = p.getDouble(_kGoldRate);
    final s = p.getDouble(_kSilverRate);
    if (g != null && g > 0) {
      goldRate = g;
      silverRate = (s != null && s >= 0) ? s : 100;
    } else {
      // First start of this version: keep the rates typed on the billing page before.
      final draft = loadDraft();
      final dg = parseNum((draft?['goldRate'] ?? '').toString());
      final ds = parseNum((draft?['silverRate'] ?? '').toString());
      if (dg > 0) goldRate = dg;
      if (ds > 0) silverRate = ds;
    }
    final src = p.getInt(_kRateSource);
    rateSource = (src != null && src >= 0 && src < RateSource.values.length) ? RateSource.values[src] : RateSource.manual;
    onlineAdjustPercent = p.getDouble(_kRateAdjust) ?? 0;
    ratesUpdatedAt = DateTime.tryParse(p.getString(_kRateTime) ?? '');
    onlineSourceName = p.getString(_kRateName) ?? '';
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
  /// period it was received, with the bill it cleared listed under it. Advances count
  /// the day they were received (not again when the bill is made from the booking).
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
      final adjusted = b.data.advanceUsed > 0 ? b.data.advanceUsed : 0.0;
      t.paidAtBilling += b.paidAtBilling - adjusted;
      t.advanceAdjusted += adjusted;
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
    for (final k in bookings) {
      for (final p in k.advances) {
        final pt = at(p.date);
        pt.advances += p.amount;
        pt.advanceEntries.add(AdvanceEntry(k, p));
      }
      if (k.refundAmount > 0.005) {
        final pt = at(k.refundDate ?? k.createdAt);
        pt.refunds += k.refundAmount;
        pt.refundedBookings.add(k);
      }
    }
    for (final t in map.values) {
      t.clearances.sort((a, b) => b.payment.date.compareTo(a.payment.date));
      t.dueBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      t.advanceEntries.sort((a, b) => b.payment.date.compareTo(a.payment.date));
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

  // ---- saving ----

  Future<void> _saveAll() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_kBills, jsonEncode(bills.map((b) => b.toJson()).toList()));
    await p.setString(_kBookings, jsonEncode(bookings.map((b) => b.toJson()).toList()));
    await p.setString(_kCustomers, jsonEncode(customers.map((c) => c.toJson()).toList()));
    await p.setInt(_kNext, nextNumber);
    await p.setString(_kPrefix, prefix);
    await p.setInt(_kChanges, changesSinceBackup);
  }

  /// Saves everything and counts it as a change that a backup does not contain yet.
  Future<void> _saveChanged() async {
    changesSinceBackup++;
    await _saveAll();
  }

  // ---- bills ----

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
    _ensureCustomer(bill.data.customerName, bill.data.customerPhone);
    notifyListeners();
    await _saveChanged();
    return bill;
  }

  SavedBill? _find(String invoiceNo) {
    for (final b in bills) {
      if (b.invoiceNo == invoiceNo) return b;
    }
    return null;
  }

  SavedBill? billByInvoice(String invoiceNo) => _find(invoiceNo);

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
    await _saveChanged();
    return null;
  }

  Future<void> removePayment(String invoiceNo, Payment payment) async {
    _find(invoiceNo)?.payments.remove(payment);
    notifyListeners();
    await _saveChanged();
  }

  Future<void> setQrMode(String invoiceNo, QrMode mode) async {
    final bill = _find(invoiceNo);
    if (bill == null) return;
    bill.data.qrMode = mode;
    notifyListeners();
    await _saveChanged();
  }

  /// Remembers that a due reminder was sent for this bill.
  Future<void> logBillReminder(String invoiceNo) async {
    _find(invoiceNo)?.remindedAt.add(DateTime.now());
    notifyListeners();
    await _saveAll();
  }

  /// Copies a past bill's customer and items into the billing page as a fresh bill.
  void useAsTemplate(BillData data) {
    pendingTemplate = BillData.fromJson(data.toJson());
    notifyListeners();
  }

  /// Opens the billing page with this booking's customer, item and advance filled in.
  void startBillFromBooking(Booking booking) {
    pendingBooking = booking;
    notifyListeners();
  }

  Future<void> deleteBill(String invoiceNo) async {
    bills.removeWhere((b) => b.invoiceNo == invoiceNo);
    notifyListeners();
    await _saveChanged();
  }

  Future<void> deleteAllBills() async {
    bills = [];
    notifyListeners();
    await _saveChanged();
  }

  Future<void> updateSettings({required String newPrefix, required int newNext}) async {
    prefix = newPrefix;
    nextNumber = newNext < 1 ? 1 : newNext;
    notifyListeners();
    await _saveAll();
  }

  // ---- customers ----

  Customer? customerFor(String name, String phone) {
    for (final c in customers) {
      if (c.matches(name, phone)) return c;
    }
    return null;
  }

  /// Adds the customer to the list if nobody matching is there yet; fills in a missing mobile number.
  void _ensureCustomer(String name, String phone) {
    final n = name.trim();
    if (n.isEmpty) return;
    final existing = customerFor(n, phone);
    if (existing == null) {
      customers.add(Customer(name: n, phone: phone.trim()));
    } else if (existing.phone.trim().isEmpty && phone.trim().isNotEmpty) {
      existing.phone = phone.trim();
    }
  }

  void _ensureCustomersFromRecords() {
    for (final b in bills.reversed) {
      _ensureCustomer(b.data.customerName, b.data.customerPhone);
    }
    for (final k in bookings.reversed) {
      _ensureCustomer(k.customerName, k.customerPhone);
    }
  }

  /// Customers sorted by name.
  List<Customer> get customersSorted {
    final list = List<Customer>.of(customers);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<SavedBill> billsOf(Customer c) =>
      bills.where((b) => c.matches(b.data.customerName, b.data.customerPhone)).toList();

  List<Booking> bookingsOf(Customer c) =>
      bookings.where((k) => c.matches(k.customerName, k.customerPhone)).toList();

  double dueOf(Customer c) => billsOf(c).fold(0.0, (s, b) => s + b.dueAmount);

  double advanceHeldOf(Customer c) => bookingsOf(c).fold(0.0, (s, k) => s + k.advanceHeld);

  /// Adds or updates a customer. Returns an error message, or null on success.
  Future<String?> saveCustomer(Customer customer, {Customer? editing}) async {
    final name = customer.name.trim();
    if (name.isEmpty) return 'Please enter the customer name.';
    for (final c in customers) {
      if (identical(c, editing)) continue;
      if (c.matches(name, customer.phone)) {
        return 'This customer is already in the list (${c.name}).';
      }
    }
    customer.name = name;
    customer.phone = customer.phone.trim();
    if (editing == null) {
      customers.add(customer);
    } else {
      editing
        ..name = customer.name
        ..phone = customer.phone
        ..address = customer.address
        ..note = customer.note
        ..birthday = customer.birthday
        ..anniversary = customer.anniversary;
    }
    notifyListeners();
    await _saveChanged();
    return null;
  }

  Future<void> deleteCustomer(Customer c) async {
    customers.remove(c);
    notifyListeners();
    await _saveChanged();
  }

  /// Customers whose birthday or anniversary falls in the next [days] days (0 = today only).
  List<({Customer customer, bool birthday, int days})> upcomingOccasions({int days = 7}) {
    final now = DateTime.now();
    final out = <({Customer customer, bool birthday, int days})>[];
    for (final c in customers) {
      final b = daysUntilOccasion(c.birthday, now);
      if (b != null && b <= days) out.add((customer: c, birthday: true, days: b));
      final a = daysUntilOccasion(c.anniversary, now);
      if (a != null && a <= days) out.add((customer: c, birthday: false, days: a));
    }
    out.sort((x, y) => x.days.compareTo(y.days));
    return out;
  }

  // ---- bookings (advance) ----

  Booking? bookingById(String id) {
    for (final k in bookings) {
      if (k.id == id) return k;
    }
    return null;
  }

  List<Booking> get openBookings => bookings.where((k) => k.isOpen).toList();

  /// Advance money currently held for open bookings.
  double get advanceHeld => bookings.fold(0.0, (s, k) => s + k.advanceHeld);

  /// Open bookings that are overdue or due for delivery within [days] days, soonest first.
  List<Booking> bookingsDueSoon({int days = 3}) {
    final now = DateTime.now();
    final list = bookings.where((k) {
      if (!k.isOpen) return false;
      final left = k.daysToDelivery(now);
      return left != null && left <= days;
    }).toList();
    list.sort((a, b) => (a.deliveryDate ?? a.createdAt).compareTo(b.deliveryDate ?? b.createdAt));
    return list;
  }

  /// Adds a new booking, or replaces the details of [existing]. Returns an error message, or null on success.
  Future<String?> saveBooking(Booking booking, {bool isNew = true}) async {
    if (booking.customerName.trim().isEmpty) return 'Please enter the customer name.';
    if (isNew) {
      bookings.insert(0, booking);
    } else {
      final i = bookings.indexWhere((k) => k.id == booking.id);
      if (i < 0) {
        bookings.insert(0, booking);
      } else {
        bookings[i] = booking;
      }
    }
    _ensureCustomer(booking.customerName, booking.customerPhone);
    notifyListeners();
    await _saveChanged();
    return null;
  }

  Future<String?> addAdvance(String bookingId, double amount, {String note = ''}) async {
    final k = bookingById(bookingId);
    if (k == null) return 'Booking not found.';
    if (!k.isOpen) return 'This booking is closed.';
    if (amount <= 0) return 'Enter an amount greater than 0.';
    k.advances.add(Payment(date: DateTime.now(), amount: amount, note: note));
    notifyListeners();
    await _saveChanged();
    return null;
  }

  Future<void> removeAdvance(String bookingId, Payment payment) async {
    bookingById(bookingId)?.advances.remove(payment);
    notifyListeners();
    await _saveChanged();
  }

  Future<void> setBookingStatus(String bookingId, BookingStatus status) async {
    final k = bookingById(bookingId);
    if (k == null) return;
    k.status = status;
    notifyListeners();
    await _saveChanged();
  }

  /// Cancels a booking. When [refund] is true the whole advance is counted as given back.
  Future<void> cancelBooking(String bookingId, {required bool refund, String note = ''}) async {
    final k = bookingById(bookingId);
    if (k == null) return;
    k.status = BookingStatus.cancelled;
    if (refund && k.advanceTotal > 0.005) {
      k.refundAmount = k.advanceTotal;
      k.refundDate = DateTime.now();
    }
    if (note.trim().isNotEmpty) {
      k.note = k.note.trim().isEmpty ? note.trim() : '${k.note.trim()}\n${note.trim()}';
    }
    notifyListeners();
    await _saveChanged();
  }

  /// Marks the booking delivered with the invoice that was made from it. Any advance that was
  /// more than the bill needed is counted as given back.
  Future<void> completeBooking(String bookingId, SavedBill bill) async {
    final k = bookingById(bookingId);
    if (k == null) return;
    k.status = BookingStatus.delivered;
    k.billInvoiceNo = bill.invoiceNo;
    final extra = k.advanceTotal - bill.data.advanceUsed;
    if (extra > 0.005) {
      k.refundAmount = extra;
      k.refundDate = DateTime.now();
    }
    notifyListeners();
    await _saveChanged();
  }

  Future<void> deleteBooking(String bookingId) async {
    bookings.removeWhere((k) => k.id == bookingId);
    notifyListeners();
    await _saveChanged();
  }

  Future<void> logBookingReminder(String bookingId) async {
    bookingById(bookingId)?.remindedAt.add(DateTime.now());
    notifyListeners();
    await _saveAll();
  }

  // ---- gold & silver rates ----

  Future<void> _saveRates() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setDouble(_kGoldRate, goldRate);
      await p.setDouble(_kSilverRate, silverRate);
      await p.setInt(_kRateSource, rateSource.index);
      await p.setDouble(_kRateAdjust, onlineAdjustPercent);
      if (ratesUpdatedAt != null) await p.setString(_kRateTime, ratesUpdatedAt!.toIso8601String());
      await p.setString(_kRateName, onlineSourceName);
    } catch (_) {
      // Best effort only.
    }
  }

  /// The seller typed the rates himself (dashboard).
  Future<void> setManualRates(double gold, double silver) async {
    goldRate = gold;
    silverRate = silver;
    rateSource = RateSource.manual;
    ratesUpdatedAt = DateTime.now();
    ratesVersion++;
    notifyListeners();
    await _saveRates();
  }

  /// The rates typed on the billing page. Does not make the billing page reload them.
  Future<void> rememberBillingRates(double gold, double silver) async {
    if (gold <= 0 || silver < 0) return;
    if ((gold - goldRate).abs() < 0.001 && (silver - silverRate).abs() < 0.001) return;
    goldRate = gold;
    silverRate = silver;
    rateSource = RateSource.manual;
    ratesUpdatedAt = DateTime.now();
    notifyListeners();
    await _saveRates();
  }

  Future<void> setRateSource(RateSource source) async {
    rateSource = source;
    notifyListeners();
    await _saveRates();
  }

  Future<void> setOnlineAdjust(double percent) async {
    onlineAdjustPercent = percent;
    notifyListeners();
    await _saveRates();
  }

  /// Fetches the online rates and uses them. Throws a [RateException] with a readable message on failure.
  Future<void> fetchOnlineRates() async {
    final live = await RateService.fetch(adjustPercent: onlineAdjustPercent);
    goldRate = live.goldPer10g;
    silverRate = live.silverPerGram;
    rateSource = RateSource.online;
    ratesUpdatedAt = live.fetchedAt;
    onlineSourceName = live.source;
    ratesVersion++;
    notifyListeners();
    await _saveRates();
  }

  /// When the rates are set to Online, quietly refreshes them if they are older than 30 minutes.
  Future<void> refreshOnlineIfStale() async {
    if (rateSource != RateSource.online) return;
    final t = ratesUpdatedAt;
    if (t != null && DateTime.now().difference(t).inMinutes < 30) return;
    try {
      await fetchOnlineRates();
    } catch (_) {
      // No internet: keep the last rates.
    }
  }

  // ---- backup reminder & settings ----

  static String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  bool get hasAnyData => bills.isNotEmpty || bookings.isNotEmpty || customers.isNotEmpty;

  int? get daysSinceBackup => lastBackupAt == null ? null : DateTime.now().difference(lastBackupAt!).inDays;

  /// True when there is something new that no backup has yet, and the reminder time has come.
  bool get backupDue {
    if (backupEveryDays <= 0) return false;
    if (!hasAnyData) return false;
    if (lastBackupAt == null) return true;
    if (changesSinceBackup <= 0) return false;
    return DateTime.now().difference(lastBackupAt!).inDays >= backupEveryDays;
  }

  /// Show the "please back up" pop-up at most once a day.
  bool get shouldPromptBackupToday => backupDue && lastBackupPromptDay != _dayKey(DateTime.now());

  Future<void> markBackupPromptShown() async {
    lastBackupPromptDay = _dayKey(DateTime.now());
    try {
      await _prefs?.setString(_kBackupPromptDay, lastBackupPromptDay);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> setBackupEveryDays(int days) async {
    backupEveryDays = days;
    notifyListeners();
    try {
      await _prefs?.setInt(_kBackupEvery, days);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> setDueTemplate(String text) async {
    dueTemplate = text.trim().isEmpty ? defaultDueTemplate : text;
    notifyListeners();
    try {
      await _prefs?.setString(_kDueTemplate, dueTemplate);
    } catch (_) {
      // Best effort only.
    }
  }

  // ---- reminders ----

  /// Bills with money still to collect, oldest first.
  List<SavedBill> get dueBills {
    final list = bills.where((b) => b.hasDue).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Number of individual reminders waiting (due bills, deliveries soon, occasions today).
  int get reminderCount => dueBillCount + bookingsDueSoon().length + upcomingOccasions(days: 0).length;

  /// How many things need the seller's attention today (dues, deliveries, occasions, backup).
  int get attentionCount {
    var n = 0;
    if (dueBillCount > 0) n++;
    if (bookingsDueSoon().isNotEmpty) n++;
    if (upcomingOccasions(days: 0).isNotEmpty) n++;
    if (backupDue) n++;
    return n;
  }

  // ---- backup & restore ----

  /// Everything needed to rebuild this app's data: bills (with payments), customers, bookings,
  /// invoice counter, saved rates and reminder settings.
  String exportJson() {
    final draft = loadDraft();
    final map = <String, dynamic>{
      'app': 'janki_jwellers',
      'backupVersion': kBackupVersion,
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'invoicePrefix': prefix,
      'nextNumber': nextNumber,
      'bills': bills.map((b) => b.toJson()).toList(),
      'customers': customers.map((c) => c.toJson()).toList(),
      'bookings': bookings.map((b) => b.toJson()).toList(),
      'stock': stockStore.toJsonList(),
      'settings': {
        'goldRate': goldRate,
        'silverRate': silverRate,
        'rateSource': rateSource.index,
        'onlineAdjustPercent': onlineAdjustPercent,
        'backupEveryDays': backupEveryDays,
        'dueTemplate': dueTemplate,
      },
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
    changesSinceBackup = 0;
    notifyListeners();
    try {
      await _prefs?.setString(_kLastBackup, lastBackupAt!.toIso8601String());
      await _prefs?.setInt(_kChanges, 0);
    } catch (_) {
      // Best effort only.
    }
  }

  /// Restores a backup. [replace] = wipe current data first; otherwise only records that are not
  /// already here (same invoice number / booking / customer) are added. The file is fully
  /// checked before anything changes. Backups from older versions (bills only) still restore.
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
    await stockStore.restore(map['stock'], replace: replace);

    final incoming = <SavedBill>[];
    var unreadable = 0;
    for (final e in map['bills'] as List) {
      try {
        incoming.add(SavedBill.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {
        unreadable++;
      }
    }
    final hasBookingsKey = map['bookings'] is List;
    final hasCustomersKey = map['customers'] is List;
    final incomingBookings = <Booking>[];
    if (hasBookingsKey) {
      for (final e in map['bookings'] as List) {
        try {
          incomingBookings.add(Booking.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          unreadable++;
        }
      }
    }
    final incomingCustomers = <Customer>[];
    if (hasCustomersKey) {
      for (final e in map['customers'] as List) {
        try {
          incomingCustomers.add(Customer.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          unreadable++;
        }
      }
    }
    if (incoming.isEmpty && incomingBookings.isEmpty && incomingCustomers.isEmpty) {
      return const ImportResult(error: 'No readable data in this backup. Nothing was changed.');
    }

    if (replace) {
      bills = [];
      if (hasBookingsKey) bookings = [];
      if (hasCustomersKey) customers = [];
    }
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

    var bookingsAdded = 0;
    for (final k in incomingBookings) {
      if (bookings.any((x) => x.id == k.id)) {
        skipped++;
      } else {
        bookings.add(k);
        bookingsAdded++;
      }
    }
    bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    var customersAdded = 0;
    for (final c in incomingCustomers) {
      final existing = customerFor(c.name, c.phone);
      if (existing == null) {
        customers.add(c);
        customersAdded++;
      } else {
        // Keep what is here, but fill in anything that was missing.
        if (existing.address.trim().isEmpty) existing.address = c.address;
        if (existing.note.trim().isEmpty) existing.note = c.note;
        existing.birthday ??= c.birthday;
        existing.anniversary ??= c.anniversary;
      }
    }
    _ensureCustomersFromRecords();

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

    final settings = map['settings'];
    if (replace && settings is Map) {
      final g = settings['goldRate'];
      final s = settings['silverRate'];
      if (g is num && g > 0) goldRate = g.toDouble();
      if (s is num && s >= 0) silverRate = s.toDouble();
      final src = settings['rateSource'];
      if (src is int && src >= 0 && src < RateSource.values.length) rateSource = RateSource.values[src];
      final adj = settings['onlineAdjustPercent'];
      if (adj is num) onlineAdjustPercent = adj.toDouble();
      final every = settings['backupEveryDays'];
      if (every is int && every >= 0 && every <= 365) backupEveryDays = every;
      final tpl = settings['dueTemplate'];
      if (tpl is String && tpl.trim().isNotEmpty) dueTemplate = tpl;
      ratesVersion++;
      await _saveRates();
      try {
        await _prefs?.setInt(_kBackupEvery, backupEveryDays);
        await _prefs?.setString(_kDueTemplate, dueTemplate);
      } catch (_) {
        // Best effort only.
      }
    }

    var draftRestored = false;
    final draft = map['draft'];
    if (replace && draft is Map) {
      await saveDraft(Map<String, dynamic>.from(draft));
      draftRestored = true;
    }

    notifyListeners();
    await _saveChanged();
    return ImportResult(
      added: added,
      skipped: skipped,
      unreadable: unreadable,
      draftRestored: draftRestored,
      bookingsAdded: bookingsAdded,
      customersAdded: customersAdded,
    );
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
