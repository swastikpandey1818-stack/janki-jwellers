import 'package:flutter/material.dart';

import '../constants.dart';
import '../crm_models.dart';
import '../messages.dart';
import '../models.dart';
import '../store.dart';
import '../whatsapp.dart';
import '../widgets.dart';
import 'booking_form_page.dart';
import 'bookings_page.dart';

const _red = Color(0xFFC62828);
const _green = Color(0xFF2E7D32);

String _initial(String name) => name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

/// Shows a list of saved customers and returns the one that was tapped (null if closed).
Future<Customer?> pickCustomer(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PickCustomerSheet(),
  );
}

class _PickCustomerSheet extends StatefulWidget {
  const _PickCustomerSheet();

  @override
  State<_PickCustomerSheet> createState() => _PickCustomerSheetState();
}

class _PickCustomerSheetState extends State<_PickCustomerSheet> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final all = store.customersSorted;
    final list = q.isEmpty
        ? all
        : all.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Choose customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: maroon)),
              const SizedBox(height: 10),
              TextField(
                controller: search,
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(hintText: 'Search name or mobile', prefixIcon: Icon(Icons.search)),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(all.isEmpty ? 'No customers yet. They are added automatically when you make a bill.' : 'No matching customer.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.brown.shade400)),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFFF1D6),
                          child: Text(_initial(c.name), style: const TextStyle(color: maroon, fontWeight: FontWeight.w800)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(c.phone.trim().isEmpty ? 'No mobile number' : c.phone.trim()),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Add or edit a customer. Returns true when saved.
Future<bool> showCustomerDialog(BuildContext context, {Customer? editing}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CustomerDialog(editing: editing),
  );
  return saved == true;
}

class _CustomerDialog extends StatefulWidget {
  final Customer? editing;
  const _CustomerDialog({this.editing});

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final name = TextEditingController(text: widget.editing?.name ?? '');
  late final phone = TextEditingController(text: widget.editing?.phone ?? '');
  late final address = TextEditingController(text: widget.editing?.address ?? '');
  late final note = TextEditingController(text: widget.editing?.note ?? '');
  late DateTime? birthday = widget.editing?.birthday;
  late DateTime? anniversary = widget.editing?.anniversary;
  String? error;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) {
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Pick the date (year does not matter)',
    );
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    final customer = Customer(
      name: name.text,
      phone: phone.text,
      address: address.text.trim(),
      note: note.text.trim(),
      birthday: birthday,
      anniversary: anniversary,
    );
    final err = await store.saveCustomer(customer, editing: widget.editing);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        error = err;
        saving = false;
      });
    } else {
      Navigator.pop(context, true);
    }
  }

  Widget _dateRow(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            final d = await _pick(value);
            if (d != null) onChanged(d);
          },
          icon: const Icon(Icons.cake_outlined, size: 18),
          label: Text(value == null ? label : '$label: ${fmtDayMonth(value)}'),
        ),
      ),
      if (value != null)
        IconButton(
          tooltip: 'Remove',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close, size: 18),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing == null ? 'Add customer' : 'Edit customer'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name', errorText: error),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number (for WhatsApp)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Address (optional)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 12),
          _dateRow('Birthday', birthday, (d) => setState(() => birthday = d)),
          _dateRow('Anniversary', anniversary, (d) => setState(() => anniversary = d)),
          if (widget.editing != null) ...[
            const SizedBox(height: 8),
            Text('Old bills keep the name and mobile they were made with.',
                style: TextStyle(color: Colors.brown.shade400, fontSize: 11.5)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Customers list page
// ---------------------------------------------------------------------------

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final search = TextEditingController();
  String query = '';
  bool dueOnly = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _open(Customer c) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: c)));
  }

  Widget _tile(Customer c) {
    final due = store.dueOf(c);
    final held = store.advanceHeldOf(c);
    final bills = store.billsOf(c).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: const Color(0xFFFFF1D6),
              child: Text(_initial(c.name), style: const TextStyle(color: maroon, fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(c.phone.trim().isEmpty ? 'No mobile number' : c.phone.trim(),
                    style: TextStyle(color: Colors.brown.shade400, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('$bills bill${bills == 1 ? '' : 's'}', style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (due > 0.005)
                Text('Due ${money(due)}', style: const TextStyle(color: _red, fontWeight: FontWeight.w800, fontSize: 12.5)),
              if (held > 0.005)
                Text('Advance ${money(held)}',
                    style: const TextStyle(color: _green, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = query.trim().toLowerCase();
        var list = store.customersSorted;
        if (dueOnly) list = list.where((c) => store.dueOf(c) > 0.005).toList();
        if (q.isNotEmpty) {
          list = list.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
        }
        final dueCount = store.customers.where((c) => store.dueOf(c) > 0.005).length;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: sectionTitle('Customers', subtitle: '${store.customers.length} saved. New customers are added when you make a bill.'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                      onPressed: () => showCustomerDialog(context),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Add'),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: search,
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'Search name or mobile',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                search.clear();
                                setState(() => query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: !dueOnly,
                        onSelected: (_) => setState(() => dueOnly = false),
                      ),
                      ChoiceChip(
                        label: Text('With due ($dueCount)'),
                        selected: dueOnly,
                        onSelected: (_) => setState(() => dueOnly = true),
                      ),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? ListView(children: [
                        EmptyState(
                          title: store.customers.isEmpty ? 'No customers yet' : 'No matching customers',
                          subtitle: store.customers.isEmpty
                              ? 'Make a bill or tap Add to save your first customer.'
                              : 'Try a different name or mobile number.',
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (context, i) => _tile(list[i]),
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// One customer
// ---------------------------------------------------------------------------

class CustomerDetailPage extends StatelessWidget {
  final Customer customer;
  const CustomerDetailPage({super.key, required this.customer});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this customer?'),
        content: Text('${customer.name} will be removed from the customer list. '
            'Their bills and bookings are not deleted, and they come back in the list if you bill them again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.deleteCustomer(customer);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  void _newBill(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    store.useAsTemplate(BillData(customerName: customer.name, customerPhone: customer.phone));
    navIndex.value = 1;
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: Colors.brown.shade400),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _stat(String label, String value, {Color? color}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E9), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: Colors.brown.shade500)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color ?? maroon)),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.customers.contains(customer)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Customer')),
            body: const Center(child: Text('This customer was removed.')),
          );
        }
        final bills = store.billsOf(customer);
        final bookings = store.bookingsOf(customer);
        final spent = bills.fold(0.0, (s, b) => s + b.grandTotal);
        final due = store.dueOf(customer);
        final held = store.advanceHeldOf(customer);
        return Scaffold(
          appBar: AppBar(
            title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                tooltip: 'Edit',
                onPressed: () => showCustomerDialog(context, editing: customer),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Remove customer',
                onPressed: () => _delete(context),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 950),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFFFFF1D6),
                          child: Text(_initial(customer.name),
                              style: const TextStyle(color: maroon, fontWeight: FontWeight.w900, fontSize: 22)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                            Text(customer.phone.trim().isEmpty ? 'No mobile number' : customer.phone.trim(),
                                style: TextStyle(color: Colors.brown.shade500)),
                          ]),
                        ),
                      ]),
                      if (customer.address.trim().isNotEmpty) _line(Icons.location_on_outlined, customer.address.trim()),
                      if (customer.birthday != null) _line(Icons.cake_outlined, 'Birthday: ${fmtDayMonth(customer.birthday!)}'),
                      if (customer.anniversary != null)
                        _line(Icons.favorite_border, 'Anniversary: ${fmtDayMonth(customer.anniversary!)}'),
                      if (customer.note.trim().isNotEmpty) _line(Icons.notes, customer.note.trim()),
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  _stat('Bills', '${bills.length}'),
                  const SizedBox(width: 8),
                  _stat('Total bought', money(spent)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _stat('Due', money(due), color: due > 0.005 ? _red : _green),
                  const SizedBox(width: 8),
                  _stat('Advance held', money(held), color: held > 0.005 ? _green : maroon),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855), foregroundColor: Colors.white),
                      onPressed: () => sendWhatsAppDialog(context,
                          phone: customer.phone, text: generalText(customer.name), title: 'Message ${customer.name}'),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('WHATSAPP'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => callWithMessage(context, customer.phone),
                      icon: const Icon(Icons.call, size: 18),
                      label: const Text('CALL'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                      onPressed: () => _newBill(context),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('NEW BILL'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => BookingFormPage(customer: customer)),
                      ),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('NEW BOOKING'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                sectionTitle('Bookings (${bookings.length})'),
                const SizedBox(height: 8),
                if (bookings.isEmpty)
                  Text('No bookings.', style: TextStyle(color: Colors.brown.shade400))
                else
                  ...bookings.map((k) => BookingTile(booking: k)),
                const SizedBox(height: 14),
                sectionTitle('Bills (${bills.length})'),
                const SizedBox(height: 8),
                if (bills.isEmpty)
                  Text('No bills yet.', style: TextStyle(color: Colors.brown.shade400))
                else
                  ...bills.map((b) => BillTile(bill: b)),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        );
      },
    );
  }
}
