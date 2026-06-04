# Core Architecture

Dekon keeps inventory state conflict-free by treating every business mutation
as an append-only event. Projections and reports may be rebuilt from the event
log, but they must not become the source of truth.

## Module Boundaries

- `lib/src/domain`: Pure Dart domain rules. No Flutter, SQLite, HTTP, or file
  system imports. Owns event envelopes, schema/version rules, canonical JSON,
  payload hashes, validation, and hybrid logical clocks.
- `lib/src/persistence`: SQLite adapters and transaction boundaries. Owns table
  creation for core event storage, local device identity persistence, duplicate
  detection, and unsupported-event storage.
- `lib/src/platform`: Platform integration helpers, such as choosing the app
  database file path. Platform code must stay out of domain code.
- `lib/src/sync`: Future LAN transport and pairing code. It will accept or
  reject events through the persistence boundary, not by writing SQLite rows
  directly.
- `lib/src/reporting`: Future read models and queries. Reports read projections
  or event-derived views; they do not mutate inventory.
- `lib/src/ui`: Future Flutter screens. UI calls application services and never
  computes durable stock totals directly.

## Core Invariants

- `event_id` is globally unique and stored under a SQLite unique constraint.
- Rewriting or deleting events is forbidden in application code.
- Duplicate events with the same `event_id` and canonical payload are ignored.
- Duplicate events with the same `event_id` but different payload/hash fail
  loudly because they indicate corruption or a sync bug.
- Future schema versions are stored as unsupported events and are not applied by
  projectors until the app understands their schema.
- Payload hashes are SHA-256 over canonical JSON with sorted object keys.
- Hybrid logical clocks are used for deterministic ordering; local wall-clock
  timestamps are display metadata only.
