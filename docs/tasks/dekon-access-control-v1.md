# Task: Enforce Minimal Cashier Access Controls in Dekon

## Verified Findings - 2026-06-06

- This task documentation is stored at `docs/tasks/dekon-access-control-v1.md`; the initial prompt-provided source was at the repository root.
- The app uses local Flutter state (`StatefulWidget`, `FutureBuilder`, `IndexedStack`) with repository injection through `AppShell`.
- Local device role state is stored in `app_settings` as `device_role`, `device_role_locked`, and `device_onboarding_completed`; cashier role is locked only after `CashierPairingPanel` completes pairing.
- The main LAN server exposes `GET /health`, `GET /device`, `POST /pair`, `GET /events`, `POST /events`, and `GET /sync/state`.
- Pairing stores trusted peers in `devices` and `sync_peers`; requests authenticate with `x-dekon-device-id` plus HMAC headers over method, path/query, timestamp, and body hash.
- Before this fix, authenticated remote peers could submit any supported event type through `POST /events`; the server did not restrict cashier peers to sale events.
- Before this fix, `POST /events` did not bind the posted event `device_id` to the authenticated peer identity, so a modified client could attempt device-ID spoofing.
- Before this fix, `GET /events` returned full event payloads to paired cashiers, including product `purchase_cost_minor` and restock `unit_cost_minor` values.
- There are no separate remote report, backup, restore, product, or settings HTTP endpoints in this version; those administrative operations are local Flutter/repository flows plus sync event exchange.

## Goal

Restrict Cashier devices to the minimum capabilities required for checkout.

Do not introduce an enterprise identity or access-management system.

Implement a deliberately small authorization model:

```text
Main device:
  Trusted administrative device
  Full local access

Cashier device:
  Paired remote client
  Restricted access
```

A Cashier may:

```text
- Sell products
- Scan and search products
- View a read-only Cashier-safe inventory projection
- View available stock quantity
- View sale price
- View transactions initiated by that Cashier device
```

A Cashier must not:

```text
- Restock inventory
- Create products
- Rename products
- Change barcodes
- Change prices
- View purchase cost
- View gross profit or gross margin
- View reports
- View store-wide sales or restock histories
- Modify inventory
- Manually adjust stock
- Delete or archive products
- Pair or remove devices
- Change synchronization settings
- Export data
- Create backups
- Restore backups
```

Enforce these restrictions on the Main device for every remote request.

Do not rely only on hiding UI controls.

---

# 1. Scope Constraints

## 1.1 Keep the solution intentionally small

Do not implement:

```text
- Staff accounts
- Employee directories
- OAuth
- OpenID Connect
- JWT-based enterprise authentication
- Cloud identity providers
- External authorization services
- Configurable role editors
- Permission-management dashboards
- Per-resource ACLs
- Attribute-based policy engines
- Manager roles
- Stock-clerk roles
- Per-employee PIN login
- Shift management
- Manager override flows
- Complex audit dashboards
```

These may become future requirements, but they are out of scope.

## 1.2 Use two internal roles only

Model:

```dart
enum DeviceRole {
  mainAdmin,
  cashier,
}
```

The Main device operates locally as:

```text
mainAdmin
```

Every remote paired client operates as:

```text
cashier
```

Do not allow a remote device to become `mainAdmin` in this version.

Do not add a role-selection UI.

## 1.3 Device-scoped authorization

This version authorizes paired devices, not individual employees.

Residual risk:

```text
Anyone with physical access to an unlocked Main device can perform
administrative actions.
```

Document this clearly. Do not silently solve it by introducing a staff-account system.

If the app already has an Owner PIN or local lock-screen mechanism, preserve and reuse it. Do not add a new PIN subsystem as part of this task.

---

# 2. Inspect the Existing Architecture First

Before modifying code:

1. Read:

```text
AGENTS.md
README.md
pubspec.yaml
docs/tasks/dekon-sync-v1.md
existing files under docs/tasks/
```

2. Run:

```bash
git status --short
find lib -type f | sort
find test -type f | sort
```

3. Inspect and document:

