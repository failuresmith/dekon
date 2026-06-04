# Software Requirements Specification: Offline-First Inventory/POS MVP

## 1. Scope

Build a Flutter MVP inventory and point-of-sale application for small shops that works offline by default and synchronizes over a local network when one phone is acting as the server. The MVP covers product management, barcode lookup/scanning, purchases, sales, and basic reports.

The system must prioritize data integrity, predictable sync, and safe recovery over broad feature coverage.

## 2. Out Of Scope For MVP

- Multi-branch accounting, tax filing, payroll, customer credit, supplier payable workflows, and full double-entry accounting.
- Cloud sync, remote backups, hosted admin panels, and multi-tenant service operation.
- Google-based backup is not required for the first APK; it can be added later as an optional backup target after provider, auth, quota, and privacy behavior are defined.
- Silent mobile app updates. Android requires user consent to install APK updates outside an app store.
- iOS self-update through GitHub Releases. iOS distribution must use App Store, TestFlight, MDM, or enterprise distribution rules.
- Payment terminal integration.
- Real-time inventory reservation across multiple devices while offline.

## 3. Users And Roles

- Cashier: sells products, scans barcodes, views basic product information.
- Buyer/Stock Clerk: records purchases and stock additions.
- Owner/Admin: manages products, reviews reports, starts or stops the LAN sync server, exports backups, and approves updates.

MVP role enforcement can be local-device PIN based. Strong multi-user authorization is a later phase unless the app handles sensitive financial data across untrusted staff devices.

## 4. Product Goals

- Keep selling and buying workflows available without internet.
- Preserve an auditable inventory ledger.
- Synchronize devices on the same LAN without a cloud dependency.
- Avoid sync conflicts by using append-only business events and deterministic merge rules.
- Keep the UI small: Sell, Buy, Reports, plus minimal product maintenance reachable from those flows.
- Support update discovery from GitHub Releases with explicit user approval.

## 5. Platform Requirements

- Primary target: Android phones running Android 7.0 Nougat / API 24 or newer.
- Minimum supported Android version: API 24. This is the lowest supported floor for the current Flutter toolchain and satisfies Dekon's MVP requirements for SQLite, camera permission flow, local HTTP LAN sync, and user-approved APK install/update flow.
- Dependencies selected later for SQLite, barcode scanning, LAN sync, and update checks must support API 24. Raising `minSdk` above API 24 requires explicit product approval.
- Framework: Flutter.
- Local storage: SQLite.
- LAN server: one Android phone runs a Dart `shelf` HTTP server while the app is open.
- Sync transport: HTTP over LAN using JSON payloads.
- Release distribution: GitHub Releases for APK artifacts.
- Android application ID: `xyz.infinica.dekon`.
- Selected production package set is documented in `docs/PACKAGES.md`.

Desktop support can be added later for admin/reporting, but it is not required for the MVP. Android 6.0/API 23 and older are out of scope for the MVP because the selected Flutter baseline no longer supports them.

## 6. Functional Requirements

### 6.1 Products

- Create and edit products with:
  - product ID
  - name
  - barcode
  - SKU
  - unit
  - sale price
  - purchase cost
  - active/inactive status
- Barcode must be unique among active products.
- Product deletion must be soft-delete/inactivation only.
- Product edits must be represented as events, not destructive overwrites.

### 6.2 Barcode Scan

- Scan barcode from camera during Sell and Buy flows.
- Provide manual barcode/SKU entry fallback.
- If barcode is unknown, allow creating a minimal product record before continuing.
- Camera permission denial must not block manual operation.

### 6.3 Sales

- Create a sale with one or more line items.
- Each line item records product ID, quantity, unit price, and discount if enabled.
- Sales must be persisted locally before UI success is shown.
- Sale events reduce stock through the inventory projection.
- Refunds/voids must be represented by compensating events, not deleting the original sale.
- MVP may allow negative stock, but it must warn clearly before confirmation.
- Negative stock policy: allow with warning.

### 6.4 Purchases

