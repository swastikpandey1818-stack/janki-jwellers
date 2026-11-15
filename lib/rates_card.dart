import 'package:flutter/material.dart';

import 'constants.dart';
import 'models.dart';
import 'rate_service.dart';
import 'store.dart';

/// Dashboard card to set today's gold and silver rate: type it yourself, or fetch it online.
class RatesCard extends StatefulWidget {
  const RatesCard({super.key});

  @override
  State<RatesCard> createState() => _RatesCardState();
}

class _RatesCardState extends State<RatesCard> {
  final goldController = TextEditingController();
  final silverController = TextEditingController();
  final adjustController = TextEditingController();

  late RateSource mode = store.rateSource;
  int seenVersion = -1;
  bool fetching = false;
  String? error;

  static const _red = Color(0xFFC62828);
  static const _green = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _syncControllers();
    store.addListener(_onStore);
  }

  void _syncControllers() {
    goldController.text = fmtRate(store.goldRate);
    silverController.text = fmtRate(store.silverRate);
    adjustController.text = fmtRate(store.onlineAdjustPercent);
    seenVersion = store.ratesVersion;
  }

  void _onStore() {
    if (!mounted) return;
    if (seenVersion != store.ratesVersion) {
      setState(_syncControllers);
    }
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    goldController.dispose();
    silverController.dispose();
    adjustController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveManual() async {
    final gold = parseNum(goldController.text);
    final silver = parseNum(silverController.text);
    if (gold <= 0) {
      _message('Enter the 24K gold rate per 10 grams.');
      return;
    }
    if (silver < 0) {
      _message('Silver rate cannot be negative.');
      return;
    }
    await store.setManualRates(gold, silver);
    setState(() => error = null);
    _message('Rates saved. New bills will use them.');
  }

  Future<void> _fetch() async {
    if (fetching) return;
    final adjust = parseNum(adjustController.text);
    if (adjustController.text.trim().isNotEmpty && (adjust < -50 || adjust > 50)) {
      _message('Adjustment should be between -50 and 50 percent.');
      return;
    }
    setState(() {
      fetching = true;
      error = null;
    });
    try {
      await store.setOnlineAdjust(adjust);
      await store.fetchOnlineRates();
      if (mounted) _message('Online rates updated.');
    } on RateException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not fetch the rates right now.');
    } finally {
      if (mounted) setState(() => fetching = false);
    }
  }

  void _pickMode(RateSource source) {
    if (source == mode) return;
    setState(() {
      mode = source;
      error = null;
    });
    if (source == RateSource.online) _fetch();
  }

  Widget _rateTile(String label, String value, String unit) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E9), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.brown.shade500)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: maroon)),
            ),
            Text(unit, style: TextStyle(fontSize: 11.5, color: Colors.brown.shade400)),
          ]),
        ),
      );

  String get _statusText {
    final t = store.ratesUpdatedAt;
    final when = t == null ? '' : '  •  ${fmtDateTime(t)}';
    return store.rateSource == RateSource.online
        ? 'Rates in use: fetched online$when'
        : 'Rates in use: set by you$when';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final gold22 = store.goldRate * 22 / 24;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.trending_up, color: maroon),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text("Today's Gold & Silver Rate",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: maroon)),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RateSource>(
                  segments: const [
                    ButtonSegment(value: RateSource.manual, label: Text('Set myself'), icon: Icon(Icons.edit_outlined)),
                    ButtonSegment(value: RateSource.online, label: Text('Fetch online'), icon: Icon(Icons.cloud_download_outlined)),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (set) => _pickMode(set.first),
                ),
              ),
              const SizedBox(height: 12),
              if (mode == RateSource.manual) ...[
                TextField(
                  controller: goldController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '24K Gold rate per 10 grams (Rs.)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: silverController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Silver rate per gram (Rs.)'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                    onPressed: _saveManual,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('SAVE RATES'),
                  ),
                ),
              ] else ...[
                Row(children: [
                  _rateTile('24K Gold', store.rateSource == RateSource.online ? money(store.goldRate) : '--',
                      'per 10 grams'),
                  const SizedBox(width: 10),
                  _rateTile('Silver', store.rateSource == RateSource.online ? money(store.silverRate) : '--',
                      'per gram'),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: adjustController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Adjustment on online rate (%)',
                    helperText: 'Add % to match your local market, e.g. 6 for import duty. 0 = no change.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                    onPressed: fetching ? null : _fetch,
                    icon: fetching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh),
                    label: Text(fetching ? 'FETCHING...' : 'FETCH LIVE RATES'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Online rate = international gold / silver price converted to rupees. '
                  'It is a guide: check it against your local market, or use the adjustment above.',
                  style: TextStyle(color: Colors.brown.shade400, fontSize: 11.5),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline, color: _red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(error!, style: const TextStyle(color: _red, fontSize: 12.5))),
                  ]),
                ],
              ],
              const Divider(height: 22),
              Row(children: [
                Icon(store.rateSource == RateSource.online ? Icons.cloud_done_outlined : Icons.edit_note,
                    size: 18, color: _green),
                const SizedBox(width: 6),
                Expanded(child: Text(_statusText, style: const TextStyle(fontSize: 12.5, color: _green))),
              ]),
              const SizedBox(height: 4),
              Text(
                '22K gold ≈ ${money(gold22)} per 10 grams  •  Used for all new invoices and bookings.',
                style: TextStyle(color: Colors.brown.shade400, fontSize: 11.5),
              ),
            ]),
          ),
        );
      },
    );
  }
}
