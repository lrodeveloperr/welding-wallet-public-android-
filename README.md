# Welding Gas Wallet

Welding Gas Wallet is an offline-first Flutter app for recording welding-gas cylinders, suppliers, ownership, refill/exchange costs, reminders and optional native-file backup on Android and iOS. Current cylinders use one-tap Ready, Low, Empty and Away status; refill or exchange resets status to Ready.

## Product boundary

The product is **cylinders only**. It does not scan cylinders or request camera access. It does not track welding consumables, batches/lots, material/manufacturer certificates, WPS/PQR, welder qualifications, weld maps, production planning or welding-compliance decisions.

Cylinder names are optional and generated from gas and capacity when omitted. Capacity supports ft³, L, m³, kg and lb, with ft³ defaulting in US/Canadian regions and L elsewhere.

The current customer-facing interface and store listing are English-only.

## Monetization

- Free: up to three current editable cylinders.
- Pro: unlimited cylinder records.
- Android uses the configured monthly/annual subscriptions.
- iOS uses the configured one-time lifetime unlock.
- Existing store identifiers are retained for purchase and entitlement continuity.

## Data and backup

Core records stay local and work offline. Backup is optional through the native file picker, including Google Drive or iCloud Drive where the operating system exposes them. Backups never carry entitlement state.

The Flutter wallet schema is v6. Existing v5 records migrate with status set to Ready; obsolete consumable fields remain ignored and are not written into new wallet data or exports. The backend codec writes schema v4 and accepts v3 backups, defaulting missing status to Ready.

## Build

```bash
flutter pub get
flutter gen-l10n
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```
