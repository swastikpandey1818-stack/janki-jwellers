import 'dart:async';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../crm_models.dart';
import '../exchange_dialog.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'bill_detail_page.dart';
import 'customers_page.dart';

/// Text controllers for one item while the bill is being typed.
class ItemForm {
  final name = TextEditingController();
  final weight = TextEditingController();
  final customGoldRate = TextEditingController();
  final otherRate = TextEditingController();
  final otherAmount = TextEditingController();
  final otherMaking = TextEditingController();
  ItemType type = ItemType.gold;
  int goldPurity = 22;
  bool useCustomGoldRate = false;

  ItemForm();

  ItemForm.fromData(ItemData d) {
    name.text = d.name;
    weight.text = d.weight;
    customGoldRate.text = d.customGoldRate;
    otherRate.text = d.otherRate;
    otherAmount.text = d.otherAmount;
    otherMaking.text = d.otherMaking;
    type = d.type;
    goldPurity = d.goldPurity;
    useCustomGoldRate = d.useCustomGoldRate;
  }

  ItemData toData() => ItemData(
        name: name.text,
        weight: weight.text,
        customGoldRate: customGoldRate.text,
        otherRate: otherRate.text,
        otherAmount: otherAmount.text,
        otherMaking: otherMaking.text,
        type: type,
        goldPurity: goldPurity,
        useCustomGoldRate: useCustomGoldRate,
      );

