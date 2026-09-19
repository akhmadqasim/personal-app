# iOS "Personal" (Gym module) — Implementation Plan

> For agents: work task by task, in order; each task ends with a commit. Code
> cannot be compiled on the authoring machine (Windows) — write Swift that
> compiles under Xcode 26 / Swift 6.2 strict concurrency, keep files small,
> and rely on the CI workflow (Task 1) plus the user's MacBook for the build.
> Prefer boring, well-known SwiftUI/GRDB APIs over clever ones.

**Goal:** Ship `ios/` — a SwiftUI iOS 26 app that logs gym sessions offline
and syncs with the API, styled per the design system.

**Architecture:** Feature folders under `Modules/Gym/Features`, each
`View` + `@Observable @MainActor ViewModel`; all persistence through
`GymRepository` (GRDB `DatabasePool`); `SyncEngine` is the only code that talks
to `/api/sync`; `AppEnvironment` wires everything and is injected with
`.environment(...)`.

**Tech stack:** Swift 6.2, SwiftUI, GRDB.swift 7.x (SPM), Swift Charts, Swift
Testing, XcodeGen 2.x, GitHub Actions `macos-26`.

**Specs:** `docs/specs/ios-gym-app.md`, `docs/specs/ios-design-system.md`,
`docs/specs/gym-tracker.md` (protocol), `api/migrations/0001_gym.sql` (schema).

## Global constraints

- English only. Bundle id `com.akhmadqasim.personal`, product `Personal`, iOS 26.0, iPhone, portrait.
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode 26 project setting `defaultIsolation: MainActor` in project.yml). Non-UI services that must run off the main actor are declared `nonisolated` / actors explicitly.
- No third-party dependencies other than GRDB.swift.
- Local schema = `api/migrations/0001_gym.sql` + `dirty INTEGER NOT NULL DEFAULT 0` per synced table + `sync_state`; `seq` nullable, not UNIQUE.
- Sync rules exactly as spec §5 (LWW, ≤500 rows per push, `has_more` loop, dirty clearing by unchanged `updated_at`).
- Base URL `https://api.akhmadqasim.com`; bearer token in Keychain (service `com.akhmadqasim.personal`, account `api_token`).
- Every task: `xcodegen generate` must succeed; tests under `PersonalTests` must compile and pass in CI.
- Commits: conventional, no attribution trailers.

---

### Task 1: XcodeGen project, app shell, theme tokens, CI

**Files:** `ios/project.yml`, `ios/README.md`, `ios/Personal/App/PersonalApp.swift`,
`ios/Personal/App/AppEnvironment.swift` (stub holding nothing yet),
`ios/Personal/App/RootTabView.swift`, `ios/Personal/Core/Design/Theme.swift`,
`ios/Personal/Resources/Assets.xcassets/{AppIcon.appiconset,AccentColor.colorset}/Contents.json`,
`ios/Personal/Resources/Info.plist` (only if XcodeGen `info.properties` is insufficient),
`ios/PersonalTests/SmokeTests.swift`, `.github/workflows/ios-ci.yml`.

- [ ] `project.yml`:

```yaml
name: Personal
options:
  bundleIdPrefix: com.akhmadqasim
  deploymentTarget:
    iOS: "26.0"
  xcodeVersion: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: "7.11.0"
targets:
  Personal:
    type: application
    platform: iOS
    sources: [Personal]
    dependencies:
      - package: GRDB
    info:
      path: Personal/Resources/Info.plist
      properties:
        CFBundleDisplayName: Personal
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSCameraUsageDescription: Take a photo of your equipment for the exercise catalog.
        NSPhotoLibraryUsageDescription: Choose a photo for the exercise catalog.
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.akhmadqasim.personal
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
  PersonalTests:
    type: bundle.unit-test
    platform: iOS
    sources: [PersonalTests]
    dependencies:
      - target: Personal
schemes:
  Personal:
    build:
      targets: { Personal: all, PersonalTests: [test] }
    test:
      targets: [PersonalTests]
```

