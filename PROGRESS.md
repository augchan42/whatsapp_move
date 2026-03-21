# WhatsApp Android → iPhone Migration

## Status: IN PROGRESS — Waiting for iPhone setup

## Device Info
- **Source**: Pixel 3 XL, Android 12 (SDK 31), WhatsApp v2.26.10.72
- **Target**: iPhone (factory reset, in setup flow)
- **Connection**: Both connected to MacBook Pro via USB

## Problem
Move to iOS app fails to access WhatsApp's migration ContentProvider (`com.whatsapp.provider.migrate.ios`) due to Android 12 package visibility restrictions. The provider exists but is disabled by default and protected by signature-level permissions.

## Solution
Manual migration using open source tools: decrypt Android DB, convert to iOS format, inject into iPhone backup.

## Steps

### Phase 1: Extract Data from Android
- [x] **1.1** Pull encrypted database (`msgstore.db.crypt14`) from phone — 2.3MB
- [x] **1.2** Extract encryption key via legacy WhatsApp downgrade + `adb backup` trick
  - Backed up current WhatsApp APK to `/data/local/tmp/WhatsAppbackup.apk`
  - Uninstalled WhatsApp (kept data with `-k`)
  - Installed legacy WhatsApp v2.11.431 (from Wayback Machine archive)
  - Ran `adb backup` — got 39MB backup
  - Extracted key from `apps/com.whatsapp/f/key` (158 bytes)
  - Reinstalled current WhatsApp v2.26.10.72
- [x] **1.3** Decrypt database using wa-crypt-tools — 5.5MB SQLite, 4,229 messages, 866 chats
- [x] **1.4** Create compatibility views for new WhatsApp schema
  - New schema uses `message` table (not `messages`), `jid` table with `@lid` format
  - Created `legacy_available_messages_view` mapping new columns to old names
  - Created `group_participants` view joining `group_participant_user` with `jid`
  - Updated `chat_view` to include `raw_string_jid` from `jid` table
  - Verified: 4,224 messages across 96 visible chats
- [x] **1.5** Pull media files from phone — 510MB complete

### Phase 2: Build Tools & Prepare iOS
- [x] **2.1** Build watoi tool — compiled successfully with Xcode
- [ ] **2.2** Get WhatsApp CoreData model (`.momd` files) — need WhatsApp.ipa or extract from iPhone
- [ ] **2.3** Set up iPhone: finish setup, install WhatsApp, activate with phone number
- [ ] **2.4** Create local unencrypted Finder backup of iPhone

### Phase 3: Convert & Import
- [ ] **3.1** Extract iOS `ChatStorage.sqlite` from iPhone backup
- [ ] **3.2** Run watoi: `msgstore_compat.db` → `ChatStorage.sqlite` with `.momd`
- [ ] **3.3** Replace `ChatStorage.sqlite` in iPhone backup
- [ ] **3.4** Restore modified backup to iPhone via Finder
- [ ] **3.5** Open WhatsApp on iPhone — verify chats appear

## What You Need To Do Now
1. **Finish iPhone setup** — skip Move to iOS, just complete the setup wizard
2. **Install WhatsApp** from the App Store on the iPhone
3. **Activate WhatsApp** with your phone number (this will disconnect Android WhatsApp)
4. **Send yourself a test message** so there's data in the iOS database
5. **Connect iPhone to Mac via USB**
6. **Open Finder** → click iPhone → **uncheck "Encrypt local backup"** → click **"Back Up Now"**
7. Tell me when the backup is done

## File Locations
```
data/android/msgstore.db.crypt14   — encrypted database (from phone)
data/android/msgstore.db           — decrypted database (SQLite)
data/android/msgstore_compat.db    — decrypted DB with compatibility views (for watoi)
data/android/key                   — encryption key (158 bytes)
data/android/Media/                — WhatsApp media files (pulling)
data/whatsapp.apk                  — current WhatsApp APK
data/LegacyWhatsApp.apk           — WhatsApp v2.11.431 (Wayback Machine)
tmp/whatsapp.ab                    — adb backup working copy (39MB)
tmp/whatsapp.tar                   — extracted backup tar (92MB)
```

## Vendor Tools
```
vendor/wa-crypt-tools/             — WhatsApp crypt12/14/15 decryptor (Python)
vendor/watoi/                      — Android→iOS WhatsApp DB converter (Obj-C, built)
vendor/WhatsApp-Key-Database-Extractor/  — Key extraction reference
```

## Key Technical Notes
- Legacy WhatsApp APK URL: `https://web.archive.org/web/20141111030303if_/http://www.whatsapp.com/android/current/WhatsApp.apk`
- APK MD5: `73fa47a3870d0b9ee6e29d843118e09b`
- WhatsApp new schema (2024+) uses `message` table, `jid` table with `@lid` internal IDs
- Visible chats use standard `@s.whatsapp.net` and `@g.us` JID formats
- watoi expects `legacy_available_messages_view` with old column names — solved via SQL views
