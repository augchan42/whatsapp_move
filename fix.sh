#!/bin/bash
#
# Fix: Move to iOS WhatsApp transfer failure on Android 11+
#
# The Problem:
#   Move to iOS fails with "Failed to find provider info for com.whatsapp.provider.migrate.ios"
#   because Play Store installs leave the migration ContentProvider disabled.
#
# The Fix:
#   Reinstall WhatsApp from a fresh APK (not Play Store). This forces Android's
#   PackageManager to re-register all components, including the migration provider.
#
# Requirements:
#   - USB debugging enabled on Android device
#   - ADB installed on computer
#   - Device connected via USB
#
# Usage:
#   ./fix.sh                    # auto-detect device
#   ./fix.sh <device_serial>    # target specific device
#
# See docs/ADR-001-move-to-ios-whatsapp-fix.md for full details.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓] $1${NC}"; }
warn()  { echo -e "${YELLOW}[!] $1${NC}"; }
error() { echo -e "${RED}[✗] $1${NC}"; exit 1; }

# Find ADB
ADB=$(which adb 2>/dev/null) || ADB="$HOME/Library/Android/sdk/platform-tools/adb"
[ -x "$ADB" ] || error "ADB not found. Install Android Platform Tools."

# Device selection
if [ -n "${1:-}" ]; then
    SERIAL="-s $1"
else
    DEVICE_COUNT=$($ADB devices | grep -c "device$" || true)
    if [ "$DEVICE_COUNT" -eq 0 ]; then
        error "No device connected. Enable USB debugging and connect via USB."
    elif [ "$DEVICE_COUNT" -gt 1 ]; then
        echo "Multiple devices detected:"
        $ADB devices -l | grep "device " | grep -v "emulator"
        error "Specify device serial: ./fix.sh <serial>"
    fi
    SERIAL=""
fi

# Verify WhatsApp is installed
$ADB $SERIAL shell pm path com.whatsapp >/dev/null 2>&1 || error "WhatsApp is not installed on this device."

# Verify Move to iOS is installed
$ADB $SERIAL shell pm path com.apple.movetoios >/dev/null 2>&1 || error "Move to iOS is not installed on this device."

# Get device info
MODEL=$($ADB $SERIAL shell getprop ro.product.model)
ANDROID=$($ADB $SERIAL shell getprop ro.build.version.release)
WA_VERSION=$($ADB $SERIAL shell dumpsys package com.whatsapp | grep versionName | head -1 | sed 's/.*=//')
echo ""
echo "Device:   $MODEL"
echo "Android:  $ANDROID"
echo "WhatsApp: $WA_VERSION"
echo ""

# Download fresh WhatsApp APK
APK_PATH="/tmp/WhatsApp-fresh.apk"
if [ ! -f "$APK_PATH" ] || [ $(find "$APK_PATH" -mmin +60 2>/dev/null | wc -l) -gt 0 ]; then
    log "Downloading latest WhatsApp APK from whatsapp.com..."
    curl -L -o "$APK_PATH" "https://www.whatsapp.com/android/current/WhatsApp.apk" || error "Failed to download WhatsApp APK"
    # Verify it's actually an APK
    file "$APK_PATH" | grep -q "Zip archive" || error "Downloaded file is not a valid APK"
    log "Downloaded $(du -h "$APK_PATH" | cut -f1) APK"
else
    log "Using cached WhatsApp APK (less than 1 hour old)"
fi

# Step 1: Back up current APK on device
log "Backing up current WhatsApp APK on device..."
CURRENT_APK=$($ADB $SERIAL shell pm path com.whatsapp | head -1 | sed 's/package://')
$ADB $SERIAL shell cp "$CURRENT_APK" /data/local/tmp/WhatsAppbackup.apk
log "APK backed up to /data/local/tmp/WhatsAppbackup.apk"

# Step 2: Uninstall keeping data
warn "Uninstalling WhatsApp (keeping all data)..."
$ADB $SERIAL shell pm uninstall -k com.whatsapp || error "Failed to uninstall WhatsApp"
log "WhatsApp uninstalled (data preserved)"

# Step 3: Install fresh APK
log "Installing fresh WhatsApp APK..."
$ADB $SERIAL install -r -d -g "$APK_PATH" || {
    warn "Fresh install failed. Restoring backup APK..."
    $ADB $SERIAL shell pm install /data/local/tmp/WhatsAppbackup.apk || error "Failed to restore WhatsApp! Reinstall from Play Store."
    error "Fix failed. WhatsApp has been restored from backup."
}
log "Fresh WhatsApp installed"

# Done
echo ""
log "Fix applied! Now try the WhatsApp toggle in Move to iOS."
echo ""
echo "If it still doesn't work, run this to also grant package visibility:"
echo "  $ADB $SERIAL shell appops set com.whatsapp QUERY_ALL_PACKAGES allow"
echo "  $ADB $SERIAL shell appops set com.apple.movetoios QUERY_ALL_PACKAGES allow"
echo ""
