# Welding Gas Wallet — Android

Native Kotlin + Jetpack Compose Android app for Welding Gas Wallet.

- Offline-first local wallet storage.
- No account required for core use.
- First three current cylinders editable on the free tier.
- Non-current cylinders are read-only on the free tier.
- Supplier-safe event history, costs and reminders.
- Google Play subscription wiring is enabled when `PLAY_LICENSE_KEY` is supplied as a Gradle property.
- Light-first Material 3 UI inspired by the interaction density and hierarchy of `nkuppan/expensemanager`.

## Build

CI builds the debug APK with Gradle 8.13. Locally, use Android Studio or a Gradle 8.13 installation:

```bash
gradle :app:assembleDebug
```

For a Play-connected build, supply the Play RSA public key outside source control:

```bash
gradle :app:assembleRelease -PPLAY_LICENSE_KEY="..."
```

The public repository intentionally contains no Play license key or signing secret.
