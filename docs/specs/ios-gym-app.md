# Spec: iOS app "Personal" — Gym module

Date: 2026-09-19 · Status: approved (delegated) · Depends on: `gym-tracker.md`
(API + sync protocol), `ios-design-system.md` (look and feel).

## 1. Goal

A single-user SwiftUI app for iOS 26 that logs gym training offline-first and
replicates to `api.akhmadqasim.com` with the LWW + `seq` protocol. The app is
the client half of the personal hub; the gym module is the first of several,
so the shell (tabs, sync, settings, design system) is module-agnostic.

Language: English everywhere (UI, code, comments, docs).

## 2. Technical decisions

| Topic | Choice | Why |
|---|---|---|
| Platform | iOS 26+, Swift 6.2, strict concurrency | Liquid Glass chrome, modern APIs, no legacy paths |
| UI | SwiftUI, `@Observable` view models, `NavigationStack` per tab | Native, minimal boilerplate |
| Storage | GRDB.swift 7 (`DatabasePool`), schema mirrors `api/migrations` | Same SQL on both sides; sync is plain SQL |
| Project | XcodeGen (`ios/project.yml` → `Personal.xcodeproj`) | Project file is generated, never hand-edited; works from any OS |
| Networking | `URLSession` + `Codable`; bearer from Keychain | No third-party HTTP stack |
| Images | Built-in art from the asset catalog; custom photos via API + on-disk cache | Consistent look, offline |
| Charts | Swift Charts | Native |
| Tests | Swift Testing (`@Test`) for unit tests; no UI tests in v1 | Fast, deterministic |
| CI | GitHub Actions `macos-26`: xcodegen → `xcodebuild test` on an iPhone simulator | Compile + tests verified on every push even without a local Mac |

Bundle id `com.akhmadqasim.personal`, display name **Personal**, deployment
target iOS 26.0, iPhone only, portrait only.

## 3. Repository layout (`ios/`)

```
ios/
├── project.yml                     # XcodeGen: targets Personal + PersonalTests, GRDB via SPM
├── README.md                       # brew install xcodegen; xcodegen generate; open; run
├── Personal/
│   ├── App/
│   │   ├── PersonalApp.swift       # @main, builds AppEnvironment, injects via .environment
│   │   ├── AppEnvironment.swift    # database, api client, sync engine, image store, settings
│   │   └── RootTabView.swift       # Today · Programs · Progress (+ Settings sheet)
│   ├── Core/
│   │   ├── Database/
│   │   │   ├── AppDatabase.swift   # DatabasePool factory (file + in-memory for tests)
│   │   │   └── Migrations.swift    # v1 = api 0001 schema + local `dirty` column + sync_state
│   │   ├── Sync/
│   │   │   ├── SyncClient.swift    # POST /api/sync request/response Codable types
│   │   │   ├── SyncEngine.swift    # collect dirty → push → apply pull (LWW) → cursor
│   │   │   ├── SyncScheduler.swift # launch / foreground / after-save / manual, debounced
│   │   │   └── SyncStatus.swift    # observable: idle / syncing / error(message) / lastSyncedAt
│   │   ├── Networking/
│   │   │   ├── APIClient.swift     # base URL, bearer, JSON + bytes, ApiError mapping
│   │   │   └── Keychain.swift      # token get/set/delete
│   │   ├── Images/
│   │   │   ├── ImageStore.swift    # resolve image_key → UIImage (asset | disk cache | download)
│   │   │   └── ImageUploader.swift # downscale ≤1024 px, JPEG 0.8, PUT, returns image_key
│   │   ├── Design/
│   │   │   ├── Theme.swift         # colour/type/spacing tokens from ios-design-system.md
│   │   │   └── Components/         # PillButton, StatusPill, ThumbnailRow, GroupCard, SegmentedPill,
│   │   │                           #   SheetHeader, Toast, EmptyState, CircleIconButton, AmbientBackground
│   │   └── Util/                   # Clock (now in ms), Date formatting, Haptics
│   ├── Modules/Gym/
│   │   ├── Models/                 # Exercise, Program, ProgramDay, ProgramExercise, WorkoutSession, WorkoutSet
│   │   ├── GymRepository.swift     # all gym queries + writes (sets dirty/updated_at)
│   │   ├── BuiltinArt.swift        # slug → asset name, fallback symbol + accent colour
│   │   └── Features/
│   │       ├── Today/              # TodayView, TodayViewModel
│   │       ├── Session/            # SessionView, SessionViewModel, SetRow, ExercisePickerSheet
│   │       ├── Programs/           # ProgramsView, ProgramDetailView, DayEditorView (+ view models)
│   │       ├── Exercises/          # ExerciseListView, ExerciseDetailView, ExerciseEditorView
│   │       ├── Progress/           # ProgressView, ExerciseChartCard
│   │       └── Settings/           # SettingsView (token, sync, export, about)
│   ├── Resources/
│   │   ├── Assets.xcassets         # AppIcon, AccentColor, Builtin/<slug> image sets (optional art)
│   │   └── Info.plist              # via project.yml properties
│   └── PersonalTests/
│       ├── SyncEngineTests.swift   # LWW apply, dirty clearing, cursor, pagination loop
│       ├── GymRepositoryTests.swift# next-up, last set per exercise, history grouping
│       ├── MigrationsTests.swift   # schema matches expected columns
│       └── APIClientTests.swift    # URLProtocol stub: auth header, error mapping
└── .github/workflows/ios-ci.yml    # (at repo root) paths: ios/**
```

