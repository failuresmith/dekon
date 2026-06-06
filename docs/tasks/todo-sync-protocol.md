# Dekon Secure Sync V1

## Status

Current phase: Authenticated WebSocket projection stream implemented; stopped before client reconciliation, app-resume sync, and gap repair
Last updated: 2026-06-06

## Verified Existing Architecture

- Main-device role detection: local `app_settings.device_role` defaults to `main_device` through `DeviceRole.fromStorage`; `AppShell` uses that role to expose Main workflows and Settings can start `LanSyncServer` pairing mode.
- Cashier-device role detection: local `app_settings.device_role = cashier_device` plus `device_role_locked = true`; the role is locked only after `CashierPairingPanel` completes a successful pairing.
- Pairing mechanism: Main creates a QR/manual pairing payload with `base_url`, `server_device_id`, `pairing_secret`, and `expires_at`; Cashier calls `POST /pair`; Main stores the peer through `SyncStore.trustCashierPeer`.
- Trusted device identity source: Main authenticates remote requests from `x-dekon-device-id` plus HMAC headers, then loads a trusted row from `devices` joined to `sync_peers`; effective remote role is always Cashier.
- HTTP transport: `LanSyncServer` exposes `GET /health`, `GET /device`, `POST /pair`, `GET /events`, `POST /events`, and `GET /sync/state` through `shelf`.
- WebSocket transport: none found in `lib` or tests.
- Existing polling: `CashierSyncIndicator` pings and calls `LanSyncClient.syncWithPeer(... waitForRemoteEvents: true ...)` on a timer; `GET /events` supports long-poll waiting through `wait=true`.
- Inventory serializer: current Cashier sync uses event-log sanitization in `cashierSafeEventFor`; before Phase 1 there was no explicit Cashier product projection serializer for snapshots or push messages.
- Database package: `sqflite` in app code, `sqflite_common_ffi` in tests.
- Transaction support: `Database.transaction` is available; `SyncStore.importEvents` appends and projects each imported event in one transaction, while local `DekonRepository._commit` appends then projects in separate operations.
- App-resume handling: no sync-specific `WidgetsBindingObserver` or app-resume snapshot handling found; current convergence depends on widget initialization, timers, and repository event streams.

## Verified Root Cause of Product-Rename Sync Failure

Main product rename does not bypass the local event log. `ProductFormDialog` calls `DekonRepository.updateProduct`, which emits `product.field_set` events including `field = name`; `_commit` appends the event, applies the local projection, and notifies the local activity bus.

The propagation defect is that Main has no push channel and no centralized replicated-mutation publishing path. `LanSyncServer` only serves sanitized events when a Cashier initiates authenticated `GET /events`; there is no WebSocket server/client, projection version, snapshot repair path, or post-commit broadcast. A renamed product can therefore remain stale on a Cashier until that Cashier's polling loop is running and completes a successful pull. Phase 2 is where the versioned publishing path and push behavior should fix this.

## Verified Security Risks

- Cashier-visible data is currently derived from rich domain events and filtered afterward; this is harder to audit than a dedicated projection serializer.
- Phase 3 added a Cashier-safe HTTP snapshot endpoint; WebSocket `snapshot_required` delivery is not implemented yet.
- Authenticated WebSocket projection transport exists for sanitized incremental updates, but the Cashier UI does not yet keep a continuous listener alive.
- Phase 2 now persists Cashier projection versions in `app_settings`; Phase 3 applies full snapshots on Cashier sync, but incremental version gap repair is not implemented yet.
- Local Main mutations now use a serialized append/project/version/publish path, but remote posted sale events still use the current event-import path until the later sale-command phase replaces it.
- Cashier sales rely on event IDs for duplicate handling; dedicated command IDs are not implemented yet.
- Cashier sale submission is not disabled by a first-class synchronized/offline state model.

## Completed

- [x] Inspect repository and existing sync protocol
- [x] Trace Main-device product rename end to end
- [x] Document verified rename propagation root cause
- [x] Identify trusted paired-device identity source
- [x] Add Cashier-safe product projection
- [x] Add Phase 1 serializer redaction tests
- [x] Add persisted Cashier-projection version on Main
- [x] Add persisted last-applied projection version on Cashier
- [x] Route local replicated Main mutations through one publishing path
- [x] Add sanitized local product-upsert projection publisher
- [x] Add sanitized local inventory-patch projection publisher
- [x] Add sanitized WebSocket projection updates
- [x] Add Cashier-safe snapshot endpoint
- [x] Apply snapshot on connect
- [x] Apply snapshot on reconnect
- [ ] Apply snapshot on app resume
- [ ] Repair revision gaps with a snapshot
- [x] Authenticate Cashier HTTP requests
- [x] Authenticate Cashier WebSocket connections
- [x] Enforce Cashier sale-only authorization
- [ ] Add command IDs and sale deduplication
- [ ] Restrict Cashier UI
- [ ] Add sync-state UI
- [ ] Add automated tests
- [ ] Complete manual multi-device QA

## Decisions

- Phase 1 added `CashierProductProjection` and dedicated serializers for Cashier inventory snapshots and product-upsert projection messages, but did not route existing HTTP polling through them yet.
- Serializer JSON follows existing sync naming conventions: `product_id`, `stock_quantity`, `sale_price_minor`, `projection_version`.
- The Cashier projection excludes `sku`, `unit`, `purchase_cost_minor`, margins, supplier data, notes, history, backup metadata, and device registry data.
- Existing `/events` polling and access-control behavior was left intact except for adding the new projection module; transport replacement belongs to later phases.
- Phase 2 stores `cashier_inventory_projection_version` and `last_applied_cashier_projection_version` in `app_settings` to avoid adding a new table before the snapshot protocol needs one.
- Local repository mutations are serialized through one queue so local commit order, projection-version order, and local publication order match.
- Private-only product edits, such as purchase-cost changes, do not advance the Cashier projection version.
- Product edits that combine visible and private fields advance the Cashier projection version once and publish only the sanitized product projection.
- Sales and restocks publish sanitized stock patches that contain product IDs and resulting stock quantities only.
- Phase 3 uses authenticated `GET /cashier/inventory-snapshot` over the existing HTTP transport instead of introducing WebSocket delivery.
- `LanSyncClient.syncWithPeer` drains existing event-poll updates, applies a full Cashier-safe snapshot transactionally, then enters long-poll mode when requested.
- Cashier snapshot application replaces the local checkout cache and persists `last_applied_cashier_projection_version` in one SQLite transaction.
- Snapshot application stores `purchase_cost_minor` as `0` on Cashier because purchase cost is not part of the Cashier projection.
- WebSocket push uses `GET /cashier/projection-stream` and authenticates with the existing HMAC headers before upgrade.
- `LanSyncServer.start` now binds the Dart `HttpServer` directly so WebSocket upgrades can be handled before ordinary requests are passed to the existing Shelf handler.
- WebSocket broadcasts reuse the sanitized projection messages emitted by the local publishing path; no administrative product serializer is used.
- `LanSyncClient.openCashierProjectionStream` opens an authenticated WebSocket for later reconciliation work, but it does not yet own a long-running listener.

