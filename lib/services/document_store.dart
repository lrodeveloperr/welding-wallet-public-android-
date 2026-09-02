import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

const int maximumCertificateBytes = 15 * 1024 * 1024;

class StoredDocument {
  const StoredDocument({required this.path, required this.originalName});

  final String path;
  final String originalName;
}

class DocumentStore {
  Future<StoredDocument?> pickAndStoreCertificate(String itemId) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
    );
    if (picked == null) return null;
    if (await picked.length() > maximumCertificateBytes) {
      throw StateError('Certificate files must be 15 MB or smaller.');
    }
    final bytes = await picked.readAsBytes();

    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}wallet${Platform.pathSeparator}documents',
    );
    if (!await directory.exists()) await directory.create(recursive: true);

    final extensionIndex = picked.name.lastIndexOf('.');
    final extension = extensionIndex == -1
        ? ''
        : picked.name.substring(extensionIndex).toLowerCase();
    final safeId = itemId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${safeId}_${DateTime.now().toUtc().millisecondsSinceEpoch}$extension',
    );
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return StoredDocument(path: destination.path, originalName: picked.name);
  }

  Future<void> open(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> delete(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteAll() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}wallet${Platform.pathSeparator}documents',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
