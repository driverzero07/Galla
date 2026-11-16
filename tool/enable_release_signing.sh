#!/usr/bin/env bash
# Release signing for the Play Store (Part 7). Run once from the project
# root after `bash tool/setup.sh`:   bash tool/enable_release_signing.sh
#
# 1. Creates a keystore if android/upload-keystore.jks does not exist (you
#    are asked for a password; KEEP THE FILE AND PASSWORD SAFE, outside git).
# 2. Writes android/key.properties (git-ignored).
# 3. Patches android/app/build.gradle(.kts) so `flutter build appbundle`
#    signs with it. Safe to run again.
#
# Play App Signing: upload this .aab; Google keeps the real app-signing key.
set -euo pipefail
cd "$(dirname "$0")/.."

KS=android/upload-keystore.jks
PROPS=android/key.properties
if [ ! -f "$KS" ]; then
  echo "Creating upload keystore (you will be asked for a password)..."
  read -r -s -p "Keystore password (min 6 chars): " PW; echo
  keytool -genkeypair -v -keystore "$KS" -storetype JKS -keyalg RSA -keysize 2048 \
    -validity 10000 -alias upload -storepass "$PW" -keypass "$PW" \
    -dname "CN=Galla, O=Galla, C=PK"
  printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=upload\nstoreFile=../upload-keystore.jks\n' \
    "$PW" "$PW" > "$PROPS"
fi

# Never commit secrets.
touch .gitignore
for f in "android/key.properties" "android/upload-keystore.jks" "*.jks"; do
  grep -qxF "$f" .gitignore || echo "$f" >> .gitignore
done

python3 - <<'PY'
import re, pathlib
kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")
if kts.exists():
    s = kts.read_text()
    if "keystoreProperties" in s:
        print("Signing already configured."); raise SystemExit
    loader = '''import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'''
    s = loader + s
    signing = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

'''
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
    s = re.sub(r'signingConfig = signingConfigs\.getByName\("debug"\)',
               'signingConfig = signingConfigs.getByName("release")', s)
    kts.write_text(s)
    print("Patched", kts)
elif groovy.exists():
    s = groovy.read_text()
    if "keystoreProperties" in s:
        print("Signing already configured."); raise SystemExit
    loader = '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

'''
    s = re.sub(r'(android\s*\{)', loader + r'\1', s, 1)
    signing = '''    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

'''
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
    s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    groovy.write_text(s)
    print("Patched", groovy)
else:
    print("No android/app/build.gradle(.kts): run tool/setup.sh first."); raise SystemExit(1)
PY
grep -n "signingConfig" android/app/build.gradle* || true
echo "Done. Build with:  bash tool/size_check.sh"
