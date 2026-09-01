# Welding Wallet name consistency checklist

Checked as part of the Gas + Consumables upgrade.

- [x] Visible product name: **Welding Wallet**
- [x] Flutter `MaterialApp` title
- [x] Android launcher label
- [x] iOS `CFBundleDisplayName` and `CFBundleName`
- [x] Dart package name and test imports
- [x] README and user-facing documentation
- [x] Backup format/error wording
- [x] GitHub Actions artifact names
- [x] Onboarding, Pro/paywall and settings copy
- [x] Cylinder and consumable screens use the new umbrella brand
- [x] Tests compile against the renamed Dart package
- [x] Legacy application IDs are intentionally preserved for upgrade continuity
- [x] Existing store product IDs are intentionally preserved for entitlement continuity
- [x] Existing legal-policy URL slug is intentionally preserved until the hosted policy route is migrated

## Intentional legacy identifiers

Do **not** rename these solely for branding:

- Android application ID / namespace: `com.goodusestudios.weldinggaswallet`
- Existing iOS bundle identifier values in project configuration: `com.goodusestudios.weldinggaswallet`
- Existing store product IDs: `com.gooduse.weldinggaswallet.pro.monthly` and `com.gooduse.weldinggaswallet.pro.annual`
- Hosted policy URL path: `/privacy-policy/welding-gas-wallet/`

Changing an application/bundle identifier would create a different installed/store app and break in-place upgrades. Renaming existing subscription identifiers would disconnect configured store products and entitlement history. The policy URL remains on the legacy slug so existing published links do not 404.