## Residual Risks

- Main rename propagation is prepared for push through the local projection publisher, but LAN delivery is still not immediate until WebSocket transport is implemented.
- Client-side WebSocket reconciliation, app-resume snapshot refresh, and gap-repair behavior remain unimplemented.
- The current event-log sanitizer still exists alongside the new projection serializer until later phases migrate the transport.
- Remote posted events are not yet converted into command-ID sale submissions or projection publications; that belongs to the sale-command phase.
- No manual multi-device QA has been run.

## Verification Log

### 2026-06-06

Commands run:
- `which dart`
- `which flutter`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format .`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test`

Results:
- Host `dart` and `flutter` were not on `PATH`, so the requested Dart/Flutter commands were run inside the repository Docker Flutter environment.
- `git diff --check` passed.
- `dart format .` formatted one Dart file.
- `flutter analyze` passed with no issues.
- `flutter test` passed all tests, including `test/sync/cashier_product_projection_test.dart`.

Manual QA:
- Not run for Phase 1.

Remaining issues:
- Phase 2 network delivery remains unimplemented: WebSocket transport, snapshot repair, and remote command flow are still pending.

Phase 2 commands run:
- `docker compose run --rm flutter-dev dart format .`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test`

Phase 2 results:
- `dart format .` formatted the Phase 2 repository, projection, and test files.
- `flutter analyze` passed with no issues.
- `flutter test` passed all tests, including `test/application/cashier_projection_publishing_test.dart`.

Phase 3 commands run:
- `docker compose run --rm flutter-dev dart format .`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test`

Phase 3 results:
- `dart format .` formatted the snapshot client/test files.
- First `flutter analyze` found a missing snapshot parser import in `LanSyncClient`; fixed and reran.
- `flutter analyze` passed with no issues.
- `flutter test` passed all tests, including Cashier snapshot endpoint and client application tests in `test/sync/lan_sync_server_test.dart`.

WebSocket commands run:
- `docker compose run --rm flutter-dev dart format .`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test`

WebSocket results:
- `dart format .` formatted the WebSocket server and LAN sync test files.
- `flutter analyze` passed with no issues.
- `flutter test` passed all tests, including the loopback WebSocket authentication and sanitized update stream test in `test/sync/lan_sync_server_test.dart`.

# Task: Implement Secure Push-First Cashier Synchronization for Dekon

## Goal

Refine the Dekon Flutter application's LAN synchronization protocol so that connected Cashier devices receive immediate inventory updates without receiving privileged business data or administrative capabilities.

Implement the simplest reliable architecture suitable for a small store:

```text
Main device:
  Authoritative server
  Full business state
  Full administrative access

Cashier devices:
  Restricted paired clients
  Read-only checkout-safe inventory cache
  Sale submission only
```

Use:

```text
- One authoritative Main device
- Paired Cashier devices as restricted clients
- WebSocket push updates for immediate inventory convergence
- Existing HTTP or request-response transport for commands and snapshots
- A persisted Cashier-projection version for gap detection
- Full Cashier-safe inventory snapshots for connect, reconnect, and repair
- Command IDs for retry-safe Cashier sale submission
- Main-side authorization before every remote operation
```

Do not implement:

```text
- Full event sourcing
- Durable event replay logs
- Peer-to-peer Cashier synchronization
- Multi-master writes
- CRDTs
- Distributed consensus
- MQTT brokers
- Cloud synchronization
- Offline queued sales
- Offline queued restocks
- Configurable role editors
- Employee accounts
- Enterprise identity management
- OAuth
- JWT-based IAM
- Manager roles
- Stock-clerk roles
- Complex permission dashboards
```

The implementation must be small, auditable, testable, and difficult to misuse accidentally.

---

# 1. Read Existing Instructions and Inspect the Repository

Before modifying code:

1. Read:

```text
AGENTS.md
README.md
pubspec.yaml
docs/tasks/todo-sync-protocol.md
docs/tasks/dekon-access-control-v1.md
other files under docs/tasks/
```

2. Run:

```bash
git status --short
find lib -type f | sort
find test -type f | sort
```

3. Inspect:

```text
- Root app shell
- Main-device mode detection
- Cashier-device mode detection
- Pairing workflow
- QR pairing payload
- Paired-device persistence
- Device ID generation
- Pairing token or credential storage
- LAN HTTP server
- HTTP client
- WebSocket server
- WebSocket client
- Existing polling logic
- Inventory repository
- Product serializer
- Product edit flow
- Sale completion flow
- Restock completion flow
- Reports flow
- Backup restore flow
- Database schema
- Database transaction support
- Application lifecycle listeners
- Existing tests
```

4. Identify the current transport:

```text
- HTTP only
- WebSocket only
- HTTP plus WebSocket
- Polling
- Another LAN mechanism
```

5. Reuse the current transport where practical. Do not rewrite working code merely to match a preferred architecture.

6. Preserve unrelated user changes. Do not reset, overwrite, or remove work outside this task.

---

# 2. Record Verified Findings Before Editing

At the top of this task file, maintain:

```md
# Dekon Secure Sync V1

## Status

Current phase:
Last updated:

## Verified Existing Architecture

- Main-device role detection:
- Cashier-device role detection:
- Pairing mechanism:
- Trusted device identity source:
- HTTP transport:
- WebSocket transport:
- Existing polling:
- Inventory serializer:
- Database package:
- Transaction support:
- App-resume handling:

## Verified Root Cause of Product-Rename Sync Failure

...

## Verified Security Risks

