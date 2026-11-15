import 'package:flutter/material.dart';

const appVersion = '1.7.0';

const shopName = 'Shree Janki Jewellers';
const shopAddress = 'Hasanpura, Thakur Badi Mandir, Siwan, Bihar';
const shopPhone = '+91 84099 84584';
const shopUpiId = '8409984584-1@okbizaxis';

// Colours taken from the Shree Janki Jewellers logo (deep red + gold).
const maroon = Color(0xFF6E0B0F);
const maroonDark = Color(0xFF3E0508);
const gold = Color(0xFFD4A017);
const goldLight = Color(0xFFF6D27A);
const cream = Color(0xFFF8F4ED);

const logoAsset = 'assets/images/logo_monogram.jpg'; // SJ monogram, small spots + PDF
const logoFullAsset = 'assets/images/logo_full.jpg'; // full logo, dashboard header
const goldBarAsset = 'assets/images/gold_bar.png';
const silverBarAsset = 'assets/images/silver_bar.png';
const gemAsset = 'assets/images/gem.png';
const emptyBillsAsset = 'assets/images/empty_bills.png';

String money(double value) => 'Rs. ${value.toStringAsFixed(2)}';

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${_two(h)}:${_two(d.minute)} $ap';
}

String fmtDateTime(DateTime d) => '${fmtDate(d)}  ${fmtTime(d)}';

/// Rate for display / typing: whole numbers without decimals, otherwise at most 2 decimals.
String fmtRate(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "12 Mar" - used for birthdays and anniversaries where the year does not matter.
String fmtDayMonth(DateTime d) => '${d.day} ${_monthShort[d.month - 1]}';

/// "today", "tomorrow", "in 3 days", "2 days ago".
String relativeDays(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  if (days > 1) return 'in $days days';
  return '${-days} days ago';
}