```text
- Root navigation and app-shell logic
- Main-device versus Cashier-device mode detection
- Device pairing flow
- Persisted paired-device records
- Existing device ID generation
- Existing pairing secret, token, or credential mechanism
- HTTP endpoints
- WebSocket handlers
- Sync messages
- Snapshot serialization
- Product serialization
- Sale submission flow
- Restock submission flow
- Product mutation flow
- Report retrieval flow
- Backup and restore flow
- Existing tests
```

4. Determine whether the current Main device already has a server-side paired-device registry.

5. Determine whether the current implementation trusts a role, mode, or capability value sent by the Cashier client.

6. Determine whether Cashier snapshots currently include fields that should remain private, such as:

```text
purchase cost
gross margin
gross profit
supplier information
internal notes
restock history
```

7. Record verified findings at the top of:

```text
docs/tasks/dekon-access-control-v1.md
```

Do not guess.

---

# 3. Threat Model

Protect against a modified or compromised Cashier client.

Assume that a Cashier device can:

```text
- Call HTTP endpoints directly
- Send manually constructed WebSocket messages
- Modify request payload fields
- Attempt to spoof a role
- Attempt to access reports
- Attempt to restock
- Attempt to edit a product
- Attempt to fetch another Cashier's history
- Attempt to retrieve full inventory fields
- Replay a previously accepted request
```

Do not assume the Flutter UI is trustworthy.

The Main device must enforce authorization independently.

---

# 4. Authorization Model

## 4.1 Define explicit capabilities

Create a small centralized capability enum:

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
  manageSyncSettings,
  exportData,
  createBackup,
  restoreBackup,
}
```

Adapt names to existing conventions.

Do not scatter role checks throughout unrelated widgets and transport handlers.

## 4.2 Define one static policy map

Use a static, code-defined policy.

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
    Capability.manageSyncSettings,
    Capability.exportData,
    Capability.createBackup,
    Capability.restoreBackup,
  },

  DeviceRole.cashier: {
    Capability.recordSale,
    Capability.viewCashierInventory,
    Capability.viewOwnSales,
  },
};
```

There must be no dynamic role editor.

There must be no permission-management UI.

## 4.3 Deny by default

Unknown capabilities, unknown routes, unknown commands, and unpaired devices must be denied.

Conceptually:

```dart
bool isAllowed({
  required DeviceRole role,
  required Capability capability,
}) {
  return capabilitiesByRole[role]?.contains(capability) ?? false;
}
```

Never use permissive fallback logic.

Do not use:

```dart
return true;
```

for unknown roles or unknown operations.

---

# 5. Do Not Trust Client-Provided Roles

## 5.1 Resolve role on the Main device

A Cashier must not be allowed to send:

```json
{
  "role": "mainAdmin"
}
```

and gain privileges.

The Main device must resolve authorization from its own persisted pairing record.

Conceptually:

```text
incoming remote request
→ authenticate paired device
→ resolve deviceId from trusted pairing context
→ load server-side paired-device record
→ assign DeviceRole.cashier
→ authorize requested operation
```

Do not trust these values when supplied by a remote client:

```text
role
permissions
isAdmin
isMainDevice
canRestock
canViewReports
originDeviceId
```

The Main device must derive the effective remote-device identity from the established pairing or connection context.

## 5.2 Main local operations

Administrative operations executed locally on the Main device may use:

```text
DeviceRole.mainAdmin
```

Do not expose remote administrative endpoints unless they are required by existing behavior.

Prefer keeping privileged mutations local to the Main app.

## 5.3 Remote devices remain Cashiers

In this version:

```text
Every paired remote device = Cashier
```

Do not add a remote-admin mode.

Do not add a trusted-manager device mode.

---

# 6. Reuse the Existing Pairing Mechanism

## 6.1 Do not replace working pairing logic unnecessarily

Inspect the current device-pairing implementation.

If it already creates:

```text
deviceId
pairing token
secret
session identifier
trusted connection record
```

reuse it.

## 6.2 Add the smallest missing enforcement layer

If the current pairing mechanism only stores a device ID without a secret or trusted session context, add the smallest safe credential mechanism compatible with the existing architecture.