- [ ] `Theme.swift`: `enum Theme` with nested `Colors` (every token from the design system as `Color(light:dark:)` via a `UIColor { traits in … }` initialiser extension), `Type` (Font presets: `largeTitle`, `title`, `section`, `headline`, `body`, `secondary`, `caption`, `pill`, `numeric` (`.monospacedDigit()`)), `Spacing` (4-pt grid constants, `screenInset = 16`, `cardPadding = 16`), `Radius` (`card = 20`, `thumb = 12`, `input = 12`, `sheet = 28`), and `MuscleGroup` colour map `accent(for slug: String) -> Color` + `soft(for:)`.
- [ ] `RootTabView`: `TabView` with three `Tab`s (Today `sun.max`, Programs `list.bullet.rectangle`, Progress `chart.line.uptrend.xyaxis`) each containing a placeholder `Text` for now; `.tabBarMinimizeBehavior(.onScrollDown)`; tint `Theme.Colors.ink`.
- [ ] `PersonalApp`: `@main`, `WindowGroup { RootTabView() }` with `.environment(AppEnvironment.shared)` (stub `@Observable final class AppEnvironment { static let shared = AppEnvironment() }`).
- [ ] `SmokeTests.swift`: `@Test func themeHasInk() { #expect(Theme.Colors.ink != .clear) }`.
- [ ] `ios-ci.yml`:

```yaml
name: iOS CI
on:
  pull_request: { paths: ["ios/**", ".github/workflows/ios-ci.yml"] }
  push: { branches: [main], paths: ["ios/**", ".github/workflows/ios-ci.yml"] }
jobs:
  test:
    runs-on: macos-26
    timeout-minutes: 45
    defaults: { run: { working-directory: ios } }
    steps:
      - uses: actions/checkout@v6
      - run: sudo xcode-select -s /Applications/Xcode_26.0.app || sudo xcode-select -s /Applications/Xcode.app
      - run: brew install xcodegen
      - run: xcodegen generate
      - run: xcodebuild -resolvePackageDependencies -project Personal.xcodeproj -scheme Personal
      - run: |
          xcodebuild test -project Personal.xcodeproj -scheme Personal \
            -destination 'platform=iOS Simulator,name=iPhone 17' \
            -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO | tee xcodebuild.log | tail -50
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: xcodebuild-log, path: ios/xcodebuild.log }
```

If the runner image has no `iPhone 17` simulator, use `xcrun simctl list devices available` in a step and pick the first iPhone.
- [ ] `README.md`: brew install xcodegen; `xcodegen generate`; open `Personal.xcodeproj`; set your team in Signing; run on device; put the API token in Settings.
- [ ] Commit: `feat(ios): project scaffold, theme tokens, tab shell, CI`.

---

### Task 2: Database, migrations, models, repository (with tests)

**Files:** `Core/Database/AppDatabase.swift`, `Core/Database/Migrations.swift`,
`Modules/Gym/Models/*.swift` (6 records), `Modules/Gym/GymRepository.swift`,
`Core/Util/Clock.swift`, `PersonalTests/MigrationsTests.swift`,
`PersonalTests/GymRepositoryTests.swift`.

