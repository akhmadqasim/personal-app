# Sync protocol (do not change without updating docs/specs)

- Base columns on every synced table, in this order: `id, updated_at, deleted_at, seq`.
- Last-write-wins per row: insert if new; overwrite if `push.updated_at > db.updated_at`; else ignore.
- `seq` is global (`sync_meta.last_seq`), assigned by the server only; UNIQUE per table.
- Push: max 500 rows, one atomic D1 batch, tables in FK order, any validation error rejects the whole batch (422).
- Pull: rows with `seq > since_seq`, ordered by `seq`, max 500 total, `has_more` + cursor.
- Deletes are soft (`deleted_at`); never hard-delete.
- Seed rows use `updated_at = 0` so user edits always win.