## 4. Local schema

Identical to `api/migrations/0001_gym.sql` plus, on every synced table:

```sql
dirty INTEGER NOT NULL DEFAULT 0      -- 1 = changed locally, not yet acknowledged
```

`seq` is nullable locally (NULL until the server assigns one) and not UNIQUE.
Plus `sync_state(key TEXT PRIMARY KEY, value INTEGER NOT NULL)` holding
`since_seq` (default 0) and `last_synced_at`.

The seed catalog is **not** embedded: the first sync pulls it. Until the first
sync succeeds the Exercises list shows an empty state with a "Sync now" CTA.

Foreign keys are enforced (`PRAGMA foreign_keys = ON`).

## 5. Sync engine (client rules from the API spec)

Every write through `GymRepository` sets `updated_at = now_ms()` and `dirty = 1`.
Deletes set `deleted_at` (soft) the same way. Reads always filter
`deleted_at IS NULL`.

`SyncEngine.sync()` (serialised; a second call while running just marks
"run again"):

1. Snapshot dirty rows per table (FK order, max 500 in total per request);
   remember `(table, id, updated_at)` of what was pushed. Chunk in FK order too:
   a parent goes in the same or an earlier chunk than its children, because an
   FK violation is a 422 retrying cannot repair.
2. `POST /api/sync { since_seq, push }` — the network phase writes nothing.
   The cursor lives in memory (`since_seq = response.seq` for the next request)
   and the pulled pages are collected. Loop, at most 20 round trips per run,
   while the server answers `has_more` or dirty rows are still unsent.
3. Then one write transaction for the whole run:
   - strict attempt: `PRAGMA defer_foreign_keys = ON`, pulled rows table by
     table in FK order — the server pages by `seq` and an edited parent gets a
     new one, so a child can arrive a page before its parent. Per row: if a
     local row exists with `dirty = 1` and `local.updated_at >
     incoming.updated_at` → keep local; otherwise write the incoming row with
     `dirty = 0` and its `seq`;
   - if that transaction fails, retry it once in lenient mode: immediate
     foreign keys and one savepoint per row, so a row the database refuses (a
     missing NOT NULL column, an orphan) is skipped and logged instead of
     wedging the cursor on that page for every future run;
   - in the same transaction: `dirty = 0` for each pushed row whose
     `updated_at` is unchanged since the snapshot, then `since_seq` = the last
     response's `seq` and `last_synced_at = now`.
4. A failure in either phase writes nothing at all: the cursor stays where it
   was and the next trigger retries the same pages.
5. Errors: 401 → status `error("Check your API token in Settings")`; 409 →
   retry after 1 s, up to 3 times; 422 → status error with the first message
   (should never happen; rows stay dirty); network/5xx → status error, rows
   stay dirty, next trigger retries.

Triggers (`SyncScheduler`): app launch, scene becomes active, 2 s after any
repository write (debounced), manual "Sync now". Status is shown as a small
line in Settings and a toast on failure.

## 6. Screens (design per `ios-design-system.md`)

**Today** — "✦ Today" large title, gear → Settings sheet. Card "Next up":
picks the first day of the active program whose name has not been logged in
the last 6 days (fallback: first day). Meta "N exercises · ~M min" (M = sum of
sets × (rest + 40 s)). CTA **Start session** → creates `workout_session`
(program_day_id set) and one `workout_set` per program exercise target set,
prefilled from the last completed set of that exercise (else target weight/
reps), `completed = 0` → pushes Session. Below: **History ›** — sessions
grouped by day with status pill Completed (finished) / In progress; tap → Session.
Empty state before any program: "No program yet" + CTA "Create program".

