# Dekon Sync Hardening V2

## Status

Current phase: Phase 8 - complete
Last updated: 2026-06-06

## Verified Existing Behavior

- Main remains authoritative for global inventory state.
- Cashiers are authenticated through trusted device HMAC headers and are treated as remote Cashier principals.
- The legacy authenticated `POST /events` path accepted `inventory.sale_recorded` because `capabilityForRemoteEvent` mapped it to `Capability.recordSale`.
- The dedicated `POST /cashier/sales` command path validates Main-side stock and is retry-idempotent through command IDs.
- Legacy `GET /events` pull returns Cashier-safe events and remains useful for compatibility.

## Changes Made

- Phase 1: remote Cashier `POST /events` no longer receives a capability for `inventory.sale_recorded`, so legacy sale events are rejected before import or projection.
- Phase 2 scope: add bounded operation-specific client timeouts for pairing, ping, snapshot fetch, event push/pull, long-poll transport, sale-command submission, and projection WebSocket connect.
- Phase 2 out-of-scope: UI sync-state redesign, app-level sync controller ownership, WebSocket heartbeat, discovery backoff, and protocol rewrites.
- Phase 2: added `LanSyncTimeouts` defaults: ping 2s, pairing 8s, sale command 8s, inventory snapshot 15s, event pull 8s, event push 8s, long-poll transport margin 5s, WebSocket connect 5s.
- Phase 2: added `SyncTimeoutException` with stable error codes and persisted trusted-peer timeout diagnostics in `sync_peers.last_error`.
- Phase 3: replaced the old three-value Cashier sync enum with an explicit `CashierSyncStatus` model covering transport reachability, projection stream connection, snapshot sync progress, last applied projection version, pending/conflicted outbox counts, stale/degraded flags, last error code, and unpaired state.
- Phase 3: Cashier indicator now shows degraded amber when ping succeeds but sync freshness or projection stream health is missing.
- Phase 3: Cashier indicator now shows conflicted and unpaired visual states.
- Phase 3: Main app-bar Cashier connection indicator now uses live projection WebSocket presence from `LanSyncServer`, not recent `last_seen_at`.
- Phase 4 scope: add WebSocket heartbeat for the Cashier projection stream and verify reconnect fetches a fresh snapshot before reopening the stream.
- Phase 4: Main and Cashier projection WebSockets now set Dart `WebSocket.pingInterval` to 15 seconds by default.
- Phase 4: unexpected projection stream closure continues through the existing refresh path: ping, full sync/snapshot repair, then reopen stream.
- Phase 5 scope: move foreground Cashier sync lifecycle ownership out of `CashierSyncIndicator` into a controller while preserving existing foreground-only behavior.
- Phase 5: added `CashierSyncController`; it owns ping, sync refresh, outbox/status refresh, projection stream open/reopen, app lifecycle handling, transfer activity state, and refresh serialization.
- Phase 5: `CashierSyncIndicator` is now a view/subscriber that renders controller status and owns only animation/widget lifecycle plumbing.
- Phase 6 scope: make the visible `Stop Pairing` action stop only the active pairing session without shutting down the LAN sync server.
- Phase 6: added `LanSyncServer.stopPairing()` to clear only the current pairing payload.
- Phase 6: Settings `Stop Pairing` now calls `stopPairing()` and leaves `main_sync_server_enabled` unchanged.
- Phase 6: full `LanSyncServer.stop()` behavior remains available and unchanged for intentional server shutdown.
- Phase 7 scope: make QR/manual pairing codes short-lived setup credentials and generate separate per-device HMAC secrets for trusted Cashiers.
- Phase 7: `POST /pair` now stores and returns a fresh generated per-device shared secret instead of reusing the pairing code as the long-term secret.
- Phase 7: successful pairing rotates the active pairing payload secret, so an old QR pairing code cannot be reused.
- Phase 7: `LanSyncClient.pairWithServer` now stores the returned `shared_secret`, preserving compatibility with old Main devices that still return the QR pairing secret and supporting new Main devices that return per-device secrets.
- Phase 8 scope: force connected Cashiers to repair from a fresh snapshot after successful Main backup restore.
- Phase 8: `DekonRepository.restoreBackup` now runs inside the replicated-mutation queue, imports the backup, increments the Cashier projection version once, and broadcasts `snapshot_required`.
- Phase 8: restore validation/import behavior remains in `BackupService`; failed validation still exits before projection-version mutation or broadcast.

## Decisions

