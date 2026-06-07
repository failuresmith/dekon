# Sync Protocol Review

Last reviewed: 2026-06-06

This describes the current implementation, not only the intended design in
`docs/tasks/todo-sync-protocol.md`.

## Executive Summary

Dekon sync is a local-LAN, Main-to-Cashier protocol.

- Main is authoritative for inventory, product metadata, reports, pairing, and
  backup/restore.
- Cashiers are restricted paired clients. They keep a checkout-safe inventory
  cache and may submit sale commands.
- HTTP handles pairing, pings, snapshots, sale commands, and the legacy event
  sync path.
- WebSocket handles live Cashier-safe projection updates only.
- Reconnect is mostly client-driven: the Cashier pings, syncs, refreshes the
  Main address through discovery, fetches snapshots, and reopens the WebSocket.
- The system is efficient for small-store inventory. Normal live updates are
  compact projection messages; full snapshots are reserved for connect,
  reconnect, and repair.
- The largest reliability concerns are lifecycle-related: no background sync
  service, no explicit WebSocket heartbeat, normal sync is mounted-UI driven,
  and the legacy `/events` sale path still exists beside the safer sale-command
  path.

## Main Components

- `SyncStore`: persistence boundary for trusted peers, cursors, projection
  versions, snapshots, imports, sale-command outbox, and peer state.
- `LanSyncServer`: Main-side HTTP and WebSocket server.
- `LanSyncClient`: Cashier-side HTTP/WebSocket client.
- `SyncAuthenticator`: HMAC request authentication.
- `SyncServiceDiscovery`: platform abstraction for Android NSD/mDNS discovery.
- `CashierSyncIndicator`: Cashier UI widget that also drives ping, sync,
  snapshot refresh, WebSocket connection, retry, and app-resume refresh.
- `MainCashierConnectionIndicator`: Main UI indicator. The Settings device list
  uses live projection WebSocket presence for the green Cashier icon.
- `DekonRepository`: domain entry point. Main mutations publish sanitized
  Cashier projection updates through `SyncActivityBus`.

## Persistent State

Core sync tables and settings:

- `local_device_identity`: one local UUIDv7 device ID per install.
- `devices`: local, trusted, or revoked devices; display name; shared-secret
  hash; last seen time.
- `sync_peers`: peer base URL, raw shared secret, push/pull cursors,
  last-successful-sync time, and last error.
- `app_settings`:
  - `device_role`
  - `device_role_locked`
  - `main_sync_server_enabled`
  - `cashier_inventory_projection_version` on Main
  - `last_applied_cashier_projection_version` on Cashier
  - `cashier_unpair_backup_required`
- `cashier_sale_command_outbox`: durable Cashier sale commands with
  `queued`, `syncing`, `accepted`, `conflict`, and `voided` states.
- `cashier_sale_command_outbox_lines`: local line details used for audit and
  pending-sale stock reservation.

## Device Identity

Each install gets a UUIDv7 device ID from `DeviceIdentityRepository`. The local
device is inserted into `devices` with `trust_status = local`.

Pairing adds the remote device to:

- `devices` with `trust_status = trusted`
- `sync_peers` with the peer `base_url` and shared secret

Main assigns stable sequential Cashier display names such as `Cashier-1`.
Re-pairing the same device keeps its existing Cashier number.

Remote identity is not trusted from request JSON. For authenticated endpoints,
Main reads `x-dekon-device-id`, loads that device from trusted `sync_peers`, and
verifies the HMAC with the stored shared secret. The resulting remote principal
is always role `cashier`.

## Authentication

Authenticated HTTP requests and the WebSocket upgrade use these headers:

- `x-dekon-device-id`
- `x-dekon-timestamp`
- `x-dekon-body-sha256`
- `x-dekon-signature`

The signature is HMAC-SHA256 over:

```text
METHOD
/path?query
timestamp
body_sha256
```

The clock skew window is 5 minutes. Error responses include `server_time`; the
client updates a local clock offset and retries authenticated requests after a
401 when possible.

