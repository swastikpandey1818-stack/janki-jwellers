import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import 'store.dart';

/// Saves a full backup file (bills, payments, customers, bookings, rates, settings).
/// Returns an error message, or null when the backup was saved.
Future<String?> saveBackupFile() async {
  try {
    final bytes = Uint8List.fromList(utf8.encode(store.exportJson()));
    await FileSaver.instance.saveFile(
      name: store.exportFileName(),
      bytes: bytes,
      fileExtension: 'json',
      mimeType: MimeType.json,
    );
    await store.markBackedUp();
    return null;
  } catch (e) {
    return '$e';
  }
}