Requirements:

```text
- Generate a high-entropy pairing credential during pairing
- Store the authoritative paired-device record on the Main device
- Store the Cashier credential locally on the Cashier device
- Associate active WebSocket and HTTP requests with the paired device
- Reject unpaired devices
- Support removing a paired Cashier from the Main device
- Reject removed devices on future requests
```

Do not build certificate infrastructure or enterprise key management.

## 6.3 Pairing authorization

Only the Main device may:

```text
- Start pairing mode
- Display the pairing QR code
- Accept a new Cashier
- Remove a Cashier
```

A Cashier must not remotely initiate pairing or add another device.

---

# 7. Centralize Main-Side Authorization

## 7.1 Create a small authorization service

Add a centralized service.

Suggested conceptual interface:

```dart
abstract interface class AuthorizationService {
  void requireCapability({
    required DevicePrincipal principal,
    required Capability capability,
  });
}
```

A suitable principal model:

```dart
class DevicePrincipal {
  final String deviceId;
  final DeviceRole role;
  final bool isLocalMainDevice;

  const DevicePrincipal({
    required this.deviceId,
    required this.role,
    required this.isLocalMainDevice,
  });
}
```

Adapt to repository conventions.

## 7.2 Stable denial error

When authorization fails, return a stable domain error:

```text
permission_denied
```

Operator-facing message:

```text
You do not have permission to perform this action.
```

For HTTP:

```text
403 Forbidden
```

For WebSocket:

```json
{
  "type": "command_rejected",
  "errorCode": "permission_denied",
  "userMessage": "You do not have permission to perform this action."
}
```

Do not expose stack traces.

## 7.3 Enforce before mutation

Required flow:

```text
receive request
→ authenticate paired device
→ resolve trusted principal
→ map operation to capability
→ require capability
→ validate payload
→ execute canonical mutation
→ persist
→ broadcast safe update
```

Authorization must happen before:

```text
- Database mutation
- Revision increment
- Broadcast
- Audit-history insertion
- Backup creation
- Restore processing
```

Unauthorized attempts must have no side effects.

---

# 8. Protect Every Remote Command

Map remote operations to capabilities.

Conceptually:

```dart
final requiredCapability = switch (command.type) {
  CommandType.createSale => Capability.recordSale,
  CommandType.createRestock => Capability.recordRestock,
  CommandType.createProduct => Capability.createProduct,
  CommandType.updateProduct => Capability.modifyProduct,
  CommandType.archiveProduct => Capability.archiveProduct,
  CommandType.adjustInventory => Capability.adjustInventory,
  CommandType.createBackup => Capability.createBackup,
  CommandType.restoreBackup => Capability.restoreBackup,
};
```

## 8.1 Allow Cashier sale submission

Cashier may submit:

```text
create_sale
```

The Main device must:

```text
- Authenticate Cashier
- Authorize recordSale
- Validate the sale
- Apply inventory mutation transactionally
- Persist canonical sale
- Increment revision
- Broadcast Cashier-safe inventory result
```

## 8.2 Deny Cashier restocking

Cashier must not submit:

```text
create_restock
```

If attempted manually, reject with:

```text
permission_denied
```

Do not mutate stock.

Do not increment revision.

Do not broadcast an update.

## 8.3 Deny Cashier product mutations

Reject remote Cashier attempts to:

```text
create_product
update_product
rename_product
change_barcode
change_price
archive_product
delete_product
adjust_inventory
```

## 8.4 Deny Cashier administrative operations

Reject remote Cashier attempts to:

```text
start_pairing
remove_device
change_sync_settings
create_backup
restore_backup
export_data
```

## 8.5 Unknown command

Reject unknown remote command types by default.

Do not ignore them silently.

Do not execute fallback behavior.

Return:

```text
unsupported_or_unauthorized_command
```

or:

```text
permission_denied
```

Choose one stable convention and document it.

---

# 9. Cashier-Safe Inventory Projection

## 9.1 Do not replicate full product records

The Main device may store full product data.

A Cashier should receive only fields needed for checkout.