**Session** — ambient background from the first exercise's art; caption
"Push A · Tue 19 Sep · 00:42:10 elapsed"; title = day name (or "Free session");
action row **Finish** (sets `finished_at`, haptic success, pops) ·
**Add exercise** (picker sheet) · **More** (menu: Rename, Discard →
slide-to-confirm sheet soft-deletes session and sets). One `GroupCard` per
exercise: header (40 pt art, name, muscle chip, "Last time 57.5 × 8"), set
rows `#1  60 kg × 8  ○/✓`; tap a set → inline editor (weight decimal pad, reps
stepper, RPE optional); swipe → Delete (soft); "+ Add set" copies the previous
set. Completing a set is one tap on the circle.

**Programs** — list of programs as rows (art of first exercise of first day;
status pill Active); "+" circle button → new program sheet (name). Program
detail: grouped card per day (name, N exercises); reorder via drag handles;
"Make active". Day editor: rows per program exercise with target sets × reps,
weight, rest; "+ Add exercise" → Exercise picker (chips by muscle group,
search); tap row → target editor sheet.

**Exercises** (pushed from Programs toolbar and from the picker) — chips for
muscle group; rows show art tile on `Soft` accent (or custom photo); "+" →
editor (name, muscle group, equipment, notes, photo from camera/library →
`ImageUploader`, requires network — disabled offline with hint). Built-in
rows are editable too (LWW: user edit wins).

**Progress** — per exercise (top 6 by recent volume + search): card with a
line chart of best set weight per session (last 12 weeks), best set tile,
weekly volume bars. Uses `dataviz` rules; accent = muscle-group colour.

**Settings** (sheet) — grouped rows: API token (secure field + "Test
connection" → `GET /api/health` with token via `/api/sync` empty push);
Sync now + last synced; Export (opens share sheet with `/api/gym/export`
JSON); About (version, commit). Token saved to Keychain; changing it triggers
a sync.

## 7. Images

`ImageStore.image(for key: String?) async -> UIImage?`:
- `nil` → generic placeholder tile.
- `builtin/<slug>` → asset `Builtin/<slug>` if present, else
  `BuiltinArt.fallback(slug)` = SF Symbol on the muscle-group `Soft` tile
  (consistent by construction; real illustrations can be dropped into the
  asset catalog later without code changes).
- `exercises/…` → disk cache under `Caches/images/<sha256(key)>`, else
  download `GET /api/gym/images/{key}` (bearer) and cache; keys are immutable.

`ImageUploader.upload(image, for exerciseId)`: resize longest side to 1024,
JPEG quality 0.8, `PUT /api/gym/exercises/{id}/image` (`Content-Type:
image/jpeg`), then `GymRepository.setImageKey(exerciseId, key)` (dirty) →
sync.

## 8. Error handling

`ApiError` mirrors the server codes (`unauthorized`, `not_found`, `conflict`,
`payload_too_large`, `unsupported_media_type`, `validation_failed`,
`internal`, plus `network`, `decoding`). Screens never show raw errors: the
toast copy is a fixed English sentence per case. Repository writes cannot
fail on validation because the UI constrains inputs (reps ≥ 1, weight ≥ 0,
RPE 1–10, names trimmed non-empty).

## 9. Testing

Unit tests run against an in-memory `DatabaseQueue` with the same migrations:
- `SyncEngineTests`: pushes only dirty rows in FK order and ≤ 500; applies
  pull with LWW (dirty-newer local wins, otherwise incoming); clears dirty
  only when unchanged since snapshot; follows `has_more`; stores cursor;
  maps 401/409/422/network correctly (stubbed `APIClient`).
- `GymRepositoryTests`: start session prefills from last completed set; next-up
  selection; history grouping by day; soft delete hides rows.
- `MigrationsTests`: every table has `id, updated_at, deleted_at, seq, dirty`.
- `APIClientTests`: bearer header present; error body → `ApiError`.

CI (`ios-ci.yml`, `macos-26`): `brew install xcodegen`, `xcodegen generate`,
`xcodebuild test -scheme Personal -destination 'platform=iOS Simulator,name=iPhone 17'`.
Red CI blocks merge, same as the API.

## 10. Out of scope (later)

Dashboard tab, widgets, Apple Watch, HealthKit, rest timer notifications,
plate calculator, multi-user, CloudKit.
