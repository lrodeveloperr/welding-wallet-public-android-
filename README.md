# Welding Gas Wallet

Welding Gas Wallet is an offline-first Flutter app for recording welding-gas cylinders, suppliers, ownership, refill and exchange costs, and due-date reminders on Android and iOS.

The former Jetpack Compose presentation layer has been removed. The active app is now Flutter, while the original Kotlin backend remains in `backend/` as a parity reference for its security-sensitive Android billing and storage tests. Shared production behavior lives in `lib/core/` and is used by both mobile platforms.

## Flutter interface

The selected skin adapts the MIT-licensed [Inventorya](https://github.com/mina-android/Inventorya) dashboard language to Welding Gas Wallet:

- dashboard title and strong uppercase section labels;
- quick-action cards for add, refill, exchange and reminder;
- summary-and-count cards for current cylinders, due dates and spend;
- clear inventory rows and persistent bottom navigation;
- responsive two-column mobile layout and four-column wide layout;
- Material icons, high-contrast light surfaces and no copied brand assets.

## Preserved rules

- Three current cylinders are editable on the free plan. A fourth draft is stored and can resume once after a store-verified Pro purchase.
- Downgrades retain every record; non-selected and non-current cylinders become read-only.
- Suppliers referenced by cylinders, events or pending drafts cannot be deleted.
- Costs remain separated by ISO currency instead of being combined incorrectly.
- Private storage uses atomic current/previous files with corruption quarantine and recovery.
- Exported backups omit entitlement state and device-local photo paths and are capped at 5 MB.
- Reminder deletion cancels the scheduled system notification before removing the wallet record.
- Store access fails closed and uses only the locked monthly and annual product identifiers.

## Build

Requirements: Flutter 3.47.2, Dart 3.12 or newer, Android SDK 26+, and Xcode 15+ for iOS.

```bash
flutter pub get
flutter gen-l10n
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

The GitHub Actions workflow runs formatting, analysis, domain/widget tests, a dashboard golden render, and the Android debug build. It publishes the APK, build log, and rendered design evidence as workflow artifacts.

## Store configuration

Configure these subscription products in Google Play and App Store Connect before release:

- `com.gooduse.weldinggaswallet.pro.monthly`
- `com.gooduse.weldinggaswallet.pro.annual`

Production delivery should connect the store verification evidence to your server or the preserved Android verifier before granting long-lived access. The shell only caches store-confirmed access for 24 hours and never grants Pro from private wallet data or backups.

## Privacy and support

- [Privacy policy](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/privacy/)
- [Terms](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/terms/)
- [Safety disclaimer](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/disclaimer/)
- [Support](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/support/)
- [Data deletion](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/deletion/)
