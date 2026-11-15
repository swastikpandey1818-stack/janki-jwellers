import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'constants.dart';
import 'models.dart';

class PdfService {
  static String fileName(SavedBill bill) {
    final safe = bill.customerName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'Shree_Janki_Jewellers_${bill.invoiceNo}_$safe.pdf';
  }

  static String _upiUri(SavedBill bill) => Uri(
        scheme: 'upi',
        host: 'pay',
        queryParameters: {
          'pa': shopUpiId,
          'pn': 'Shree Janki Jewellers',
          'am': bill.qrAmount.toStringAsFixed(2),
          'cu': 'INR',
          'tn': bill.invoiceNo,
        },
      ).toString();

  static pw.Widget _summaryRow(String label, double value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label),
          pw.Text(money(value)),
        ]),
      );

  static Future<Uint8List> build(SavedBill bill) async {
    final d = bill.data;
    final document = pw.Document();
    pw.MemoryImage? logoImage;
    try {
      final data = await rootBundle.load(logoAsset);
      logoImage = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      // Keep PDF generation available if the optional logo cannot be loaded.
    }

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (context) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          if (logoImage != null) ...[
            pw.Container(
              width: 60,
              height: 60,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.amber700),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
              child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(shopName,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
              pw.SizedBox(height: 4),
              pw.Text(shopAddress, style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Phone: $shopPhone', style: const pw.TextStyle(fontSize: 9)),
            ],
          )),
        ]),
        pw.SizedBox(height: 12),
        pw.Container(height: 2, color: PdfColors.amber700),
        pw.SizedBox(height: 12),
        pw.Center(
            child: pw.Text('JEWELLERY INVOICE',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2))),
        pw.SizedBox(height: 14),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Invoice No: ${bill.invoiceNo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: ${fmtDate(bill.createdAt)}   Time: ${fmtTime(bill.createdAt)}'),
        ]),
        pw.Divider(),
        pw.Text('CUSTOMER DETAILS', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Text('Name: ${d.customerName.trim()}'),
        pw.Text('Mobile: ${d.customerPhone.trim().isEmpty ? "Not provided" : d.customerPhone.trim()}'),
        pw.SizedBox(height: 12),
        pw.Text('REFERENCE RATES', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text('24K Gold: ${money(d.goldRatePer10g)} per 10 grams'),
        pw.Text('Silver: ${money(d.silverRatePerGram)} per gram'),
        pw.Text('Making Charges: ${d.makingEnabled ? "Enabled" : "Disabled"}'),
        if (d.makingEnabled)
          pw.Text(
              'Gold Making: ${d.goldMakingPercent.toStringAsFixed(2)}%  |  Silver Making: ${d.silverMakingPercent.toStringAsFixed(2)}%'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Description', 'Type / Purity', 'Weight/Qty', 'Rate', 'Item Amount', 'Making', 'Total'],
          data: d.items.map((item) {
            final amount = d.amountFor(item);
            final making = d.makingFor(item);
            final rateText = item.type == ItemType.gold
                ? '${money(d.metalRateFor(item))}/g'
                : item.type == ItemType.silver
                    ? '${money(d.silverRatePerGram)}/g'
                    : money(item.otherRateValue);
            final typeText = item.type == ItemType.gold ? 'Gold ${item.goldPurity}K' : itemTypeName(item.type);
            final weightText = item.type == ItemType.other
                ? (item.weight.trim().isEmpty ? '-' : item.weight.trim())
                : '${item.weightValue.toStringAsFixed(2)} g';
            return [
              item.name.trim().isEmpty ? 'Item' : item.name.trim(),
              typeText,
              weightText,
              rateText,
              money(amount),
              money(making),
              money(amount + making),
            ];
          }).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.amber100),
          cellAlignment: pw.Alignment.center,
          columnWidths: {
            0: const pw.FlexColumnWidth(1.3),
            1: const pw.FlexColumnWidth(0.85),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(0.95),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(0.85),
            6: const pw.FlexColumnWidth(0.95),
          },
        ),
        pw.SizedBox(height: 7),
        pw.Text(
          'The rate printed for each gold item is its applied per-gram rate. '
          'Purity and rate are shown for gold below 18K as well.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 16),
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 245,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                _summaryRow('Items Amount', d.jewelleryTotal),
                _summaryRow('Making Charges', d.makingTotal),
                pw.Divider(),
                _summaryRow('Subtotal', d.subtotal),
                _summaryRow('GST (${d.applyGst ? d.gstPercentage : 0}%)', d.gstAmount),
                pw.Divider(),
                pw.Container(
                  padding: const pw.EdgeInsets.all(9),
                  color: PdfColors.amber100,
                  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text('GRAND TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.Text(money(d.grandTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  ]),
                ),
                if (d.hasPaymentEntry) ...[
                  pw.SizedBox(height: 6),
                  _summaryRow('Paid at billing', bill.paidAtBilling),
                  ...bill.payments.map((pm) => _summaryRow('Received ${fmtDate(pm.date)}', pm.amount)),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(9),
                    color: bill.hasDue ? PdfColors.red50 : PdfColors.green50,
                    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text(bill.hasDue ? 'BALANCE DUE' : 'PAID IN FULL',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                              color: bill.hasDue ? PdfColors.red800 : PdfColors.green800)),
                      pw.Text(money(bill.dueAmount),
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                              color: bill.hasDue ? PdfColors.red800 : PdfColors.green800)),
                    ]),
                  ),
                ],
              ]),
            )),
        pw.SizedBox(height: 20),
        if (bill.qrAmount > 0)
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: _upiUri(bill),
            width: 92,
            height: 92,
            drawText: false,
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SCAN TO PAY',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
            pw.SizedBox(height: 4),
            pw.Text('UPI ID: $shopUpiId', style: const pw.TextStyle(fontSize: 8)),
            pw.Text(
                d.hasPaymentEntry
                    ? 'Amount on QR: ${money(bill.qrAmount)} (${qrModeLabel(d.effectiveQrMode)})'
                    : 'Payable amount: ${money(d.grandTotal)}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text('Verify the payee name and amount in your UPI app before paying.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          ])),
        ]),
        pw.SizedBox(height: 22),
        pw.Divider(),
        pw.Center(
            child: pw.Text('Thank you for shopping with Shree Janki Jewellers!',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
      ],
    ));
    return document.save();
  }
}
