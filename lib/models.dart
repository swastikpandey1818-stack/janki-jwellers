enum ItemType { gold, silver, other }

double parseNum(String value) => double.tryParse(value.trim()) ?? 0;

/// Which amount the UPI QR code on the invoice asks the customer to pay.
enum QrMode { due, paid, total }

String qrModeLabel(QrMode m) {
  switch (m) {
    case QrMode.due:
      return 'Balance Due';
    case QrMode.paid:
      return 'Paid Now';
    case QrMode.total:
      return 'Full Total';
  }
}

/// Money received against a bill after it was created (clearing the due).
class Payment {
  final DateTime date;
  final double amount;
  final String note;

  Payment({required this.date, required this.amount, this.note = ''});

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'amount': amount,
        'note': note,
      };

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : parseNum((j['amount'] ?? '').toString()),
        note: (j['note'] ?? '').toString(),
      );
}

String itemTypeName(ItemType type) {
  switch (type) {
    case ItemType.gold:
      return 'Gold';
    case ItemType.silver:
      return 'Silver';
    case ItemType.other:
      return 'Others';
  }
}

/// One line of a bill (plain data, no controllers).
class ItemData {
  String name;
  String weight;
  String customGoldRate;
  String otherRate;
  String otherAmount;
  String otherMaking;
  ItemType type;
  int goldPurity;
  bool useCustomGoldRate;

  ItemData({
    this.name = '',
    this.weight = '',
    this.customGoldRate = '',
    this.otherRate = '',
    this.otherAmount = '',
    this.otherMaking = '',
    this.type = ItemType.gold,
    this.goldPurity = 22,
    this.useCustomGoldRate = false,
  });

  double get weightValue => parseNum(weight);
  double get customGoldRateValue => parseNum(customGoldRate);
  double get otherRateValue => parseNum(otherRate);
  double get otherAmountValue => parseNum(otherAmount);
  double get otherMakingValue => parseNum(otherMaking);

  Map<String, dynamic> toJson() => {
        'name': name,
        'weight': weight,
        'customGoldRate': customGoldRate,
        'otherRate': otherRate,
        'otherAmount': otherAmount,
        'otherMaking': otherMaking,
        'type': type.index,
        'goldPurity': goldPurity,
        'useCustomGoldRate': useCustomGoldRate,
      };

  factory ItemData.fromJson(Map<String, dynamic> j) {
    final t = j['type'];
    final p = j['goldPurity'];
    return ItemData(
      name: (j['name'] ?? '').toString(),
      weight: (j['weight'] ?? '').toString(),
      customGoldRate: (j['customGoldRate'] ?? '').toString(),
      otherRate: (j['otherRate'] ?? '').toString(),
      otherAmount: (j['otherAmount'] ?? '').toString(),
      otherMaking: (j['otherMaking'] ?? '').toString(),
      type: (t is int && t >= 0 && t < ItemType.values.length) ? ItemType.values[t] : ItemType.gold,
      goldPurity: (p is int && const [24, 22, 20, 18, 14].contains(p)) ? p : 22,
      useCustomGoldRate: j['useCustomGoldRate'] == true,
    );
  }
}

/// Everything entered for one bill, plus all the price maths.
class BillData {
  String customerName;
  String customerPhone;
  String goldRate;
  String silverRate;
  String goldMaking;
  String silverMaking;
  String gst;
  bool makingEnabled;
  bool applyGst;
  /// What the customer has paid so far. Empty = paid in full (no due).
  String amountPaid;
  /// Chosen QR amount. null = automatic (balance due when part paid, else full total).
  QrMode? qrMode;
  /// Booking this bill was made from ('' = none), and how much of that booking's
  /// advance was adjusted in this bill (money that was already counted when received).
  String bookingId;
  double advanceUsed;
  List<ItemData> items;

  BillData({
    this.customerName = '',
    this.customerPhone = '',
    this.goldRate = '70000',
    this.silverRate = '100',
    this.goldMaking = '10',
    this.silverMaking = '10',
    this.gst = '3',
    this.makingEnabled = true,
    this.applyGst = false,
    this.amountPaid = '',
    this.qrMode,
    this.bookingId = '',
    this.advanceUsed = 0,
    List<ItemData>? items,
  }) : items = items ?? [ItemData()];

  double get goldRatePer10g => parseNum(goldRate);
  double get silverRatePerGram => parseNum(silverRate);
  double get goldMakingPercent => parseNum(goldMaking);
  double get silverMakingPercent => parseNum(silverMaking);
  double get gstPercentage => parseNum(gst);

  double metalRateFor(ItemData item) {
    switch (item.type) {
      case ItemType.gold:
        return item.useCustomGoldRate
            ? item.customGoldRateValue
            : (goldRatePer10g / 10) * item.goldPurity / 24;
      case ItemType.silver:
        return silverRatePerGram;
      case ItemType.other:
        return item.otherRateValue;
    }
  }

  double amountFor(ItemData item) =>
      item.type == ItemType.other ? item.otherAmountValue : item.weightValue * metalRateFor(item);

  double makingFor(ItemData item) {
    if (!makingEnabled) return 0;
    switch (item.type) {
      case ItemType.gold:
        return amountFor(item) * goldMakingPercent / 100;
      case ItemType.silver:
        return amountFor(item) * silverMakingPercent / 100;
      case ItemType.other:
        return item.otherMakingValue;
    }
  }

