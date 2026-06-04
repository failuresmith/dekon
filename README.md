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

The app scaffold is intentionally not created yet. The next step is to confirm MVP platform and dependency choices, then generate the Flutter project and add the smallest required packages.
