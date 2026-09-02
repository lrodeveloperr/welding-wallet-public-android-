# Welding Gas Wallet

Welding Gas Wallet is an offline-first Flutter app for recording welding-gas cylinders, suppliers, ownership, refill/exchange costs, reminders and optional native-file backup on Android and iOS.

## Product boundary

The product is **cylinders only**. It does not track welding consumables, batches/lots, material/manufacturer certificates, WPS/PQR, welder qualifications, weld maps, production planning or welding-compliance decisions.

## Monetization

- Free: one fixed non-personalized bottom banner and up to three current editable cylinders.
- Pro: no ads and unlimited cylinder records.
- Android uses the configured monthly/annual subscriptions.
- iOS uses the configured one-time lifetime unlock.
- Existing store identifiers are retained for purchase and entitlement continuity.

## Data and backup

Core records stay local and work offline. Backup is optional through the native file picker, including Google Drive or iCloud Drive where the operating system exposes them. Backups never carry entitlement state.

The data schema remains at v5 solely for forward compatibility with installs that briefly wrote the removed module. Obsolete fields are ignored by the cylinder-only model and are not written into new wallet data or exports.

## Build

```bash
flutter pub get
flutter gen-l10n
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```
