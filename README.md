# BiLingo

An Android app that shows a **word and its meaning** as a local notification
every time the screen turns on or the phone is unlocked. English, German and Hindi.

## How it works

- `android/app/src/main/assets/words.json` is the seed data. On first run it is
  loaded into a local SQLite database (`WordDatabase.kt`). To add words, edit
  the JSON and bump `DB_VERSION`.
- Words are served least-shown-first, so nothing repeats until every word in
  the selected languages has been seen.
- `WordService.kt` is a foreground service that holds a runtime-registered
  receiver for `ACTION_SCREEN_ON` and `ACTION_USER_PRESENT` (these cannot be
  declared in the manifest). `BootReceiver.kt` restarts it after a reboot.
- `WordNotifier.kt` posts the notification. A second trigger within 30 seconds
  is ignored, because screen-on is normally followed straight away by unlock.
- The Flutter UI (`lib/`) only edits settings and talks to the native side over
  the `com.dmonly.app/words` method channel.

Everything is on-device. The only permissions are notifications, foreground
service, and start-on-boot. No internet.

## Notes

- A low-priority, silent notification is shown in the shade and on the lock
  screen; it does not pop up over other apps.
- Some manufacturers (Xiaomi, Huawei, OnePlus, Samsung) kill background
  services aggressively. If words stop appearing, exempt the app from battery
  optimisation.

## Build

```bash
flutter pub get
flutter analyze
flutter build apk --release
```
