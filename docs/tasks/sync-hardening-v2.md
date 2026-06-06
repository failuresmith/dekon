# Dekon Sync Hardening V2

## Status

Current phase: Phase 1 - complete
Last updated: 2026-06-06

## Verified Existing Behavior

- Main remains authoritative for global inventory state.
- Cashiers are authenticated through trusted device HMAC headers and are treated as remote Cashier principals.
- The legacy authenticated `POST /events` path accepted `inventory.sale_recorded` because `capabilityForRemoteEvent` mapped it to `Capability.recordSale`.
- The dedicated `POST /cashier/sales` command path validates Main-side stock and is retry-idempotent through command IDs.
- Legacy `GET /events` pull returns Cashier-safe events and remains useful for compatibility.

## Changes Made

- Phase 1: remote Cashier `POST /events` no longer receives a capability for `inventory.sale_recorded`, so legacy sale events are rejected before import or projection.

## Decisions

- Keep `Capability.recordSale` for the dedicated `/cashier/sales` command path.
- Preserve legacy pull behavior through `GET /events`.
- Treat legacy sale-event push as intentionally removed, including future-schema sale events, because it bypasses Main-side stock validation.

## Tests Added

- Cashier `POST /events` sale is rejected without changing stock.
- Rejected sale event does not increment Cashier projection version.
- Rejected sale event does not emit a Cashier projection broadcast.
- Future-schema sale events are rejected on legacy `POST /events`.
- Sale-event batches are rejected before projection.
- `/cashier/sales` still accepts, broadcasts once, and remains idempotent on retry.

## Validation Log

