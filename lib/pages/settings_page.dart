import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backup_helper.dart';
import '../constants.dart';
import '../lock.dart';
import '../store.dart';
import '../widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final prefixController = TextEditingController(text: store.prefix);
  final nextController = TextEditingController(text: store.nextNumber.toString());
  final templateController = TextEditingController(text: store.dueTemplate);

  @override
  void dispose() {
    templateController.dispose();
    prefixController.dispose();
    nextController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final prefix = prefixController.text.trim().toUpperCase();
    final next = int.tryParse(nextController.text.trim());
    if (prefix.isEmpty) {
      _message('Invoice prefix cannot be empty.');
      return;
    }
    if (next == null || next < 1) {
      _message('Next invoice number must be 1 or more.');
      return;
    }
    await store.updateSettings(newPrefix: prefix, newNext: next);
    prefixController.text = store.prefix;
    nextController.text = store.nextNumber.toString();
    _message('Saved. Next invoice will be ${store.nextInvoiceNo}.');
  }

  // ---------- backup & restore ----------

  bool backupBusy = false;

  Future<void> _exportBackup() async {
    if (backupBusy) return;
    setState(() => backupBusy = true);
    try {
      final err = await saveBackupFile();
      _message(err == null
          ? 'Backup saved: ${store.totalBills} bills, ${store.customers.length} customers, ${store.bookings.length} bookings. Keep this file safe (Drive / WhatsApp to yourself).'
          : 'Could not save backup: $err');
    } finally {
      if (mounted) setState(() => backupBusy = false);
    }
  }

  Future<void> _copyBackup() async {
    await Clipboard.setData(ClipboardData(text: store.exportJson()));
    await store.markBackedUp();
    _message('Backup copied. Paste it into a note or message to keep it.');
  }

  Future<void> _restoreFromFile() async {
    if (backupBusy) return;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      await _askModeAndImport(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      _message('Could not open the file: $e');
    }
  }

  Future<void> _restoreFromText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste backup text'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Paste the whole backup here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Continue')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    await _askModeAndImport(text);
  }

  Future<void> _askModeAndImport(String text) async {
    if (!mounted) return;
    // true = replace everything, false = merge, null = cancel
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How should the backup be restored?'),
        content: const Text(
            'MERGE keeps the bills already on this phone and adds the ones from the backup that are missing.\n\n'
            'REPLACE removes the bills on this phone first and restores exactly what is in the backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Merge')),
        ],
      ),
    );
    if (replace == null) return;
    final result = await store.importJson(text, replace: replace);
    if (!mounted) return;
    prefixController.text = store.prefix;
    nextController.text = store.nextNumber.toString();
    templateController.text = store.dueTemplate;
    if (result.error != null) {
      _message(result.error!);
      return;
    }
    final extra = [
      if (result.skipped > 0) '${result.skipped} already here',
      if (result.unreadable > 0) '${result.unreadable} unreadable',
    ].join(', ');
    _message('Restored ${result.added} bill${result.added == 1 ? '' : 's'}, '
        '${result.bookingsAdded} booking${result.bookingsAdded == 1 ? '' : 's'}, '
        '${result.customersAdded} customer${result.customersAdded == 1 ? '' : 's'}'
        '${extra.isEmpty ? '' : ' ($extra)'}.'
        '${result.draftRestored ? ' Restart the app to load your unfinished bill.' : ''}');
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all bills?'),
        content: Text('All ${store.totalBills} saved bills will be removed from this phone. '
            'The invoice counter keeps going, so numbers are not reused.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.deleteAllBills();
      _message('All bills deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            sectionTitle('Invoice Numbering', subtitle: 'Every generated bill gets the next number in order.'),
            const SizedBox(height: 12),
            TextField(
              controller: prefixController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(labelText: 'Invoice prefix (e.g. SJJ)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nextController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              decoration: const InputDecoration(labelText: 'Next invoice number'),
            ),
            const SizedBox(height: 8),
            Text('Next invoice right now: ${store.nextInvoiceNo}',
                style: const TextStyle(color: maroon, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('If a number is already used by a saved bill, the app skips to the next free one.',
                style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('SAVE SETTINGS'),
              ),
            ),
            const SizedBox(height: 26),
            sectionTitle('Security', subtitle: 'Keep your bills and customers private.'),
            const SizedBox(height: 8),
            const AppLockCard(),
            const SizedBox(height: 26),
            sectionTitle('Saved Data'),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Image.asset(goldBarAsset, width: 40, height: 40,
                    errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long, color: maroon)),
                title: Text('${store.totalBills} bills saved on this phone'),
                subtitle: Text('${store.customers.length} customers  •  ${store.bookings.length} bookings  •  Total sales ${money(store.totalSales)}'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: store.totalBills == 0 ? null : _deleteAll,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('DELETE ALL BILLS'),
              ),
            ),
            const SizedBox(height: 26),
            sectionTitle('Backup & Restore',
                subtitle: 'Export all bills, payments and dues so nothing is lost when you reinstall or update.'),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(store.backupDue ? Icons.warning_amber_rounded : Icons.cloud_done_outlined,
                    color: store.backupDue ? const Color(0xFFC62828) : maroon),
                title: Text(store.lastBackupAt == null ? 'No backup made yet' : 'Last backup ${fmtDateTime(store.lastBackupAt!)}'),
                subtitle: Text('${store.changesSinceBackup} change${store.changesSinceBackup == 1 ? '' : 's'} not backed up  •  ${money(store.totalDue)} due'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                onPressed: backupBusy ? null : _exportBackup,
                icon: const Icon(Icons.upload_file),
                label: Text(backupBusy ? 'PLEASE WAIT...' : 'EXPORT FULL BACKUP (FILE)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _copyBackup,
                icon: const Icon(Icons.copy),
                label: const Text('COPY BACKUP AS TEXT'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _restoreFromFile,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('RESTORE FROM BACKUP FILE'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _restoreFromText,
                icon: const Icon(Icons.paste),
                label: const Text('RESTORE FROM PASTED TEXT'),
              ),
            ),
            const SizedBox(height: 26),
            sectionTitle('Reminders', subtitle: 'Backup reminder and the WhatsApp message for dues.'),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: ValueKey(store.backupEveryDays),
              initialValue: store.backupEveryDays,
              decoration: const InputDecoration(labelText: 'Remind me to back up'),
              items: ({0, 1, 3, 7, 15, 30, store.backupEveryDays}.toList()..sort())
                  .map((d) => DropdownMenuItem(
                      value: d, child: Text(d == 0 ? 'Never' : (d == 1 ? 'Every day' : 'Every $d days'))))
                  .toList(),
              onChanged: (v) {
                if (v != null) store.setBackupEveryDays(v);
              },
            ),
            const SizedBox(height: 4),
            Text('You are reminded only when something changed since the last backup.',
                style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
            const SizedBox(height: 14),
            TextField(
              controller: templateController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Due reminder message (WhatsApp)',
                helperText: 'Use {name} {amount} {invoice} {date} {total} {shop} {phone} {upi}',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: maroon, foregroundColor: Colors.white),
                  onPressed: () async {
                    await store.setDueTemplate(templateController.text);
                    _message('Message saved.');
                  },
                  child: const Text('SAVE MESSAGE'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await store.setDueTemplate(defaultDueTemplate);
                    templateController.text = store.dueTemplate;
                    _message('Message reset.');
                  },
                  child: const Text('RESET'),
                ),
              ),
            ]),
            const SizedBox(height: 26),
            sectionTitle('Shop Details'),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shopName, style: TextStyle(fontWeight: FontWeight.w900, color: maroon)),
                  SizedBox(height: 4),
                  Text(shopAddress),
                  Text('Phone: $shopPhone'),
                  Text('UPI: $shopUpiId'),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