- [ ] `Clock`: `protocol Clock: Sendable { func nowMs() -> Int64 }`, `struct SystemClock`, `final class FixedClock` for tests.
- [ ] `AppDatabase`: `static func open(at url: URL) throws -> DatabasePool` (WAL, `foreignKeysEnabled = true`), `static func inMemory() throws -> DatabaseQueue`; both run `Migrations.migrator.migrate(db)`.
- [ ] `Migrations.migrator` registers `"v1"` executing the API's `0001_gym.sql` statements translated 1:1, with `seq INTEGER` (nullable, no UNIQUE), an extra `dirty INTEGER NOT NULL DEFAULT 0` on the six tables, an index on `(dirty)` per table, and `CREATE TABLE sync_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL); INSERT INTO sync_state VALUES ('since_seq', 0), ('last_synced_at', 0);`.
- [ ] Models: `struct Exercise: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable` with `static let databaseTableName = "exercise"` and properties exactly matching columns (`id: String`, `updatedAt: Int64`, `deletedAt: Int64?`, `seq: Int64?`, `dirty: Bool`, `name`, `muscleGroup`, `equipment`, `imageKey: String?`, `notes: String?`); `static let databaseColumnDecodingStrategy/EncodingStrategy = .convertToSnakeCase`... (GRDB: set `databaseColumnDecodingStrategy = .convertFromSnakeCase` and `databaseColumnEncodingStrategy = .convertToSnakeCase`). Same for `Program`, `ProgramDay`, `ProgramExercise`, `WorkoutSession`, `WorkoutSet`. Enums `MuscleGroup` and `Equipment` as `String` enums with the API's values and a `label`.
- [ ] `GymRepository` (`final class`, `Sendable`, holds `DatabaseWriter` + `Clock`): 
  - reads: `activeProgram()`, `days(of:)`, `programExercises(of dayId:)`, `exercises(muscleGroup:search:)`, `exercise(id:)`, `sessions(limit:)`, `session(id:)`, `sets(of sessionId:)`, `lastCompletedSet(exerciseId:)`, `nextUpDay()` (spec §6), `bestSetPerSession(exerciseId:, weeks:)`.
  - writes (all set `updatedAt = clock.nowMs()`, `dirty = true`): `upsert(_:)` for each model, `softDelete(_ table:, id:)`, `startSession(from day: ProgramDay?) -> WorkoutSession` (creates sets prefilled), `finishSession(id:)`, `setImageKey(exerciseId:key:)`, `createProgram(name:)`, `setActiveProgram(id:)`.
  - observation: `func observeSessions() -> ValueObservation<...>` helpers used by view models via `ValueObservation.tracking`.
- [ ] Tests: migrations have the expected columns (`PRAGMA table_info`); `startSession` prefills weight/reps from the last completed set; `nextUpDay` skips days logged in the last 6 days; soft-deleted rows are invisible; every write flips `dirty`.
- [ ] Commit: `feat(ios): database, models and gym repository`.

---

### Task 3: Networking, Keychain, SyncEngine, scheduler (with tests)

**Files:** `Core/Networking/APIClient.swift`, `Core/Networking/ApiError.swift`,
`Core/Networking/Keychain.swift`, `Core/Sync/SyncClient.swift`,
`Core/Sync/SyncEngine.swift`, `Core/Sync/SyncScheduler.swift`,
`Core/Sync/SyncStatus.swift`, `PersonalTests/APIClientTests.swift`,
`PersonalTests/SyncEngineTests.swift`.