Discovery verification uses a separate signed nonce response from
`GET /sync/state?nonce=...`. This prevents accepting a spoofed discovered
address that only copies the expected device ID.

Important detail: the raw shared secret is stored locally in `sync_peers`.
`devices.shared_secret_hash` also stores a hash, but the raw secret is still
needed for HMAC.

## Discovery And Addressing

Main server:

- Binds to `0.0.0.0` by default.
- Uses fixed port `40739` by default.
- Falls back to an ephemeral port if the requested port is busy.
- Builds `serverUrl` from the first non-loopback IPv4 address.
- Advertises `_dekon-sync._tcp` through Android NSD/mDNS when available.
- Publishes TXT attributes:
  - `device_id`
  - `protocol_version`
- Re-registers discovery after Wi-Fi/Ethernet network changes, delayed 750 ms.
- Refreshes discovery advertisement when the app resumes.

Android discovery uses:

- `NEARBY_WIFI_DEVICES` on Android 13+
- multicast lock during registration/discovery
- service resolution queue
- discovery timeout clamped between 500 ms and 10 seconds

Cashier address recovery:

1. Try the stored `base_url`.
2. On failure, discover Main services through NSD/mDNS.
3. Prefer matching `device_id` and `protocol_version` when present.
4. Verify the candidate address using authenticated `/sync/state` nonce proof.
5. If mDNS fails or finds nothing, scan fixed port `40739` across known /24 IPv4
   subnets.

The subnet fallback is bounded but bursty: up to 254 candidates per subnet,
32 concurrent probes, 250 ms per host, and about 3 seconds total by default.

## Pairing

Pairing mode is started from Main Device Sync. Main creates a QR/manual payload:

```json
{
  "protocol_version": 1,
  "base_url": "http://host:port",
  "server_device_id": "...",
  "pairing_secret": "...",
  "expires_at": "..."
}
```

The default pairing TTL is 10 minutes. `pairingQrData` returns null after expiry.

QR pairing flow:

1. Main starts server and creates a payload.
2. Cashier scans the QR code.
3. Cashier sends `POST /pair` with its `device_id`, display name, and
   `pairing_secret`.
4. Main verifies the active pairing secret.
5. Main stores the Cashier as trusted and returns Main device info,
   `shared_secret`, assigned Cashier display name, and `server_time`.
6. Cashier stores Main as trusted, stores the assigned display name locally,
   runs initial sync, then locks local role as Cashier.

Manual pairing flow:

1. Main must still be in active pairing mode.
2. Cashier enters the Main address.
3. Cashier calls `GET /device` to learn the Main device ID.
4. Cashier sends `POST /pair` with `manual_pairing = true`.
5. Main accepts this without the QR `pairing_secret` in the request, as long as
   pairing mode is active, then returns the shared secret.

Operational note: the UI label says `Stop Pairing`, but the current action calls
`LanSyncServer.stop()`. That stops the whole sync server and closes projection
sockets, not just QR pairing mode.

## HTTP Endpoints

Unauthenticated:

- `GET /health`: status, Main device ID, server time.
- `GET /device`: protocol version, event schema version, Main device ID,
  display name, server time.
- `POST /pair`: only available during active pairing mode.

Authenticated:

- `GET /sync/state`: event counts, peer counts, last sync time, optional signed
  nonce proof.
- `GET /events`: legacy Cashier-safe event page, with optional long-poll wait.
- `POST /events`: legacy event push path.
- `GET /cashier/inventory-snapshot`: full Cashier-safe inventory snapshot.
- `POST /cashier/sales`: Cashier sale-command submission.
- `GET /cashier/projection-stream`: WebSocket upgrade for live projection
  updates.

## Initial Sync

After pairing, `LanSyncClient.syncWithPeer` runs:

1. Push local events to Main through legacy `POST /events` until no events are
   left.
2. Pull legacy Cashier-safe events through `GET /events` until no events are
   left.