...

## Completed

- [ ] Inspect repository and existing sync protocol
- [ ] Trace Main-device product rename end to end
- [ ] Document verified rename propagation root cause
- [ ] Identify trusted paired-device identity source
- [ ] Add Cashier-safe product projection
- [ ] Add persisted Cashier-projection version on Main
- [ ] Add persisted last-applied projection version on Cashier
- [ ] Route replicated Main mutations through one publishing path
- [ ] Add sanitized WebSocket projection updates
- [ ] Add Cashier-safe snapshot endpoint
- [ ] Apply snapshot on connect
- [ ] Apply snapshot on reconnect
- [ ] Apply snapshot on app resume
- [ ] Repair revision gaps with a snapshot
- [ ] Authenticate Cashier HTTP requests
- [ ] Authenticate Cashier WebSocket connections
- [ ] Enforce Cashier sale-only authorization
- [ ] Add command IDs and sale deduplication
- [ ] Restrict Cashier UI
- [ ] Add sync-state UI
- [ ] Add automated tests
- [ ] Complete manual multi-device QA

## Decisions

...

## Residual Risks

...

## Verification Log

### YYYY-MM-DD

Commands run:
Results:
Manual QA:
Remaining issues:
```

Do not guess the current root cause. Trace and document it.

---

# 3. Required Architecture

## 3.1 Hub-and-spoke topology

Use:

```text
Main device
├── Cashier A
├── Cashier B
└── Cashier C
```

Cashiers must not communicate directly with one another.

All canonical mutations occur on the Main device.

## 3.2 Main device owns full state

The Main device stores:

```text
- Full inventory records
- Complete sales history
- Complete restock history
- Product costs
- Margins
- Supplier information if supported
- Reports
- Backup and restore data
- Paired-device registry
- Cashier-projection version
- Processed Cashier sale-command IDs
```

## 3.3 Cashier devices receive a restricted read model

Cashiers store only:

```text
- Checkout-safe inventory projection
- Last applied Cashier-projection version
- Their own paired-device credential
- Their own device ID
- Their own initiated sale history if required by the current UI
```

Cashier inventory is a local read-only cache.

It is not an authoritative inventory database.

---

# 4. Replace Full Inventory Replication with a Cashier-Safe Projection

## 4.1 Problem

Do not synchronize complete product records to Cashiers and merely hide private fields in the UI.

A compromised or modified Cashier client could inspect the payload directly.

## 4.2 Create an explicit projection model

Add an explicit Cashier-safe product model.

Adapt names and field types to the repository conventions.

Conceptually:

```dart
class CashierProductProjection {
  final String id;
  final String barcode;
  final String name;
  final num stockQuantity;
  final num salePrice;
  final bool isActive;

  const CashierProductProjection({
    required this.id,
    required this.barcode,
    required this.name,
    required this.stockQuantity,
    required this.salePrice,
    required this.isActive,
  });
}
```

Include only fields demonstrably required for checkout.

## 4.3 Allowed Cashier fields

A Cashier may receive:

```text
- Product ID
- Barcode
- Product name
- Available stock quantity
- Sale price
- Active or archived state
```

## 4.4 Forbidden Cashier fields

A Cashier must not receive:

```text
- Purchase cost
- Gross profit
- Gross margin
- Inventory valuation
- Supplier name
- Supplier ID
- Internal notes
- Full sales history
- Full restock history
- Other Cashier identities
- Backup metadata
- Administrative flags
- Internal database columns
- Pairing secrets belonging to another device
```

## 4.5 Use dedicated serialization

Create dedicated serialization functions.

Conceptually:

```dart
Map<String, Object?> serializeCashierProduct(
  Product product,
) {
  return {
    'id': product.id,
    'barcode': product.barcode,
    'name': product.name,
    'stockQuantity': product.stockQuantity,
    'salePrice': product.salePrice,
    'isActive': product.isActive,
  };
}
```

Do not reuse an administrative product serializer accidentally.

Add tests proving restricted fields never appear in Cashier snapshots or WebSocket messages.

---

# 5. Use a Projection-Specific Version Counter

## 5.1 Do not use a broad global domain revision

Cashiers do not receive every Main-device mutation.

Example:

```text
Owner changes purchase cost:
  Cashier must not receive this data.

Owner changes product name:
  Cashier must receive this change.
```

If Cashier synchronization uses a revision that increments for private changes, Cashiers will detect false gaps.

## 5.2 Add Cashier projection version

Persist on the Main device:

```text
cashierInventoryProjectionVersion
```

Persist on each Cashier:

```text
lastAppliedCashierProjectionVersion
```

Use integer values:

```text
1, 2, 3, 4, ...
```

The Main version must survive application restarts.

The Cashier cursor must survive application restarts.

## 5.3 Increment only when Cashier-visible state changes

| Main mutation                | Increment projection version? |             Push update? |
| ---------------------------- | ----------------------------: | -----------------------: |
| Create product               |                           Yes |                      Yes |
| Rename product               |                           Yes |                      Yes |
| Change barcode               |                           Yes |                      Yes |
| Change sale price            |                           Yes |                      Yes |
| Change stock quantity        |                           Yes |                      Yes |
| Archive or delete product    |                           Yes |                      Yes |
| Complete sale                |                           Yes |                      Yes |
| Record restock               |                           Yes |                      Yes |
| Manual stock adjustment      |                           Yes |                      Yes |
| Change purchase cost only    |                            No |                       No |
| Change supplier details only |                            No |                       No |
| Generate report              |                            No |                       No |
| Create backup                |                            No |                       No |
| Restore backup               |                           Yes | Push `snapshot_required` |

If a product edit contains both visible and private changes:

```text
- Persist all changes on Main.
- Increment the Cashier projection version once.
- Broadcast only the sanitized visible projection.
```

## 5.4 Serialize version allocation

Two concurrent Main mutations must not receive the same projection version or broadcast out of order.

Use the smallest safe mechanism supported by the existing architecture:

```text
- Database transaction
- Serialized mutation queue
- Mutex around version allocation and committed publication
- Existing repository transaction abstraction
```

Required guarantee:

```text
For Cashier-visible mutations:
  commit order == projection-version order == broadcast order
