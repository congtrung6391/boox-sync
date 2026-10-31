#!/bin/bash
# Build an apk without Gradle: aapt2 + javac + d8 + apksigner.
# Usage: android/build-apk.sh <project-dir> <ApkName>   (project has AndroidManifest.xml and src/)
set -euo pipefail
PROJECT=$(cd "$1" && pwd)
NAME=$2
cd "$PROJECT"

export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}
export PATH="$JAVA_HOME/bin:$PATH"
SDK=${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}
BT=$SDK/build-tools/30.0.3
JAR=$SDK/platforms/android-30/android.jar
OUT=build

rm -rf $OUT && mkdir -p $OUT/classes
$BT/aapt2 link -o $OUT/base.apk --manifest AndroidManifest.xml -I "$JAR" --min-sdk-version 30 --target-sdk-version 30
javac --release 8 -Xlint:-options -classpath "$JAR" -d $OUT/classes $(find src -name '*.java')
$BT/d8 --lib "$JAR" --min-api 30 --output $OUT $(find $OUT/classes -name '*.class')
cp $OUT/base.apk $OUT/unsigned.apk
(cd $OUT && zip -q unsigned.apk classes.dex)
$BT/zipalign -f 4 $OUT/unsigned.apk $OUT/aligned.apk

KS=${BOOXSYNC_KEYSTORE:-$HOME/.booxsync/debug.keystore}
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass booxsync -keypass booxsync -alias booxsync \
    -dname "CN=BooxSync Debug" -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
fi
$BT/apksigner sign --ks "$KS" --ks-pass pass:booxsync --key-pass pass:booxsync --out "$OUT/$NAME.apk" $OUT/aligned.apk
echo "Built $PROJECT/$OUT/$NAME.apk ($(du -h "$OUT/$NAME.apk" | cut -f1))"
