import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/models.dart';
import '../core/wallet_engine.dart';

class BackupService {
  Future<bool> save(String encoded) async {
    final now = DateTime.now().toUtc();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: 'welding-wallet-$stamp.json',
      bytes: Uint8List.fromList(utf8.encode(encoded)),
    );
    return uri != null;
  }

  Future<String?> pick() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (picked == null) return null;
    final length = await picked.length();
    if (length > maximumBackupBytes) {
      throw const WalletRuleException('The backup is larger than 5 MB.');
    }
    try {
      return utf8.decode(await picked.readAsBytes());
    } on FormatException {
      throw const WalletRuleException('This is not a Welding Wallet backup.');
    }
  }
}