```

Do not introduce a distributed coordination system.

---

# 6. Centralize Replicated Mutation Publishing

## 6.1 Fix the original architectural flaw

Main-device product edits must not write directly to the database while bypassing synchronization.

Create or refine one Main-side application-layer path for any mutation that may change the Cashier projection.

Suggested conceptual interface:

```dart
abstract interface class CashierProjectionPublisher {
  Future<T> executeReplicatedMutation<T>({
    required Future<T> Function() persistMutation,
    required CashierProjectionUpdate? Function(T result) buildUpdate,
  });
}
```

Alternative naming is acceptable if it fits the repository.

## 6.2 Required ordering

For each Cashier-visible mutation:

```text
authenticate and authorize if remote
→ validate mutation
→ begin database transaction
→ apply full Main-domain mutation
→ increment and persist Cashier projection version
→ commit database transaction
→ construct sanitized Cashier projection update
→ broadcast update
→ return success
```

Never broadcast before persistence commits.

## 6.3 Broadcast failure after commit

If Cashier broadcasting fails:

```text
- Keep the committed Main mutation.
- Do not roll back a completed sale.
- Do not roll back a completed restock.
- Mark disconnected Cashiers as behind implicitly.
- Repair through full snapshot on reconnect.
```

Do not build durable replay logs in this version.

---

# 7. Use Sanitized Projection Updates

## 7.1 Do not broadcast rich business events to Cashiers

Cashiers do not need complete domain details such as:

```text
- Restock costs
- Supplier details
- Another Cashier's full sale
- Another Cashier's identity
- Margin calculations
- Reason for every stock change
```

Broadcast only enough information to keep checkout inventory accurate.

## 7.2 Common message envelope

Use:

```json
{
  "projectionVersion": 47,
  "type": "inventory_patch",
  "payload": {}
}
```

All pushed Cashier synchronization messages must include:

```text
- projectionVersion
- type
- payload
```

## 7.3 Product upsert

Use after:

```text
- Product creation
- Product rename
- Barcode change
- Sale-price change
- Other checkout-visible product edit
```

Example:

```json
{
  "projectionVersion": 47,
  "type": "product_upsert",
  "payload": {
    "product": {
      "id": "product-123",
      "barcode": "123456789",
      "name": "Smartphone",
      "stockQuantity": 9,
      "salePrice": 2200,
      "isActive": true
    }
  }
}
```

## 7.4 Product archived

Use after archival or deletion:

```json
{
  "projectionVersion": 48,
  "type": "product_archived",
  "payload": {
    "productId": "product-123"
  }
}
```

Respect existing soft-delete or hard-delete semantics. Do not invent a new deletion model.

## 7.5 Inventory patch

Use after:

```text
- Sale
- Restock
- Manual inventory correction
```

Example:

```json
{
  "projectionVersion": 49,
  "type": "inventory_patch",
  "payload": {
    "products": [
      {
        "productId": "product-123",
        "stockQuantity": 8
      }
    ]
  }
}
```

Send resulting canonical stock quantities.

Do not ask Cashiers to calculate canonical stock independently.

## 7.6 Snapshot required

Use after backup restore or whenever incremental synchronization is unsafe:

```json
{
  "projectionVersion": 50,
  "type": "snapshot_required",
  "payload": {
    "reason": "backup_restored"
  }
}
```

Cashiers must fetch a fresh snapshot.

---

# 8. Cashier-Safe Snapshot

## 8.1 Add or refine snapshot endpoint

Use the existing routing style.

Suggested endpoint:

```text
GET /cashier/inventory-snapshot
```

Equivalent naming is acceptable if it matches repository conventions.

## 8.2 Snapshot response

Return:

```json
{
  "projectionVersion": 50,
  "products": [
    {
      "id": "product-123",
      "barcode": "123456789",
      "name": "Smartphone",
      "stockQuantity": 8,
      "salePrice": 2200,
      "isActive": true
    }
  ]
}
```

Do not include privileged product fields.

## 8.3 Atomic Main-side snapshot generation

Generate a snapshot that is internally consistent with its version.

Required property:

```text
Every product in snapshot corresponds to snapshot.projectionVersion.
```

Use the existing database transaction or read-isolation mechanism where available.

Do not return products read at one state with a version read from another state.

## 8.4 Transactional Cashier snapshot application

On Cashier:

```text
validate snapshot
→ begin local database transaction
→ replace Cashier inventory cache
→ persist lastAppliedCashierProjectionVersion
→ commit transaction
→ notify UI state
```

Do not partially apply snapshots.

---

# 9. Handle Snapshot and Push Races Safely

A WebSocket update may arrive while a snapshot is being fetched or applied.

Implement a small Cashier-side reconciliation controller.

## 9.1 Cashier sync states

Use an explicit state model:

```dart
enum CashierSyncState {
  connecting,
  syncing,
  synchronized,
  offline,
  error,
}
```

Adapt naming if an equivalent already exists.

## 9.2 During snapshot synchronization

While snapshot application is in progress:

```text
- Set state to syncing.
- Disable Cashier sale submission.
- Queue incoming projection updates temporarily.
- Apply snapshot transactionally.
- Inspect queued updates in version order.
```

After snapshot application:

```text
If queued updates are contiguous:
  apply them in order

If queued updates contain a gap:
  discard queued updates
  fetch a fresh snapshot again