3. Fetch and apply the full Cashier-safe inventory snapshot.
4. Drain up to 100 queued Cashier sale commands.
5. Optionally enter long-poll event pulling when WebSocket is not being used.

The snapshot step is important: it replaces the Cashier cache with the current
Main projection and persists `last_applied_cashier_projection_version` in the
same transaction.

## Cashier Projection Model

Main maintains a monotonically increasing
`cashier_inventory_projection_version`. It advances only for Cashier-visible
changes:

- product create
- product visible-field edit
- product soft delete or active-state change
- inventory stock change from local restock/sale paths
- accepted Cashier sale command

Private-only product edits, such as purchase-cost changes, do not advance the
Cashier projection.

Cashier-safe product fields are:

- `product_id`
- `barcode`
- `name`
- `stock_quantity`
- `sale_price_minor`
- `active`

Excluded fields include purchase cost, SKU, private unit details, supplier data,
margin/profit data, backup metadata, device registry data, and full event
history.

Projection message types:

- `product_upsert`: full Cashier-safe product row, including current stock.
- `inventory_patch`: product IDs and resulting stock quantities.
- `snapshot_required`: tells Cashier to fetch a full snapshot.
- `cashier_unpaired`: tells a specific Cashier it was revoked.

## Main Mutation Publishing

Main-side replicated mutations go through a serialized queue in
`DekonRepository`. The transaction:

1. Appends event(s).
2. Applies local projections.
3. Increments the Cashier projection version if the change is Cashier-visible.
4. Commits.

After commit, the repository emits:

- `eventsChanged`
- a sanitized Cashier projection update, when applicable

`LanSyncServer` listens to `cashierProjectionUpdates` and broadcasts the JSON
message to all connected projection WebSockets.

This ordering matters: event append, local projection, projection-version
increment, and publish are serialized so Cashiers see a single ordered version
stream.

## WebSocket Behavior

WebSocket is used only for live Cashier projection delivery:

```text
GET /cashier/projection-stream
```

The upgrade request must include the same HMAC headers as authenticated HTTP
requests. Unauthenticated upgrades are rejected.

Server behavior:

- Stores each open socket with the authenticated Cashier device ID.
- Marks the peer successful on connect.
- Broadcasts every sanitized projection update to every connected Cashier
  socket.
- Removes sockets on `done` or send failure.
- Sends `cashier_unpaired` only to sockets for the revoked device, then closes
  them.

Client behavior:

- `CashierSyncIndicator` opens the WebSocket after a successful ping and sync.
- Incoming messages are parsed into typed projection updates before mutation.
- Duplicate or old projection versions are ignored.
- Non-contiguous versions trigger a full snapshot repair.
- `snapshot_required` triggers a full snapshot repair.
- Inventory patches for unknown local products trigger a full snapshot repair.
- On unexpected stream close, the indicator runs a normal refresh and reconnect.
- On app pause/detach/hidden, the indicator closes the stream.
- On app resume, it closes any stale stream, runs snapshot sync, and reopens.

There is no explicit application-level heartbeat message and the server does not
set a WebSocket `pingInterval`. Liveness is inferred from socket close events,
periodic Cashier pings, and successful sync operations.

## Reconnect And Liveness

Cashier liveness is UI-driven:

- Initial refresh runs after the indicator mounts.
- Default poll interval is 1 second.
- A refresh pings Main through `/sync/state`.
- If ping succeeds, the client runs `syncWithPeer`.
- Then it opens or reopens the projection WebSocket.
- If the WebSocket is unavailable after a successful sync, the indicator stays
  green, falls back to long-poll sync, and retries the stream after 5 seconds.
- If sync fails after a successful ping, the indicator also stays green.
- If ping fails, the indicator is disconnected.

Main liveness views differ:

- The Settings paired-Cashier list uses `LanSyncServer.isCashierConnected`,
  meaning an active authenticated projection WebSocket.
- The small app-bar Main indicator uses `last_seen_at` within a 75-second window,
  not direct socket presence.

