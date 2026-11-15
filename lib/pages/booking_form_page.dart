import 'package:flutter/material.dart';

import '../constants.dart';
import '../crm_models.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'booking_detail_page.dart';
import 'customers_page.dart';

/// Create a new booking (with the first advance) or edit the details of an existing one.
class BookingFormPage extends StatefulWidget {
  final Booking? editing;
  final Customer? customer;
  const BookingFormPage({super.key, this.editing, this.customer});

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  final nameC = TextEditingController();
  final phoneC = TextEditingController();
  final descC = TextEditingController();
  final weightC = TextEditingController();
  final lockedC = TextEditingController();
  final estimateC = TextEditingController();
  final advanceC = TextEditingController();
  final advanceNoteC = TextEditingController();
  final noteC = TextEditingController();

  ItemType metal = ItemType.gold;
  int purity = 22;
  DateTime? delivery;
  bool saving = false;

  bool get isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final k = widget.editing;
    if (k != null) {
      nameC.text = k.customerName;
      phoneC.text = k.customerPhone;
      descC.text = k.description;
      weightC.text = k.weight;
      lockedC.text = k.lockedRate;
      estimateC.text = k.estimatedAmount;
      noteC.text = k.note;
      metal = k.metal;
      purity = k.goldPurity;
      delivery = k.deliveryDate;
    } else if (widget.customer != null) {
      nameC.text = widget.customer!.name;
      phoneC.text = widget.customer!.phone;
    }
  }

  @override
  void dispose() {
    nameC.dispose();
    phoneC.dispose();
    descC.dispose();
    weightC.dispose();
    lockedC.dispose();
    estimateC.dispose();
    advanceC.dispose();
    advanceNoteC.dispose();
    noteC.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickCustomer() async {
    final c = await pickCustomer(context);
    if (c == null) return;
    setState(() {
      nameC.text = c.name;
      phoneC.text = c.phone;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: delivery ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Expected delivery date',
    );
    if (d != null) setState(() => delivery = d);
  }

  double get _metalValue {
    final temp = Booking(
      id: 'tmp',
      customerName: '',
      metal: metal,
      weight: weightC.text,
      goldPurity: purity,
      lockedRate: metal == ItemType.gold ? lockedC.text : '',
    );
    return temp.metalValueAt(goldPer10g: store.goldRate, silverPerGram: store.silverRate);
  }

  Future<void> _save() async {
    if (saving) return;
    final name = nameC.text.trim();
    if (name.isEmpty) {
      _message('Please enter the customer name.');
      return;
    }
    if (metal == ItemType.gold && lockedC.text.trim().isNotEmpty && parseNum(lockedC.text) <= 0) {
      _message('Enter a valid booked gold rate, or leave it empty.');
      return;
    }
    final advance = parseNum(advanceC.text);
    setState(() => saving = true);
    try {
      final k = widget.editing ?? Booking(id: Booking.newId(), customerName: name);
      k.customerName = name;
      k.customerPhone = phoneC.text.trim();
      k.description = descC.text.trim();
      k.metal = metal;
      k.weight = weightC.text.trim();
      k.goldPurity = purity;
      k.lockedRate = metal == ItemType.gold ? lockedC.text.trim() : '';
      k.estimatedAmount = estimateC.text.trim();
      k.deliveryDate = delivery;
      k.note = noteC.text.trim();
      if (!isEdit && advance > 0) {
        k.advances.add(Payment(date: DateTime.now(), amount: advance, note: advanceNoteC.text.trim()));
      }
      final err = await store.saveBooking(k, isNew: !isEdit);
      if (!mounted) return;
      if (err != null) {
        _message(err);
        return;
      }
      if (isEdit) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => BookingDetailPage(bookingId: k.id, justCreated: true)),
        );
      }
    } catch (e) {
      _message('Could not save: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    final value = _metalValue;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit booking' : 'New booking / advance', style: const TextStyle(fontWeight: FontWeight.bold))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            sectionTitle('Customer'),
            const SizedBox(height: 10),
            TextField(
              controller: nameC,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Customer name',
                suffixIcon: IconButton(
                  tooltip: 'Choose from saved customers',
                  onPressed: _pickCustomer,
                  icon: const Icon(Icons.person_search),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneC,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number (for WhatsApp)'),
            ),
            const SizedBox(height: 22),
            sectionTitle('What is booked', subtitle: 'Leave the item empty if this is just an advance.'),
            const SizedBox(height: 10),
            TextField(
              controller: descC,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Item description (e.g. Necklace set)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ItemType>(
              initialValue: metal,
              decoration: const InputDecoration(labelText: 'Metal'),
              items: const [
                DropdownMenuItem(value: ItemType.gold, child: Text('Gold')),
                DropdownMenuItem(value: ItemType.silver, child: Text('Silver')),
                DropdownMenuItem(value: ItemType.other, child: Text('Others (Pearls, Gems, etc.)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => metal = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: weightC,
              keyboardType: numberKeyboard,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: metal == ItemType.other ? 'Weight / Quantity (optional)' : 'Approx. weight in grams'),
            ),
            if (metal == ItemType.gold) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: purity,
                decoration: const InputDecoration(labelText: 'Gold purity'),
                items: const [24, 22, 20, 18, 14].map((p) => DropdownMenuItem(value: p, child: Text('$p Karat'))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => purity = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lockedC,
                keyboardType: numberKeyboard,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Booked 24K gold rate per 10 g (optional)',
                  helperText: 'If filled, the final bill uses this rate for this item.',
                  suffixIcon: TextButton(
                    onPressed: () => setState(() => lockedC.text = fmtRate(store.goldRate)),
                    child: const Text("Today's"),
                  ),
                ),
              ),
            ],
            if (metal != ItemType.other && value > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: const Color(0xFFFFF8E9), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Metal value ≈ ${money(value)} at the ${metal == ItemType.gold && parseNum(lockedC.text) > 0 ? 'booked' : "today's"} rate. Making charges are extra.',
                  style: const TextStyle(color: maroon, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: estimateC,
              keyboardType: numberKeyboard,
              decoration: const InputDecoration(labelText: 'Estimated total amount (Rs., optional)'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(delivery == null ? 'Expected delivery date' : 'Delivery: ${fmtDate(delivery!)}'),
                ),
              ),
              if (delivery != null)
                IconButton(
                  tooltip: 'Remove date',
                  onPressed: () => setState(() => delivery = null),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ]),
            if (!isEdit) ...[
              const SizedBox(height: 22),
              sectionTitle('Advance received now', subtitle: 'You can add more advance later from the booking.'),
              const SizedBox(height: 10),
              TextField(
                controller: advanceC,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(labelText: 'Advance amount (Rs.)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: advanceNoteC,
                decoration: const InputDecoration(labelText: 'Note (optional, e.g. cash / UPI)'),
              ),
            ],
            const SizedBox(height: 22),
            TextField(
              controller: noteC,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (design, size, special request...)'),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(saving ? 'PLEASE WAIT...' : (isEdit ? 'SAVE CHANGES' : 'SAVE BOOKING')),
              ),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}