- [ ] `ApiError: Error, Equatable` cases `unauthorized, notFound, conflict, payloadTooLarge, unsupportedMediaType, validation([FieldError]), server(String), network(String), decoding`. `FieldError { table, id, message }`.
- [ ] `APIClient` (`actor`): `init(baseURL: URL, tokenProvider: @Sendable () -> String?, session: URLSession = .shared)`; `func postJSON<T: Decodable>(_ path: String, body: some Encodable) async throws -> T`; `func putBytes(_ path: String, data: Data, contentType: String) async throws -> [String: String]`; `func getData(_ path: String) async throws -> (Data, String?)` (bytes + content type). Maps HTTP status + `{code,message,errors}` body to `ApiError`. Adds `Authorization: Bearer <token>`.
- [ ] `Keychain`: `enum Keychain { static func token() -> String?; static func setToken(_:) throws; static func deleteToken() }` using `SecItem*` with service `com.akhmadqasim.personal`, account `api_token`.
- [ ] `SyncClient`: `struct SyncRequest: Encodable { sinceSeq: Int64; push: [String: [JSONRow]] }`, `struct SyncResponse: Decodable { seq: Int64; hasMore: Bool; pull: [String: [JSONRow]] }`, where `JSONRow = [String: JSONValue]` and `enum JSONValue: Codable, Equatable { null, bool, int(Int64), double(Double), string(String) }`. Keys are snake_case as on the wire (`CodingKeys`).
- [ ] `SyncEngine` (`actor`): `init(db: DatabaseWriter, api: APIClient, clock: Clock)`; `static let tables = ["exercise","program","program_day","program_exercise","workout_session","workout_set"]` (FK order); `static let maxPushRows = 500`; `func sync() async -> SyncOutcome` implementing spec §5 with generic row handling via `Row` (read `SELECT * FROM <t> WHERE dirty = 1`, strip `dirty`, send `seq` omitted) and `INSERT OR REPLACE` for incoming rows after the LWW check; clears dirty by comparing `updated_at`; stores cursor; loops on `has_more`/remaining dirty (≤ 20 iterations); returns `.success(pulled: Int, pushed: Int)` / `.failure(ApiError)`; 409 retry ×3 with 1 s sleep.
- [ ] `SyncStatus` (`@Observable @MainActor final class`): `state: .idle | .syncing | .error(String)`, `lastSyncedAt: Date?`.
- [ ] `SyncScheduler` (`@MainActor final class`): `func trigger(_ reason: Reason)` debounced 2 s for `.afterWrite`, immediate for `.launch/.foreground/.manual`; serialises runs; updates `SyncStatus`; exposes `func syncNow() async`.
- [ ] Tests with an in-memory DB and a `URLProtocol` stub (`StubURLProtocol` registered on a custom `URLSessionConfiguration.ephemeral`): auth header present; 401 → `.unauthorized`; push contains only dirty rows in FK order and omits `dirty`; pull with newer incoming overwrites; pull with older incoming than a dirty local keeps local; dirty cleared only when unchanged; `has_more` loop follows the cursor; cursor persisted in `sync_state`.
- [ ] Commit: `feat(ios): api client, keychain and sync engine`.

---

### Task 4: Design components + images

**Files:** `Core/Design/Components/{PillButton,StatusPill,ThumbnailRow,GroupCard,SegmentedPill,SheetHeader,Toast,EmptyState,CircleIconButton,AmbientBackground}.swift`,
`Core/Images/ImageStore.swift`, `Core/Images/ImageUploader.swift`,
`Modules/Gym/BuiltinArt.swift`, `Core/Util/Haptics.swift`, `Core/Util/DateFormat.swift`.

- [ ] Components implement §3 of the design system exactly (sizes, radii, fonts, colours from `Theme`); each has a `#Preview` for light and dark. `PillButton(style: .primary|.secondary|.accent(Color)|.destructive, title:, systemImage:, action:)`, `StatusPill(kind: .completed|.inProgress|.skipped|.pr|.draft)`, `ThumbnailRow(thumbnail: some View, caption:, title:, meta: [(symbol, text)], trailing: some View, pill: StatusPill?)`, `GroupCard { content }`, `SegmentedPill(selection: Binding<Int>, labels:)`, `SheetHeader(symbol:, title:, subtitle:, onClose:)`, `Toast` view modifier `.toast(_ item: Binding<ToastItem?>)`, `EmptyState(symbol:, title:, message:, action:)`, `CircleIconButton(systemImage:, action:)` using `.glassEffect(.regular.interactive(), in: .circle)`, `AmbientBackground(image: UIImage?)`.
- [ ] `BuiltinArt.symbol(for slug: String) -> String` (map the 60 seed slugs to SF Symbols by equipment/muscle: barbell → `dumbbell`, machine → `figure.strengthtraining.traditional`, cable → `cable.connector.horizontal`, bodyweight → `figure.core.training`, cardio → `figure.run`, default `dumbbell`), `BuiltinArt.tile(slug:muscleGroup:size:) -> some View`.
- [ ] `ImageStore` (`actor`): `func image(for key: String?, muscleGroup: String) async -> UIImage?` per spec §7 (asset lookup `UIImage(named: "Builtin/\(slug)")`, disk cache with SHA-256 file names via `CryptoKit`, download through `APIClient.getData`). `ImageUploader.upload(_ image: UIImage, exerciseId: String) async throws -> String` (resize via `UIGraphicsImageRenderer`, JPEG 0.8, `PUT`).
- [ ] Commit: `feat(ios): design components, built-in art and image store`.

