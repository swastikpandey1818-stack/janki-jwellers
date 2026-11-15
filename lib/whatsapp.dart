import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'crm_models.dart';

/// Opens a WhatsApp chat with [phone] and the text already typed. Returns false when it could not open.
Future<bool> openWhatsApp(String phone, String text) async {
  final number = waNumber(phone);
  if (number.isEmpty) return false;
  final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens the phone dialler with the number filled in.
Future<bool> callNumber(String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: cleaned));
  } catch (_) {
    return false;
  }
}

Future<void> callWithMessage(BuildContext context, String phone) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await callNumber(phone);
  if (!ok) {
    messenger.showSnackBar(const SnackBar(content: Text('No valid mobile number to call.')));
  }
}

/// Shows the message so it can be changed, then opens WhatsApp. Returns true when WhatsApp was opened.
Future<bool> sendWhatsAppDialog(
  BuildContext context, {
  required String phone,
  required String text,
  String title = 'WhatsApp message',
}) async {
  if (waNumber(phone).isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This customer has no valid mobile number. Add it first.')),
    );
    return false;
  }
  final edited = await showDialog<String>(
    context: context,
    builder: (_) => _MessageDialog(title: title, phone: phone, text: text),
  );
  if (edited == null || edited.trim().isEmpty) return false;
  final ok = await openWhatsApp(phone, edited);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp. Is it installed on this phone?')),
    );
  }
  return ok;
}

class _MessageDialog extends StatefulWidget {
  final String title;
  final String phone;
  final String text;
  const _MessageDialog({required this.title, required this.phone, required this.text});

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  late final TextEditingController controller = TextEditingController(text: widget.text);
  bool copied = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('To: ${widget.phone.trim()}', style: const TextStyle(color: maroon, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(hintText: 'Message'),
          ),
          const SizedBox(height: 6),
          Text('You can edit the message before sending.',
              style: TextStyle(color: Colors.brown.shade400, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: controller.text));
            if (mounted) setState(() => copied = true);
          },
          child: Text(copied ? 'Copied' : 'Copy'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, controller.text),
          icon: const Icon(Icons.send, size: 18),
          label: const Text('WhatsApp'),
        ),
      ],
    );
  }
}
