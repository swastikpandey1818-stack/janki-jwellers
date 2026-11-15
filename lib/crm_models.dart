import 'models.dart';

// ---------------------------------------------------------------------------
// Phone numbers and customer matching
// ---------------------------------------------------------------------------

String _digitsOf(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

/// Number in the format WhatsApp links need (country code + number, digits only).
/// 10-digit numbers get the India code 91. Returns '' when the number is not usable.
String waNumber(String raw) {
  var d = _digitsOf(raw);
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  if (d.length == 10) return '91$d';
  if (d.length >= 11 && d.length <= 15) return d;
  return '';
}

/// Last 10 digits of a phone number, or '' when there are fewer than 10 digits.
String phoneKey(String raw) {
  final d = _digitsOf(raw);
  return d.length >= 10 ? d.substring(d.length - 10) : '';
}

/// Same person if the mobile numbers match, or (when a number is missing) the names match.
bool sameCustomer(String nameA, String phoneA, String nameB, String phoneB) {
  final a = phoneKey(phoneA);
  final b = phoneKey(phoneB);
  if (a.isNotEmpty && b.isNotEmpty) return a == b;
  final na = nameA.trim().toLowerCase();
  final nb = nameB.trim().toLowerCase();
  return na.isNotEmpty && na == nb;
}

/// Replaces {name}, {amount}... in a message template with the given values.
String fillTemplate(String template, Map<String, String> values) {
  var out = template;
  values.forEach((key, value) {
    out = out.replaceAll('{$key}', value);
  });
  return out;
}

/// Days from today until the next birthday / anniversary (0 = today). Null when no date is set.
int? daysUntilOccasion(DateTime? date, DateTime now) {
  if (date == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  var next = DateTime(now.year, date.month, date.day);
  if (next.isBefore(today)) next = DateTime(now.year + 1, date.month, date.day);
  return next.difference(today).inDays;
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

double _num(dynamic v) => (v is num) ? v.toDouble() : parseNum((v ?? '').toString());

// ---------------------------------------------------------------------------
// Customer
// ---------------------------------------------------------------------------

class Customer {
  String name;
  String phone;
  String address;
  String note;
  /// Only the day and month matter; the year is whatever was picked.
  DateTime? birthday;
  DateTime? anniversary;
  final DateTime createdAt;

  Customer({
    required this.name,
    this.phone = '',
    this.address = '',
    this.note = '',
    this.birthday,
    this.anniversary,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool matches(String otherName, String otherPhone) => sameCustomer(name, phone, otherName, otherPhone);

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'note': note,
        'birthday': birthday?.toIso8601String(),
        'anniversary': anniversary?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        birthday: _parseDate(j['birthday']),
        anniversary: _parseDate(j['anniversary']),
        createdAt: _parseDate(j['createdAt']),
      );
}

// ---------------------------------------------------------------------------
// Advance & booking
// ---------------------------------------------------------------------------

enum BookingStatus { pending, ready, delivered, cancelled }

String bookingStatusLabel(BookingStatus s) {
  switch (s) {
    case BookingStatus.pending:
      return 'Pending';
    case BookingStatus.ready:
      return 'Ready';
    case BookingStatus.delivered:
      return 'Delivered';
    case BookingStatus.cancelled:
      return 'Cancelled';
  }
}

/// An order for jewellery that will be made / delivered later, with advance money taken now.
class Booking {
  final String id;
  String customerName;
  String customerPhone;
  String description;
  ItemType metal;
  String weight;
  int goldPurity;
  /// Gold only: 24K rate per 10 grams promised to the customer. Empty = not locked.
  String lockedRate;
  String estimatedAmount;
  final DateTime createdAt;
  DateTime? deliveryDate;
  BookingStatus status;
  String note;
  /// Advance money received (newest last).
  final List<Payment> advances;
  /// Invoice made when the booking was delivered.
  String billInvoiceNo;
  /// When a WhatsApp reminder was sent for this booking.
  final List<DateTime> remindedAt;
  /// Advance given back to the customer (after a cancellation, or the part not needed in the bill).
  double refundAmount;
  DateTime? refundDate;

  Booking({
    required this.id,
    required this.customerName,
    this.customerPhone = '',
    this.description = '',
    this.metal = ItemType.gold,
    this.weight = '',
    this.goldPurity = 22,
    this.lockedRate = '',
    this.estimatedAmount = '',
    DateTime? createdAt,
    this.deliveryDate,
    this.status = BookingStatus.pending,
    this.note = '',
    List<Payment>? advances,
    this.billInvoiceNo = '',
    List<DateTime>? remindedAt,
    this.refundAmount = 0,
    this.refundDate,
  })  : createdAt = createdAt ?? DateTime.now(),
        advances = advances ?? [],
        remindedAt = remindedAt ?? [];

  static String newId() => 'BK${DateTime.now().microsecondsSinceEpoch}';

  double get estimateValue => parseNum(estimatedAmount);
  double get weightValue => parseNum(weight);
  double get lockedRateValue => parseNum(lockedRate);
  double get advanceTotal => advances.fold(0.0, (s, p) => s + p.amount);

  /// What is still to be paid on the estimate (never below 0).
  double get balance {
    final b = estimateValue - advanceTotal;
    return b < 0.005 ? 0 : b;
  }

  bool get isOpen => status == BookingStatus.pending || status == BookingStatus.ready;

  /// Advance still held for the customer (only while the booking is open).
  double get advanceHeld => isOpen ? advanceTotal : 0;

  /// Metal value (without making charges) at the given 24K gold rate per 10 g or silver rate per gram.
  double metalValueAt({required double goldPer10g, required double silverPerGram}) {
    switch (metal) {
      case ItemType.gold:
        final rate = lockedRateValue > 0 ? lockedRateValue : goldPer10g;
        return weightValue * (rate / 10) * goldPurity / 24;
      case ItemType.silver:
        return weightValue * silverPerGram;
      case ItemType.other:
        return 0;
    }
  }

  /// Whole days until delivery (negative = overdue). Null when no delivery date is set.
  int? daysToDelivery(DateTime now) {
    final d = deliveryDate;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// The bill line for this booking (gold with a locked rate keeps that rate).
  ItemData toItemData() {
    switch (metal) {
      case ItemType.gold:
        final locked = lockedRateValue > 0;
        return ItemData(
          name: description,
          weight: weight,
          type: ItemType.gold,
          goldPurity: goldPurity,
          useCustomGoldRate: locked,
          customGoldRate: locked ? ((lockedRateValue / 10) * goldPurity / 24).toStringAsFixed(2) : '',
        );
      case ItemType.silver:
        return ItemData(name: description, weight: weight, type: ItemType.silver);
      case ItemType.other:
        return ItemData(name: description, weight: weight, type: ItemType.other, otherAmount: estimatedAmount);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'description': description,
        'metal': metal.index,
        'weight': weight,
        'goldPurity': goldPurity,
        'lockedRate': lockedRate,
        'estimatedAmount': estimatedAmount,
        'createdAt': createdAt.toIso8601String(),
        'deliveryDate': deliveryDate?.toIso8601String(),
        'status': status.index,
        'note': note,
        'advances': advances.map((p) => p.toJson()).toList(),
        'billInvoiceNo': billInvoiceNo,
        'remindedAt': remindedAt.map((d) => d.toIso8601String()).toList(),
        'refundAmount': refundAmount,
        'refundDate': refundDate?.toIso8601String(),
      };

  factory Booking.fromJson(Map<String, dynamic> j) {
    final m = j['metal'];
    final st = j['status'];
    final gp = j['goldPurity'];
    final id = (j['id'] ?? '').toString();
    return Booking(
      id: id.isEmpty ? newId() : id,
      customerName: (j['customerName'] ?? '').toString(),
      customerPhone: (j['customerPhone'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      metal: (m is int && m >= 0 && m < ItemType.values.length) ? ItemType.values[m] : ItemType.gold,
      weight: (j['weight'] ?? '').toString(),
      goldPurity: (gp is int && const [24, 22, 20, 18, 14].contains(gp)) ? gp : 22,
      lockedRate: (j['lockedRate'] ?? '').toString(),
      estimatedAmount: (j['estimatedAmount'] ?? '').toString(),
      createdAt: _parseDate(j['createdAt']),
      deliveryDate: _parseDate(j['deliveryDate']),
      status: (st is int && st >= 0 && st < BookingStatus.values.length) ? BookingStatus.values[st] : BookingStatus.pending,
      note: (j['note'] ?? '').toString(),
      advances: (j['advances'] as List?)
              ?.map((e) => Payment.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <Payment>[],
      billInvoiceNo: (j['billInvoiceNo'] ?? '').toString(),
      remindedAt: (j['remindedAt'] as List?)
              ?.map((e) => DateTime.tryParse(e.toString()))
              .whereType<DateTime>()
              .toList() ??
          <DateTime>[],
      refundAmount: _num(j['refundAmount']),
      refundDate: _parseDate(j['refundDate']),
    );
  }
}
