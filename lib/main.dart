import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'core/wallet_engine.dart';
import 'core/wallet_repository.dart';
import 'ui/wallet_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = WidgetsBinding.instance.platformDispatcher.locale
      .toLanguageTag();
  final engine = WalletEngine(
    repository: FileWalletRepository(initialLocale: locale),
  );
  runApp(WeldingWalletApp(controller: AppController(engine: engine)));
}