- Create a purchase/stock-in record with one or more line items.
- Each line item records product ID, quantity, unit cost, and optional supplier note.
- Purchase events increase stock through the inventory projection.
- Corrections must use compensating adjustment events.

### 6.5 Reports

- Show at least:
  - current stock by product
  - daily sales total
  - daily purchase total
  - gross margin estimate
  - low-stock list
- Reports must be computed from local SQLite projections and work offline.
- Reports must show last successful sync time and unsynced event count.

### 6.6 LAN Sync

- Any device can run independently offline.
- One phone can be selected as the LAN server.
- Clients discover or manually enter the server address.
- Primary server discovery UX is QR code pairing.
- Devices exchange append-only events.
- Sync must be resumable after app restarts, network loss, and duplicate requests.
- Applying the same event more than once must be idempotent.

### 6.7 GitHub Releases Update Check

- App checks the configured GitHub Releases endpoint for a newer version.
- App shows release version, date, and notes summary.
- User explicitly approves downloading the APK.
- Android install requires user confirmation through the platform installer.
- Update checks must fail closed: failure to reach GitHub must not block POS operation.

## 7. Data Model

### 7.1 Core Tables

- `devices`: local device identity and trust metadata.
- `events`: append-only event log.
- `sync_peers`: known LAN peers and last sync state.
- `products_projection`: current product view.
- `inventory_projection`: current stock by product.
- `sales_projection`: sale headers and totals for reporting.
- `purchase_projection`: purchase headers and totals for reporting.

### 7.2 Event Fields

Each event must include:

- `event_id`: globally unique UUIDv7 or ULID.
- `device_id`: stable device UUID.
- `hlc`: hybrid logical clock timestamp.
- `type`: event type.
- `entity_id`: aggregate/product/sale/purchase ID.
- `payload`: canonical JSON.
- `schema_version`: event schema version.
- `payload_hash`: hash of canonical payload.
- `created_at`: device local timestamp for display only.
- `received_at`: local persistence timestamp.

`event_id` must have a unique constraint. `payload_hash` protects against accidental same-ID/different-payload corruption.

### 7.3 Event Types

- `product.created`
- `product.field_set`
- `product.deactivated`
- `inventory.purchase_recorded`
- `inventory.sale_recorded`
- `inventory.adjustment_recorded`
- `sale.voided`
- `purchase.corrected`

Inventory-changing events are additive ledger entries. Product metadata conflicts resolve deterministically per field using `(hlc, device_id, event_id)` ordering.

## 8. Sync Design

### 8.1 Conflict-Free Strategy

- Inventory quantity is never edited directly. It is derived from purchase, sale, void, and adjustment events.
- Duplicate events are ignored by `event_id`.
- Product metadata uses field-level last-writer-wins with hybrid logical clocks and deterministic tie-breakers.
- Unknown event schema versions are stored but not applied until the app is upgraded or a migration is available.
- Sync order must not affect final projections for supported event types.

### 8.2 HTTP Endpoints

MVP LAN server endpoints:

- `GET /health`
- `GET /device`
- `GET /events?since=<cursor>&limit=<n>`
- `POST /events`
- `GET /sync/state`

`POST /events` returns accepted, duplicate, rejected, and unsupported event IDs.

### 8.3 Sync Security

- LAN sync must require device pairing before accepting events.
- MVP pairing uses QR code pairing shown on the server phone.
- Pairing creates a shared secret or trusted device record.
- Sync requests must include request authentication.
- Sensitive tokens must not be logged.
- Server mode must be visible in the UI and easy to stop.

## 9. Non-Functional Requirements

- Offline-first: selling, buying, and reports work without internet or LAN.
- Durability: critical events must be written in SQLite transactions.
- Idempotency: duplicate sync requests must be safe.
- Recovery: app restart during sync must not corrupt the event log.
- Observability: expose sync status, last error, unsynced count, and last successful sync.
- Privacy: product and transaction data stays local unless syncing with paired LAN devices or exporting backups.
- Performance: common Sell/Buy interactions should remain responsive with 10,000 products and 100,000 events on a mid-range Android phone.
- Backup: MVP should provide manual export/import to a local directory. Database encryption is not required for the first APK. Optional Google-based backup is a later enhancement.

