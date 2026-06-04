# TODO: SRS To Ready APK

This checklist tracks the work needed to move from `docs/SRS.md` to a signed Android APK for Dekon.

## Current Status

- [x] SRS created.
- [x] Docker Flutter/Android toolchain created and verified.
- [x] Android minimum selected: API 24.
- [x] Application ID selected: `xyz.infinica.dekon`.
- [x] MVP dependency set selected in `docs/PACKAGES.md`.
- [x] GitHub Releases auto-update postponed until after the product MVP is built.
- [x] Flutter app scaffolded, selected packages added, and empty debug APK verified.
- [x] Core architecture, event envelope, persistence boundaries, and tests implemented.
- [x] SQLite migrations/projection tables and domain projectors implemented.
- [x] Minimal Sell, Buy, Reports UI implemented on top of the event/projector layer.
- [x] Barcode scanning integrated into Sell and Buy with manual fallback.
- [x] LAN sync server endpoints, QR pairing, HMAC auth, and sync integration tests implemented.
- [x] Local backup/export and restore/import workflow implemented.
- [ ] Next step: run Android barcode/LAN sync/backup smoke tests, then prepare release signing.

## Guardrails

- [x] Keep Android `minSdk = 24` unless a higher minimum is explicitly approved.
- [x] Production dependency policy decided: install the minimum required set only.
- [x] Do not add production dependencies outside `docs/PACKAGES.md` without explicit approval.
- [ ] Prefer `pnpm` for any JavaScript tooling.
- [x] Keep POS operation offline-first; network/update failures must not block Sell, Buy, or Reports.
- [x] Treat all inventory mutations as append-only events; do not directly edit stock totals.
- [x] Do not log secrets, pairing tokens, release credentials, or sensitive transaction payloads.

## 1. Product And Technical Decisions

- [x] Confirm Android-only MVP scope.
- [x] Confirm package name/application ID: `xyz.infinica.dekon`.
- [x] Confirm app display name: Dekon.
- [x] Confirm release signing strategy: generate a new release keystore.
- [x] Confirm keystore ownership: project-generated, not committed to the repository.
- [x] Defer GitHub repository owner/name for release update checks until after product MVP is built.
- [x] Decide MVP database encryption: no database encryption for first APK.
- [x] Decide sync server discovery approach: QR code.
- [x] Decide device pairing UX: QR code pairing.
- [x] Decide local user/PIN protection: defer.
- [x] Decide negative stock policy: allow with warning.
- [x] Decide backup/import: local-directory export/import for MVP; optional Google-based backup later.
- [x] Use Android local-directory backup/import through a native directory picker first.
- [x] Treat Google-based backup as post-MVP backlog, not a ready-APK blocker.

## 2. Dependency Approval

- [x] Select SQLite package: `sqflite`.
- [x] Select path packages: `path`, `path_provider`.
- [x] Select local backup/import picker: `file_selector`.
- [x] Select barcode and QR scanning package: `mobile_scanner`.
- [x] Select QR generation package: `qr_flutter`.
- [x] Select HTTP server/client packages: `shelf`, `http`.
- [x] Select ID package for UUIDv7: `uuid`.
- [x] Select cryptography package for event hashes and sync request authentication: `crypto`.
- [x] Defer app update/download/install packages or platform-channel approach until after product MVP is built.
- [x] Select dev packages: `flutter_lints`, `sqflite_common_ffi`.
- [x] Select state/routing approach: no additional production package for MVP; use Flutter primitives and explicit `shelf` routing.
- [x] Exclude initially: `drift`, `sqlite3`, `sqlite3_flutter_libs`, `shelf_router`, `google_mlkit_barcode_scanning`, `file_picker`, `permission_handler`, `shared_preferences`, `logging`.

## 3. Project Scaffold