Create an explicit serializer or projection.

Suggested model:

```dart
class CashierProductProjection {
  final String id;
  final String barcode;
  final String name;
  final num stockQuantity;
  final num salePrice;
  final bool isActive;
}
```

Adapt fields to the actual product model.

## 9.2 Allowed Cashier fields

Cashier inventory snapshots and push updates may include:

```text
product ID
barcode
product name
available stock quantity
sale price
active or archived state
```

Include other fields only when they are demonstrably required for checkout.

## 9.3 Forbidden Cashier fields

Do not send:

```text
purchase cost
gross profit
gross margin
supplier information
supplier identifiers
inventory valuation
internal notes
full restock history
full sales history
backup metadata
other Cashiers' identities
technical database fields
```

Do not merely hide these fields in the UI. Remove them from serialized Cashier payloads.

## 9.4 Snapshot endpoint

Cashier snapshot responses must use the Cashier-safe serializer.

Do not reuse a full administrative product serializer accidentally.

## 9.5 WebSocket broadcasts

Every Main-to-Cashier push update must also use Cashier-safe payloads.

Review:

```text
product_created
product_updated
product_archived
sale_created
restock_created
inventory_adjusted
snapshot_required
```

Broadcast only the inventory result required for Cashier convergence.

Example sale result:

```json
{
  "revision": 44,
  "type": "sale_created",
  "payload": {
    "saleId": "sale-991",
    "originDeviceId": "cashier-2",
    "items": [
      {
        "productId": "product-123",
        "newStockQuantity": 9
      }
    ]
  }
}
```

Do not include purchase cost or profit values.

---

# 10. Cashier History Access

## 10.1 Own sales only

A Cashier may view only transactions initiated from that Cashier device.

The Main device must filter using the trusted authenticated device identity.

Do not trust a client query parameter such as:

```text
deviceId=cashier-2
```

to determine whose records are returned.

Required behavior:

```text
authenticated Cashier A requests own sales
→ Main derives Cashier A identity from pairing context
→ Main returns only Cashier A transactions
```

## 10.2 Deny store-wide history

Cashier must not access:

```text
all sales
all restocks
another Cashier's sales
another Cashier's restocks
```

## 10.3 Local history cache

If the existing Cashier app stores locally initiated sales for usability, preserve that behavior.

Do not replicate another Cashier's transaction history.

All Cashiers still receive inventory-result updates caused by every accepted transaction.

---

# 11. Deny Cashier Report Access

## 11.1 Hide reports in Cashier UI

Cashier navigation must not show:

```text
Reports
```

## 11.2 Enforce report denial on Main

If the Cashier manually calls report endpoints, reject the request.

Protect:

```text
revenue
purchase totals
gross profit
gross margin
inventory valuation
sales trends
full transaction counts
store-wide metrics
```

Return:

```text
403 Forbidden
```

or the equivalent stable protocol error.

## 11.3 Optional own-sales summary

Do not add shift management or financial summary features as part of this task.

A Cashier may view its own recent sale records if the current UI supports them.

Do not introduce new report concepts.

---

# 12. Role-Specific Flutter UI

## 12.1 Main-device navigation

The Main device retains:

```text
Sell
Restock
Inventory
Reports
Settings
```

Main Inventory remains editable.

Main Settings retains:

```text
Device Sync
Backup and Restore
```

## 12.2 Cashier navigation

Cashier should show only:

```text
Sell
Inventory
My Sales
```

If a dedicated My Sales screen does not exist, add the smallest practical read-only screen or preserve an existing sale-history entry point.

Do not show:

```text
Restock
Reports
Administrative Settings
Backup and Restore
Pairing controls
```

## 12.3 Cashier Inventory screen

Cashier Inventory is read-only.

Allow:

```text
- Search
- Scan
- View product name
- View barcode where useful
- View available stock
- View sale price
```

Remove or disable:

```text
- Add Product
- Edit Product
- Delete Product
- Archive Product
- Manual Adjustment
- Purchase Cost
- Supplier Details
```

Do not show disabled administrative controls unless their presence is necessary for explanation. Prefer hiding irrelevant controls.

