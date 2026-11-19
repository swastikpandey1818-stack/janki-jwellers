import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models.dart';
import '../stock.dart';
import '../widgets.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String query = '';
  ItemType? filter;

  Color _typeColor(ItemType t) => t == ItemType.gold ? const Color(0xFFB8860B) : t == ItemType.silver ? Colors.blueGrey : maroon;

  IconData _typeIcon(ItemType t) => t == ItemType.other ? Icons.diamond_outlined : Icons.circle;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _form({StockItem? edit}) async {
    final name = TextEditingController(text: edit?.name ?? '');
    final purity = TextEditingController(text: edit?.purity ?? '');
    final weight = TextEditingController(text: edit == null || edit.weight == 0 ? '' : fmtRate(edit.weight));
    final pieces = TextEditingController(text: edit == null || edit.pieces == 0 ? '' : '${edit.pieces}');
    final minP = TextEditingController(text: edit == null || edit.minPieces == 0 ? '' : '${edit.minPieces}');
    var type = edit?.type ?? ItemType.gold;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(edit == null ? 'New stock item' : 'Edit item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Item name (e.g. Chain, Ring)'),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ItemType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ItemType.gold, label: Text('Gold')),
                    ButtonSegment(value: ItemType.silver, label: Text('Silver')),
                    ButtonSegment(value: ItemType.other, label: Text('Other')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setD(() => type = s.first),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: purity, decoration: const InputDecoration(labelText: 'Purity (e.g. 22K, 92.5%)')),
              if (edit == null) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Opening weight (grams)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pieces,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Opening pieces'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: minP,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Low-stock alert at (pieces)', helperText: 'Leave empty for no alert'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Color(0xFFC62828))),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setD(() => error = 'Enter the item name.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (edit == null) {
      await stockStore.add(StockItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        type: type,
        purity: purity.text.trim(),
        weight: parseNum(weight.text),
        pieces: int.tryParse(pieces.text.trim()) ?? 0,
        minPieces: int.tryParse(minP.text.trim()) ?? 0,
      ));
    } else {
      edit
        ..name = name.text.trim()
        ..type = type
        ..purity = purity.text.trim()
        ..minPieces = int.tryParse(minP.text.trim()) ?? 0;
      await stockStore.edit(edit);
    }
  }

  Future<void> _move(StockItem item, bool isIn) async {
    final weight = TextEditingController();
    final pieces = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isIn ? 'Stock IN: ${item.name}' : 'Stock OUT: ${item.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Now: ${item.weight.toStringAsFixed(3)} g, ${item.pieces} pcs',
                  style: TextStyle(color: Colors.brown.shade500, fontSize: 12.5)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: weight,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Weight (grams)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pieces,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Pieces'),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: isIn ? 'Note (e.g. from supplier)' : 'Note (e.g. sold, invoice no.)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isIn ? 'Add stock' : 'Remove stock')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await stockStore.move(item,
        isIn: isIn, weight: parseNum(weight.text), pieces: int.tryParse(pieces.text.trim()) ?? 0, note: note.text.trim());
    if (err != null) _toast(err);
  }

  Future<void> _delete(StockItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text('"${item.name}" and its stock history will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await stockStore.remove(item.id);
  }

  void _history(StockItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text('${item.name} history', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: maroon)),
            const SizedBox(height: 8),
            if (item.moves.isEmpty) const Text('No movements yet.'),
            for (final m in item.moves)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(m.isIn ? Icons.south_west : Icons.north_east,
                    color: m.isIn ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
                title: Text('${m.isIn ? '+' : '-'} ${m.weight.toStringAsFixed(3)} g,  ${m.pieces} pcs',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${fmtDateTime(m.date)}${m.note.isEmpty ? '' : '  -  ${m.note}'}'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stockStore,
      builder: (context, _) {
        final q = query.trim().toLowerCase();
        final list = stockStore.sorted.where((e) {
          if (filter != null && e.type != filter) return false;
          return q.isEmpty || e.name.toLowerCase().contains(q) || e.purity.toLowerCase().contains(q);
        }).toList();
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: maroon,
            foregroundColor: Colors.white,
            onPressed: () => _form(),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
            children: [
              Row(children: [
                _stat('Gold', '${stockStore.weightOf(ItemType.gold).toStringAsFixed(2)} g', const Color(0xFFB8860B)),
                const SizedBox(width: 8),
                _stat('Silver', '${stockStore.weightOf(ItemType.silver).toStringAsFixed(2)} g', Colors.blueGrey),
                const SizedBox(width: 8),
                _stat('Low stock', '${stockStore.lowCount}', stockStore.lowCount > 0 ? const Color(0xFFC62828) : const Color(0xFF2E7D32)),
              ]),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search stock'),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('All'), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
                for (final t in ItemType.values)
                  ChoiceChip(
                    label: Text(itemTypeName(t)),
                    selected: filter == t,
                    onSelected: (_) => setState(() => filter = filter == t ? null : t),
                  ),
              ]),
              const SizedBox(height: 10),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 50),
                  child: Column(children: [
                    Icon(Icons.inventory_2_outlined, size: 54, color: gold.withValues(alpha: 0.8)),
                    const SizedBox(height: 8),
                    Text(stockStore.items.isEmpty ? 'No stock items yet' : 'Nothing matches',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: maroon, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Tap "Add item" to start your stock register', style: TextStyle(color: Colors.brown.shade400)),
                  ]),
                ),
              for (final item in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(_typeIcon(item.type), size: 14, color: _typeColor(item.type)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item.purity.isEmpty ? item.name : '${item.name}  (${item.purity})',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                          if (item.low)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(10)),
                              child: const Text('LOW', style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w900, fontSize: 11)),
                            ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _form(edit: item);
                              if (v == 'history') _history(item);
                              if (v == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'history', child: Text('History')),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 22),
                          child: Text('${item.weight.toStringAsFixed(3)} g   |   ${item.pieces} pcs',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: maroon)),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _move(item, true),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Stock In'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFC62828))),
                              onPressed: () => _move(item, false),
                              icon: const Icon(Icons.remove, size: 18),
                              label: const Text('Stock Out'),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ]),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.brown.shade500)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: c)),
              ),
            ]),
          ),
        ),
      );
}
