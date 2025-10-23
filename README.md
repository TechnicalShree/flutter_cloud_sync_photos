# CloudSync Photos

This repository contains the Flutter client for CloudSync Photos.

## Building a signed Android release

Google Play Protect blocks APKs that are signed with the public debug key. To
generate a trusted release build:

1. Create a keystore (or reuse your existing one) and note the alias and
   passwords.
2. Copy `android/key.properties.sample` to `android/key.properties` and update
   the placeholders with your keystore details.
3. Build the signed artifact with `flutter build apk --release` or your
   preferred Gradle task.

The Gradle configuration now fails release builds when no keystore
configuration is provided. This prevents accidental debug-signed releases that
trigger Play Protect warnings.