## 12.4 Unknown barcode on Cashier

When a Cashier scans an unknown barcode, show:

```text
Product not found.

Ask the store owner to add this product on the Main device.
```

Do not offer:

```text
Create New Product
```

on a Cashier.

## 12.5 Cashier Settings access

A Cashier may show a minimal connection-status screen if needed:

```text
Connection status
Main device connection
Reconnect action
Technical connection details if already available
```

Do not expose:

```text
Pair another device
Remove device
Backup
Restore
Export
Administrative settings
```

---

# 13. Integrate with Push-First Sync

This task extends:

```text
docs/tasks/dekon-sync-v1.md
```

Preserve the existing sync architecture:

```text
- Main device is authoritative
- Cashiers submit allowed commands to Main
- Main commits canonical state before broadcasting
- Cashiers receive immediate inventory updates
- Cashiers use full inventory snapshots after reconnect
- Revision gaps trigger snapshot repair
- Cashier mutations remain disabled while disconnected
```

Authorization rules must apply before the canonical mutation pipeline executes.

Correct ordering:

```text
remote request
→ authenticate paired Cashier
→ authorize capability
→ validate command
→ deduplicate command
→ persist canonical mutation
→ increment revision
→ commit
→ broadcast Cashier-safe result
```

Do not break snapshot reconciliation.

Do not break idempotency handling.

Do not expose privileged fields through snapshots or broadcasts.

---

# 14. Minimal Local Security Logging

Do not build an enterprise audit system.

Add lightweight structured logging for rejected privileged remote attempts.

Record locally on the Main device:

```text
timestamp
deviceId
operation
result = permission_denied
```

Do not include secrets.

Do not include pairing tokens.

Do not build:

```text
- Search dashboards
- Remote log shipping
- SIEM integration
- Compliance reports
- Retention-policy UI
```

Use the existing logging approach where available.

If persistent logging would require invasive schema changes, use structured application logs and document the limitation.

---

# 15. Tests

Add tests using existing repository conventions.

## 15.1 Cashier can sell

```text
Given:
- Cashier A is paired
- Product P has stock 10

When:
- Cashier A submits create_sale for quantity 1

Then:
- Main authorizes the command
- Main commits the sale
- Stock becomes 9
- Revision increments
- Cashier-safe update is broadcast
```

## 15.2 Cashier cannot restock

```text
Given:
- Cashier A is paired

When:
- Cashier A manually submits create_restock

Then:
- Main returns permission_denied
- Inventory does not change
- Revision does not increment
- No restock is persisted
- No inventory update is broadcast
```

## 15.3 Cashier cannot create product

```text
When Cashier A manually submits create_product
Then Main returns permission_denied
And no product is created
```

## 15.4 Cashier cannot rename product

```text
When Cashier A manually submits update_product with a new name
Then Main returns permission_denied
And product name remains unchanged
```

## 15.5 Cashier cannot change price

```text
When Cashier A manually submits update_product with a new sale price
Then Main returns permission_denied
And price remains unchanged
```

## 15.6 Cashier cannot adjust stock

```text
When Cashier A manually submits adjust_inventory
Then Main returns permission_denied
And stock remains unchanged
```

## 15.7 Cashier cannot fetch reports

```text
When Cashier A requests report data
Then Main returns 403 or permission_denied
And no report payload is returned
```

## 15.8 Cashier cannot fetch another Cashier's history

```text
Given:
- Cashier A created Sale A
- Cashier B created Sale B

When:
- Cashier A attempts to request Cashier B history
  by manipulating query parameters or payload fields

Then:
- Main derives identity from trusted pairing context
- Cashier A receives only Sale A
```

## 15.9 Cashier snapshot is redacted

```text
Given:
- Main product includes sale price, purchase cost, and internal fields

When:
- Cashier requests inventory snapshot

Then:
- Snapshot includes sale price
- Snapshot excludes purchase cost
- Snapshot excludes margin
- Snapshot excludes supplier data
- Snapshot excludes internal notes
```

## 15.10 Cashier push events are redacted

