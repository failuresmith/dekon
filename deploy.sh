docker compose run --rm flutter-dev flutter build apk --release --split-per-abi

APK=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

for serial in $(adb devices | awk 'NR > 1 && $2 == "device" {print $1}'); do
  adb -s "$serial" install -r "$APK"
done