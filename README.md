# Fix: Move to iOS WhatsApp Transfer Failure

A one-command fix for the WhatsApp transfer failure when using Apple's **Move to iOS** app on Android 11+ devices.

## The Problem

When migrating from Android to iPhone, Move to iOS fails to transfer WhatsApp data. Toggling the WhatsApp switch immediately errors out with no useful message to the user.

Under the hood, the error is:
```
E ActivityThread: Failed to find provider info for com.whatsapp.provider.migrate.ios
```

This affects Android 11+ devices where package visibility restrictions prevent Move to iOS from accessing WhatsApp's migration ContentProvider. The provider exists but is left in a disabled state by Play Store installations.

## The Fix

```bash
./fix.sh
```

That's it. The script:
1. Downloads the latest WhatsApp APK from whatsapp.com
2. Uninstalls WhatsApp while **keeping all your data** (`-k` flag)
3. Reinstalls from the fresh APK

This forces Android's PackageManager to re-register all components from scratch, enabling the migration provider that Move to iOS needs.

## Requirements

- **Android device** with USB debugging enabled ([how to enable](https://developer.android.com/studio/debug/dev-options#enable))
- **ADB** installed on your computer ([download](https://developer.android.com/tools/releases/platform-tools))
- **USB cable** connecting phone to computer
- **iPhone** in initial setup flow with Move to iOS ready

## Quick Start

```bash
git clone https://github.com/digital-rain-tech/whatsapp-move-to-ios-fix.git
cd whatsapp-move-to-ios-fix
./fix.sh
```

If you have multiple Android devices connected:
```bash
# List devices
adb devices -l

# Target a specific device
./fix.sh <device_serial>
```

## Tested Devices

| Device | Android | WhatsApp | Result |
|--------|---------|----------|--------|
| Pixel 3 XL | 12 (SDK 31) | v2.26.10.72 | Fixed |
| CMF by Nothing A001 | 15 (SDK 35) | v2.26.10.72 | Fixed |

If this works (or doesn't work) on your device, please [open an issue](../../issues) with your device model, Android version, and WhatsApp version so we can expand this table.

## Why Does This Happen?

WhatsApp exposes a ContentProvider (`com.whatsapp.provider.migrate.ios`) that Move to iOS queries to initiate the data transfer. On Android 11+, two things go wrong:

1. **Package visibility**: Android 11 introduced restrictions where apps can't see each other's components unless explicitly declared. WhatsApp only declares visibility to Google's migration tools, not Apple's.

2. **Stale component state**: Play Store updates preserve the enabled/disabled state of app components. The migration provider appears to be disabled by default and only activated during specific flows. Over time (or across updates), this state becomes stale — the provider stays disabled even though it should be available.

A fresh install from a direct APK download (bypassing Play Store) forces the PackageManager to re-read the manifest and register all components as the developer intended.

See [docs/ADR-001](docs/ADR-001-move-to-ios-whatsapp-fix.md) for the full technical investigation, including ADB logs, provider analysis, and the debugging journey.

## What If It Still Doesn't Work?

If `fix.sh` alone doesn't solve it, try granting package visibility explicitly:

```bash
adb shell appops set com.whatsapp QUERY_ALL_PACKAGES allow
adb shell appops set com.apple.movetoios QUERY_ALL_PACKAGES allow
```

Then rerun `./fix.sh`.

## Safety

- Your WhatsApp **messages, media, and settings are preserved** throughout. The `-k` flag keeps all app data during uninstall.
- If the fresh install fails for any reason, the script automatically restores WhatsApp from a backup copy.
- As an extra precaution, back up your WhatsApp chats to Google Drive before running the fix (WhatsApp > Settings > Chats > Chat backup).

## Background

This fix was born from a weekend of trying to migrate 3 Android phones to iPhones. Every single one failed on the WhatsApp transfer step. After hours of ADB debugging, logcat analysis, and exploring open-source migration tools, we discovered that a simple reinstall from a fresh APK resolves the issue.

The full debugging journey — including attempts at forcing package visibility, enabling the provider via ADB, building a manual database migration pipeline, and extracting encryption keys via a legacy WhatsApp downgrade — is documented in the [ADR](docs/ADR-001-move-to-ios-whatsapp-fix.md).

## License

[MIT](LICENSE) - Digital Rain Technology Limited