  double get jewelleryTotal => items.fold(0.0, (s, i) => s + amountFor(i));
  double get makingTotal => items.fold(0.0, (s, i) => s + makingFor(i));
  double get subtotal => jewelleryTotal + makingTotal;
  double get gstAmount => applyGst ? subtotal * gstPercentage / 100 : 0;
  double get grandTotal => subtotal + gstAmount;

  // ---- part payment / due ----
  /// True once an amount paid has been typed (even 0 means nothing paid yet).
  bool get hasPaymentEntry => amountPaid.trim().isNotEmpty;
  double get amountPaidValue => parseNum(amountPaid);

  /// Money received so far (the full total when no amount paid was entered).
  double get paidAmount => hasPaymentEntry ? amountPaidValue : grandTotal;

  /// Balance still to be paid: grand total minus amount paid.
  double get dueAmount {
    if (!hasPaymentEntry) return 0;
    final d = grandTotal - amountPaidValue;
    return d < 0.005 ? 0 : d;
  }

  bool get hasDue => dueAmount > 0;

  QrMode get effectiveQrMode => qrMode ?? (hasPaymentEntry ? QrMode.due : QrMode.total);

  /// Amount the QR asks for, given the balance that is currently due.
  double qrAmountWith(double due) {
    switch (effectiveQrMode) {
      case QrMode.due:
        return due;
      case QrMode.paid:
        return paidAmount;
      case QrMode.total:
        return grandTotal;
    }
  }

  Map<String, dynamic> toJson() => {
        'customerName': customerName,
        'customerPhone': customerPhone,
        'goldRate': goldRate,
        'silverRate': silverRate,
        'goldMaking': goldMaking,
        'silverMaking': silverMaking,
        'gst': gst,
        'makingEnabled': makingEnabled,
        'applyGst': applyGst,
        'amountPaid': amountPaid,
        'qrMode': qrMode?.index,
        'bookingId': bookingId,
        'advanceUsed': advanceUsed,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory BillData.fromJson(Map<String, dynamic> j) {
    final saved = (j['items'] as List?)
            ?.map((e) => ItemData.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        <ItemData>[];
    return BillData(
      customerName: (j['customerName'] ?? '').toString(),
      customerPhone: (j['customerPhone'] ?? '').toString(),
      goldRate: (j['goldRate'] ?? '70000').toString(),
      silverRate: (j['silverRate'] ?? '100').toString(),
      goldMaking: (j['goldMaking'] ?? '10').toString(),
      silverMaking: (j['silverMaking'] ?? '10').toString(),
      gst: (j['gst'] ?? '3').toString(),
      makingEnabled: j['makingEnabled'] != false,
      applyGst: j['applyGst'] == true,
      amountPaid: (j['amountPaid'] ?? '').toString(),
      qrMode: (j['qrMode'] is int && j['qrMode'] >= 0 && j['qrMode'] < QrMode.values.length)
          ? QrMode.values[j['qrMode'] as int]
          : null,
      bookingId: (j['bookingId'] ?? '').toString(),
      advanceUsed: (j['advanceUsed'] is num) ? (j['advanceUsed'] as num).toDouble() : 0,
      items: saved.isEmpty ? [ItemData()] : saved,
    );
  }
}

/// A generated invoice that is stored in history.
class SavedBill {
  final String invoiceNo;
  final int serial;
  final DateTime createdAt;
  final BillData data;
  /// Money collected after the bill was made (newest last).
  final List<Payment> payments;
  /// When a WhatsApp due reminder was sent for this bill (newest last).
  final List<DateTime> remindedAt;

  SavedBill({
    required this.invoiceNo,
    required this.serial,
    required this.createdAt,
    required this.data,
    List<Payment>? payments,
    List<DateTime>? remindedAt,
  })  : payments = payments ?? [],
        remindedAt = remindedAt ?? [];

  double get grandTotal => data.grandTotal;

  /// Received when the bill was made (the full total if no amount paid was entered).
  double get paidAtBilling => data.paidAmount;
  double get laterPaid => payments.fold(0.0, (s, p) => s + p.amount);
  double get totalPaid => paidAtBilling + laterPaid;

  /// Still to be collected: grand total minus everything received so far.
  double get dueAmount {
    if (!data.hasPaymentEntry) return 0;
    final d = grandTotal - totalPaid;
    return d < 0.005 ? 0 : d;
  }

  bool get hasDue => dueAmount > 0;

  /// Amount the QR code on this invoice asks for.
  double get qrAmount => data.qrAmountWith(dueAmount);

  String get customerName => data.customerName.trim().isEmpty ? 'Customer' : data.customerName.trim();

  Map<String, dynamic> toJson() => {
        'invoiceNo': invoiceNo,
        'serial': serial,
        'createdAt': createdAt.toIso8601String(),
        'data': data.toJson(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'remindedAt': remindedAt.map((d) => d.toIso8601String()).toList(),
      };

  factory SavedBill.fromJson(Map<String, dynamic> j) => SavedBill(
        invoiceNo: (j['invoiceNo'] ?? '').toString(),
        serial: (j['serial'] is int) ? j['serial'] as int : 0,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
        data: BillData.fromJson(Map<String, dynamic>.from(j['data'] as Map)),
        payments: (j['payments'] as List?)
                ?.map((e) => Payment.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <Payment>[],
        remindedAt: (j['remindedAt'] as List?)
                ?.map((e) => DateTime.tryParse(e.toString()))
                .whereType<DateTime>()
                .toList() ??
            <DateTime>[],
      );
}
