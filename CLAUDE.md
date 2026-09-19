# personal-app

Personal monorepo: `api/` (Rust on Cloudflare Workers, D1, R2) and `ios/` (SwiftUI, later).
Single user, static bearer token. Modules live in `api/src/modules/`; the sync engine
replicates each module's tables to the iOS app (offline-first, last-write-wins + `seq`).

## Commands (run in `api/`)
- `npx wrangler dev --var API_TOKEN:dev` — local server with emulated D1/R2
- `cargo test --lib` — unit tests (pure logic, no Cloudflare)
- `cargo test --test api` — integration tests (starts `wrangler dev` itself)
- `cargo fmt --all && cargo clippy --all-targets -- -D warnings` — must pass before commit
- Deploy: push to `main` (CI → D1 migrations → `wrangler deploy`)
- Build note: `[profile.release] strip` must stay `"debuginfo"`, not `true`. `strip = true` drops the `target_features` custom section, and `wasm-bindgen` then fails with `externref table required for catch wrappers`.

## Where things are
- Specs `docs/specs/`, plans `docs/plans/`
- Rules `.claude/rules/` — read before editing code
- New module: `.claude/skills/new-module`
