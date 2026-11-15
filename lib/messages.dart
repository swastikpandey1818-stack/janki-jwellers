import 'constants.dart';
import 'crm_models.dart';
import 'models.dart';
import 'store.dart';

/// Ready-made WhatsApp texts. The seller can still edit each one before sending.

String dueReminderText(SavedBill bill) => fillTemplate(store.dueTemplate, {
      'name': bill.customerName,
      'amount': money(bill.dueAmount),
      'invoice': bill.invoiceNo,
      'date': fmtDate(bill.createdAt),
      'total': money(bill.grandTotal),
      'shop': shopName,
      'phone': shopPhone,
      'upi': shopUpiId,
    });

String billThanksText(SavedBill bill) {
  final buf = StringBuffer()
    ..writeln('Namaste ${bill.customerName} ji,')
    ..writeln()
    ..writeln('Thank you for shopping at $shopName.')
    ..writeln('Invoice ${bill.invoiceNo} dated ${fmtDate(bill.createdAt)}: ${money(bill.grandTotal)}.');
  if (bill.hasDue) {
    buf.writeln('Balance due: ${money(bill.dueAmount)}.');
  } else {
    buf.writeln('Paid in full. Thank you!');
  }
  buf
    ..writeln()
    ..writeln('We look forward to serving you again.')
    ..writeln(shopName)
    ..write(shopPhone);
  return buf.toString();
}

String advanceReceiptText(Booking k, Payment p) {
  final buf = StringBuffer()
    ..writeln('Namaste ${k.customerName} ji,')
    ..writeln()
    ..writeln('We have received your advance of ${money(p.amount)} on ${fmtDate(p.date)} '
        'for your booking at $shopName.');
  if (k.description.trim().isNotEmpty) buf.writeln('Item: ${k.description.trim()}');
  buf.writeln('Total advance paid: ${money(k.advanceTotal)}');
  if (k.estimateValue > 0) buf.writeln('Estimated balance: ${money(k.balance)}');
  if (k.deliveryDate != null) buf.writeln('Expected date: ${fmtDate(k.deliveryDate!)}');
  buf
    ..writeln()
    ..writeln('Thank you!')
    ..writeln(shopName)
    ..write(shopPhone);
  return buf.toString();
}

String bookingReadyText(Booking k) {
  final buf = StringBuffer()
    ..writeln('Namaste ${k.customerName} ji,')
    ..writeln()
    ..writeln('Good news! Your order${k.description.trim().isEmpty ? '' : ' (${k.description.trim()})'} '
        'is ready at $shopName.');
  if (k.estimateValue > 0) {
    buf.writeln('Advance paid: ${money(k.advanceTotal)}. Estimated balance: ${money(k.balance)}.');
  }
  buf
    ..writeln('Please visit us to collect it.')
    ..writeln()
    ..writeln(shopName)
    ..write(shopPhone);
  return buf.toString();
}

String bookingReminderText(Booking k) {
  final buf = StringBuffer()
    ..writeln('Namaste ${k.customerName} ji,')
    ..writeln()
    ..write('This is a reminder about your booking at $shopName');
  if (k.description.trim().isNotEmpty) buf.write(' (${k.description.trim()})');
  if (k.deliveryDate != null) buf.write(' for ${fmtDate(k.deliveryDate!)}');
  buf.writeln('.');
  if (k.advanceTotal > 0) buf.writeln('Advance paid: ${money(k.advanceTotal)}.');
  if (k.estimateValue > 0) buf.writeln('Estimated balance: ${money(k.balance)}.');
  buf
    ..writeln()
    ..writeln(shopName)
    ..write(shopPhone);
  return buf.toString();
}

String birthdayText(Customer c) => 'Namaste ${c.name} ji,\n\n'
    'Wishing you a very Happy Birthday! May this year bring you joy, health and prosperity.\n\n'
    'With warm wishes,\n$shopName\n$shopPhone';

String anniversaryText(Customer c) => 'Namaste ${c.name} ji,\n\n'
    'Wishing you a very Happy Anniversary! May your bond grow stronger every year.\n\n'
    'With warm wishes,\n$shopName\n$shopPhone';

String generalText(String name) => 'Namaste $name ji,\n\n\n$shopName\n$shopPhone';
