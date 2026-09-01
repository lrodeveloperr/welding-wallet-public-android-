import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

class WalletStorageException implements Exception {
  const WalletStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class WalletRepository {
  Future<WalletData> read();
  Future<WalletData> transact(WalletData Function(WalletData current) update);
  Future<void> replace(WalletData data);
  Future<void> purge();
}

class FileWalletRepository implements WalletRepository {
  FileWalletRepository({this.initialLocale = 'en', Directory? directory})
    : _directoryOverride = directory;

  final String initialLocale;
  final Directory? _directoryOverride;
  Future<void> _writeQueue = Future<void>.value();

  Future<Directory> get _directory async {
    final root = _directoryOverride ?? await getApplicationSupportDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}wallet');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String name) async =>
      File('${(await _directory).path}${Platform.pathSeparator}$name');

  @override
  Future<WalletData> read() async {
    final current = await _file('wallet.json');
    final previous = await _file('wallet.previous.json');
    final recovered = await _decode(current);
    if (recovered != null) return recovered;
    final fallback = await _decode(previous);
    if (fallback != null) {
      await _atomicWrite(fallback);
      return fallback;
    }
    if (await current.exists()) await _quarantine(current);
    return WalletData.empty(locale: initialLocale);
  }

  Future<WalletData?> _decode(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final data = WalletData.fromJson(Map<String, Object?>.from(json));
      if (data.schemaVersion > walletSchemaVersion) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _quarantine(File file) async {
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    try {
      await file.rename('${file.path}.corrupt.$stamp');
    } catch (_) {
      // Recovery still proceeds with an empty wallet if quarantine is unavailable.
    }
  }

  @override
  Future<WalletData> transact(
    WalletData Function(WalletData current) update,
  ) async {
    final completer = Completer<WalletData>();
    _writeQueue = _writeQueue.catchError((Object _) {}).then((_) async {
      try {
        final current = await read();
        final next = update(current);
        await _atomicWrite(next);
        completer.complete(next);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<void> replace(WalletData data) async {
    await transact((_) => data);
  }

  Future<void> _atomicWrite(WalletData data) async {
    final current = await _file('wallet.json');
    final previous = await _file('wallet.previous.json');
    final temporary = await _file('wallet.tmp.json');
    try {
      await temporary.writeAsString(jsonEncode(data.toJson()), flush: true);
      if (await current.exists()) {
        await current.copy(previous.path);
      }
      if (await current.exists()) await current.delete();
      await temporary.rename(current.path);
    } catch (error) {
      throw WalletStorageException('Could not safely save wallet data.', error);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> purge() async {
    final directory = await _directory;
    if (!await directory.exists()) return;
    for (final entity in directory.listSync()) {
      if (entity is File && entity.path.contains('wallet')) {
        await entity.delete();
      }
    }
  }
}

class MemoryWalletRepository implements WalletRepository {
  MemoryWalletRepository([WalletData? initial])
    : _data = initial ?? WalletData.empty();

  WalletData _data;

  @override
  Future<WalletData> read() async => _data;

  @override
  Future<WalletData> transact(
    WalletData Function(WalletData current) update,
  ) async {
    _data = update(_data);
    return _data;
  }

  @override
  Future<void> replace(WalletData data) async => _data = data;

  @override
  Future<void> purge() async => _data = WalletData.empty();
}