```text
When:
- Main restocks or updates a product

Then:
- Cashier receives enough data to converge inventory
- Cashier payload excludes privileged fields
```

## 15.11 Role spoofing fails

```text
When:
- Cashier sends role=mainAdmin
- Cashier sends isAdmin=true
- Cashier sends canRestock=true

Then:
- Main ignores untrusted role claims
- Main resolves role from server-side pairing record
- Restricted operations remain denied
```

## 15.12 Unpaired device denied

```text
When:
- Unknown device calls snapshot endpoint
- Unknown device submits sale
- Unknown device opens privileged command channel

Then:
- Main rejects access
```

## 15.13 Removed Cashier denied

```text
Given:
- Cashier A was previously paired
- Main removes Cashier A

When:
- Cashier A reconnects or submits a request

Then:
- Main rejects access
```

## 15.14 Cashier UI hides restricted screens

```text
Given app operates as Cashier
Then:
- Sell is visible
- Read-only Inventory is visible
- My Sales is visible if supported
- Restock is absent
- Reports is absent
- Product edit controls are absent
- Backup is absent
- Restore is absent
- Pairing controls are absent
```

## 15.15 Main UI retains administrative screens

```text
Given app operates as Main
Then:
- Sell is visible
- Restock is visible
- Editable Inventory is visible
- Reports is visible
- Device Sync is visible
- Backup and Restore are visible
```

## 15.16 Authorization occurs before mutation

```text
Given Cashier sends unauthorized command
Then:
- Database mutation is not called
- Revision is not incremented
- Broadcast is not called
```

## 15.17 Unknown remote command denied

```text
When Cashier sends unsupported command type
Then:
- command is rejected
- no side effect occurs
```

---

# 16. Manual QA Checklist

Test using:

```text
1 Main device
2 Cashier devices
Same local Wi-Fi network
```

## Main device

Verify:

```text
- Can sell
- Can restock
- Can create product
- Can rename product
- Can change price
- Can adjust inventory if supported
- Can view reports
- Can pair Cashier
- Can remove Cashier
- Can back up
- Can restore
```

## Cashier device

Verify:

```text
- Can sell
- Can search products
- Can scan products
- Can see product name
- Can see sale price
- Can see available stock
- Can view own recent sales if supported
```

Verify Cashier UI does not show:

```text
- Restock
- Reports
- Product editing
- Price editing
- Purchase cost
- Gross margin
- Gross profit
- Backup
- Restore
- Pairing
```

## Crafted unauthorized requests

Using tests or a development client, manually attempt:

```text
- Cashier restock
- Cashier product creation
- Cashier rename
- Cashier price change
- Cashier report retrieval
- Cashier restore
- Cashier role spoofing
- Cashier attempt to read another Cashier's history
```

Expected:

```text
permission_denied
```

Verify:

```text
- Inventory remains unchanged
- Revision remains unchanged
- No broadcast occurs
```

## Cashier-safe projection

Inspect snapshot and WebSocket payloads.

Verify no privileged fields leak.

---

# 17. Progress Ledger

Maintain:

```text
docs/tasks/dekon-access-control-v1.md
```

Keep this section at the top:

```md
# Dekon Cashier Access Control V1

## Status

Current phase:
Last updated:

## Verified Existing Architecture

...

## Verified Risks

...

## Completed

- [ ] Inspect pairing and transport
- [ ] Document trusted device identity source
- [ ] Add DeviceRole enum
- [ ] Add Capability enum
- [ ] Add static deny-by-default capability policy
- [ ] Add centralized AuthorizationService
- [ ] Enforce Cashier authorization before mutations
- [ ] Reject unpaired devices
- [ ] Reject removed devices
- [ ] Prevent role spoofing
- [ ] Add Cashier-safe inventory projection
- [ ] Redact Cashier snapshot payloads
- [ ] Redact Cashier WebSocket payloads
- [ ] Filter Cashier history by trusted device identity
- [ ] Hide Restock from Cashier UI
- [ ] Hide Reports from Cashier UI
- [ ] Make Cashier Inventory read-only
- [ ] Remove Create Product flow from Cashier
- [ ] Hide administrative settings from Cashier
- [ ] Add lightweight denial logging
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

---

# 18. Implementation Phases

## Phase 1: Inspect and centralize authorization

Implement:

```text
- Inspect pairing, role detection, and request flow
- Document verified architecture
- Add DeviceRole
- Add Capability
- Add static capability map
- Add AuthorizationService
- Add stable permission_denied error
- Add tests for policy map and default denial
```

Stop and summarize if the trusted paired-device identity source is unclear.

## Phase 2: Enforce Main-side restrictions

Implement:

```text
- Resolve remote role from server-side pairing context
- Ignore client role claims
- Protect every remote command
- Reject Cashier restock
- Reject Cashier product mutations
- Reject Cashier admin operations
- Reject unknown commands
- Add tests proving no side effects occur
```

## Phase 3: Protect data visibility

Implement:

```text
- CashierProductProjection
- Cashier-safe snapshot serializer
- Cashier-safe push-event serializer
- Trusted-device own-history filtering
- Report access denial
- Tests for redaction and object-level access
```

## Phase 4: Restrict Flutter UI

Implement:

```text
- Role-specific navigation
- Cashier Sell screen
- Cashier read-only Inventory
- Cashier own-sales history if currently supported
- Unknown barcode asks owner to add product
- Hide restricted settings
- Preserve Main administrative UI
- Widget tests
```

## Phase 5: Logging and QA

Implement:

```text
- Lightweight denied-operation logging
- Complete automated test coverage
- Run manual multi-device QA
- Document residual risks
```

Do not move to a later phase while earlier tests fail.

---

# 19. Validation Commands

Run:

```bash
dart format .
flutter analyze
flutter test
```

Run any existing integration tests.

Record actual output accurately.

Do not claim multi-device behavior was manually verified unless it was tested on devices or emulators.

---

# 20. Completion Criteria

The task is complete only when:

```text
1. Main remains the only administrative device.
2. Every remote paired device is treated as Cashier.
3. Cashier role is resolved from trusted Main-side pairing state.
4. Client-provided admin claims are ignored.
5. Unknown and removed devices are denied.
6. Cashier can sell.
7. Cashier can view read-only checkout-safe inventory.
8. Cashier can view only its own initiated sales if history is supported.
9. Cashier cannot restock.
10. Cashier cannot create or modify products.
11. Cashier cannot adjust inventory.
12. Cashier cannot access reports.
13. Cashier cannot access full histories.
14. Cashier cannot access backup, restore, export, pairing, or sync administration.
15. Cashier snapshots exclude sensitive fields.
16. Cashier broadcasts exclude sensitive fields.
17. Authorization occurs before mutation, revision increment, persistence, and broadcast.
18. Unauthorized operations have no side effects.
19. Cashier UI hides irrelevant restricted workflows.
20. Main UI retains administrative workflows.
21. The implementation adds no enterprise access-management subsystem.
22. Automated tests pass.
23. Manual QA findings and residual risks are documented accurately.
```

---

# 21. Final Report Format

After implementation, report:

## Verified Previous Architecture

Explain:

```text
- How device identity is established
- How paired devices are persisted
- Whether any access checks previously existed
- Whether Cashiers previously received sensitive fields
```

## Authorization Model Implemented

Summarize:

```text
- mainAdmin local device
- cashier remote paired device
- static capability map
- deny-by-default behavior
- trusted Main-side role resolution
```

## Protected Operations

List allowed and denied Cashier actions.

## Data Redaction

List fields included and excluded from Cashier snapshots and broadcasts.

## UI Changes

List Main and Cashier navigation differences.

## Changed Files

List each modified file and its purpose.

## Tests

List automated and manual tests.

## Commands Run

Report actual results for:

```bash
dart format .
flutter analyze
flutter test
```

## Residual Risks

State clearly:

```text
- Main device physical access remains trusted
- Authorization is device-scoped, not employee-scoped
- Per-employee accountability is not implemented
- Manager approval workflows are not implemented
```

Do not claim stronger guarantees than the implementation and tests establish.