Peer success updates `devices.last_seen_at` and
`sync_peers.last_successful_sync_at`.

## Cashier Sale Commands

Locked Cashier sale recording does not append authoritative sale events locally.
It creates a durable command in the local outbox.

Command properties:

- `command_id` is UUIDv7.
- `command_id` is also used as the accepted Main sale event ID.
- Lines contain product IDs and quantities only.
- Local outbox line details preserve product names/prices for local audit.
- Active outbox commands are capped at 500.

Cashier local stock availability subtracts queued, syncing, and conflicted
commands. This prevents the Cashier from repeatedly selling the same local
snapshot quantity while Main is away.

Drain behavior:

1. FIFO by `created_at`, then `command_id`.
2. `queued` or `syncing` command becomes `syncing`.
3. Client submits `POST /cashier/sales`.
4. Main validates against authoritative product active state and stock.
5. Main computes sale prices and FIFO costs from authoritative projections.
6. Main appends and projects one sale event atomically.
7. Main increments Cashier projection version and publishes a stock patch.
8. Cashier imports the returned safe sale event, fetches a snapshot, and marks
   the command accepted.
9. If Main rejects with product unavailable or insufficient stock, the command
   becomes `conflict` and later commands stop draining.
10. A conflict is resolved by explicit voiding or replacement, not hard delete.

Retries are idempotent because the command ID is the event ID. If Main already
accepted the command, it returns the existing sale event as a duplicate instead
of mutating stock again.

## Legacy Event Sync Path

The older event path still exists:

- Cashier can pull sanitized Main events through `GET /events`.
- Cashier can push local events through `POST /events`.
- Cursors are encoded HLC/event-ID pairs.
- Pull pages request up to 100 events by default.
- Server limits requested event pages to 1..500.
- Long-poll waits up to 25 seconds by default and 30 seconds max.

Server-side Cashier event sanitization:

- Product creates and visible product field changes are reduced to safe fields.
- Restocks, other Cashier sales, adjustments, sale voids, and purchase
  corrections become stock-only inventory adjustments.
- The requesting Cashier's own sales keep safe sale details for local history.

Risks in this path:

- `POST /events` processes each event in its own transaction, so a batch can
  partially apply.
- Remote Cashier product/restock/admin events are rejected by capability checks.
- Remote Cashier sale events are still authorized for compatibility.
- The legacy sale event import path does not perform the same authoritative
  stock validation as `POST /cashier/sales`; tests show it can project negative
  stock. The locked Cashier UI uses sale commands, but this compatibility path
  should be removed, versioned, or constrained before relying on it.

## Unpairing

Main unpair flow:

1. Send `cashier_unpaired` to live projection sockets for that Cashier.
2. Close those sockets.
3. Mark the peer `revoked`.
4. Clear `last_seen_at`.
5. Store `last_error = peer_unpaired`.

A revoked Cashier with a valid signature receives `peer_unpaired` on future
authenticated requests. The Cashier marks `cashier_unpair_backup_required`,
blocks normal use, backs up sale history, clears sync/event/projection state,
and returns to Cashier pairing.

## Observability

The sync activity bus exposes:

- event-change notifications
- sync-state-change notifications
- transfer activity with sent/received event counts
- recent peer message log
- Cashier projection update stream

Peer message previews redact keys containing `secret`, `signature`, `password`,
or `token`. The in-memory peer message log is capped at 50 messages by default.

User-visible sync state is intentionally small:

- Cashier app-bar dot is red/green/breathing green.
- Main app-bar dot appears when a Cashier was recently seen.
- Settings exposes technical details, mDNS status, local address, and peer
  messages.
- Reports show unsynced warnings when there are local events not pushed to
  trusted peers.

## Efficiency

Efficient parts:

- Normal Main changes push compact projection updates, not full event history.
- Product edits publish one sanitized product row.
- Stock changes publish only product IDs and resulting quantities.
- Snapshots are full but used for initial sync, reconnect, and repair.
- Push/pull batches are bounded.
- Long-poll avoids tight polling when WebSocket is not used.
- The sale-command outbox drains at most 100 commands per sync call.

