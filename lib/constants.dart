import 'package:flutter/material.dart';

const shopName = 'SHREE JANKI JEWELLERS';
const shopAddress = 'Hasanpura, Thakur Badi Mandir, Siwan, Bihar';
const shopPhone = '+91 84099 84584';
const shopUpiId = '8409984584-1@okbizaxis';

const maroon = Color(0xFF5B1425);
const gold = Color(0xFFC69A3A);
const cream = Color(0xFFF8F4ED);

const logoAsset = 'assets/icon/shree_janki_app_icon.png';
const headerBannerAsset = 'assets/images/header_banner.png';
const drawerHeaderAsset = 'assets/images/drawer_header.png';
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