## 10. Acceptance Criteria

- A user can create products and scan or manually enter barcodes.
- A user can record purchases and sales while offline.
- Stock and daily reports update immediately from local data.
- Two devices can create independent events offline and converge after LAN sync.
- Re-running sync does not duplicate stock movements or sales totals.
- Product metadata conflicts resolve deterministically and consistently on all devices.
- The server phone can start/stop LAN HTTP sync.
- Update check can detect a newer GitHub Release and present a user-approved install path on Android.
- App handles network loss, duplicate events, and app restart during sync without corrupting data.
- Android build configuration uses `minSdk = 24` unless a later dependency is explicitly approved to require a higher minimum.
- Android build configuration uses application ID `xyz.infinica.dekon`.

## 11. Test Coverage Expectations

- Unit tests for event validation, canonical hashing, HLC ordering, and conflict resolution.
- Unit tests for inventory projection from purchase/sale/void/adjustment events.
- SQLite integration tests for event idempotency and transaction rollback.
- Sync integration tests for duplicate POST, interrupted sync, unsupported schema, and out-of-order events.
- Widget tests for Sell, Buy, and Reports minimal flows.
- Manual Android smoke test for camera scan fallback, LAN server mode, and update-check flow.

## 12. Security And Reliability Risks

- APK updates from GitHub Releases can train users to install apps outside app stores. Mitigation: show publisher/version clearly, verify release signatures, and require explicit user approval. This flow is postponed until after the product MVP is built.
- LAN sync without authentication can allow data poisoning. Mitigation: device pairing and authenticated requests are required before accepting events.
- Device clock skew can cause confusing metadata conflict outcomes. Mitigation: use HLC and deterministic tie-breakers; treat wall-clock timestamps as display data.
- Lost or stolen phone exposes transaction data. Mitigation: OS screen lock, optional later app PIN, safe local backup handling, and no secret logging.
- Negative stock may hide operational mistakes. Mitigation: warn before sale and include low/negative-stock reporting.
- SQLite corruption or device loss can destroy records. Mitigation: transactions, periodic backups, and export/import workflow.

## 13. Implementation Phases

### Phase 1: App Shell And Local Ledger

- Flutter app scaffold.
- SQLite schema and migrations.
- Event writer and projectors.
- Minimal Sell, Buy, Reports screens.

### Phase 2: Barcode And Product Management

- Camera barcode scan.
- Manual barcode entry.
- Product create/edit/inactivate.

### Phase 3: LAN Sync

- Shelf HTTP server mode.
- Device pairing.
- Event pull/push protocol.
- Sync status and retry behavior.

### Phase 4: Releases And Update Check

- GitHub Actions release build.
- Release signing using a newly generated keystore that is not committed to the repository.
- GitHub Releases metadata check after the product MVP is built.
- User-approved APK download/install flow after the product MVP is built.

## 14. Resolved Decisions

- Android application ID: `xyz.infinica.dekon`.
- Release signing: generate a new release keystore; do not commit secrets.
- GitHub Releases repository and update flow: postpone until after the product MVP is built.
- Production dependencies: install the minimum required set only.
- Database encryption: not required for the first APK.
- Sync discovery: QR code.
- Device pairing UX: QR code pairing.
- Local access control: defer.
- Negative stock policy: allow with warning.
- Backup/import: local-directory export/import for MVP; optional Google-based backup later.
- Package selections: `sqflite`, `path`, `path_provider`, `file_selector`, `shelf`, `http`, `crypto`, `uuid`, `mobile_scanner`, and `qr_flutter` for production; `flutter_lints` and `sqflite_common_ffi` for development/testing.

## 15. Open Decisions

- Exact backup target semantics for "local directory" on Android storage.
- Whether optional Google-based backup means Google Drive app folder, Google Drive user-visible folder, or Google Cloud Storage.
