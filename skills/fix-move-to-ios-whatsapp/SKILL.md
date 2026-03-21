---
name: fix-move-to-ios-whatsapp
description: Use when user mentions Move to iOS WhatsApp transfer failing, "Failed to find provider" errors, WhatsApp toggle not working in Move to iOS, or Android to iPhone WhatsApp migration issues. Diagnoses and fixes the ContentProvider visibility bug on Android 11+ by reinstalling WhatsApp from a fresh APK.
user-invocable: true
argument-hint: [device_serial] (optional - auto-detects if one device connected)
allowed-tools: Bash, Read, WebSearch, WebFetch
---

# Fix Move to iOS WhatsApp Transfer

Diagnoses and fixes the WhatsApp transfer failure in Apple's Move to iOS app on Android 11+ devices.

## When to Use

- Move to iOS fails when toggling the WhatsApp switch
- User sees "Failed to find provider info for com.whatsapp.provider.migrate.ios" in logs
- WhatsApp data doesn't transfer during Android to iPhone migration
- User is migrating from Android to iPhone and WhatsApp won't come across

## Background

On Android 11+, WhatsApp's migration ContentProvider (`com.whatsapp.provider.migrate.ios`) can become disabled due to stale component state from Play Store updates. Move to iOS cannot see or access the provider, causing the transfer to fail silently.

The fix is to reinstall WhatsApp from a fresh APK download (not Play Store), which forces Android's PackageManager to re-register all components from scratch.

Confirmed working on:
- Pixel 3 XL, Android 12 (SDK 31)
- CMF by Nothing A001, Android 15 (SDK 35)

## Workflow

### Step 1: Locate ADB and verify device connection

```bash
# Try common ADB locations
which adb || ls ~/Library/Android/sdk/platform-tools/adb || ls /usr/local/bin/adb
```

```bash
# List connected devices
adb devices -l
```

If no device found, instruct the user to:
1. Enable Developer Options (Settings > About phone > tap Build number 7 times)
2. Enable USB debugging (Settings > System > Developer options > USB debugging)
3. Connect via USB and tap "Allow" on the debugging prompt

If multiple devices, ask user which serial to target, or use the argument passed to the skill.

### Step 2: Gather device info and verify WhatsApp is installed

```bash
ADB_DEVICE="adb -s <serial>"
$ADB_DEVICE shell getprop ro.product.model
$ADB_DEVICE shell getprop ro.build.version.release
$ADB_DEVICE shell getprop ro.build.version.sdk
$ADB_DEVICE shell dumpsys package com.whatsapp | grep -E "versionName|versionCode"
$ADB_DEVICE shell pm list packages | grep movetoios
```

If WhatsApp is not installed, stop — nothing to fix.
If Move to iOS is not installed, tell user to install it from Play Store first.

### Step 3: Diagnose the issue (optional — for logging)

Only if user wants to see the error:

```bash
# Clear logcat and capture
$ADB_DEVICE logcat --pid=$($ADB_DEVICE shell pidof com.apple.movetoios) -c
$ADB_DEVICE logcat --pid=$($ADB_DEVICE shell pidof com.apple.movetoios)
```

Look for:
```
E ActivityThread: Failed to find provider info for com.whatsapp.provider.migrate.ios
V whatsapp: did receive a null cursor from files.
```

### Step 4: Apply the fix

**IMPORTANT: Always back up the current APK first as a safety measure.**

```bash
# 1. Back up current WhatsApp APK on device
APK_PATH=$($ADB_DEVICE shell pm path com.whatsapp | head -1 | sed 's/package://')
$ADB_DEVICE shell cp "$APK_PATH" /data/local/tmp/WhatsAppbackup.apk

# 2. Uninstall WhatsApp KEEPING all data
$ADB_DEVICE shell pm uninstall -k com.whatsapp

# 3. Download fresh WhatsApp APK
curl -L -o /tmp/WhatsApp-fresh.apk "https://www.whatsapp.com/android/current/WhatsApp.apk"

# 4. Verify it's a real APK (should be >50MB)
ls -la /tmp/WhatsApp-fresh.apk
file /tmp/WhatsApp-fresh.apk  # Should say "Zip archive"

# 5. Install fresh APK
$ADB_DEVICE install -r -d -g /tmp/WhatsApp-fresh.apk
```

If step 5 fails, restore from backup:
```bash
$ADB_DEVICE shell pm install /data/local/tmp/WhatsAppbackup.apk
```

### Step 5: Verify and instruct user

Tell the user:
1. Open WhatsApp on the Android phone — make sure it loads normally
2. On the iPhone, ensure it's in the initial setup flow (factory reset if needed)
3. At "Apps & Data", choose "Move Data from Android"
4. On Android, open Move to iOS, enter the code, toggle WhatsApp

### Step 6: If it still fails — escalate

Try granting package visibility:
```bash
$ADB_DEVICE shell appops set com.whatsapp QUERY_ALL_PACKAGES allow
$ADB_DEVICE shell appops set com.apple.movetoios QUERY_ALL_PACKAGES allow
$ADB_DEVICE shell am force-stop com.whatsapp
$ADB_DEVICE shell am force-stop com.apple.movetoios
```

If that still fails, the nuclear option is the legacy WhatsApp downgrade cycle:
```bash
# Uninstall current WhatsApp (data kept)
$ADB_DEVICE shell pm uninstall -k com.whatsapp

# Install legacy WhatsApp v2.11.431 from Wayback Machine
curl -L -o /tmp/LegacyWhatsApp.apk "https://web.archive.org/web/20141111030303if_/http://www.whatsapp.com/android/current/WhatsApp.apk"
$ADB_DEVICE install -r -d -g /tmp/LegacyWhatsApp.apk

# Uninstall legacy (data kept)
$ADB_DEVICE shell pm uninstall -k com.whatsapp

# Install fresh current WhatsApp
$ADB_DEVICE install -r -d -g /tmp/WhatsApp-fresh.apk
```

## Quick Reference

| Command | Purpose |
|---------|---------|
| `adb devices -l` | List connected devices |
| `adb shell pm uninstall -k com.whatsapp` | Uninstall keeping data |
| `adb install -r -d -g <apk>` | Install allowing downgrade |
| `adb shell appops set <pkg> QUERY_ALL_PACKAGES allow` | Grant package visibility |
| `adb logcat --pid=<pid>` | Stream app logs |

## Common Mistakes

- **Do NOT use `pm uninstall` without `-k`** — that deletes all WhatsApp data
- **Do NOT install from Play Store** — that preserves the stale component state
- **iPhone must be in initial setup flow** — Move to iOS only works during first-time setup, not after the phone is already set up
- **WhatsApp must be open/loaded** on Android before toggling the switch in Move to iOS

## Source

Full technical investigation: https://github.com/digital-rain-tech/whatsapp_move