- Keep `Capability.recordSale` for the dedicated `/cashier/sales` command path.
- Preserve legacy pull behavior through `GET /events`.
- Treat legacy sale-event push as intentionally removed, including future-schema sale events, because it bypasses Main-side stock validation.
- Phase 2: operation timeouts do not trigger immediate address-discovery retry or subnet probing; stale-address socket failures still do. This keeps timeout failures bounded and preserves the operation-specific timeout code. Discovery backoff and throttling remain Phase 11.
- Phase 3: `last_seen_at` remains diagnostic state only; the Main app-bar live connection dot requires an active authenticated projection WebSocket.
- Phase 3: the indicator does not breathe merely because a sync future is in progress; breathing remains tied to actual transfer activity.
- Phase 4: heartbeat uses Dart's built-in WebSocket ping/pong handling instead of an app-level heartbeat message. If pongs stop arriving, Dart closes the socket; the Cashier marks the stream disconnected through `onDone` and runs snapshot sync before reconnecting.
- Phase 5: foreground-only Cashier sync remains an explicit invariant. The controller starts while the app UI is mounted, closes the projection stream on pause/hidden/detached, and refreshes/reopens on resume. Background sync service work is out of scope.
- Phase 6: pairing availability is an independent session state. Stopping pairing should not revoke trusted peers, unregister discovery, close projection sockets, or disable the Main sync server setting.
- Phase 7: existing trusted peer records are not migrated because they already contain the active long-term HMAC secret. They remain compatible and continue authenticating with their stored secret.
- Phase 7: new pairing with an updated Main may not be compatible with older Cashier builds that reject a returned `shared_secret` different from the QR `pairing_secret`; this is the documented compatibility break required to stop using the pairing code as the long-term secret.
- Phase 7: the pairing code is rotated before the async trusted-peer write to consume the old QR code before the server yields to another pairing request.
- Phase 8: a restore emits a snapshot repair message instead of trying to summarize restored event deltas. Cashier snapshots remain the confidentiality boundary for restored product data.
- Phase 8: projection version advances from the current Main setting, not from restored data, so restore cannot move Main's projection version backward.

## Tests Added