Less efficient or scaling-sensitive parts:

- Full snapshot application deletes and replaces the Cashier product and
  inventory projections.
- Legacy `GET /events` scans raw event pages of 100 and filters them into safe
  events, so many private or irrelevant events can make Cashier pulls do extra
  work.
- WebSocket broadcasts every projection update to every connected Cashier. There
  is no per-device filtering except for unpair messages.
- Normal Cashier polling defaults to every 1 second while the indicator is
  mounted.
- Fixed-port subnet fallback can probe many addresses quickly.
- Normal HTTP operations do not consistently set explicit request timeouts
  outside the discovery/probe path.

For the stated small-store scope, this is acceptable. For large catalogs, many
Cashiers, noisy event logs, or unreliable Wi-Fi, the snapshot and polling costs
would need closer measurement.

## Reliability-Relevant Strengths

- Main remains authoritative for accepted inventory state.
- Cashiers can keep selling while Main is away through a durable local sale
  command outbox.
- Queued/syncing/conflicted Cashier commands reserve local stock.
- Sale-command retry is idempotent.
- Accepted command mutation on Main is atomic for append, projection, and
  projection-version increment.
- Projection messages have monotonic versions.
- Duplicate projection messages are ignored.
- Missing projection versions trigger snapshot repair.
- Unknown product patches trigger snapshot repair.
- App resume forces a fresh sync and stream reopen.
- Stale Main addresses are repaired through authenticated discovery.
- mDNS identity is verified cryptographically before updating `base_url`.
- Revoked peers are distinguished from ordinary unauthorized peers.
- User-facing raw sync diagnostics are mostly kept in Settings.

## Robustness Findings And Priorities

Robust connectivity means more than opening a socket. For this protocol it means:

- peers can find each other after address and Wi-Fi changes
- liveness failures are detected quickly
- sync attempts do not hang indefinitely
- Cashier inventory converges after missed updates
- offline sale commands survive process restarts
- Main never accepts unsafe duplicate or unauthorized inventory mutation
- users can tell connected, stale, syncing, conflicted, and unpaired states apart

### P0: Legacy Sale Events Can Bypass Main Stock Validation

Locked Cashier UI uses `/cashier/sales`, which validates stock atomically on
Main. But the legacy authenticated `POST /events` path still authorizes remote
Cashier sale events. That path imports events and projects them; it does not run
the authoritative stock check used by sale commands. Existing tests even show
remote event import can project negative stock.

Hardening:

- Reject `inventory.sale_recorded` on `POST /events` for Cashier peers.
- Keep `/cashier/sales` as the only remote Cashier write path.
- If legacy event push is still needed for migrations, gate it behind an
  explicit protocol version or one-time migration mode.

### P0: Pairing Secret Becomes The Long-Term Shared Secret

Main currently uses the active QR/manual pairing secret as the stored HMAC
shared secret. Every Cashier paired under the same active pairing payload gets
the same secret. That weakens device identity: a compromised Cashier that learns
another Cashier device ID may be able to sign as that peer if both were paired
under the same payload.

Hardening:

- Treat the QR/manual secret only as a short-lived pairing code.
- Generate a fresh high-entropy per-device shared secret inside `POST /pair`.
- Store only the per-device secret for future HMAC.
- Invalidate or rotate the pairing code after each successful pairing, unless
  the UI explicitly starts another pairing session.

### P0: Sync Operations Lack Bounded HTTP Timeouts

Most normal HTTP operations use `http.Client.get/post` without explicit
timeouts. Discovery verification has a timeout, but pairing, ping, snapshot
fetch, event pull/push, sale submission, and outbox drain can wait on the OS or
socket stack for too long. While `CashierSyncIndicator._refresh` is waiting,
future refreshes only set `_refreshAgain`; the visible state can become stale.

Hardening:

