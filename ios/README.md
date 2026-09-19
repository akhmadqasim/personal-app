# Personal — iOS

SwiftUI app for iOS 26 (iPhone, portrait). The Xcode project is **generated** by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` and is never
committed — edit `project.yml`, not the project file.

## Build

```sh
brew install xcodegen
cd ios
xcodegen generate
open Personal.xcodeproj
```

Then in Xcode: select the `Personal` scheme and run (⌘R), or run the tests with ⌘U.

`xcodegen generate` resets `DEVELOPMENT_TEAM` — set your Team in Signing &
Capabilities after each regenerate.

First run: Settings (the gear on Today) → paste the API token → Sync now. The
exercise catalog arrives with that first sync; until then the catalog screen is
empty by design.

## Layout

| Path | Contents |
|---|---|
| `Personal/App/` | `@main` entry point, `AppEnvironment`, root tab shell |
| `Personal/Core/Design/` | `Theme` — colour, type, spacing and radius tokens |
| `Personal/Resources/` | asset catalog; `Info.plist` is generated from `project.yml` |
| `PersonalTests/` | Swift Testing unit tests |

Dependencies: GRDB.swift via SPM, resolved by Xcode on first build. Nothing else.

## Specs

- `docs/specs/ios-gym-app.md` — architecture, sync protocol, screens
- `docs/specs/ios-design-system.md` — the tokens `Theme` implements

## CI

`.github/workflows/ios-ci.yml` runs on `macos-26`: `xcodegen generate` →
`xcodebuild test` on the first available iPhone simulator. Red CI blocks merge.