Commands run:
- `which dart`
- `which flutter`
- `docker compose run --rm flutter-dev dart format lib/src/sync/sync_access_control.dart test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev dart format test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `git diff --check`

Results:
- Host `dart` and `flutter` were not available on `PATH`.
- Docker `dart format` formatted `test/sync/lan_sync_server_test.dart`.
- First focused sync test run exposed one remaining legacy sale-event push expectation in the pairing test.
- The pairing test was updated to queue and drain a Cashier sale command through `/cashier/sales`.
- Final focused `flutter test test/sync/lan_sync_server_test.dart` passed.
- `flutter analyze` passed with no issues.
- `git diff --check` passed.

## Manual QA

Scenarios tested:
- Not run.

Results:
- Not run.

## Residual Risks

- Phase 2 through Phase 11 are not implemented yet.
- No manual multi-device QA has been run.

---

You are working in the Dekon Flutter codebase.

Goal: refactor the existing LAN Main-to-Cashier sync implementation into a significantly more robust mobile-safe version without breaking current functionality.

Read first:

* AGENTS.md
* README.md
* pubspec.yaml
* docs/tasks/todo-sync-protocol.md
* docs/tasks/dekon-access-control-v1.md
* docs/tasks/sync.md
* all sync-related files under lib/ and test/

Before editing, run:

```bash
git status --short
find lib -type f | sort
find test -type f | sort
```

Preserve unrelated user changes. Do not reset, rewrite, or remove working features outside this task.

## Core constraint

This is a hardening refactor, not a redesign.

Keep:

* Main as authoritative
* Cashiers as restricted paired clients
* HTTP for pairing, state, snapshots, sale commands, and legacy compatibility
* WebSocket for live Cashier-safe projection updates
* Cashier sale-command outbox
* Cashier-safe projection model
* existing tests and UX unless explicitly changed below

Do not introduce:

* cloud sync
* CRDTs
* multi-master writes
* MQTT
* distributed consensus
* employee accounts
* enterprise IAM
* a full rewrite of sync

## Main priorities

Implement in this order.

### Phase 1 — Remove unsafe legacy sale mutation path

Problem:
The legacy authenticated `POST /events` path still accepts Cashier sale events and can bypass the authoritative `/cashier/sales` stock validation.

Change:

* Reject `inventory.sale_recorded` or equivalent sale events from remote Cashier peers through `POST /events`.
* Keep `/cashier/sales` as the only remote Cashier write path.
* Preserve legacy pull behavior if still needed.
* If tests depend on legacy Cashier sale event push, update them to use sale commands.

Add tests:

* Cashier `POST /events` sale is rejected.
* Stock does not change.
* Projection version does not increment.
* No projection broadcast occurs.
* `/cashier/sales` still works and remains idempotent.

### Phase 2 — Add bounded HTTP and WebSocket timeouts

Problem:
Normal operations can hang too long on mobile Wi-Fi.

Change:
Add operation-specific timeouts in `LanSyncClient` and related call sites:

* `/sync/state` ping: short timeout
* pairing: medium timeout
* sale command submission: medium timeout
* inventory snapshot: medium/long timeout
* event pull/push: bounded timeout
* long-poll: server wait timeout plus transport margin
* WebSocket connect: bounded timeout

Represent timeout failures explicitly in sync status instead of generic failure where practical.

Add tests:

* hung ping times out
* hung snapshot fetch times out
* hung sale command times out without marking accepted
* hung WebSocket connect times out
* refresh loop does not get permanently stuck after a timeout

### Phase 3 — Split liveness from freshness

Problem:
The UI can show “green” when Main is reachable but inventory is stale, sync failed, or projection stream is disconnected.

Change:
Introduce a small explicit sync state model, preferably owned outside the widget:

```dart
class CashierSyncStatus {
  final bool transportReachable;
  final bool projectionStreamConnected;
  final bool snapshotSyncInProgress;
  final int? lastAppliedProjectionVersion;
  final int pendingOutboxCount;
  final int conflictedOutboxCount;
  final bool stale;
  final bool degraded;
  final String? lastErrorCode;
}
```

Adapt naming to the codebase.

UI behavior:

* reachable + fresh + stream connected = quiet healthy state
* reachable but stale/degraded = warning, not healthy green
* outbox conflict = actionable warning
* unpaired/revoked = blocking state
* `last_seen_at` is diagnostic only, not proof of “connected now”

Add tests:

* ping success but snapshot failure shows degraded/stale
* stream disconnected after sync shows reachable but not fully fresh
* conflict state is visible
* unpaired state blocks normal cashier use

### Phase 4 — Add WebSocket heartbeat

Problem:
Half-open Wi-Fi sockets can leave Main or Cashier thinking the stream is alive.

Change:

* Add WebSocket heartbeat using Dart WebSocket ping interval where supported, or a small app-level heartbeat if necessary.
* Document the chosen mechanism in the task file.
* On heartbeat failure, mark projection stream disconnected.
* Reconnect by fetching a fresh snapshot first, then reopen the stream.

Add tests:

* dropped stream triggers reconnect path
* silent/dead stream is detected
* reconnect fetches snapshot before accepting pushed deltas

### Phase 5 — Move sync ownership out of `CashierSyncIndicator`

Problem:
The UI indicator currently owns protocol lifecycle: pinging, snapshot sync, stream lifetime, retry, and resume handling.

Change:
Create an app-level `CashierSyncController` or equivalent.

Responsibilities:

* start/stop foreground sync lifecycle
* ping Main
* refresh Main address through discovery
* fetch/apply snapshots
* drain sale-command outbox
* open/reopen projection stream
* handle app resume/pause
* serialize projection message application
* publish `CashierSyncStatus`

`CashierSyncIndicator` should become a subscriber/view only.

Keep foreground-only behavior unless existing product requirements demand background sync. If foreground-only, document it as an explicit invariant.

Add tests:

* controller starts sync without depending on widget mount internals
* widget disposal does not corrupt controller state
* app resume triggers snapshot repair and stream reopen
* controller prevents overlapping refresh loops

### Phase 6 — Fix Stop Pairing semantics

Problem:
The UI says “Stop Pairing” but currently stops the whole sync server and disconnects active Cashiers.

Change:

* Add `LanSyncServer.stopPairing()` or equivalent.
* It should clear only active pairing payload/session.
* It must keep:

  * server running
  * discovery active if already active
  * existing trusted Cashier sockets connected
  * `main_sync_server_enabled` unchanged
* Move full “Turn off sync server” behind a distinct technical/admin action if needed.

Add tests:

* stop pairing prevents new pairing
* existing Cashier remains connected
* projection stream remains alive
* full server stop still behaves as before where intentionally used

### Phase 7 — Generate per-device shared secrets during pairing

Problem:
Pairing secret may become the long-term shared secret for multiple Cashiers.

Change:

* Treat QR/manual pairing secret only as a short-lived pairing code.
* During `POST /pair`, generate a fresh high-entropy per-device shared secret.
* Store only that per-device secret for future HMAC.
* Rotate/invalidate the active pairing code after successful pairing unless the UI explicitly starts a new pairing session.
* Preserve backward compatibility carefully:

  * existing paired devices should continue working if possible
  * document any migration behavior

Add tests:

* two Cashiers paired under the same pairing session do not share long-term HMAC secret
* old pairing code cannot be reused after invalidation
* authenticated requests still verify using the per-device secret
* existing pair records migrate or remain compatible according to documented behavior

### Phase 8 — Restore forces snapshot repair

Problem:
Backup restore does not reliably force connected Cashiers to replace their cache.

Change:
After successful Main restore:

* safely advance `cashier_inventory_projection_version`
* broadcast `snapshot_required`
* ensure connected Cashiers fetch and apply a fresh snapshot
* ensure projection version never moves backward due to restored data

Add tests:

* restore broadcasts `snapshot_required`
* connected Cashier refreshes snapshot without app restart
* projection version remains monotonic
* private restored fields do not leak to Cashier

### Phase 9 — Serialize projection message handling

Problem:
Projection messages and snapshot repairs can run concurrently because message application is unawaited.

Change:

* Add a small async queue for Cashier projection message handling.
* Apply projection updates sequentially.
* Coalesce duplicate snapshot repair requests while a snapshot fetch is already running.
* Drop older queued messages after a newer snapshot has been applied.
* Keep the queue bounded.

Add tests:

* concurrent pushed messages apply in order
* duplicate snapshot repairs coalesce into one fetch
* older queued messages are ignored after snapshot
* version gap triggers one snapshot repair, not many

### Phase 10 — Add per-Cashier applied-version acknowledgement

Problem:
Main knows socket presence but not whether a Cashier has actually converged.

Change:

* Include `last_applied_cashier_projection_version` in `/sync/state` ping or add a small authenticated acknowledgement endpoint/message.
* Store or expose per-Cashier applied version on Main.
* Surface lag only in Settings/diagnostics unless it becomes actionable.
* Do not block sales merely because diagnostics are unavailable.

Add tests:

* Cashier reports applied version
* Main records applied version per Cashier
* connected-but-lagging Cashier can be distinguished from connected-and-current

### Phase 11 — Add discovery backoff and scan throttling

Problem:
mDNS failure fallback can scan /24 networks repeatedly and noisily.

Change:

* Add exponential backoff after failed discovery refresh.
* Cache negative discovery result briefly.
* Avoid triggering subnet scan from a 1-second loop repeatedly.
* Prefer a manual “Scan again” action in Settings after repeated failures.
* Keep initial recovery practical for small-store Wi-Fi.

Add tests:

* repeated failed discovery attempts back off
* subnet scan is not repeated every second
* manual scan bypasses backoff where intended

## Documentation ledger

Update or create a task file, for example:

```text
docs/tasks/sync-hardening-v2.md
```

Keep this structure:

```md
# Dekon Sync Hardening V2

## Status
Current phase:
Last updated:

## Verified Existing Behavior
...

## Changes Made
...

## Decisions
...

## Tests Added
...

## Validation Log
Commands run:
Results:

## Manual QA
Scenarios tested:
Results:

## Residual Risks
...
```

Do not claim manual multi-device QA unless actually performed on devices or emulators.

## Validation

After each phase, run relevant focused tests.

Before final report, run:

```bash
dart format .
flutter analyze
flutter test
```

If host Dart/Flutter are unavailable, use the existing Docker Flutter environment if present.

## Final report

Return:

```md
## Summary
...

## Changed Files
...

## Robustness Improvements
...

## Backward Compatibility Notes
...

## Tests
...

## Commands Run
...

## Manual QA
...

## Residual Risks
...
```

Be precise. Do not claim stronger guarantees than the implementation and tests prove.