- Cashier `POST /events` sale is rejected without changing stock.
- Rejected sale event does not increment Cashier projection version.
- Rejected sale event does not emit a Cashier projection broadcast.
- Future-schema sale events are rejected on legacy `POST /events`.
- Sale-event batches are rejected before projection.
- `/cashier/sales` still accepts, broadcasts once, and remains idempotent on retry.
- Hung ping times out and a later ping can succeed.
- Hung snapshot fetch times out explicitly.
- Hung sale command times out without marking the outbox command accepted.
- Hung WebSocket connect times out explicitly.
- Long-poll uses server wait timeout plus transport margin.
- Ping success plus projection stream fallback shows degraded, not synced.
- Sync failure after successful ping shows degraded, not synced.
- Outbox conflict shows a conflicted indicator state.
- Unpaired Cashier shows an unpaired indicator state.
- Main shell does not show a live Cashier connection dot for a merely trusted/recently seen Cashier without a live socket.
- Projection WebSocket client has a heartbeat ping interval.
- Dropped projection stream refreshes sync before reconnecting and applying later pushed messages.
- Controller starts sync without depending on widget mount internals.
- App resume refreshes snapshot before reopening projection stream.
- Controller serializes overlapping refresh triggers.
- Indicator disposal no longer owns protocol teardown directly; it disposes the controller subscription/controller.
- Stop Pairing prevents new `/pair` requests.
- Stop Pairing keeps the LAN sync server active and discovery registered.
- Stop Pairing keeps an existing Cashier projection stream connected.
- Projection broadcasts still reach the connected Cashier after pairing is stopped.
- Settings Stop Pairing hides the QR code without disabling Main sync server persistence.
- QR pairing stores a per-device shared secret that differs from the pairing code.
- Two Cashiers paired during the same active pairing flow receive different long-term HMAC secrets.
- Reusing an old QR pairing code after a successful pairing is rejected.
- Authenticated requests verify with the returned per-device shared secret, not the old pairing code.
- Existing trusted peer records continue authenticating with their stored secret.
- Restore broadcasts `snapshot_required` over an active Cashier projection stream.
- Connected Cashier applies a fresh snapshot after restore without app restart.
- Restore increments Cashier projection version monotonically from the current Main version.
- Restored private product fields do not appear in the WebSocket repair message or Cashier snapshot state.

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
- `docker compose run --rm flutter-dev dart format lib/src/ui/cashier_sync_controller.dart lib/src/ui/cashier_sync_indicator.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev dart format test/ui/cashier_sync_controller_test.dart && docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_controller_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev dart format test/ui/cashier_sync_controller_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test test/ui/minimal_ui_test.dart`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format lib/src/sync/lan_sync_server.dart lib/src/ui/settings_screen.dart test/sync/lan_sync_server_test.dart test/ui/backup_recovery_ui_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/backup_recovery_ui_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format lib/src/application/dekon_repository.dart test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev dart format test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/backup/backup_service_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format lib/src/sync/lan_sync_server.dart lib/src/sync/lan_sync_client.dart test/sync/lan_sync_server_test.dart docs/tasks/sync-hardening-v2.md`
- `docker compose run --rm flutter-dev dart format lib/src/sync/lan_sync_server.dart lib/src/sync/lan_sync_client.dart test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_client_timeout_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/backup_recovery_ui_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format lib/src/sync/lan_sync_server.dart lib/src/sync/lan_sync_client.dart test/sync/lan_sync_server_test.dart test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_server_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format lib/src/ui/cashier_sync_status.dart lib/src/ui/cashier_sync_indicator.dart lib/src/ui/transaction_screen.dart lib/src/ui/app_shell.dart lib/src/sync/sync_store.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev dart format test/ui/cashier_sync_indicator_test.dart lib/src/ui/cashier_sync_indicator.dart lib/src/ui/cashier_sync_status.dart`
- `docker compose run --rm flutter-dev dart format test/ui/cashier_sync_indicator_test.dart && docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/minimal_ui_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/main_cashier_connection_indicator_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `docker compose run --rm flutter-dev dart format test/ui/minimal_ui_test.dart && docker compose run --rm flutter-dev flutter test test/ui/minimal_ui_test.dart`
- `docker compose run --rm flutter-dev flutter test test/ui/cashier_sync_indicator_test.dart`
- `docker compose run --rm flutter-dev dart format test/ui/minimal_ui_test.dart`
- `docker compose run --rm flutter-dev flutter analyze`
- `git diff --check`
- `docker compose run --rm flutter-dev dart format lib/src/sync/lan_sync_client.dart lib/src/sync/sync_store.dart test/sync/lan_sync_client_timeout_test.dart`
- `docker compose run --rm flutter-dev flutter test test/sync/lan_sync_client_timeout_test.dart`
- `docker compose run --rm flutter-dev dart format lib/src/sync/lan_sync_client.dart && docker compose run --rm flutter-dev flutter test test/sync/lan_sync_client_timeout_test.dart`
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
- Phase 2 first analyzer run found invalid const `Duration.isNegative` asserts; removed the const-incompatible asserts.
- Phase 2 first timeout test run showed timeout-triggered discovery/subnet probing could overwrite operation-specific timeout diagnostics; fixed by not running discovery retry for `SyncTimeoutException`.
- Final focused `flutter test test/sync/lan_sync_client_timeout_test.dart` passed.
- Existing focused `flutter test test/sync/lan_sync_server_test.dart` passed.
- Phase 2 `flutter analyze` passed with no issues.
- Phase 2 `git diff --check` passed.
- Phase 3 first focused indicator run exposed old assertions that expected green/synced when freshness was missing; tests were updated to assert degraded.
- Phase 3 first minimal UI run exposed a test that treated trusted/recently seen Cashier state as live connected; updated to assert no live dot without an active socket.
- Phase 3 analyzer found an unused helper left from the old Main indicator test; removed it.
- Final focused `flutter test test/ui/cashier_sync_indicator_test.dart` passed.
- Final focused `flutter test test/ui/minimal_ui_test.dart` passed.
- Focused `flutter test test/ui/main_cashier_connection_indicator_test.dart` passed.
- Phase 3 `flutter analyze` passed with no issues.
- Phase 3 `git diff --check` passed.
- Phase 4 focused `flutter test test/ui/cashier_sync_indicator_test.dart` passed.
- Phase 4 focused `flutter test test/sync/lan_sync_server_test.dart` passed.
- Phase 4 `flutter analyze` passed with no issues.
- Phase 4 `git diff --check` passed.
- Phase 5 focused `flutter test test/ui/cashier_sync_controller_test.dart` passed.
- Existing focused `flutter test test/ui/cashier_sync_indicator_test.dart` passed after the extraction.
- Focused `flutter test test/ui/minimal_ui_test.dart` passed.
- Phase 5 `flutter analyze` passed with no issues.
- Phase 5 `git diff --check` passed.
- Phase 6 focused `flutter test test/sync/lan_sync_server_test.dart` passed.
- Phase 6 focused `flutter test test/ui/backup_recovery_ui_test.dart` passed.
- Phase 6 `flutter analyze` passed with no issues.
- Phase 6 `git diff --check` passed.
- Phase 7 first format command failed because it accidentally included the Markdown task file; Dart files were formatted before the parse error, and the corrected Dart-only format command passed.
- Phase 7 focused `flutter test test/sync/lan_sync_server_test.dart` passed.
- Phase 7 focused `flutter test test/sync/lan_sync_client_timeout_test.dart` passed.
- Phase 7 focused `flutter test test/ui/backup_recovery_ui_test.dart` passed.
- Phase 7 focused `flutter test test/sync/lan_sync_server_test.dart` passed again after moving pairing-code rotation before the async trust write.
- Phase 7 `flutter analyze` passed with no issues.
- Phase 7 `git diff --check` passed.
- Phase 8 first focused sync test run failed at compile time because the test used a non-existent client method name; fixed the test to use `applyCashierProjectionMessage`.
- Phase 8 focused `flutter test test/sync/lan_sync_server_test.dart` passed.
- Phase 8 focused `flutter test test/backup/backup_service_test.dart` passed.
- Phase 8 `flutter analyze` passed with no issues.
- Phase 8 `git diff --check` passed.

## Manual QA

Scenarios tested:
- Not run.

Results:
- Not run.

## Residual Risks

- Phase 9 through Phase 11 are not implemented yet.
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