- [x] Generate Flutter project in the repo.
- [x] Set Android application ID to `xyz.infinica.dekon`.
- [x] Set Android `minSdk = 24`.
- [x] Set target/compile SDK to match the Docker toolchain.
- [x] Disable unused platforms or keep them ungenerated for MVP.
- [x] Add production dependencies: `sqflite`, `path`, `path_provider`, `file_selector`, `shelf`, `http`, `crypto`, `uuid`, `mobile_scanner`, `qr_flutter`.
- [x] Add dev dependencies: `flutter_lints`, `sqflite_common_ffi`.
- [x] Add baseline lint rules through `flutter_lints`.
- [x] Add app configuration without GitHub Releases endpoint until update flow is resumed.
- [x] Verify `flutter doctor -v` in Docker.
- [x] Verify `flutter test` runs on the empty scaffold.
- [x] Verify debug APK builds in Docker.

## 4. Core Architecture

- [x] Define module boundaries for UI, domain, persistence, sync, reporting, and platform integrations.
- [x] Define event envelope model and schema versioning.
- [x] Define canonical JSON serialization and payload hashing.
- [x] Implement stable local device identity.
- [x] Implement hybrid logical clock.
- [x] Implement event validation.
- [x] Implement append-only event writer with SQLite transaction boundaries.
- [x] Implement unsupported-event storage without applying unknown schemas.
- [x] Add tests for event validation, hashing, HLC ordering, and duplicate handling.

## 5. SQLite Persistence

- [x] Create migration system.
- [x] Create `devices` table.
- [x] Create `events` table with unique `event_id`.
- [x] Create `sync_peers` table.
- [x] Create `products_projection` table.
- [x] Create `inventory_projection` table.
- [x] Create `sales_projection` table.
- [x] Create `purchase_projection` table.
- [x] Add rollback-safe transaction tests.
- [x] Add idempotency tests for duplicate event inserts.

## 6. Domain Projectors

- [x] Implement product create/update/deactivate projector.
- [x] Enforce active barcode uniqueness.
- [x] Implement sale event projector.
- [x] Implement purchase event projector.
- [x] Implement inventory adjustment projector.
- [x] Implement void/correction compensating event projectors.
- [x] Implement field-level product conflict resolution using `(hlc, device_id, event_id)`.
- [x] Add tests for out-of-order event application.
- [x] Add tests for product conflict convergence.
- [x] Add tests for inventory totals from purchase, sale, void, and adjustment events.

## 7. Minimal UI

- [x] Build app shell with Sell, Buy, Reports navigation.
- [x] Build reusable product search/manual barcode entry component.
- [x] Build minimal product create/edit/inactivate flow.
- [x] Build Sell flow with multiple line items.
- [x] Persist sale before showing success.
- [x] Warn before confirming negative stock.
- [x] Build Buy flow with multiple line items.
- [x] Persist purchase before showing success.
- [x] Build Reports screen for stock, daily sales, daily purchases, gross margin estimate, and low stock.
- [x] Show unsynced event count and last successful sync time.
- [x] Add widget tests for Sell, Buy, and Reports happy paths.
- [x] Add widget tests for unknown barcode/product creation path.

## 8. Barcode Scanning

- [x] Add camera permission handling.
- [x] Integrate barcode scanner into Sell flow.
- [x] Integrate barcode scanner into Buy flow.
- [x] Preserve manual entry fallback when permission is denied.
- [x] Handle unknown barcode by opening minimal product creation.
- [ ] Test permission-denied flow manually on Android.
- [ ] Test scan success and manual fallback on Android.

## 9. LAN Sync

- [x] Implement server mode lifecycle: start, visible running state, and stop.
- [x] Bind server to LAN-reachable interface only while server mode is enabled.
- [x] Implement `GET /health`.
- [x] Implement `GET /device`.
- [x] Implement `GET /events?since=<cursor>&limit=<n>`.
- [x] Implement `POST /events`.
- [x] Implement `GET /sync/state`.
- [x] Implement QR code server discovery.
- [x] Implement QR code device pairing.
- [ ] Keep manual server address entry as a support fallback only if QR setup fails.
- [x] Store trusted peer/device records.
- [x] Authenticate sync requests.
- [x] Redact tokens and secrets from logs.
- [x] Make event pull/push resumable after interruption.
- [x] Return accepted, duplicate, rejected, and unsupported event IDs from `POST /events`.
- [x] Add integration tests for duplicate `POST /events`.
- [x] Add integration tests for interrupted sync resume.
- [x] Add integration tests for unsupported schema storage.
- [x] Add integration tests for out-of-order sync convergence.

