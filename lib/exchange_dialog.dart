import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'models.dart';

/// Asks for one old gold / silver item the customer is giving back.
Future<ExchangeItem?> showExchangeDialog(
  BuildContext context, {
  required double goldRate10g,
  required double silverRatePerGram,
}) {
  return showDialog<ExchangeItem>(
    context: context,
    builder: (_) => _ExchangeDialog(goldRate10g: goldRate10g, silverRate: silverRatePerGram),
  );
}

class _ExchangeDialog extends StatefulWidget {
  const _ExchangeDialog({required this.goldRate10g, required this.silverRate});
  final double goldRate10g;
  final double silverRate;

  @override
  State<_ExchangeDialog> createState() => _ExchangeDialogState();
}

class _ExchangeDialogState extends State<_ExchangeDialog> {
  bool silver = false;
  int karat = 22;
  double touch = 100;
  final weight = TextEditingController();
  final rate = TextEditingController();
  final loss = TextEditingController(text: '0');
  String? error;

  static const _karats = [24, 22, 20, 18, 14];
  static const _touches = [100.0, 92.5, 80.0, 70.0];

  @override
  void initState() {
    super.initState();
    _autoRate();
  }

  @override
  void dispose() {
    weight.dispose();
    rate.dispose();
    loss.dispose();
    super.dispose();
  }

  double _autoRateValue() =>
      silver ? widget.silverRate * touch / 100 : (widget.goldRate10g / 10) * karat / 24;

  void _autoRate() => rate.text = fmtRate(_autoRateValue());

  String get _purityLabel => silver ? '${fmtRate(touch)}%' : '${karat}K';

  ExchangeItem get _preview => ExchangeItem(
        isSilver: silver,
        weight: parseNum(weight.text),
        purity: _purityLabel,
        ratePerGram: parseNum(rate.text),
        deductionPercent: parseNum(loss.text),
      );

  void _add() {
    final item = _preview;
    if (item.weight <= 0) {
      setState(() => error = 'Enter the weight in grams.');
      return;
    }
    if (item.ratePerGram <= 0) {
      setState(() => error = 'Enter a rate per gram.');
      return;
    }
    if (item.deductionPercent < 0 || item.deductionPercent >= 100) {
      setState(() => error = 'Melting loss must be between 0 and 99%.');
      return;
    }
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    const kb = TextInputType.numberWithOptions(decimal: true);
    final filter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final p = _preview;
    return AlertDialog(
      title: const Text('Old Gold / Silver'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Gold')),
                  ButtonSegment(value: true, label: Text('Silver')),
                ],
                selected: {silver},
                onSelectionChanged: (s) => setState(() {
                  silver = s.first;
                  _autoRate();
                }),
              ),
            ),
            const SizedBox(height: 12),
            Text(silver ? 'Touch / purity' : 'Purity', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: silver
                  ? [
                      for (final t in _touches)
                        ChoiceChip(
                          label: Text('${fmtRate(t)}%'),
                          selected: touch == t,
                          onSelected: (_) => setState(() {
                            touch = t;
                            _autoRate();
                          }),
                        ),
                    ]
                  : [
                      for (final k in _karats)
                        ChoiceChip(
                          label: Text('${k}K'),
                          selected: karat == k,
                          onSelected: (_) => setState(() {
                            karat = k;
                            _autoRate();
                          }),
                        ),
                    ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weight,
              keyboardType: kb,
              inputFormatters: filter,
              autofocus: true,
              onChanged: (_) => setState(() => error = null),
              decoration: const InputDecoration(labelText: 'Weight (grams)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: rate,
              keyboardType: kb,
              inputFormatters: filter,
              onChanged: (_) => setState(() => error = null),
              decoration: const InputDecoration(labelText: 'Rate per gram (Rs.)', helperText: 'Filled from today\'s rate. You can change it.'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: loss,
              keyboardType: kb,
              inputFormatters: filter,
              onChanged: (_) => setState(() => error = null),
              decoration: const InputDecoration(labelText: 'Melting loss / cut (%)'),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gold),
              ),
              child: Text(
                'Net ${p.netWeight.toStringAsFixed(3)} g  =  ${money(p.value)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: maroon),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Color(0xFFC62828))),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _add, child: const Text('Add')),
      ],
    );
  }
}