```

Keep the queue bounded.

If repeated churn prevents stable convergence:

```text
- Refetch snapshot
- Remain in syncing state
- Report a controlled sync error after a bounded number of retries
```

Do not create an unbounded in-memory event log.

---

# 10. Connect, Reconnect, Resume, and Gap Repair

## 10.1 Initial connection

Use:

```text
Cashier connects to Main
→ authenticate paired Cashier
→ establish WebSocket
→ set state to syncing
→ fetch Cashier-safe snapshot
→ apply snapshot transactionally
→ process queued contiguous updates
→ set state to synchronized
```

Fetching a snapshot on every new connection is acceptable for this version.

## 10.2 Reconnect

Use:

```text
Cashier detects disconnection
→ set state to offline
→ disable sale submission
→ preserve cached inventory for browsing
→ reconnect
→ fetch fresh snapshot
→ converge
→ set state to synchronized
```

## 10.3 App resume

When the Cashier app returns to the foreground:

```text
- Verify WebSocket connection.
- Set state to syncing.
- Fetch a fresh Cashier-safe snapshot.
- Replace local cache transactionally.
- Resume sale submission only after convergence.
```

Use the project's existing lifecycle handling if present. Otherwise, add the smallest Flutter lifecycle listener compatible with the existing architecture.

## 10.4 Duplicate pushed update

When:

```text
incomingVersion <= lastAppliedVersion
```

ignore the update safely.

## 10.5 Contiguous pushed update

When:

```text
incomingVersion == lastAppliedVersion + 1
```

apply the sanitized delta transactionally and persist the new cursor.

## 10.6 Revision gap

When:

```text
incomingVersion > lastAppliedVersion + 1
```

do not apply the delta blindly.

Use:

```text
set state to syncing
→ fetch full snapshot
→ replace cache
→ resume synchronized mode
```

Do not implement replay logs.

---

# 11. Authenticate Paired Cashier Devices

## 11.1 Reuse existing pairing

Inspect the current QR pairing flow.

If it already creates a trusted Cashier credential, reuse it.

Do not replace functional pairing code unnecessarily.

## 11.2 Add smallest missing credential layer

If the existing pairing mechanism does not authenticate requests adequately, add the smallest safe extension:

```text
- Main generates a high-entropy Cashier pairing credential
- Main stores credential association with paired device record
- Cashier stores only its own credential
- Cashier sends credential for HTTP requests
- Cashier authenticates its WebSocket connection
- Main rejects unpaired devices
- Main rejects removed devices
```

Do not build certificate infrastructure, PKI, IAM, or cloud key management.

## 11.3 Derive identity from trusted context

Do not trust client-supplied values such as:

```text
deviceId
role
isAdmin
permissions
canRestock
canViewReports
originDeviceId
```

The Main device must derive effective identity from:

```text
authenticated pairing credential
→ Main-side paired-device record
→ restricted Cashier principal
```

A remote paired device is always:

```text
DeviceRole.cashier
```

A remote device must never become:

```text
DeviceRole.mainAdmin
```

## 11.4 Remove device

When Owner removes a Cashier on the Main device:

```text
- Invalidate credential
- Close active Cashier WebSocket when practical
- Reject future HTTP requests
- Reject future WebSocket connections
```

---

# 12. Authorize Cashier Requests on Main

## 12.1 Use minimal static roles

Use:

```dart
enum DeviceRole {
  mainAdmin,
  cashier,
}
```

No role editor.

No dynamic role management.

## 12.2 Use minimal capabilities

Use:

```dart
enum Capability {
  recordSale,
  viewCashierInventory,
  viewOwnSales,