---

### Task 5: Today + Session features

**Files:** `Modules/Gym/Features/Today/{TodayView,TodayViewModel}.swift`,
`Modules/Gym/Features/Session/{SessionView,SessionViewModel,ExerciseCard,SetRow,SetEditorSheet,ExercisePickerSheet}.swift`,
`App/AppEnvironment.swift` (now holds db, repository, api, syncEngine, scheduler, syncStatus, imageStore), `App/RootTabView.swift` (Today tab wired).

- [ ] Behaviour per spec §6 (Today, Session). View models observe the DB with `ValueObservation` (`for await` over `values(in:)`) and call repository writes; after each write `scheduler.trigger(.afterWrite)`.
- [ ] Session timer: elapsed from `startedAt` updated every second while visible (`TimelineView(.periodic(from:by: 1))`).
- [ ] Finish: haptic success, toast "Session saved", pop.
- [ ] Discard: sheet with slide-to-confirm (a `DragGesture` capsule; at ≥ 90% confirms) → soft delete session + sets.
- [ ] Commit: `feat(ios): today and session screens`.

---

### Task 6: Programs + Exercises + Settings

**Files:** `Modules/Gym/Features/Programs/{ProgramsView,ProgramsViewModel,ProgramDetailView,DayEditorView,TargetEditorSheet}.swift`,
`Modules/Gym/Features/Exercises/{ExerciseListView,ExerciseDetailView,ExerciseEditorView}.swift`,
`Modules/Gym/Features/Settings/{SettingsView,SettingsViewModel}.swift`, `RootTabView.swift`.

- [ ] Per spec §6. Exercise editor photo: `PhotosPicker` + camera via `UIImagePickerController` wrapper; upload disabled when `syncStatus.state == .error` or no token; shows progress; on success `setImageKey` and toast.
- [ ] Settings: `SecureField` for token → `Keychain.setToken` → `scheduler.trigger(.manual)`; "Test connection" posts an empty sync and shows toast; Export → `APIClient.getData("/api/gym/export")` → `ShareLink` with a temp file `gym-export-<date>.json`; About shows `CFBundleShortVersionString` + build.
- [ ] Commit: `feat(ios): programs, exercises and settings screens`.

---

### Task 7: Progress tab + polish

**Files:** `Modules/Gym/Features/Progress/{ProgressView,ProgressViewModel,ExerciseChartCard}.swift`, `RootTabView.swift`.

- [ ] Charts with Swift Charts: line + area of best set weight per session over 12 weeks, bar chart of weekly volume (Σ weight × reps); colours from muscle-group accent; axis labels in `caption`; follow the `dataviz` skill rules (no 3-D, consistent palette, readable in dark mode).
- [ ] Empty state when fewer than 2 sessions exist for an exercise.
- [ ] Accessibility pass: labels on icon buttons, Dynamic Type check on rows, Reduce Motion respected in `SetRow` completion animation.
- [ ] Commit: `feat(ios): progress charts and accessibility polish`.

---

## Self-review

- Spec coverage: §2 stack → T1; §3 layout → T1–T7; §4 schema → T2; §5 sync → T3; §6 screens → T5–T7; §7 images → T4/T6; §8 errors → T3/T5; §9 tests/CI → T1–T3; design system → T4.
- Interfaces: `GymRepository` (T2) is consumed by T5–T7; `SyncEngine.sync()` (T3) by `SyncScheduler` (T3) by view models (T5–T6); `ImageStore` (T4) by T5–T6; `Theme` (T1) by everything.
- Deliberately interface-level rather than verbatim code: compilation happens in CI/on the MacBook, so implementers must own the Swift details.