  void dispose() {
    name.dispose();
    weight.dispose();
    customGoldRate.dispose();
    otherRate.dispose();
    otherAmount.dispose();
    otherMaking.dispose();
  }
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> with WidgetsBindingObserver {
  final customerName = TextEditingController();
  final customerPhone = TextEditingController();
  final goldRateController = TextEditingController(text: '70000');
  final silverRateController = TextEditingController(text: '100');
  final goldMakingPercentController = TextEditingController(text: '10');
  final silverMakingPercentController = TextEditingController(text: '10');
  final gstController = TextEditingController(text: '3');
  final amountPaidController = TextEditingController();

  final List<ItemForm> items = [ItemForm()];
  bool makingEnabled = true;
  bool applyGst = false;
  QrMode? qrMode;
  bool busy = false;
  /// Old gold / silver the customer gives back (deducted from the total).
  List<ExchangeItem> exchanges = [];
  Timer? _saveTimer;

  /// Booking this bill is being made from ('' = none). Its advance counts as already paid.
  String linkedBookingId = '';
  int _seenRatesVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onStore);
    _restoreDraft();
    _syncRatesFromStore();
  }

  /// The rates live in the store (set on the Dashboard); the fields here show them.
  void _syncRatesFromStore() {
    goldRateController.text = fmtRate(store.goldRate);
    silverRateController.text = fmtRate(store.silverRate);
    _seenRatesVersion = store.ratesVersion;
  }

  // ---------- draft cache (typed bill + prices survive closing the app) ----------

  // Every setState (typing, switches, dropdowns) also schedules a draft save.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveDraftNow);
  }

  void _saveDraftNow() {
    final data = _toData();
    store.saveDraft(data.toJson());
    store.rememberBillingRates(data.goldRatePer10g, data.silverRatePerGram);
  }

  void _restoreDraft() {
    final json = store.loadDraft();
    if (json == null) return;
    try {
      _applyData(BillData.fromJson(json), includeRates: true);
    } catch (_) {
      // Unreadable draft: start with a blank bill.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveTimer?.cancel();
      _saveDraftNow();
    }
  }

  // ---------- form <-> data ----------

  BillData _toData() => BillData(
        customerName: customerName.text,
        customerPhone: customerPhone.text,
        goldRate: goldRateController.text,
        silverRate: silverRateController.text,
        goldMaking: goldMakingPercentController.text,
        silverMaking: silverMakingPercentController.text,
        gst: gstController.text,
        makingEnabled: makingEnabled,
        applyGst: applyGst,
        amountPaid: amountPaidController.text,
        qrMode: qrMode,
        bookingId: linkedBookingId,
        items: items.map((i) => i.toData()).toList(),
        exchanges: List<ExchangeItem>.of(exchanges),
      );

  void _disposeLater(List<ItemForm> old) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final item in old) {
        item.dispose();
      }
    });
  }

  /// Fills the form from [d]. Call inside setState when the screen is already showing.
  void _applyData(BillData d, {required bool includeRates}) {
    customerName.text = d.customerName;
    customerPhone.text = d.customerPhone;
    // A saved draft keeps its amount paid; a copied old bill starts with nothing paid entered.
    amountPaidController.text = includeRates ? d.amountPaid : '';
    qrMode = includeRates ? d.qrMode : null;
    linkedBookingId = includeRates ? d.bookingId : '';
    exchanges = includeRates ? List<ExchangeItem>.of(d.exchanges) : <ExchangeItem>[];
    if (includeRates) {
      goldRateController.text = d.goldRate;
      silverRateController.text = d.silverRate;
      goldMakingPercentController.text = d.goldMaking;
      silverMakingPercentController.text = d.silverMaking;
      gstController.text = d.gst;
      makingEnabled = d.makingEnabled;
      applyGst = d.applyGst;
    }
    final old = List<ItemForm>.of(items);
    items
      ..clear()
      ..addAll(d.items.map(ItemForm.fromData));
    if (items.isEmpty) items.add(ItemForm());
    _disposeLater(old);
  }

  void _onStore() {
    if (!mounted) return;
    if (_seenRatesVersion != store.ratesVersion) {
      setState(_syncRatesFromStore);
    }
    final booking = store.pendingBooking;
    if (booking != null) {
      store.pendingBooking = null;
      setState(() {
        _applyData(
          BillData(
            customerName: booking.customerName,
            customerPhone: booking.customerPhone,
            items: [booking.toItemData()],
          ),
          includeRates: false,
        );
        linkedBookingId = booking.id;
        amountPaidController.text = booking.advanceTotal > 0.005 ? fmtRate(booking.advanceTotal) : '';
      });
      _message(booking.advanceTotal > 0.005
          ? 'Bill started from the booking. Advance ${money(booking.advanceTotal)} is counted as paid.'
          : 'Bill started from the booking.');
      return;
    }
    final template = store.pendingTemplate;
    if (template == null) return;
    store.pendingTemplate = null;
    setState(() => _applyData(template, includeRates: false));
    _message("Customer and items copied into a new bill. Today's rates are used.");
  }

  void _resetForm() {
    final old = List<ItemForm>.of(items);
    setState(() {
      customerName.clear();
      customerPhone.clear();
      amountPaidController.clear();
      qrMode = null;
      linkedBookingId = '';
      exchanges = [];
      items
        ..clear()
        ..add(ItemForm());
    });
    _disposeLater(old);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this bill?'),
        content: const Text('Customer and items will be cleared. Your rates and making % stay saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) _resetForm();
  }

  void addItem() => setState(() => items.add(ItemForm()));

  Future<void> _addExchange() async {
    final item = await showExchangeDialog(
      context,
      goldRate10g: parseNum(goldRateController.text),
      silverRatePerGram: parseNum(silverRateController.text),
    );
    if (item != null && mounted) setState(() => exchanges.add(item));
  }

  Widget _exchangeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.swap_horiz, color: maroon),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Old Gold / Silver Exchange',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: maroon)),
            ),
            OutlinedButton.icon(onPressed: _addExchange, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
          ]),
          if (exchanges.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Customer giving old jewellery? Add it here and its value is deducted from the bill.',
                  style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
            ),
          for (final e in exchanges)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${e.weight.toStringAsFixed(3)} g, loss ${fmtRate(e.deductionPercent)}%  ->  net ${e.netWeight.toStringAsFixed(3)} g @ ${money(e.ratePerGram)}/g'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('- ${money(e.value)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => exchanges.remove(e)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  void removeItem(int index) {
    if (items.length == 1) {
      _message('At least one item is required.');
      return;
    }
    final removed = items[index];
    setState(() => items.removeAt(index));
    _disposeLater([removed]);
  }

  // ---------- generate invoice ----------

  bool _validate(BillData d, Booking? booking) {
    if (d.customerName.trim().isEmpty) {
      _message('Please enter customer name.');
      return false;
    }
    if (d.goldRatePer10g <= 0 ||
        d.silverRatePerGram < 0 ||
        d.goldMakingPercent < 0 ||
        d.silverMakingPercent < 0 ||
        d.gstPercentage < 0) {
      _message('Enter a valid gold rate. Rates and percentages cannot be negative.');
      return false;
    }
    if (d.applyGst && d.gstPercentage > 100) {
      _message('GST percentage cannot exceed 100%.');
      return false;
    }
    if (d.exchangeTotal > d.grossTotal + 0.005) {
      _message('Old gold / silver value (${money(d.exchangeTotal)}) cannot be more than the bill total (${money(d.grossTotal)}).');
      return false;
    }
    if (d.amountPaidValue < 0) {
      _message('Amount paid cannot be negative.');
      return false;
    }
    if (d.hasPaymentEntry && d.amountPaidValue > d.grandTotal + 0.005) {
      _message('Amount paid cannot be more than the grand total (${money(d.grandTotal)}).');
      return false;
    }
    if (booking != null && booking.advanceTotal > 0.005 && d.hasPaymentEntry) {
      final needed = booking.advanceTotal < d.grandTotal ? booking.advanceTotal : d.grandTotal;
      if (d.amountPaidValue + 0.005 < needed) {
        _message('Amount paid must include the booking advance (${money(needed)}). Leave it empty if paid in full.');
        return false;
      }
    }
    for (final item in d.items) {
      if (item.weightValue < 0 ||
          item.customGoldRateValue < 0 ||
          item.otherRateValue < 0 ||
          item.otherAmountValue < 0 ||
          item.otherMakingValue < 0) {
        _message('Weight, rates and amounts cannot be negative.');
        return false;
      }
      if (item.type == ItemType.gold &&
          item.useCustomGoldRate &&
          (item.customGoldRate.trim().isEmpty || item.customGoldRateValue <= 0)) {
        _message('Enter a valid custom gold rate per gram.');
        return false;
      }
      if (item.type == ItemType.other && item.otherAmount.trim().isEmpty) {
        _message('Please enter the item amount for every Others item.');
        return false;
      }
    }
    return true;
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generate() async {
    if (busy) return;
    final data = _toData();
    Booking? booking;
    if (linkedBookingId.isNotEmpty) {
      booking = store.bookingById(linkedBookingId);
      if (booking == null || !booking.isOpen) {
        _message('The linked booking is no longer open. Tap Unlink on the booking card to continue.');
        return;
      }
    }
    if (!_validate(data, booking)) return;
    if (booking != null) {
      data.advanceUsed = booking.advanceTotal < data.paidAmount ? booking.advanceTotal : data.paidAmount;
    }
    setState(() => busy = true);
    try {
      final bill = await store.saveBill(data);
      if (booking != null) await store.completeBooking(booking.id, bill);
      _resetForm();
      _saveDraftNow();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BillDetailPage(bill: bill, justCreated: true)),
      );
    } catch (e) {
      _message('Could not save invoice: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- UI helpers ----------

  Widget inputField(String label, TextEditingController controller,
          {TextInputType keyboardType = TextInputType.text}) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      );

  Widget summaryTile(String label, double value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 16 : 14)),
          Text(money(value),
              style: TextStyle(
                color: color ?? (bold ? maroon : Colors.black87),
                fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
                fontSize: bold ? 19 : 14,
              )),
        ]),
      );

  Widget _invoiceHeader() {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [maroon, Color(0xFF812C3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Image.asset(gemAsset, width: 56, height: 56,
              errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Colors.white, size: 40)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NEW INVOICE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
              Text(store.nextInvoiceNo,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
              Text(fmtDate(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF0D080)),
            onPressed: _confirmClear,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Clear'),
          ),
        ]),
      ),
    );
  }

  Widget _buildItemCard(ItemForm item, int index, BillData data, TextInputType numberKeyboard) {
    final it = data.items[index];
    final amount = data.amountFor(it);
    final making = data.makingFor(it);
    return KeyedSubtree(
      key: ObjectKey(item),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(10)),
                child: Image.asset(typeImage(item.type), width: 32, height: 32,
                    errorBuilder: (_, __, ___) => Text('${index + 1}',
                        style: const TextStyle(color: maroon, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Item ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(
                  onPressed: () => removeItem(index), icon: const Icon(Icons.delete_outline, color: Colors.red)),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<ItemType>(
              initialValue: item.type,
              decoration: const InputDecoration(labelText: 'Item Type'),
              items: const [
                DropdownMenuItem(value: ItemType.gold, child: Text('Gold')),
                DropdownMenuItem(value: ItemType.silver, child: Text('Silver')),
                DropdownMenuItem(value: ItemType.other, child: Text('Others (Pearls, Gems, etc.)')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => item.type = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
                controller: item.name,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Item Description / Name')),
            const SizedBox(height: 10),
            if (item.type == ItemType.gold) ...[
              TextField(
                  controller: item.weight,
                  keyboardType: numberKeyboard,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Weight in grams')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: item.goldPurity,
                decoration: const InputDecoration(labelText: 'Gold Purity'),
                items: const [24, 22, 20, 18, 14]
                    .map((p) => DropdownMenuItem(value: p, child: Text('$p Karat')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => item.goldPurity = value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use custom gold rate'),
                subtitle: const Text('Override automatic purity-adjusted pricing for this item.'),
                value: item.useCustomGoldRate,
                onChanged: (value) => setState(() => item.useCustomGoldRate = value),
              ),
              if (item.useCustomGoldRate)
                TextField(
                    controller: item.customGoldRate,
                    keyboardType: numberKeyboard,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Custom gold rate per gram (Rs.)')),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: const Color(0xFFFFF8E9), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Applied rate: ${money(data.metalRateFor(it))} per gram'
                  '${item.useCustomGoldRate ? " (manual)" : " (automatic: 24K rate × ${item.goldPurity}/24)"}',
                  style: const TextStyle(color: maroon, fontWeight: FontWeight.w700),
                ),
              ),
            ] else if (item.type == ItemType.silver) ...[
              TextField(
                  controller: item.weight,
                  keyboardType: numberKeyboard,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Weight in grams')),
              const SizedBox(height: 9),
              Text('Silver calculation rate: ${money(data.silverRatePerGram)} per gram',
                  style: const TextStyle(color: Colors.black54)),
            ] else ...[
              TextField(
                  controller: item.weight,
                  keyboardType: numberKeyboard,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Weight / Quantity (optional)')),
              const SizedBox(height: 10),
              TextField(
                  controller: item.otherRate,
                  keyboardType: numberKeyboard,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Rate (optional, for reference) Rs.')),
              const SizedBox(height: 10),
              TextField(
                  controller: item.otherAmount,
                  keyboardType: numberKeyboard,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Item Amount set by seller (Rs.)')),
              if (makingEnabled) ...[
                const SizedBox(height: 10),
                TextField(
                    controller: item.otherMaking,
                    keyboardType: numberKeyboard,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Making / Extra Charge set by seller (Rs.)')),
              ],
            ],
            const SizedBox(height: 13),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8F5F0), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Item Amount: ${money(amount)}'),
                Text('Making Charges: ${money(making)}'),
                const Divider(height: 12),
                Text('Item Total: ${money(amount + making)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: maroon, fontSize: 15)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _linkedBookingCard() {
    final k = store.bookingById(linkedBookingId);
    return Card(
      color: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          const Icon(Icons.bookmark, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              k == null
                  ? 'Linked booking not found.'
                  : 'Delivering booking for ${k.customerName}. Advance ${money(k.advanceTotal)} is counted as already paid.',
              style: const TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              linkedBookingId = '';
              amountPaidController.clear();
            }),
            child: const Text('Unlink'),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onStore);
    _saveTimer?.cancel();
    customerName.dispose();
    customerPhone.dispose();
    goldRateController.dispose();
    silverRateController.dispose();
    goldMakingPercentController.dispose();
    silverMakingPercentController.dispose();
    gstController.dispose();
    amountPaidController.dispose();
    for (final item in items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    final data = _toData();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _invoiceHeader(),
          const SizedBox(height: 20),
          sectionTitle('Customer Details', subtitle: 'Enter the customer information for this bill.'),
          const SizedBox(height: 12),
          TextField(
            controller: customerName,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Customer Name',
              suffixIcon: IconButton(
                tooltip: 'Choose from saved customers',
                icon: const Icon(Icons.person_search),
                onPressed: () async {
                  final c = await pickCustomer(context);
                  if (c == null) return;
                  setState(() {
                    customerName.text = c.name;
                    customerPhone.text = c.phone;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          inputField('Mobile Number', customerPhone, keyboardType: TextInputType.phone),
          const SizedBox(height: 24),
          sectionTitle('Daily Rates & Making Charges',
              subtitle: 'Same rates as the Dashboard (set yourself or fetched online). Saved until you change them.'),
          const SizedBox(height: 12),
          inputField('24K Gold Rate per 10 grams (Rs.)', goldRateController, keyboardType: numberKeyboard),
          const SizedBox(height: 10),
          inputField('Silver Rate per gram (Rs.)', silverRateController, keyboardType: numberKeyboard),
          const SizedBox(height: 7),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Making Charges'),
            subtitle: const Text('Turn off to remove making charges from all items.'),
            value: makingEnabled,
            onChanged: (value) => setState(() => makingEnabled = value),
          ),
          if (makingEnabled)
            Row(children: [
              Expanded(child: inputField('Gold Making (%)', goldMakingPercentController, keyboardType: numberKeyboard)),
              const SizedBox(width: 10),
              Expanded(
                  child: inputField('Silver Making (%)', silverMakingPercentController, keyboardType: numberKeyboard)),
            ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            sectionTitle('Jewellery / Items'),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
              onPressed: addItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
          ]),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: _buildItemCard(entry.value, entry.key, data, numberKeyboard),
              )),
          const SizedBox(height: 8),
          _exchangeCard(),
          const SizedBox(height: 10),
          if (linkedBookingId.isNotEmpty) _linkedBookingCard(),
          Card(
            color: const Color(0xFFFFF8E9),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(children: [
                sectionTitle('Bill Summary'),
                const SizedBox(height: 12),
                summaryTile('Items Amount', data.jewelleryTotal),
                summaryTile('Making Charges', data.makingTotal),
                const Divider(),
                summaryTile('Subtotal', data.subtotal),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Apply GST'),
                  value: applyGst,
                  onChanged: (value) => setState(() => applyGst = value),
                ),
                if (applyGst) ...[
                  inputField('GST Percentage', gstController, keyboardType: numberKeyboard),
                  const SizedBox(height: 8),
                  summaryTile('GST Amount', data.gstAmount),
                ],
                if (data.exchanges.isNotEmpty) ...[
                  summaryTile('Gross Total', data.grossTotal),
                  summaryTile('Less: Old Gold / Silver', -data.exchangeTotal, color: const Color(0xFF2E7D32)),
                ],
                const Divider(),
                summaryTile('GRAND TOTAL', data.grandTotal, bold: true),
                const Divider(),
                inputField('Amount Paid by Customer (Rs.)', amountPaidController, keyboardType: numberKeyboard),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Leave empty if the customer paid the full amount.',
                      style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
                ),
                if (data.hasPaymentEntry) ...[
                  const SizedBox(height: 8),
                  summaryTile('Amount Paid', data.amountPaidValue),
                  summaryTile(data.hasDue ? 'BALANCE DUE' : 'BALANCE DUE (fully paid)', data.dueAmount,
                      bold: true, color: data.hasDue ? const Color(0xFFC62828) : const Color(0xFF2E7D32)),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Amount on the QR code',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Colors.brown.shade600)),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final mode in QrMode.values)
                        ChoiceChip(
                          label: Text('${qrModeLabel(mode)}  ${money(mode == QrMode.due ? data.dueAmount : mode == QrMode.paid ? data.paidAmount : data.grandTotal)}'),
                          selected: data.effectiveQrMode == mode,
                          onSelected: (_) => setState(() => qrMode = mode),
                        ),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: store,
            builder: (context, _) => SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                onPressed: busy ? null : _generate,
                icon: const Icon(Icons.receipt_long),
                label: Text(busy ? 'PLEASE WAIT...' : 'GENERATE INVOICE ${store.nextInvoiceNo}'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The bill is saved in Bill History with its invoice number, then you can share, download or print it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.brown.shade400, fontSize: 12),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