  recordRestock,
  createProduct,
  modifyProduct,
  archiveProduct,
  adjustInventory,
  viewReports,
  viewAllSales,
  viewAllRestocks,
  manageDevices,
  createBackup,
  restoreBackup,
  exportData,
}
```

Adapt names to repository style.

## 12.3 Static deny-by-default policy

Conceptually:

```dart
const capabilitiesByRole = <DeviceRole, Set<Capability>>{
  DeviceRole.mainAdmin: {
    Capability.recordSale,
    Capability.viewCashierInventory,
    Capability.viewOwnSales,
    Capability.recordRestock,
    Capability.createProduct,
    Capability.modifyProduct,
    Capability.archiveProduct,
    Capability.adjustInventory,
    Capability.viewReports,
    Capability.viewAllSales,
    Capability.viewAllRestocks,
    Capability.manageDevices,
    Capability.createBackup,
    Capability.restoreBackup,
    Capability.exportData,
  },

  DeviceRole.cashier: {
    Capability.recordSale,
    Capability.viewCashierInventory,
    Capability.viewOwnSales,
  },
};
```

Unknown roles, unknown operations, unknown routes, and unpaired devices must be denied.

## 12.4 Centralize enforcement

Use a small service:

```dart
abstract interface class AuthorizationService {
  void requireCapability({
    required DevicePrincipal principal,
    required Capability capability,
  });
}
```

## 12.5 Enforce before side effects

Required ordering for every remote request:

```text
authenticate paired device
→ derive trusted Cashier principal
→ authorize capability
→ validate payload
→ deduplicate command where applicable
→ mutate database
→ advance projection version if needed
→ commit
→ broadcast sanitized update
```

Unauthorized operations must cause:

```text
- No database mutation
- No projection-version increment
- No broadcast
- No history insertion
```

## 12.6 Stable denial response

For HTTP:

```text
403 Forbidden
```

For WebSocket or command channels:

```json
{
  "type": "command_rejected",
  "errorCode": "permission_denied",
  "userMessage": "You do not have permission to perform this action."
}
```

Do not expose stack traces.

---

# 13. Cashier API Surface

Expose only what Cashiers require.

## 13.1 Allowed endpoints

Use equivalent routes if the project already has conventions:

```text
GET  /cashier/inventory-snapshot
GET  /cashier/my-sales
POST /cashier/sales
WS   /cashier/sync
```

Each endpoint must authenticate the paired Cashier.

## 13.2 Main-only operations

Keep these local to the Main application where practical:

```text
- Restock
- Product creation
- Product rename
- Barcode modification
- Price modification
- Product archival
- Manual stock adjustment
- Reports
- Full histories
- Pairing
- Device removal
- Backup
- Restore
- Export
```

If remote handlers already exist, keep them only when needed and enforce Main-side denial for Cashiers.

---

# 14. Cashier Sale Command and Retry Safety

## 14.1 Cashier may submit sales only

Cashier request:

```json
{
  "commandId": "7f0d2c51-bfd0-40eb-b087-80f9d8f924a2",
  "type": "create_sale",
  "payload": {
    "items": [
      {
        "productId": "product-123",
        "quantity": 1
      }
    ]
  }
}
```

Do not trust a client-supplied `originDeviceId`.

Derive Cashier identity from the authenticated pairing context.

## 14.2 Main sale flow

Use:

```text
authenticate paired Cashier
→ authorize recordSale
→ validate sale
→ deduplicate commandId
→ begin database transaction
→ persist canonical sale
→ update canonical inventory
→ persist processed command ID
→ advance Cashier projection version
→ commit
→ respond to initiating Cashier with its sale result
→ broadcast sanitized inventory_patch to all connected Cashiers
```

## 14.3 Deduplicate retries

A Cashier may retry because:

```text
- Request timeout
- Wi-Fi interruption
- App restart
- Lost acknowledgement
```

Persist enough information to recognize processed `commandId` values.

When the same command arrives again:

```text
- Do not create a second sale
- Do not decrement stock twice
- Return the previous canonical result or stable duplicate acknowledgement
```

## 14.4 Initiating Cashier response

Return only the initiating Cashier's sale result:

```json
{
  "status": "accepted",
  "sale": {
    "id": "sale-991",
    "createdAt": "2026-06-06T12:00:00Z",
    "items": [
      {
        "productId": "product-123",
        "quantity": 1,
        "salePrice": 2200
      }
    ]
  }
}
```

Other Cashiers receive only:

```json
{
  "projectionVersion": 49,
  "type": "inventory_patch",
  "payload": {
    "products": [
      {
        "productId": "product-123",
        "stockQuantity": 8
      }
    ]
  }
}
```

Do not broadcast one Cashier's full sale details to every Cashier.

---

# 15. Main-Only Restock Flow

Cashiers must not restock.

Owner records restock locally on Main:

```text
Owner records restock on Main
→ validate
→ begin transaction
→ persist canonical restock history
→ update canonical stock
→ advance Cashier projection version
→ commit
→ broadcast sanitized inventory_patch
```

Cashiers receive only resulting stock quantities.

They do not receive:

```text
- Purchase cost
- Supplier
- Restock record
- Owner identity
- Restock notes
```

If a Cashier manually attempts a restock request:

```text
reject permission_denied
→ no database mutation
→ no projection-version increment
→ no broadcast
```

---

# 16. Main Product Mutation Flow

Owner product edits occur locally on Main.

Use:

```text
Owner edits product
→ persist full Main record
→ determine whether Cashier-visible fields changed
```

If Cashier-visible fields changed:

```text
advance projection version
→ commit
→ broadcast sanitized product_upsert
```

If only private fields changed:

```text
commit Main record
→ do not advance projection version
→ do not broadcast
```

This must fix the original product-name propagation defect.

---

# 17. Backup Restore

## 17.1 Keep sync metadata separate

Do not allow restoring an old business backup to move the projection version backwards.

Store sync metadata separately from business backup contents where practical:

```text
- Cashier projection version
- Paired-device registry
- Active Cashier credentials
- Processed command IDs where appropriate
```

Inspect current backup behavior before modifying it.

Document the chosen compatibility behavior.

## 17.2 After successful restore

Use:

```text
restore canonical business data
→ safely advance Cashier projection version
→ commit restore
→ broadcast snapshot_required
→ connected Cashiers fetch new Cashier-safe snapshot
```

Do not broadcast hundreds of individual deltas.

---

# 18. Offline Behavior

Do not implement offline Cashier sales.

When Cashier loses Main connection:

```text
- Preserve cached inventory for browsing
- Mark cached inventory as potentially stale
- Disable Complete Sale
- Disable product mutations
- Attempt reconnect
```

Display:

```text
This cashier is offline.
Inventory may be outdated.
Reconnect to the Main device to continue.
```

When synchronization is in progress:

```text
- Disable Complete Sale
- Show syncing banner
```

Display:

```text
Syncing latest inventory…
```

When synchronized:

```text
- Keep UI quiet
- Enable sale submission
```

---

# 19. Cashier UI Restrictions

## 19.1 Main navigation

Main retains:

```text
Sell
Restock
Inventory
Reports
Settings
```

## 19.2 Cashier navigation

Cashier shows:

```text
Sell
Inventory
My Sales
```

If a dedicated My Sales screen does not exist, add the smallest read-only implementation or preserve an existing own-history route.

Do not show:

```text
Restock
Reports
Administrative Settings
Backup and Restore
Pairing controls
```

## 19.3 Cashier Inventory

Cashier Inventory is read-only.

Allow:

```text
- Search
- Scan
- Product name
- Barcode where useful
- Sale price
- Available stock
```

Hide:

```text
- Add Product
- Edit Product
- Delete Product
- Archive Product
- Manual stock adjustment
- Purchase cost
- Supplier data
```

## 19.4 Unknown barcode on Cashier

Show:

```text
Product not found.

Ask the store owner to add this product on the Main device.
```

Do not offer Create New Product on Cashier.

## 19.5 Own sales only

Cashier may view transactions initiated by its own paired device.

Main derives Cashier identity from trusted pairing context.

Do not trust query parameters requesting another device's history.

---

# 20. Lightweight Denial Logging

Do not build an audit platform.

Log restricted remote attempts locally on Main using the existing logging approach.

Record:

```text
timestamp
paired device ID
requested operation
result = permission_denied
```

Do not log:

```text
pairing secret
credential
sensitive payload values
```

If persistent logging requires invasive schema changes, use structured application logs and document the limitation.

---

# 21. Database Migration

Add the smallest safe migration needed.

## 21.1 Main-side metadata

Persist:

```text
cashierInventoryProjectionVersion
processedCashierSaleCommands
paired Cashier credentials if missing
```

## 21.2 Cashier-side metadata

Persist:

```text
lastAppliedCashierProjectionVersion
own device ID if missing
own pairing credential if missing
```

## 21.3 Migration requirements

```text
- Preserve existing inventory
- Preserve existing sale history
- Preserve existing restock history
- Preserve backup format unless justified
- Initialize new metadata safely
- Keep migration idempotent
- Support fresh installations
- Support existing installations
```

Document migration decisions.

---

# 22. Automated Tests

Use repository conventions.

Add unit, repository, protocol, and widget tests where appropriate.

## 22.1 Root-cause regression: Main rename reaches Cashier

```text
Given:
- Main and Cashier A are connected
- Product P exists on both

When:
- Owner renames Product P on Main

Then:
- Main commits the rename
- Main advances Cashier projection version
- Main broadcasts product_upsert
- Cashier A applies the update immediately
- Cashier A persists the new projection version
- Cashier A UI shows the new name without manual refresh
```

## 22.2 Private Main product edit does not leak

```text
Given Product P exists
When Owner changes purchase cost only
Then:
- Main persists the private change
- Cashier projection version does not advance
- No Cashier broadcast occurs
```

## 22.3 Product projection redaction

```text
Given Main product contains:
- sale price
- purchase cost
- margin
- supplier
- internal notes

When Cashier fetches inventory snapshot

