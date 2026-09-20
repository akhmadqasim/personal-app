---
name: new-module
description: Add a new module to api/ (tables synced to the iOS app and/or REST routes). Use when the user asks for a new domain such as servers, network, notes.
---

# Add a module to `api/`

1. **Spec first**: write `docs/specs/<module>.md` (tables with base columns, enums, endpoints, out of scope). Get approval.
2. **Migration**: `bunx wrangler d1 migrations create DB <module>` → tables with `id, updated_at, deleted_at, seq INTEGER NOT NULL UNIQUE` first; FK order matters. Seeds use `updated_at = 0` and allocate `seq` from `sync_meta.last_seq` (see `migrations/0002_gym_seed.sql`).
3. **Code** in `src/modules/<module>/`:
   - `tables.rs` — `pub static TABLES: [SyncTable; N]`, parents before children.
   - `validate.rs` — one `fn(&Row) -> Vec<String>` per table (types are already checked).
   - `mod.rs` — `pub use tables::TABLES;` and `pub fn routes(Router) -> Router` for extra endpoints under `/api/<module>/…`.
   - Register in `src/modules/mod.rs`: append tables to `sync_tables()` (respecting cross-module FK order) and chain `routes`.
4. **Tests**: unit tests in `validate.rs`; integration tests in `tests/api/<module>/` registered from `tests/api/main.rs`. Cover: sync round trip, each validation rule, each endpoint's success + auth + error cases.
5. **Docs**: update `CLAUDE.md` only if commands change. Never edit `.claude/rules/sync.md` without changing the spec.
6. `cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test --lib && cargo test --test api`, then commit.

Action modules (things that must be online, e.g. server restart) do not use sync: give them REST routes and their own tables without base columns.