- Add operation-specific timeouts:
  - ping/state: short
  - pairing: medium
  - sale command: medium
  - snapshot: medium/long based on catalog size
  - long-poll: wait timeout plus small transport margin
- Make timeout errors explicit user-facing degraded states, not generic sync
  failures.
- Add tests for hung ping, hung snapshot, hung sale command, and hung WebSocket
  connect.

### P0: Liveness And Freshness Are Conflated

The Cashier indicator stays green when ping succeeds but sync or projection
stream setup fails. That is reasonable for "Main is reachable", but it can
mislead the operator into thinking inventory is fully current. Main app-bar
presence also uses a 75-second `last_seen_at` window, while the Settings device
list correctly uses active projection WebSocket presence.

Hardening:

- Track separate states:
  - transport reachable
  - projection stream connected
  - snapshot/event sync in progress
  - last applied projection version
  - outbox pending/conflicted
  - stale/degraded
- Show healthy connectivity quietly, but show stale or conflicted sync as an
  actionable warning.
- Use live WebSocket presence for "connected now" indicators. Use `last_seen_at`
  only for "recently seen" diagnostics.

### P1: WebSocket Has No Explicit Heartbeat

The projection stream depends on TCP/WebSocket close events and the Cashier's
periodic HTTP ping. There is no server or client `pingInterval`. Some Wi-Fi
failure modes leave sockets half-open, so Main may think a Cashier is connected
or Cashier may wait for close detection longer than expected.

Hardening:

- Set WebSocket ping intervals on both sides, or centralize heartbeat on one
  side and document the close timing.
- Treat heartbeat failure as stream disconnected, then run snapshot sync before
  reconnecting.
- Test a dropped stream and a silent stream separately.

### P1: Sync Ownership Lives In A UI Indicator

`CashierSyncIndicator` owns pinging, snapshot sync, projection stream lifetime,
retry, and app-resume refresh. It is mounted in the app-bar Settings stack, so
foreground app connectivity works, but there is no app-level sync controller and
no background service.

Hardening:

- Move protocol lifecycle into an app-level `CashierSyncController`.
- Let UI subscribe to controller state instead of owning sync behavior.
- Keep foreground-only operation if that is the product decision, but make it an
  explicit invariant.
- Consider Android foreground/background service only if the product truly needs
  sync while the app is not open.

### P1: `Stop Pairing` Stops The Whole Server

The UI says `Stop Pairing`, but calls `LanSyncServer.stop()`. That stops the
server, unregisters discovery, clears pairing payload, closes projection
sockets, and disables `main_sync_server_enabled`. A store owner can accidentally
disconnect already paired Cashiers while intending only to stop accepting new
pairings.

Hardening:

- Add `stopPairing()` that clears `_pairingPayload` only.
- Keep the server and existing projection sockets alive.
- Keep a separate "Turn off sync server" action under technical/admin details,
  if needed.

### P1: Restore Does Not Force Cashier Snapshot Repair

The task spec expects backup restore to push `snapshot_required`, but current
`DekonRepository.restoreBackup` imports backup events and only notifies
`eventsChanged` and `syncStateChanged`. It does not increment the Cashier
projection version or broadcast `snapshot_required`. Connected Cashiers may stay
stale until their next full sync path catches up, and the projection version may
not communicate that a full cache replacement is required.

Hardening:

- After Main restore, increment `cashier_inventory_projection_version`.
- Broadcast `snapshot_required`.
- Make connected Cashiers fetch and apply a fresh snapshot.
- Add tests that restore changes are visible on a connected Cashier without
  restarting the app.

### P1: Projection Message Handling Is Not Serialized

The WebSocket listener calls `_applyProjectionMessage` with `unawaited`. Multiple
messages, snapshot fetches, and repairs can run concurrently. Version checks and
SQLite transactions prevent many incorrect outcomes, but concurrent repairs can
cause redundant snapshot fetches and harder-to-reason interleavings.

Hardening:

- Serialize projection message handling through a small async queue.
- Coalesce duplicate snapshot-repair requests while a snapshot fetch is already
  running.
- Drop queued older messages after a newer snapshot has been applied.

### P1: No Per-Cashier Projection Acknowledgement

Main can tell whether a Cashier has an open projection WebSocket, but it does
not know the last projection version that Cashier applied. That limits
observability: connected is not the same as converged.

Hardening:

- Let Cashier report `last_applied_cashier_projection_version` during ping or
  via a small authenticated acknowledgement.
- Surface lag only when it is actionable.
- Use this to detect Cashiers that are connected but not applying updates.

### P2: Discovery Fallback Can Be Noisy

The fixed-port /24 scan is useful when mDNS fails, but it can probe up to 254
hosts per subnet with 32 concurrent workers. That is bounded for small Wi-Fi
networks, but repeated failures from a 1-second poll loop can still be noisy.

Hardening:

- Add exponential backoff after failed discovery refresh.
- Cache negative discovery attempts for a short window.
- Prefer user-triggered scan in Settings after repeated automatic failures.

### P2: WebSocket Broadcast Has No Backpressure Strategy

Server broadcast calls `socket.add` for every connected Cashier. If a socket is
slow but not yet closed, messages may buffer. For a small store this is probably
fine; under bad Wi-Fi it can hide a degraded peer until the socket errors.

Hardening:

- Add heartbeat plus applied-version acknowledgement first.
- If needed later, track per-socket send failures and close persistently lagging
  sockets so they repair through snapshot on reconnect.

### P2: Replay Protection Is Time-Window Only

HMAC authentication accepts requests within a 5-minute clock window and does not
store per-request nonces. Sale commands and event imports are idempotent by ID,
so replay is usually contained, but pairing and state-changing compatibility
paths deserve scrutiny.

Hardening:

- Keep relying on command/event IDs for idempotent mutation replay.
- Remove or constrain legacy event mutation.
- Consider nonce storage only for high-risk administrative operations; avoid
  adding complexity unless a real replay impact remains.

## Hardening Sequence

Recommended order:

1. Disable remote Cashier sale events on `POST /events`; keep `/cashier/sales`
   as the only Cashier write path.
2. Add bounded HTTP/WebSocket operation timeouts and tests for hung operations.
3. Split liveness from freshness in state and UI.
4. Add WebSocket heartbeat and reconnect-through-snapshot behavior.
5. Move sync lifecycle out of `CashierSyncIndicator` into an app-level
   controller.
6. Add `stopPairing()` so QR pairing can stop without disconnecting trusted
   Cashiers.
7. Rotate to per-device shared secrets during pairing.
8. Broadcast `snapshot_required` after Main restore.
9. Serialize projection message application and coalesce snapshot repairs.
10. Add per-Cashier applied-version acknowledgement.
11. Add discovery backoff and scan throttling.
12. Run manual multi-device QA with real Wi-Fi changes, Main app pause/resume,
    Cashier app pause/resume, Main-away offline selling, reconnect, conflict,
    unpair, and restore.

## Test Coverage Observed

Automated tests cover:

- unauthenticated request rejection
- QR pairing and manual pairing
- stable Cashier name assignment
- server start without pairing QR
- default/fallback port behavior
- redacted peer message logs
- mDNS advertisement and stale-address refresh
- signed discovery proof and spoof rejection
- clock-skew correction
- unpair recovery
- pairing initial sync
- idempotent Cashier sale command retry
- insufficient-stock rejection
- locked-Cashier command submission
- offline Cashier queue and local stock reservation
- outbox drain and conflict pause
- long-poll event wait
- duplicate event import
- Cashier-safe event and snapshot redaction
- transactional snapshot application
- projection duplicate/gap/snapshot repair
- authenticated projection WebSocket
- product mutation authorization rejection
- event-device spoof rejection
- Cashier sync indicator retry, app-resume refresh, and stream handling

No manual multi-device QA is documented as completed in the current task notes.