Then:
- snapshot contains sale price
- snapshot excludes purchase cost
- snapshot excludes margin
- snapshot excludes supplier
- snapshot excludes internal notes
```

## 22.4 WebSocket projection redaction

```text
When Main broadcasts:
- product_upsert
- inventory_patch

Then:
- messages include only Cashier-safe fields
- messages exclude privileged fields
```

## 22.5 Main restock patches stock without leaking details

```text
Given Product P stock is 10
When Owner records restock quantity 5 on Main
Then:
- Main stores full restock record
- Main stock becomes 15
- Main advances Cashier projection version
- Cashiers receive stockQuantity = 15
- Cashiers do not receive restock cost or supplier
```

## 22.6 Cashier can submit sale

```text
Given:
- Cashier A is paired and connected
- Product P stock is 10

When:
- Cashier A submits sale quantity 1

Then:
- Main authenticates Cashier A
- Main authorizes recordSale
- Main persists sale
- Main stock becomes 9
- Main advances projection version
- Cashier A receives own sale result
- All Cashiers receive sanitized stock patch
```

## 22.7 Cashier sale retry is idempotent

```text
Given Cashier A submits sale commandId X
When Cashier A submits commandId X twice
Then:
- one sale exists
- stock decrements once
- one projection-version increment occurs
- duplicate returns previous result or stable duplicate acknowledgement
```

## 22.8 Cashier cannot restock

```text
When paired Cashier submits restock request
Then:
- Main returns permission_denied
- no restock exists
- stock remains unchanged
- projection version remains unchanged
- no broadcast occurs
```

## 22.9 Cashier cannot mutate products

Test:

```text
create product
rename product
change price
archive product
adjust inventory
```

Expected:

```text
permission_denied
no side effects
```

## 22.10 Cashier cannot access reports

```text
When Cashier calls report route
Then:
- Main returns 403 or permission_denied
- no report payload is returned
```

## 22.11 Cashier cannot access another Cashier's history

```text
Given:
- Cashier A created Sale A
- Cashier B created Sale B

When:
- Cashier A manipulates query parameters to request Cashier B history

Then:
- Main derives identity from Cashier A pairing context
- Main returns only Sale A
```

## 22.12 Role spoofing fails

```text
When Cashier sends:
- role = mainAdmin
- isAdmin = true
- canRestock = true
- forged originDeviceId

Then:
- Main ignores client claims
- Main derives Cashier role from pairing context
- restricted operations remain denied
```

## 22.13 Unpaired device denied

```text
When unknown device:
- fetches snapshot
- opens Cashier WebSocket
- submits sale

Then:
- Main rejects access
```

## 22.14 Removed device denied

```text
Given Cashier A was paired
When Owner removes Cashier A
Then:
- active WebSocket closes when practical
- future requests fail
- reconnect fails
```

## 22.15 Initial snapshot convergence

```text
When Cashier connects
Then:
- Cashier enters syncing state
- snapshot is fetched
- local cache is replaced transactionally
- projection cursor is persisted
- Cashier enters synchronized state
```

## 22.16 Reconnect snapshot repair

```text
Given:
- Cashier A disconnects
- Owner renames Product P
- Owner restocks Product P

When:
- Cashier A reconnects

