# Welding Wallet

Welding Wallet is an offline-first Flutter app for welding gas cylinders and welding consumable batch/lot traceability on Android and iOS. It keeps cylinder ownership, supplier, refill/exchange costs and reminders together with consumable product/classification, batch/lot, manufacturer certificates, issue/use history and local QR/barcode lookup.

The former Jetpack Compose presentation layer has been removed. The active app is Flutter, while the original Kotlin backend remains in `backend/` as a parity reference for its security-sensitive Android billing and storage tests. Shared production behavior lives in `lib/core/` and is used by both mobile platforms.

## Flutter interface

The selected skin adapts the MIT-licensed [Inventorya](https://github.com/mina-android/Inventorya) dashboard language to Welding Wallet:

- dashboard title and strong uppercase section labels;
- quick actions for Scan, Add Cylinder, Add Consumable and Reminder;
- operational summaries for gas cylinders, consumable batches and missing certificates;
- dedicated Gas and Consumables workflows plus combined History and Settings;
- a universal scanner that resolves saved cylinder serials and consumable barcode/QR codes;
- responsive mobile layout, Material icons, high-contrast light surfaces and no copied brand assets.

## Preserved rules

- Three current cylinders are editable on the free plan. A fourth cylinder draft is stored and can resume once after a store-verified Pro purchase.
- Three active consumable batches are editable on the free plan. A fourth consumable draft uses the same Pro entitlement and resumes once after verification.
- Downgrades retain every saved cylinder and consumable record; gated items are not silently deleted.
- Suppliers referenced by cylinders, consumables, events or pending drafts cannot be deleted.
- Consumable barcode/QR codes cannot collide with another consumable batch or a cylinder serial.
- Certificates are user-supplied local documents. Welding Wallet records attachment/history only and does not authenticate, certify or determine welding compliance.
- Costs remain separated by ISO currency instead of being combined incorrectly.
- Private storage uses atomic current/previous files with corruption quarantine and recovery.
- Exported backups omit entitlement state and device-local photo/certificate paths and are capped at 5 MB.
- Reminder deletion cancels the scheduled system notification before removing the wallet record.
- Store access fails closed and uses only the locked monthly and annual product identifiers.

## Product boundary

Welding Wallet is deliberately not a welding ERP or engineering/compliance system. It does not manage WPS/PQR, welder qualifications, weld maps, production planning, weld-quality decisions, consumable suitability or regulatory approval. Its scope is gas, consumables, certificates, reminders and history.

## Build

Requirements: Flutter 3.47.2, Dart 3.13 or newer, Android SDK 26+, and Xcode 15+ for iOS.

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

The product identifiers intentionally retain the legacy `weldinggaswallet` token so existing store products and upgrade continuity are not broken by the visible rename to Welding Wallet. Production delivery should connect the store verification evidence to your server or the preserved Android verifier before granting long-lived access. The shell only caches store-confirmed access for 24 hours and never grants Pro from private wallet data or backups.

## Privacy and support

The hosted policy route intentionally keeps its legacy slug until that route is migrated without breaking published links:

- [Privacy policy](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/privacy/)
- [Terms](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/terms/)
- [Safety disclaimer](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/disclaimer/)
- [Support](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/support/)
- [Data deletion](https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/deletion/)