## 10. Backup And Recovery

- [x] Add manual export workflow to a local directory.
- [x] Add manual import workflow from a local directory.
- [x] Use native directory picker from `file_selector` for local backup location.
- [x] Write export atomically: create temp file, flush, then move/rename to final backup file.
- [x] Include schema version, app version, export timestamp, and event count in backup metadata.
- [x] Validate backup file before import mutates local state.
- [x] Do not encrypt the database for the first APK.
- [x] Defer optional Google-based backup until after local backup/import is stable.
- [x] Validate backup compatibility with event schema version.
- [ ] Add recovery test for app restart during event write.
- [ ] Add recovery test for app restart during sync.

## 11. GitHub Releases Update Flow

- [x] Postpone this section until after product MVP is built.
- [ ] Implement release metadata check against configured GitHub Releases endpoint.
- [ ] Compare release version with installed app version.
- [ ] Display release version, date, and notes summary.
- [ ] Fail closed when GitHub/network access is unavailable.
- [ ] Download APK only after explicit user approval.
- [ ] Verify release signature/checksum before install handoff.
- [ ] Hand off APK install to Android package installer with user confirmation.
- [ ] Add tests for version comparison and network failure behavior.
- [ ] Add manual Android smoke test for update detection and install handoff.

## 12. Observability And Failure Handling

- [ ] Show local database status and last migration version if useful for support.
- [ ] Show sync status, last sync error, last success time, and unsynced event count.
- [ ] Ensure all critical write failures fail loudly in the UI.
- [ ] Ensure report calculations never hide unsupported or unapplied events.
- [ ] Add structured logs with sensitive fields redacted.

## 13. Android Release Build

- [ ] Configure app versioning.
- [ ] Generate a new release keystore.
- [ ] Configure release signing without committing keystore files or passwords.
- [ ] Configure ProGuard/R8 only if compatible with selected packages.
- [ ] Build release APK locally in Docker.
- [ ] Install APK on an Android device.
- [ ] Run manual smoke test: product create, scan/manual barcode, buy, sell, reports.
- [ ] Run manual two-device LAN sync test.
- [ ] Run manual update-check failure test with network disabled.
- [ ] Defer manual GitHub Releases update-check test until update flow is resumed.

## 14. GitHub Actions Release Automation

- [ ] Add workflow for lint, tests, and Android release APK build.
- [ ] Add secure handling for signing keystore and passwords.
- [ ] Add artifact upload for APK.
- [x] Defer release workflow that attaches APK and checksum to GitHub Releases until repository/release flow is resumed.
- [ ] Add release notes template.
- [ ] Ensure workflow does not expose secrets in logs.
- [ ] Verify release workflow on a test tag.

## 15. Final Verification Before Ready APK

- [ ] Run `flutter analyze`.
- [ ] Run `flutter test`.
- [ ] Run SQLite integration tests.
- [ ] Run sync integration tests.
- [ ] Run `flutter build apk --release`.
- [ ] Verify APK signature.
- [ ] Verify APK installs on Android API 24 or emulator/device equivalent.
- [ ] Verify APK installs on a current Android device.
- [ ] Complete manual offline smoke test.
- [ ] Complete manual LAN sync smoke test.
- [ ] Defer manual update-check smoke test until update flow is resumed.
- [ ] Record known limitations and accepted risks in release notes.

## Ready APK Definition Of Done

- [ ] Release APK is built from a clean working tree or documented release commit.
- [ ] APK is signed with the approved release key.
- [ ] APK supports Android API 24+.
- [ ] Sell, Buy, Reports, product management, barcode/manual entry, LAN sync, and local backup/import pass smoke testing.
- [ ] Duplicate/interrupted sync does not corrupt inventory or duplicate totals.
- [ ] APK artifact, checksum, and release notes are produced locally or in CI; GitHub Release publishing is postponed.
- [ ] Residual risks are documented before distribution.
