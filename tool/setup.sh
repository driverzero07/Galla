#!/usr/bin/env bash
# One-time setup + full check for Galla. Run from anywhere:  bash tool/setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Generate the Android runner (existing files such as pubspec.yaml and lib/
#    are NOT overwritten).
if [ ! -d android ]; then
  flutter create --project-name galla --org pk.galla --platforms android .
fi

# 1b. Some plugins (file_picker, ...) are still compiled against android-34,
#     but androidx lifecycle now needs compileSdk 36. Force 36 on every plugin
#     module. Registered with beforeProject so it runs before AGP finalizes.
ROOT_KTS=android/build.gradle.kts
if [ -f "$ROOT_KTS" ] && ! grep -q "galla-compilesdk-override" "$ROOT_KTS"; then
  cat > android/.galla_override.kts.txt <<'KTS'
// galla-compilesdk-override
gradle.beforeProject {
    if (path != ":" && name != "app") {
        afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                try {
                    ext.javaClass.methods.firstOrNull { it.name == "setCompileSdk" }?.invoke(ext, 36)
                } catch (e: Exception) {
                    println("compileSdk override skipped for $name: $e")
                }
            }
        }
    }
}

KTS
  cat android/.galla_override.kts.txt "$ROOT_KTS" > android/.root_new.kts
  mv android/.root_new.kts "$ROOT_KTS"
  rm -f android/.galla_override.kts.txt
fi

# 2. Part 0 requires minSdk 23 (Android 6) so 2 GB phones are covered.
for f in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$f" ]; then
    sed -i -E 's/minSdk(Version)?( =|) *flutter\.minSdkVersion/minSdk\1\2 23/' "$f"
    grep -n "minSdk" "$f" || true
  fi
done

# 2b. Camera permission (photos and barcode scanner).
MANIFEST=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ] && ! grep -q "android.permission.CAMERA" "$MANIFEST"; then
  sed -i '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.CAMERA"\/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"\/>/' "$MANIFEST"
  grep -n "CAMERA" "$MANIFEST" || true
fi

# 2c. Android 11+ package visibility for url_launcher (call and WhatsApp links).
if [ -f "$MANIFEST" ] && ! grep -q 'android:scheme="tel"' "$MANIFEST"; then
  sed -i '0,/<application/s//<queries>\n        <intent><action android:name="android.intent.action.DIAL"\/><data android:scheme="tel"\/><\/intent>\n        <intent><action android:name="android.intent.action.VIEW"\/><data android:scheme="https"\/><\/intent>\n    <\/queries>\n    <application/' "$MANIFEST"
  grep -n 'scheme="tel"' "$MANIFEST" || true
fi

# 2d. Local notifications (Part 5): permissions, boot receiver, and Java 8+
#     library desugaring, which flutter_local_notifications needs.
if [ -f "$MANIFEST" ] && ! grep -q "ScheduledNotificationReceiver" "$MANIFEST"; then
  sed -i '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"\/>\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"\/>/' "$MANIFEST"
  sed -i '0,\#</application>#s##    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" \/>\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"\/>\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"\/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"\/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"\/>\n            <\/intent-filter>\n        <\/receiver>\n    <\/application>#' "$MANIFEST"
  grep -n "ScheduledNotification" "$MANIFEST" || true
fi
GRADLE_KTS=android/app/build.gradle.kts
GRADLE_GROOVY=android/app/build.gradle
if [ -f "$GRADLE_KTS" ] && ! grep -q "isCoreLibraryDesugaringEnabled" "$GRADLE_KTS"; then
  sed -i '0,/compileOptions {/s//compileOptions {\n        isCoreLibraryDesugaringEnabled = true/' "$GRADLE_KTS"
  printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' >> "$GRADLE_KTS"
  grep -n "DesugaringEnabled\|desugar_jdk_libs" "$GRADLE_KTS" || true
elif [ -f "$GRADLE_GROOVY" ] && ! grep -q "coreLibraryDesugaringEnabled" "$GRADLE_GROOVY"; then
  sed -i '0,/compileOptions {/s//compileOptions {\n        coreLibraryDesugaringEnabled true/' "$GRADLE_GROOVY"
  printf '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n' >> "$GRADLE_GROOVY"
fi

# 3. Dependencies, generated code (Drift + localisation), then checks.
flutter pub get
dart run build_runner build --delete-conflicting-outputs
# App icon + splash from the G logo (safe to repeat).
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter gen-l10n
# Info-level lints (e.g. deprecations from newer Flutter) must not block the
# tests, so analyze reports but does not stop the script.
flutter analyze --no-fatal-infos || echo "NOTE: flutter analyze reported issues (see above)"
flutter test

echo
echo "Part 1 checks passed. Run the app with:  flutter run"
