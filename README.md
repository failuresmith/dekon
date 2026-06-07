# Dekon Inventory/POS MVP

Flutter MVP for an offline-first inventory/POS app with SQLite local storage, event-based LAN sync, and Android release distribution through GitHub Releases.

Minimum Android target for the MVP is Android 7.0 Nougat / API 24. This matches the current Flutter toolchain floor and should not be raised by dependency choices without explicit approval.

## Current Status

- SRS: `docs/SRS.md`
- Docker-based Flutter development environment: `Dockerfile.dev` and `docker-compose.yml`

## Development Container

Build the toolchain image:

```bash
docker compose build flutter-dev
```

The build forwards host proxy variables when they exist so Flutter/Dart can reach `pub.dev` from inside Docker. They are build arguments, not runtime image environment variables.

Open a shell in the container:

```bash
docker compose run --rm flutter-dev
```

Check the Flutter toolchain inside the container:

```bash
flutter doctor
```

The image is configured for Android MVP work only. `flutter doctor` should report the Flutter and Android toolchains as healthy; a connected-device warning is expected unless an Android device is attached/passed through to Docker.

## Android Release APKs

Publishing a GitHub release now triggers `.github/workflows/release-android-apks.yml`. The workflow builds signed release APKs separately for the supported Android ABIs and attaches them to the GitHub release:

- `armeabi-v7a`
- `arm64-v8a`
- `x86_64`

Configure these encrypted repository secrets before running the workflow:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded contents of the release `.jks` keystore
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: signing key alias
- `ANDROID_KEY_PASSWORD`: signing key password

Generate the base64 value on Linux with:

```bash
base64 -w 0 android/release-keystore.jks
```

The keystore and `android/key.properties` must remain outside version control. The workflow reconstructs them only inside the GitHub Actions runner.

For a release that was created before this workflow existed, open **Actions → Release Android APKs → Run workflow**, then enter the existing release tag. The generated APK files and `SHA256SUMS.txt` will be attached to that release.
