# Package Selection

Last checked: 2026-06-04.

Selection criteria:

- Trustworthy maintainers or strong ecosystem adoption.
- Works with Flutter 3.44 / Dart 3.12 and Android API 24+.
- Minimal production dependency count.
- Native platform primitives where they materially improve reliability or memory use.
- No code generation unless it pays for itself in safety or maintenance.

## Selected Production Dependencies

| Need | Package | Current Version Checked | Why |
| --- | --- | ---: | --- |
| SQLite | `sqflite` | `2.4.3` | Flutter Favorite, mature, native SQLite, low memory overhead compared with ORM/codegen stacks. |
| Paths | `path` | `1.9.1` | Dart team package for deterministic path manipulation. |
| App file locations | `path_provider` | `2.1.5` | Flutter team package for app data/cache paths. |
| Local backup/import picker | `file_selector` | `1.1.0` | Flutter team package; supports native file/directory selection UI. |
| LAN HTTP server | `shelf` | `1.4.2` | Dart team server middleware package; small and composable. |
| HTTP client | `http` | `1.6.0` | Dart team package; reliable, small, and broadly used. |
| Hash/HMAC | `crypto` | `3.0.7` | Dart team package for SHA and HMAC. |
| Event IDs | `uuid` | `4.5.3` | Supports UUID v7; avoids custom ID generation. |
| Barcode and QR scanning | `mobile_scanner` | `7.2.0` | Mature Flutter scanner using native CameraX/ML Kit on Android. Covers product barcodes and QR pairing scans. |
| QR generation | `qr_flutter` | `4.1.0` | Lightweight Flutter QR rendering for server pairing codes. |

## Selected Dev Dependencies

| Need | Package | Current Version Checked | Why |
| --- | --- | ---: | --- |
| Flutter lint rules | `flutter_lints` | `6.0.0` | Flutter team recommended lint set. |
| SQLite unit/integration tests | `sqflite_common_ffi` | `2.4.1` | Test-friendly sqflite implementation for non-device test runs. |

## Not Selected Initially

| Package | Reason |
| --- | --- |
| `drift` | Strong package, but adds ORM/codegen complexity. Direct SQL with focused repositories is enough for MVP and keeps memory/dependency surface smaller. |
| `sqlite3` | Good lower-level option, but `sqflite` is the more standard Flutter mobile choice and simpler for Android MVP. |
| `sqlite3_flutter_libs` | Pub metadata says it is no longer used and points to `sqlite3` 3.x. |
| `shelf_router` | Current latest metadata advertises a Dart SDK range below Dart 3, so it is not compatible with the selected toolchain. Use explicit `shelf` routing instead. |
| `google_mlkit_barcode_scanning` | Lower-level ML Kit binding. `mobile_scanner` provides the camera/scanner integration directly with less app code. |
| `file_picker` | Mature, but `file_selector` is first-party and enough for native file/directory selection. |
| `permission_handler` | Mature, but not selected until needed. Start with platform permissions required by selected plugins and add this only if explicit permission orchestration is necessary. |
| `shared_preferences` | Not needed initially. Store device identity and app state in SQLite to keep recovery behavior auditable. |
| `logging` | Not needed initially. Start with a small local logging wrapper and add a package only if structured logging needs grow. |

## Implementation Notes

- Use `sqflite` with explicit migrations and repository classes. Keep SQL close to the projection/event storage boundary.
- Use `uuid` v7 for `event_id`; implement the hybrid logical clock separately.
- Use `crypto` for canonical payload hashes and HMAC-authenticated sync requests.
- Use `mobile_scanner` for both product barcode scans and QR pairing scans.
- Use `qr_flutter` only to render pairing payloads.
- Use `file_selector` for local-directory backup/import UX. Exact Android directory semantics still need a final decision before implementation.
- Keep app update packages out of the first product build because GitHub Releases update flow is postponed.
