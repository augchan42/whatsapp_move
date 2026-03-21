# ADR-001: Fix for Move to iOS WhatsApp Transfer Failure on Android 12+

## Status
CONFIRMED — Fix verified on two devices:
- Pixel 3 XL, Android 12 (SDK 31) — fixed via full legacy cycle (Attempt 4)
- CMF by Nothing A001 (Galaga), Android 15 (SDK 35) — fixed via fresh APK reinstall (Attempt 2)

**Minimal fix: Attempt 2 (fresh APK reinstall). appops grants alone (Attempt 1) are NOT sufficient.**

## Date
2026-03-21

## Context
Move to iOS app fails to transfer WhatsApp data on Android 12+ devices. When the WhatsApp toggle is enabled in Move to iOS, it immediately errors with:

```
E ActivityThread: Failed to find provider info for com.whatsapp.provider.migrate.ios
V whatsapp: did receive a null cursor from files.
```

### Root Cause Analysis
Three layers of protection block the transfer:

1. **Package visibility (Android 11+)**: WhatsApp only declares visibility to `com.google.android.apps.pixelmigrate` and `com.google.android.apps.restore` — not `com.apple.movetoios`. The system blocks Move to iOS from seeing WhatsApp's provider entirely.

2. **Content provider disabled by default**: `ExportMigrationContentProvider` is not in WhatsApp's `enabledComponents` list. It only appears to activate when WhatsApp itself initiates the migration flow.

3. **Signature-level permission**: `com.whatsapp.permission.MIGRATION_CONTENT_PROVIDER` is `prot=signature`, meaning only apps signed by Meta can access it directly.

### Environment
- Device: Pixel 3 XL (crosshatch)
- Android: 12 (SDK 31)
- WhatsApp: v2.26.10.72 (latest, installed via Play Store)
- Move to iOS: latest from Play Store
- iPhone: factory reset, in initial setup flow

## Decision
Reinstall WhatsApp from a fresh APK download (not Play Store) to force re-registration of all components with the Android package manager.

## Fix: Minimal Steps for Reproduction

### What you need
- USB debugging enabled on Android device
- ADB installed on computer (macOS/Windows/Linux)
- Device connected via USB

### Steps

```bash
# 1. Set your device serial (run `adb devices` to find it)
ADB="adb -s YOUR_DEVICE_SERIAL"

# 2. Grant package visibility permissions to both apps
$ADB shell appops set com.whatsapp QUERY_ALL_PACKAGES allow
$ADB shell appops set com.apple.movetoios QUERY_ALL_PACKAGES allow

# 3. Back up current WhatsApp APK on device
APK_PATH=$($ADB shell pm path com.whatsapp | head -1 | sed 's/package://')
$ADB shell cp "$APK_PATH" /data/local/tmp/WhatsAppbackup.apk

# 4. Download legacy WhatsApp (enables adb backup support)
curl -L -o /tmp/LegacyWhatsApp.apk \
  "https://web.archive.org/web/20141111030303if_/http://www.whatsapp.com/android/current/WhatsApp.apk"
# MD5 should be: 73fa47a3870d0b9ee6e29d843118e09b

# 5. Uninstall WhatsApp KEEPING data
$ADB shell pm uninstall -k com.whatsapp

# 6. Install legacy WhatsApp (this step may be optional — see hypothesis below)
$ADB install -r -d -g /tmp/LegacyWhatsApp.apk

# 7. Uninstall legacy WhatsApp KEEPING data
$ADB shell pm uninstall -k com.whatsapp

# 8. Download and install current WhatsApp from official site (NOT Play Store)
curl -L -o /tmp/WhatsApp.apk "https://www.whatsapp.com/android/current/WhatsApp.apk"
$ADB install -r -d -g /tmp/WhatsApp.apk

# 9. Force stop both apps to pick up changes
$ADB shell am force-stop com.whatsapp
$ADB shell am force-stop com.apple.movetoios

# 10. Open WhatsApp, let it load, then try Move to iOS WhatsApp toggle
$ADB shell am start com.whatsapp/.HomeActivity
```

### On the iPhone side
- iPhone must be in **initial setup flow** (factory reset)
- At "Apps & Data" screen, choose "Move Data from Android"
- On Android, open Move to iOS, enter code, toggle WhatsApp

## Hypothesis: Why This Works

**Best guess (ranked by likelihood):**

1. **Fresh APK install re-registers the ContentProvider**: Play Store updates may preserve a stale disabled state for `ExportMigrationContentProvider`. A full uninstall + fresh install forces Android's PackageManager to re-scan all components from the manifest, re-enabling the provider.

2. **appops QUERY_ALL_PACKAGES grant**: The package visibility restriction on Android 11+ may be the primary blocker. Granting `QUERY_ALL_PACKAGES` via appops allows Move to iOS to see WhatsApp's provider even without a `<queries>` declaration.

3. **Combination effect**: The appops grant makes the provider *visible* to Move to iOS, and the reinstall makes the provider *enabled*. Both are required.

## Minimal Experiment for Second Phone

To determine the actual minimal fix, try these in order on the second phone. Stop as soon as Move to iOS works:

### Attempt 1: appops only (30 seconds)
```bash
adb shell appops set com.whatsapp QUERY_ALL_PACKAGES allow
adb shell appops set com.apple.movetoios QUERY_ALL_PACKAGES allow
adb shell am force-stop com.whatsapp
adb shell am force-stop com.apple.movetoios
```
→ Try Move to iOS. If it works, the fix is just appops.

### Attempt 2: Reinstall from fresh APK only (2 minutes)
```bash
APK_PATH=$(adb shell pm path com.whatsapp | head -1 | sed 's/package://')
adb shell cp "$APK_PATH" /data/local/tmp/WhatsAppbackup.apk
adb shell pm uninstall -k com.whatsapp
curl -L -o /tmp/WhatsApp.apk "https://www.whatsapp.com/android/current/WhatsApp.apk"
adb install -r -d -g /tmp/WhatsApp.apk
```
→ Try Move to iOS. If it works, the fix is the fresh install.

### Attempt 3: Both together (2 minutes)
```bash
# appops + reinstall (full steps 1-10 above)
```
→ This is what worked on the Pixel 3 XL.

### Attempt 4: Legacy downgrade cycle (5 minutes)
```bash
# Full steps 1-10 including legacy WhatsApp install/uninstall
```
→ This is the nuclear option that definitely works.

## Consequences

### Positive
- WhatsApp data is preserved throughout (`-k` flag keeps app data)
- No root required
- No factory reset of Android device needed
- Transfer includes media files (unlike manual DB migration)

### Negative
- Requires USB debugging and ADB (technical users only)
- WhatsApp session may need re-verification after reinstall
- Legacy APK from Wayback Machine could become unavailable
- Fix may not survive WhatsApp auto-updates from Play Store

### Risks
- If `pm uninstall -k` fails or data is lost, WhatsApp backup to Google Drive should be done first
- Legacy WhatsApp v2.11.431 is from 2014 — do not leave it installed

## References
- WhatsApp provider: `com.whatsapp/.migration.export.api.ExportMigrationContentProvider`
- Provider authority: `com.whatsapp.provider.migrate.ios`
- Permission: `com.whatsapp.permission.MIGRATION_CONTENT_PROVIDER` (prot=signature)
- Legacy APK: `https://web.archive.org/web/20141111030303if_/http://www.whatsapp.com/android/current/WhatsApp.apk`
- Legacy APK MD5: `73fa47a3870d0b9ee6e29d843118e09b`
- Android package visibility docs: https://developer.android.com/training/package-visibility