Then:
- Cashier A fetches fresh snapshot
- Product name converges
- Stock converges
```

## 22.17 Gap detection

```text
Given Cashier last applied version 40
When Cashier receives version 42
Then:
- Cashier does not apply patch blindly
- Cashier fetches snapshot
- Cashier converges
```

## 22.18 Duplicate projection update

```text
Given Cashier applied version 42
When Cashier receives version 42 again
Then:
- update is ignored
- stock does not change twice
```

## 22.19 Snapshot and push race

```text
Given Cashier is applying snapshot version 50
When update version 51 arrives
Then:
- update is queued
- snapshot applies transactionally
- update 51 applies afterward
- Cashier converges to 51
```

Test gap variant:

```text
Given snapshot version 50
When queued update version 52 arrives without 51
Then:
- Cashier fetches fresh snapshot
- Cashier does not apply 52 blindly
```

## 22.20 App resume repair

```text
Given Cashier app resumes
Then:
- Cashier enters syncing state
- fresh snapshot is fetched
- sale action remains disabled until synchronization succeeds
```

## 22.21 Main restart preserves monotonic version

```text
Given Main persisted projection version 90
When Main restarts
And Owner renames product
Then:
- new mutation receives version 91
```

## 22.22 Backup restore forces snapshot

```text
Given Main restores backup
Then:
- projection version safely advances
- Main broadcasts snapshot_required
- Cashiers fetch fresh snapshots
- projection version never moves backward
```

## 22.23 Cashier UI restrictions

```text
Given app runs as Cashier
Then:
- Sell is visible
- read-only Inventory is visible
- My Sales is visible if supported
- Restock is absent
- Reports is absent
- Add Product is absent
- Edit Product is absent
- Backup is absent
- Restore is absent
- Pairing controls are absent
```

## 22.24 Main UI remains complete

```text
Given app runs as Main
Then:
- Sell is visible
- Restock is visible
- editable Inventory is visible
- Reports is visible
- Settings is visible
- Device Sync is visible
- Backup and Restore are visible
```

---

# 23. Manual Multi-Device QA

Run manual QA with:

```text
1 Main device
2 Cashier devices
Same local Wi-Fi network
```

Record actual findings.

## 23.1 Main product edit

```text
- Rename product on Main
- Change sale price on Main
- Add product on Main
- Archive product on Main if supported
```

Expected:

```text
Both Cashiers update without manual refresh.
```

## 23.2 Private field edit

```text
- Change purchase cost on Main
```

Expected:

```text
Cashier receives no private field.
No unnecessary Cashier refresh occurs.
```

## 23.3 Main restock

```text
- Record restock on Main
```

Expected:

```text
Cashier stock quantities update immediately.
Restock cost and details remain private.
```

## 23.4 Cashier sale

```text
- Record sale from Cashier A
```

Expected:

```text
- Main stores complete sale
- Main inventory updates
- Cashier A inventory updates
- Cashier B inventory updates
- Cashier A sees own sale
- Cashier B does not see Cashier A sale details
```

## 23.5 Restricted actions

Attempt from Cashier:

```text
- Restock
- Product creation
- Product rename
- Price edit
- Inventory adjustment
- Reports
- Backup
- Restore
- Pairing
```

Expected:

```text
- UI does not expose actions
- Crafted requests receive permission_denied
- No state mutation occurs
```

## 23.6 Reconnect

```text
- Disconnect Cashier A
- Rename product on Main
- Restock product on Main
- Sell product from Cashier B
- Reconnect Cashier A
```

Expected:

```text
Cashier A fetches snapshot and converges automatically.
```

## 23.7 Restart

```text
- Restart Cashier A
- Restart Main
- Perform new Main product edit
```

Expected:

```text
- Cashier resynchronizes
- Projection version remains monotonic
```

## 23.8 Removed Cashier

```text
- Pair Cashier A
- Remove Cashier A from Main
- Attempt reconnect
```

Expected:

```text
Cashier A is rejected.
```

---

# 24. Implementation Phases

Proceed sequentially.

Do not move to a later phase while earlier tests fail.

## Phase 1: Inspect, trace, and model projection

Implement:

```text
- Inspect existing sync and access-control paths
- Record verified root cause of rename failure
- Add CashierProductProjection
- Add dedicated sanitized serializer
- Add serializer redaction tests
```

## Phase 2: Projection version and Main publishing path

Implement:

```text
- Persist Main Cashier-projection version
- Persist Cashier cursor
- Route replicated Main changes through publishing path
- Serialize projection-version allocation
- Broadcast sanitized product_upsert
- Fix Main rename propagation
- Add regression tests
```

## Phase 3: Snapshot reconciliation

Implement:

```text
- Cashier-safe snapshot endpoint
- Transactional snapshot generation
- Transactional Cashier cache replacement
- Snapshot on connection
- Snapshot on reconnect
- Snapshot on app resume
- Gap detection
- Duplicate update handling
- Snapshot-and-push race handling
- Tests
```

## Phase 4: Paired Cashier authentication and authorization

Implement:

```text
- Reuse or minimally extend pairing credentials
- Authenticate Cashier HTTP requests
- Authenticate Cashier WebSocket
- Derive identity from trusted pairing context
- Reject unpaired devices
- Reject removed devices
- Add static deny-by-default capabilities
- Deny Cashier privileged operations
- Add tests
```

## Phase 5: Sale-only Cashier command

Implement:

```text
- Allow authenticated Cashier sale submission
- Add commandId
- Persist sale-command deduplication
- Return own sale result to initiator
- Broadcast only sanitized stock patch
- Add retry-safety tests
```

## Phase 6: Main restock, restore repair, and UI restrictions

Implement:

```text
- Main-only restock stock patches
- Restore snapshot_required behavior
- Offline and syncing UI
- Cashier role-specific navigation
- Cashier read-only Inventory
- Cashier own-sales screen if supported
- Hide restricted actions
- Add widget tests
```

## Phase 7: QA and documentation

Implement:

```text
- Lightweight denied-operation logs
- Run full automated tests
- Run manual multi-device QA
- Update task ledger
- Document residual risks
```

If existing architecture conflicts with a requirement, stop and report the conflict instead of silently inventing a workaround.

---

# 25. Validation Commands

Run:

```bash
dart format .
flutter analyze
flutter test
```

Run any existing integration-test commands.

Run the application on Android devices or emulators when available.

Report commands actually executed and their results.

Do not claim manual verification unless performed.

---

# 26. Completion Criteria

The task is complete only when:

```text
1. Main remains the sole authoritative device.
2. Cashiers remain restricted paired clients.
3. Cashiers receive only checkout-safe inventory projections.
4. Private product fields never appear in Cashier snapshots.
5. Private product fields never appear in Cashier WebSocket updates.
6. Main product rename reaches connected Cashiers immediately.
7. Main product creation, visible edits, and archival propagate safely.
8. Main restock updates Cashier stock without leaking restock details.
9. Cashier sale updates stock on Main and all connected Cashiers.
10. Cashier receives only its own sale result.
11. Other Cashiers receive sanitized stock patches only.
12. Cashier projection version advances only for Cashier-visible changes.
13. Projection version remains monotonic across Main restart.
14. Cashier cursor persists across Cashier restart.
15. Snapshot repair works after connect, reconnect, resume, and version gaps.
16. Snapshot and push races converge safely.
17. Cashier HTTP requests are authenticated.
18. Cashier WebSocket connections are authenticated.
19. Cashier identity is derived from Main-side pairing context.
20. Client-supplied roles and device identities are not trusted.
21. Unpaired and removed devices are rejected.
22. Cashier sale retries do not duplicate sales.
23. Cashier cannot restock.
24. Cashier cannot mutate products.
25. Cashier cannot adjust stock.
26. Cashier cannot access reports.
27. Cashier cannot access administrative settings.
28. Cashier UI hides irrelevant restricted workflows.
29. Cashier cannot submit sales while offline or synchronizing.
30. Restore triggers fresh Cashier snapshots.
31. No replay log, multi-master, peer-to-peer, or enterprise IAM complexity is added.
32. Automated tests pass.
33. Manual QA findings and residual risks are documented accurately.
```

---

# 27. Final Report Format

After implementation, report:

## Verified Previous Root Cause

Explain why Main product edits previously failed to propagate.

## Architecture Implemented

Summarize:

```text
- Authoritative Main device
- Restricted paired Cashiers
- Cashier-safe inventory projection
- Projection-specific version
- Sanitized WebSocket updates
- Snapshot reconciliation
- Sale-only Cashier commands
- Main-side authorization
```

## Changed Files

List modified files and responsibilities.

## Data Migration

Explain:

```text
- Projection-version storage
- Cashier cursor storage
- Sale-command deduplication storage
- Pairing-credential changes
- Backup compatibility
```

## Data Exposure Review

List:

```text
- Fields Cashiers receive
- Fields Cashiers do not receive
```

## Tests Added or Updated

List automated tests.

## Commands Run

Report actual results:

```bash
dart format .
flutter analyze
flutter test
```

## Manual QA

State exactly which multi-device scenarios were tested.

## Residual Risks

State clearly:

```text
- Main-device physical access remains trusted
- Authorization remains device-scoped, not employee-scoped
- Plain LAN transport may expose traffic if encryption is not implemented
- Per-employee accountability is not implemented
- Manager approval workflows are not implemented
- Offline Cashier sales are intentionally unsupported
```

Do not claim stronger guarantees than the implementation and tests establish.
