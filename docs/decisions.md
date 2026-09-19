# Decisions log

Rulings made autonomously while implementing the gym tracker (API + iOS) on
2026-09-19. Each entry: what was decided, why, and what it costs if wrong.
Revert or revisit any of them by editing the spec first.

## API (`api/`)

1. **In-batch CAS guard on `sync_meta.last_seq`** runs as the FIRST statement of
   the push batch, bound to the `last_seq` read before the batch. A concurrent
   sync collides on the `sync_meta.key` primary key, the whole batch rolls back
   → 409. Placing it last (bound to the new value) misses equal-sized races.
   Cost if wrong: one extra statement per push.
2. **`since_seq` is clamped to `last_seq` on input** so a cursor beyond the
   server's counter self-heals. Cursors above 2^53−1 cannot cross the wire
   (JSON number precision) and are not handled; real `seq` values never get
   near that.
3. **FK violations return 422 with empty `table`/`id`**; the client must push
   in FK order (documented in both specs). Naming the offending row can wait.
4. **Tests share one local DB, run sequentially, and use `sync_all`** for
   every echo assertion because pulls are capped at 500 rows total.
5. **Harness on Linux**: `kill -9 -- -<pgid>` (procps ignores a bare negative
   pid), wrangler output to a log file, 60 s client timeout, 15-min watchdog,
   CI runs the suite without a pipeline so no grandchild holds the runner's
   stdout.
6. **`strip = "debuginfo"`** in the release profile (`strip = true` breaks
   wasm-bindgen's reference-types detection).
7. Left as is: `respond_with_errors`, `Math::random()` nonce, buffered image
   serve (≤ 5 MB), exact-match `/api/health`, whole export in memory.
8. **Deploy is a human step**: `database_id` placeholder, `API_TOKEN` and the
   two GitHub secrets — see `api/README.md`. The deploy workflow fails until
   then; that is expected.

## iOS (`ios/`)

9. **Plan was interface-level, not verbatim code**; CI on `macos-26` and the
   MacBook are the compilers. Every task was reviewed as "read as the
   compiler would" before CI.
10. **`Theme.Type` → `Theme.Typography`** (`Type` is not a legal nested name).
11. **`protocol Clock` → `AppClock`** to leave `Swift.Clock` usable.
12. **Pull is applied in one transaction per run** (network loop collects all
    pages, then strict apply with `defer_foreign_keys`, then a lenient per-row
    savepoint fallback that skips rows the database refuses). Cost: up to
    10k rows buffered per run; a skipped row is logged and counted in
    `SyncOutcome.skipped`, not shown yet.
13. **422 shows the server's first validation message** (spec §5 wins over §8).
14. **`numeric` stays 28 pt**; session rename lives in `workout_session.notes`;
    upload gating = token present + sync not in error (offline is not detected
    separately); area chart under the best-set line kept (judge on device).
15. **Glass back button replaces the system one** on pushed screens, so the
    interactive edge-swipe is lost there.
16. **`ProgramsView` uses a type-erased `NavigationPath`** because it pushes
    two route enums.
17. **`syncNow()` joins an in-flight run** and returns its outcome so
    "Test connection" cannot report a run that did not happen.
18. Parked (known, not fixed): "Sync now" inside the exercise picker sheet
    cannot show its result in the sheet; a catalog read error renders the
    "No exercises yet" state; a background sync that fails every cycle
    re-toasts every cycle; `ProgramDetail`/`DayEditor` read twice on first
    appearance; no app icon art; `Package.resolved` is not committed so GRDB
    floats within 7.x; fonts scale without per-style caps; `SegmentedPill`,
    elevation tokens and some pill kinds are defined but unused.

## Verify first on the device

1. Set the Team in Signing after every `xcodegen generate`.
2. Settings → paste token → Sync now; the 60-exercise catalog must appear
   under Programs → 🔍. Try a wrong token: Status must say "Check your API
   token in Settings".
3. Create program → day → exercises → Today "Next up" → Start session → tick,
   edit, delete, add sets → Finish → History; two sessions → Progress charts.
4. Photo upload from the library on a real device; relaunch; the photo must
   persist (proves `image_key` synced and resolved).
