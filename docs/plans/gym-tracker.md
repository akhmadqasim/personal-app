# Gym Tracker API — Implementation Plan

> For agents: work task by task, in order. Each task ends with green tests and a
> commit. Steps use `- [ ]` checkboxes. Read the spec first.

**Goal:** Ship the `api/` Rust Worker on Cloudflare (D1 + R2) that the iOS app
syncs gym data to, with health, sync, export and image endpoints.

**Architecture:** One Worker, `workers-rs` built-in `Router`. Pure logic (SQL
builders, validation, auth check, error JSON) lives in plain functions with
no Cloudflare types so it is unit-tested natively; I/O is thin and covered by
HTTP integration tests against `wrangler dev`.

**Tech stack:** Rust 1.98 (edition 2024), `worker` 0.8 (`d1` feature), `serde_json`,
`subtle`; Node 24 + `wrangler` 4 for local dev/tests; tests use
`libtest-mimic`, `reqwest`, `tokio`.

**Spec:** `docs/specs/gym-tracker.md`

## Global constraints

- Everything in English: code, comments, docs, error messages, catalog names.
- Route prefix `/api/…`, no version segment.
- `unwrap`/`expect` are denied in `src/` (clippy). Tests may allow them.
- Every synced table has `id, updated_at, deleted_at, seq` first, in that order.
- All errors are `{"code","message"}` JSON with the status from the spec.
- Push limit 500 rows; pull limit 500 rows total; image limit 5 MB.
- No `*.workers.dev` exposure (`workers_dev = false`).
- Commit messages: conventional (`feat:`, `test:`, `chore:`, `docs:`), no
  attribution trailers.
- All commands below run inside `api/` unless stated otherwise.

## Verified API facts (worker 0.8.6)

- `Router::new().get(path, fn)`, `.get_async/.post_async/.put_async(path, |req, ctx| async move {...})`,
  `.or_else_any_method_async(path, …)`, `.run(req, env).await`. Params: `:id`, catch-all `*key`;
  `ctx.param("id") -> Option<&String>`; `ctx.env: Env`.
- `Env::secret(name)?.to_string()`, `Env::d1("DB")?`, `Env::bucket("IMAGES")?`.
- `Request::json::<T>().await` (needs `mut req`), `Request::bytes().await`, `req.headers().get("x") -> Result<Option<String>>`, `req.path() -> String`.
- `Response::from_json(&v)?`, `Response::from_bytes(vec)?`, `.with_status(u16)`, `.with_headers(Headers)`; `Headers::new()`, `headers.set(k, v)?`.
- D1: `db.prepare(sql).bind(&[JsValue])?`, `.first::<T>(Some("col")).await?`, `.all().await?.results::<T>()?`, `db.batch(Vec<D1PreparedStatement>).await?` (atomic).
- R2: `bucket.put(key, Vec<u8>).http_metadata(HttpMetadata{..}).execute().await?`,
  `bucket.get(key).execute().await? -> Option<Object>`, `object.http_metadata()`, `object.body() -> Option<ObjectBody>`, `body.bytes().await?`.
- `worker::Date::now().as_millis() -> u64`; `js_sys::Math::random() -> f64`.
- `worker` compiles on the native host, so `cargo test --lib` runs pure unit tests without WASM (verified).

---

### Task 1: Scaffold the Worker, health endpoint, repo conventions

**Files:**
- Create: `api/Cargo.toml`, `api/rustfmt.toml`, `api/package.json`, `api/wrangler.toml`, `api/.gitignore`
- Create: `api/src/lib.rs`, `api/src/router.rs`
- Create: `CLAUDE.md`, `.claude/rules/rust.md`, `.claude/rules/sync.md`, `.claude/rules/testing.md`, `.gitignore` (root)
- Create: `.github/workflows/api-ci.yml`

**Interfaces:**
- Produces: `router::handle(req: Request, env: Env) -> worker::Result<Response>` used by `lib.rs`.

- [ ] **Step 1: Toolchain**

```bash
rustup target add wasm32-unknown-unknown
cargo install worker-build --locked
```

- [ ] **Step 2: `api/Cargo.toml`**

```toml
[package]
name = "personal-api"
version = "0.1.0"
edition = "2024"
rust-version = "1.98"
publish = false
description = "Personal API on Cloudflare Workers (D1 + R2)"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
worker = { version = "0.8", features = ["d1"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
subtle = "2"
wasm-bindgen = "0.2"
js-sys = "0.3"
console_error_panic_hook = "0.1"

[dev-dependencies]
libtest-mimic = "0.8"
reqwest = { version = "0.13", default-features = false, features = ["json", "rustls"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros", "time"] }
uuid = { version = "1", features = ["v4"] }

[[test]]
name = "api"
path = "tests/api/main.rs"
harness = false

[profile.release]
opt-level = "s"
lto = true
codegen-units = 1
strip = true

[lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"

[lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "deny"
module_name_repetitions = "allow"
missing_errors_doc = "allow"
must_use_candidate = "allow"
```

If `reqwest` 0.13 does not have a `rustls` feature name, run
`cargo add --dev reqwest --no-default-features -F json,rustls-tls` and keep whatever
feature name cargo accepts.

- [ ] **Step 3: `api/rustfmt.toml`, `api/package.json`, `api/.gitignore`**

```toml
edition = "2024"
use_field_init_shorthand = true
```

```json
{
  "name": "personal-api",
  "private": true,
  "devDependencies": {
    "wrangler": "^4"
  }
}
```

```
/target
/build
/node_modules
/.wrangler
.dev.vars
```

Run `npm install` (creates `package-lock.json`, commit it).

- [ ] **Step 4: `api/wrangler.toml`**

```toml
name = "personal-api"
main = "build/worker/shim.mjs"
compatibility_date = "2026-09-19"
workers_dev = false

[build]
command = "cargo install -q worker-build && worker-build --release"

[[routes]]
pattern = "api.akhmadqasim.com"
custom_domain = true

[[d1_databases]]
binding = "DB"
database_name = "personal-api"
database_id = "00000000-0000-0000-0000-000000000000"
migrations_dir = "migrations"

[[r2_buckets]]
binding = "IMAGES"
bucket_name = "personal-api-images"
```

The `database_id` placeholder is replaced in Task 12 after `wrangler d1 create`.
Local dev and tests do not need a real id.

- [ ] **Step 5: `api/src/lib.rs`**

```rust
//! Personal API: a modular Cloudflare Worker backing the iOS app.

mod auth;
mod db;
mod error;
mod modules;
mod router;
mod sync;

use worker::{Context, Env, Request, Response, Result, event};

#[event(start)]
fn start() {
    console_error_panic_hook::set_once();
}

#[event(fetch, respond_with_errors)]
async fn fetch(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    router::handle(req, env).await
}
```

For this task only, create empty placeholder modules so the crate compiles:
`src/auth.rs`, `src/db.rs`, `src/error.rs`, `src/sync/mod.rs`, `src/modules/mod.rs`
each containing just `//! Filled in by a later task.` (they are replaced in
Tasks 3–7).

- [ ] **Step 6: `api/src/router.rs` with health only**

```rust
//! HTTP entry: auth gate, core routes, module routes, 404 fallback.

use serde_json::json;
use worker::{Env, Request, Response, Result, Router};

/// Dispatches one request.
pub async fn handle(req: Request, env: Env) -> Result<Response> {
    Router::new()
        .get("/api/health", |_, _| Response::from_json(&json!({ "ok": true })))
        .run(req, env)
        .await
}
```

- [ ] **Step 7: Build and smoke-test locally**

```bash
cargo fmt --all && cargo clippy --all-targets -- -D warnings
npx wrangler dev --port 8787 --var API_TOKEN:dev
# in another shell
curl -s http://127.0.0.1:8787/api/health
```

Expected: `{"ok":true}`. Stop `wrangler dev` afterwards. On Windows, if
`worker-build` complains about `wasm-opt`, install it once with
`cargo install wasm-opt --locked` or set `WORKER_BUILD_WASM_OPT=0`... actually
the supported switch is `worker-build --release --no-opt`; if needed, change the
build command to `worker-build --release --no-opt` and note it in CLAUDE.md.

- [ ] **Step 8: Root `.gitignore`, `CLAUDE.md`, rules**

Root `.gitignore`:

```
.DS_Store
*.log
```

`CLAUDE.md` (root):

```markdown
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

## Where things are
- Specs `docs/specs/`, plans `docs/plans/`
- Rules `.claude/rules/` — read before editing code
- New module: `.claude/skills/new-module`
```

`.claude/rules/rust.md`:

```markdown
# Rust conventions (api/)

- No `unwrap`/`expect` in `src/` (clippy denies). Return `ApiError`; `?` converts `worker::Error`.
- Pure logic (SQL text, validation, token check) never imports Cloudflare types, so it runs in `cargo test --lib`.
- Handlers are thin: parse → call pure function → run I/O → respond.
- One responsibility per file; a module folder is `mod.rs` (wiring) + focused files.
- Doc comment on every public item. Comments explain why, not what.
- Format + clippy pedantic clean before every commit.
```

`.claude/rules/sync.md`:

```markdown
# Sync protocol (do not change without updating docs/specs)

- Base columns on every synced table, in this order: `id, updated_at, deleted_at, seq`.
- Last-write-wins per row: insert if new; overwrite if `push.updated_at > db.updated_at`; else ignore.
- `seq` is global (`sync_meta.last_seq`), assigned by the server only; UNIQUE per table.
- Push: max 500 rows, one atomic D1 batch, tables in FK order, any validation error rejects the whole batch (422).
- Pull: rows with `seq > since_seq`, ordered by `seq`, max 500 total, `has_more` + cursor.
- Deletes are soft (`deleted_at`); never hard-delete.
- Seed rows use `updated_at = 0` so user edits always win.
```

`.claude/rules/testing.md`:

```markdown
# Testing

- Pure functions → unit tests next to the code (`#[cfg(test)]`), no Cloudflare.
- HTTP behaviour → `tests/api/` (single binary, custom harness that boots `wrangler dev`).
- Every test uses fresh UUIDs; tests share one local DB and must not depend on order.
- Add a test for every behaviour you add or fix; a bug fix starts with a failing test.
- `cargo test --lib` and `cargo test --test api` must both be green before commit.
```

- [ ] **Step 9: `.github/workflows/api-ci.yml`**

```yaml
name: API CI

on:
  pull_request:
    paths: ["api/**", ".github/workflows/api-ci.yml"]
  push:
    branches: [main]
    paths: ["api/**", ".github/workflows/api-ci.yml"]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    defaults:
      run:
        working-directory: api
    steps:
      - uses: actions/checkout@v6
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: api
      - uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: api/package-lock.json
      - run: npm ci
      - run: cargo fmt --all --check
      - run: cargo clippy --all-targets -- -D warnings
      - run: cargo test --lib
      - run: cargo install worker-build --locked
      - run: cargo test --test api
```

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold api worker with health endpoint and repo conventions"
```

---

### Task 2: Integration test harness + health test

**Files:**
- Create: `api/tests/api/main.rs`, `api/tests/api/server.rs`, `api/tests/api/client.rs`, `api/tests/api/fixtures.rs`, `api/tests/api/health.rs`
- Create: `api/migrations/.gitkeep` (migrations arrive in Task 5; `wrangler d1 migrations apply` needs the dir)

**Interfaces:**
- Produces: `client::Client` with `get/post_json/put_bytes/get_raw/sync`, `client::Ctx::trial(name, async fn)`, `client::TOKEN`, `fixtures::*` builders used by every later test module.

- [ ] **Step 1: `tests/api/server.rs`**

```rust
//! Boots `wrangler dev` with local D1/R2 state for the duration of the test binary.

use std::fs;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

pub const TOKEN: &str = "test-token";

pub struct DevServer {
    child: Child,
    port: u16,
}

impl DevServer {
    /// Wipes local state, applies migrations, starts the dev server and waits for /api/health.
    pub fn start() -> Self {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let state = root.join(".wrangler").join("test-state");
        let _ = fs::remove_dir_all(&state);
        apply_migrations(root, &state);

        let port = free_port();
        let child = Command::new(npx())
            .args([
                "wrangler", "dev",
                "--port", &port.to_string(),
                "--ip", "127.0.0.1",
                "--var", &format!("API_TOKEN:{TOKEN}"),
                "--persist-to", &state.to_string_lossy(),
                "--log-level", "warn",
            ])
            .current_dir(root)
            .stdin(Stdio::null())
            .spawn()
            .expect("failed to spawn wrangler dev");

        let server = Self { child, port };
        server.wait_until_healthy(Duration::from_secs(300));
        server
    }

    pub fn base_url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    fn wait_until_healthy(&self, timeout: Duration) {
        let url = format!("{}/api/health", self.base_url());
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if let Ok(resp) = reqwest::blocking::get(&url) {
                if resp.status().is_success() {
                    return;
                }
            }
            std::thread::sleep(Duration::from_millis(500));
        }
        panic!("wrangler dev did not become healthy within {timeout:?}");
    }
}

impl Drop for DevServer {
    fn drop(&mut self) {
        kill_tree(&mut self.child);
    }
}

fn apply_migrations(root: &Path, state: &PathBuf) {
    let status = Command::new(npx())
        .args([
            "wrangler", "d1", "migrations", "apply", "DB",
            "--local", "--persist-to", &state.to_string_lossy(),
        ])
        .current_dir(root)
        .stdin(Stdio::null())
        .status()
        .expect("failed to run wrangler d1 migrations apply");
    assert!(status.success(), "migrations failed");
}

fn npx() -> &'static str {
    if cfg!(windows) { "npx.cmd" } else { "npx" }
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .expect("bind")
        .local_addr()
        .expect("addr")
        .port()
}

#[cfg(windows)]
fn kill_tree(child: &mut Child) {
    let _ = Command::new("taskkill")
        .args(["/PID", &child.id().to_string(), "/T", "/F"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = child.wait();
}

#[cfg(not(windows))]
fn kill_tree(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}
```

`reqwest::blocking` needs the `blocking` feature: add it to the dev-dependency
(`features = ["json", "rustls", "blocking"]`).

- [ ] **Step 2: `tests/api/client.rs`**

```rust
//! HTTP client and trial builder shared by all integration tests.

use std::future::Future;
use std::sync::Arc;

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::{Value, json};
use tokio::runtime::Runtime;

pub use crate::server::TOKEN;

#[derive(Clone)]
pub struct Client {
    http: reqwest::Client,
    base: String,
}

impl Client {
    pub fn new(base: &str) -> Self {
        Self { http: reqwest::Client::new(), base: base.to_owned() }
    }

    pub async fn get(&self, path: &str, token: Option<&str>) -> (StatusCode, Value) {
        let mut req = self.http.get(format!("{}{path}", self.base));
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    pub async fn get_raw(&self, path: &str, token: Option<&str>) -> reqwest::Response {
        let mut req = self.http.get(format!("{}{path}", self.base));
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        req.send().await.expect("request failed")
    }

    pub async fn post_json(&self, path: &str, body: &Value, token: Option<&str>) -> (StatusCode, Value) {
        let mut req = self.http.post(format!("{}{path}", self.base)).json(body);
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    pub async fn post_text(&self, path: &str, body: &str, token: Option<&str>) -> (StatusCode, Value) {
        let mut req = self
            .http
            .post(format!("{}{path}", self.base))
            .header("content-type", "application/json")
            .body(body.to_owned());
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    pub async fn put_bytes(
        &self,
        path: &str,
        bytes: Vec<u8>,
        content_type: &str,
        token: Option<&str>,
    ) -> (StatusCode, Value) {
        let mut req = self
            .http
            .put(format!("{}{path}", self.base))
            .header("content-type", content_type)
            .body(bytes);
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    /// Authenticated `POST /api/sync`.
    pub async fn sync(&self, since_seq: i64, push: Value) -> (StatusCode, Value) {
        self.post_json("/api/sync", &json!({ "since_seq": since_seq, "push": push }), Some(TOKEN))
            .await
    }

    /// Pulls everything after `since_seq`, following `has_more`, and returns all rows per table.
    pub async fn pull_all(&self, since_seq: i64) -> Value {
        let mut cursor = since_seq;
        let mut merged = serde_json::Map::new();
        loop {
            let (status, body) = self.sync(cursor, json!({})).await;
            assert_eq!(status, StatusCode::OK, "pull failed: {body}");
            for (table, rows) in body["pull"].as_object().expect("pull object") {
                let entry = merged.entry(table.clone()).or_insert_with(|| json!([]));
                entry.as_array_mut().expect("array").extend(rows.as_array().expect("rows").iter().cloned());
            }
            cursor = body["seq"].as_i64().expect("seq");
            if !body["has_more"].as_bool().unwrap_or(false) {
                return Value::Object(merged);
            }
        }
    }
}

async fn split(resp: reqwest::Response) -> (StatusCode, Value) {
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    (status, serde_json::from_str(&text).unwrap_or(Value::Null))
}

pub struct Ctx {
    rt: Arc<Runtime>,
    client: Client,
}

impl Ctx {
    pub fn new(base: &str) -> Self {
        let rt = Runtime::new().expect("tokio runtime");
        Self { rt: Arc::new(rt), client: Client::new(base) }
    }

    /// Wraps an async test as a libtest-mimic trial.
    pub fn trial<F, Fut>(&self, name: &str, f: F) -> Trial
    where
        F: Fn(Client) -> Fut + Send + 'static,
        Fut: Future<Output = ()>,
    {
        let rt = Arc::clone(&self.rt);
        let client = self.client.clone();
        Trial::test(name, move || {
            rt.block_on(f(client.clone()));
            Ok(())
        })
    }
}

/// Finds a row by id inside a pulled table.
pub fn find_row<'a>(pull: &'a Value, table: &str, id: &str) -> Option<&'a Value> {
    pull[table].as_array()?.iter().find(|r| r["id"] == id)
}
```

- [ ] **Step 3: `tests/api/fixtures.rs`**

```rust
//! Builders for valid rows; tests override fields as needed.

use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn uuid() -> String {
    uuid::Uuid::new_v4().to_string()
}

pub fn now_ms() -> i64 {
    i64::try_from(SystemTime::now().duration_since(UNIX_EPOCH).expect("clock").as_millis())
        .expect("fits")
}

pub fn exercise(id: &str, name: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "name": name, "muscle_group": "chest", "equipment": "barbell",
        "image_key": null, "notes": null
    })
}

pub fn program(id: &str, name: &str, updated_at: i64) -> Value {
    json!({ "id": id, "updated_at": updated_at, "deleted_at": null, "name": name, "is_active": 1 })
}

pub fn program_day(id: &str, program_id: &str, name: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "program_id": program_id, "name": name, "position": 0
    })
}

pub fn program_exercise(id: &str, day_id: &str, exercise_id: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "program_day_id": day_id, "exercise_id": exercise_id, "position": 0,
        "target_sets": 3, "target_reps": 10, "target_weight_kg": 60.0, "rest_seconds": 90
    })
}

pub fn workout_session(id: &str, started_at: i64, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "started_at": started_at, "finished_at": null, "program_day_id": null, "notes": null
    })
}

pub fn workout_set(id: &str, session_id: &str, exercise_id: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "session_id": session_id, "exercise_id": exercise_id, "position": 0,
        "weight_kg": 62.5, "reps": 8, "rpe": 8.5, "completed": 1
    })
}
```

- [ ] **Step 4: `tests/api/health.rs` and `tests/api/main.rs`**

```rust
//! GET /api/health

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx};

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("health::returns_ok_without_token", returns_ok_without_token));
}

async fn returns_ok_without_token(c: Client) {
    let (status, body) = c.get("/api/health", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({ "ok": true }));
}
```

```rust
//! Integration test binary: boots wrangler dev once, runs every trial, shuts down.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::missing_panics_doc)]

mod client;
mod fixtures;
mod health;
mod server;

use libtest_mimic::Arguments;

fn main() {
    let args = Arguments::from_args();
    let server = server::DevServer::start();
    let ctx = client::Ctx::new(&server.base_url());

    let mut trials = Vec::new();
    health::register(&mut trials, &ctx);

    let conclusion = libtest_mimic::run(&args, trials);
    drop(server);
    conclusion.exit();
}
```

- [ ] **Step 5: Run**

```bash
cargo test --test api
```

Expected: `wrangler dev` boots (first run compiles WASM, may take minutes),
`health::returns_ok_without_token ... ok`, process exits and no `workerd`/`node`
process lingers (`tasklist | findstr workerd` on Windows should be empty).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test: integration harness that boots wrangler dev, health test"
```

---

### Task 3: `ApiError` with JSON body

**Files:**
- Replace: `api/src/error.rs`

**Interfaces:**
- Produces: `ApiError` enum, `FieldError { table, id, message }`, `ApiResult<T>`, `ApiError::{status, code, message, to_json, into_response}`, `From<worker::Error>`.

- [ ] **Step 1: Write failing unit tests (bottom of `error.rs`)**

```rust
#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    #[test]
    fn unauthorized_maps_to_401_and_code() {
        let err = ApiError::Unauthorized;
        assert_eq!(err.status(), 401);
        assert_eq!(err.to_json(), json!({ "code": "unauthorized", "message": "missing or invalid bearer token" }));
    }

    #[test]
    fn validation_includes_field_errors() {
        let err = ApiError::Validation(vec![FieldError {
            table: "exercise".into(),
            id: "abc".into(),
            message: "name is required".into(),
        }]);
        assert_eq!(err.status(), 422);
        let json = err.to_json();
        assert_eq!(json["code"], "validation_failed");
        assert_eq!(json["errors"][0]["table"], "exercise");
        assert_eq!(json["errors"][0]["message"], "name is required");
    }

    #[test]
    fn internal_never_leaks_details() {
        let err = ApiError::Internal("secret db path".into());
        assert_eq!(err.status(), 500);
        assert_eq!(err.to_json()["message"], "internal error");
    }

    #[test]
    fn every_variant_has_expected_status() {
        let cases = [
            (ApiError::BadRequest("x".into()), 400, "bad_request"),
            (ApiError::NotFound, 404, "not_found"),
            (ApiError::Conflict("x".into()), 409, "conflict"),
            (ApiError::PayloadTooLarge("x".into()), 413, "payload_too_large"),
            (ApiError::UnsupportedMediaType("x".into()), 415, "unsupported_media_type"),
        ];
        for (err, status, code) in cases {
            assert_eq!(err.status(), status);
            assert_eq!(err.code(), code);
        }
    }
}
```

- [ ] **Step 2: Run `cargo test --lib error` → compile error (types missing)**

- [ ] **Step 3: Implement**

```rust
//! API error type and its JSON representation.

use serde::Serialize;
use serde_json::{Value, json};
use worker::{Response, console_error};

/// One validation problem on one pushed row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FieldError {
    /// Table the row belongs to (empty when unknown).
    pub table: String,
    /// Row id (empty when unknown).
    pub id: String,
    /// Human-readable reason.
    pub message: String,
}

/// Every failure the API can report. Maps 1:1 to the status codes in the spec.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    /// 400
    BadRequest(String),
    /// 401
    Unauthorized,
    /// 404
    NotFound,
    /// 409
    Conflict(String),
    /// 413
    PayloadTooLarge(String),
    /// 415
    UnsupportedMediaType(String),
    /// 422
    Validation(Vec<FieldError>),
    /// 500 — detail is logged, never returned.
    Internal(String),
}

/// Result alias used by handlers and helpers.
pub type ApiResult<T> = Result<T, ApiError>;

impl ApiError {
    /// HTTP status for this error.
    pub fn status(&self) -> u16 {
        match self {
            Self::BadRequest(_) => 400,
            Self::Unauthorized => 401,
            Self::NotFound => 404,
            Self::Conflict(_) => 409,
            Self::PayloadTooLarge(_) => 413,
            Self::UnsupportedMediaType(_) => 415,
            Self::Validation(_) => 422,
            Self::Internal(_) => 500,
        }
    }

    /// Stable machine-readable code.
    pub fn code(&self) -> &'static str {
        match self {
            Self::BadRequest(_) => "bad_request",
            Self::Unauthorized => "unauthorized",
            Self::NotFound => "not_found",
            Self::Conflict(_) => "conflict",
            Self::PayloadTooLarge(_) => "payload_too_large",
            Self::UnsupportedMediaType(_) => "unsupported_media_type",
            Self::Validation(_) => "validation_failed",
            Self::Internal(_) => "internal",
        }
    }

    /// Message shown to the client.
    pub fn message(&self) -> String {
        match self {
            Self::BadRequest(m)
            | Self::Conflict(m)
            | Self::PayloadTooLarge(m)
            | Self::UnsupportedMediaType(m) => m.clone(),
            Self::Unauthorized => "missing or invalid bearer token".into(),
            Self::NotFound => "resource not found".into(),
            Self::Validation(errors) => format!("{} validation error(s)", errors.len()),
            Self::Internal(_) => "internal error".into(),
        }
    }

    /// JSON body as defined in the spec.
    pub fn to_json(&self) -> Value {
        let mut body = json!({ "code": self.code(), "message": self.message() });
        if let Self::Validation(errors) = self {
            body["errors"] = json!(errors);
        }
        body
    }

    /// Builds the HTTP response; internal details go to the Worker log only.
    pub fn into_response(self) -> worker::Result<Response> {
        if let Self::Internal(detail) = &self {
            console_error!("internal error: {detail}");
        }
        Ok(Response::from_json(&self.to_json())?.with_status(self.status()))
    }
}

impl From<worker::Error> for ApiError {
    fn from(err: worker::Error) -> Self {
        Self::Internal(err.to_string())
    }
}
```

- [ ] **Step 4: `cargo test --lib error` → 4 passed; `cargo clippy --all-targets -- -D warnings` clean**

- [ ] **Step 5: Commit** — `git commit -am "feat: ApiError with spec-shaped JSON body"`

---

### Task 4: Bearer auth gate

**Files:**
- Replace: `api/src/auth.rs`
- Modify: `api/src/router.rs` (auth gate before routing, 404 fallback, `respond` helper)
- Create: `api/tests/api/auth.rs`; Modify: `api/tests/api/main.rs` (register)

**Interfaces:**
- Produces: `auth::is_authorized(header: Option<&str>, expected: &str) -> bool`, `auth::require(req: &Request, env: &Env) -> ApiResult<()>`, `router::respond(ApiResult<Response>) -> worker::Result<Response>`.

- [ ] **Step 1: Unit tests (bottom of `auth.rs`)**

```rust
#[cfg(test)]
mod tests {
    use super::is_authorized;

    #[test]
    fn accepts_exact_bearer_token() {
        assert!(is_authorized(Some("Bearer s3cret"), "s3cret"));
    }

    #[test]
    fn rejects_missing_wrong_or_malformed() {
        assert!(!is_authorized(None, "s3cret"));
        assert!(!is_authorized(Some("Bearer nope"), "s3cret"));
        assert!(!is_authorized(Some("s3cret"), "s3cret"));
        assert!(!is_authorized(Some("bearer s3cret"), "s3cret"));
        assert!(!is_authorized(Some("Bearer s3cret "), "s3cret"));
    }

    #[test]
    fn rejects_when_expected_is_empty() {
        assert!(!is_authorized(Some("Bearer "), ""));
    }
}
```

- [ ] **Step 2: Integration tests `tests/api/auth.rs`**

```rust
//! Bearer token gate on every route except /api/health.

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx, TOKEN};

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("auth::rejects_missing_token", rejects_missing_token));
    trials.push(ctx.trial("auth::rejects_wrong_token", rejects_wrong_token));
    trials.push(ctx.trial("auth::accepts_valid_token", accepts_valid_token));
    trials.push(ctx.trial("auth::unknown_route_is_404_when_authorized", unknown_route_is_404));
}

async fn rejects_missing_token(c: Client) {
    let (status, body) = c.post_json("/api/sync", &json!({ "since_seq": 0 }), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["code"], "unauthorized");
}

async fn rejects_wrong_token(c: Client) {
    let (status, _) = c.post_json("/api/sync", &json!({ "since_seq": 0 }), Some("wrong")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

async fn accepts_valid_token(c: Client) {
    let (status, body) = c.post_json("/api/sync", &json!({ "since_seq": 0 }), Some(TOKEN)).await;
    assert_ne!(status, StatusCode::UNAUTHORIZED, "body: {body}");
}

async fn unknown_route_is_404(c: Client) {
    let (status, body) = c.get("/api/nope", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "not_found");
}
```

Register in `main.rs` (`mod auth;` + `auth::register(&mut trials, &ctx);`).
`accepts_valid_token` only asserts "not 401" because `/api/sync` is implemented in Task 7.

- [ ] **Step 3: Run `cargo test --lib auth` (compile error) and note `cargo test --test api` fails on auth tests**

- [ ] **Step 4: Implement `auth.rs`**

```rust
//! Static bearer token check. The token is the `API_TOKEN` Worker secret.

use subtle::ConstantTimeEq;
use worker::{Env, Request};

use crate::error::{ApiError, ApiResult};

const SECRET_NAME: &str = "API_TOKEN";

/// Pure check: `Authorization: Bearer <token>` must equal `expected` byte for byte.
pub fn is_authorized(header: Option<&str>, expected: &str) -> bool {
    if expected.is_empty() {
        return false;
    }
    let Some(token) = header.and_then(|h| h.strip_prefix("Bearer ")) else {
        return false;
    };
    bool::from(token.as_bytes().ct_eq(expected.as_bytes()))
}

/// Rejects the request unless it carries the configured token.
pub fn require(req: &Request, env: &Env) -> ApiResult<()> {
    let expected = env
        .secret(SECRET_NAME)
        .map_err(|_| ApiError::Internal(format!("{SECRET_NAME} secret is not configured")))?
        .to_string();
    let header = req.headers().get("authorization")?;
    if is_authorized(header.as_deref(), &expected) {
        Ok(())
    } else {
        Err(ApiError::Unauthorized)
    }
}
```

- [ ] **Step 5: Update `router.rs`**

```rust
//! HTTP entry: auth gate, core routes, module routes, 404 fallback.

use serde_json::json;
use worker::{Env, Request, Response, Result, Router};

use crate::auth;
use crate::error::{ApiError, ApiResult};

const PUBLIC_PATHS: [&str; 1] = ["/api/health"];

/// Dispatches one request.
pub async fn handle(req: Request, env: Env) -> Result<Response> {
    if !PUBLIC_PATHS.contains(&req.path().as_str()) {
        if let Err(err) = auth::require(&req, &env) {
            return err.into_response();
        }
    }
    Router::new()
        .get("/api/health", |_, _| Response::from_json(&json!({ "ok": true })))
        .or_else_any_method_async("/*path", |_, _| async { ApiError::NotFound.into_response() })
        .run(req, env)
        .await
}

/// Converts a handler result into the Worker's result type.
pub fn respond(result: ApiResult<Response>) -> Result<Response> {
    result.or_else(ApiError::into_response)
}
```

- [ ] **Step 6: `cargo test --lib` and `cargo test --test api` green; clippy clean** (the `respond` helper is unused until Task 7 — add `#[allow(dead_code)]` for now and remove it in Task 7)

- [ ] **Step 7: Commit** — `git commit -am "feat: bearer token auth gate and 404 fallback"`

---

### Task 5: Schema migration, D1 helpers, sync table descriptor and SQL builders

**Files:**
- Create: `api/migrations/0001_gym.sql` (delete `migrations/.gitkeep`)
- Replace: `api/src/db.rs`
- Create: `api/src/sync/mod.rs`, `api/src/sync/table.rs`, `api/src/sync/sql.rs`

**Interfaces:**
- Produces: `db::Row = serde_json::Map<String, Value>`, `db::to_js`, `db::prepare`, `db::query_rows`, `db::query_i64`;
  `sync::table::{Kind, Column, SyncTable, BASE_COLUMNS}`, `SyncTable::check(&Row) -> Vec<String>`;
  `sync::sql::{upsert_sql, upsert_params, pull_sql, export_sql, READ_LAST_SEQ, WRITE_LAST_SEQ}`.

- [ ] **Step 1: Migration** — run `npx wrangler d1 migrations create DB gym`, then replace the generated file's body (keep its header comment line):

```sql
-- Migration number: 0001 	 2026-09-19T00:00:00.000Z
CREATE TABLE sync_meta (
  key   TEXT PRIMARY KEY,
  value INTEGER NOT NULL
);
INSERT INTO sync_meta (key, value) VALUES ('last_seq', 0);

CREATE TABLE exercise (
  id           TEXT PRIMARY KEY,
  updated_at   INTEGER NOT NULL,
  deleted_at   INTEGER,
  seq          INTEGER NOT NULL UNIQUE,
  name         TEXT NOT NULL,
  muscle_group TEXT NOT NULL,
  equipment    TEXT NOT NULL,
  image_key    TEXT,
  notes        TEXT
);

CREATE TABLE program (
  id         TEXT PRIMARY KEY,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  seq        INTEGER NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  is_active  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE program_day (
  id         TEXT PRIMARY KEY,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  seq        INTEGER NOT NULL UNIQUE,
  program_id TEXT NOT NULL REFERENCES program(id),
  name       TEXT NOT NULL,
  position   INTEGER NOT NULL
);
CREATE INDEX idx_program_day_program ON program_day(program_id);

CREATE TABLE program_exercise (
  id               TEXT PRIMARY KEY,
  updated_at       INTEGER NOT NULL,
  deleted_at       INTEGER,
  seq              INTEGER NOT NULL UNIQUE,
  program_day_id   TEXT NOT NULL REFERENCES program_day(id),
  exercise_id      TEXT NOT NULL REFERENCES exercise(id),
  position         INTEGER NOT NULL,
  target_sets      INTEGER NOT NULL,
  target_reps      INTEGER NOT NULL,
  target_weight_kg REAL,
  rest_seconds     INTEGER
);
CREATE INDEX idx_program_exercise_day ON program_exercise(program_day_id);

CREATE TABLE workout_session (
  id             TEXT PRIMARY KEY,
  updated_at     INTEGER NOT NULL,
  deleted_at     INTEGER,
  seq            INTEGER NOT NULL UNIQUE,
  started_at     INTEGER NOT NULL,
  finished_at    INTEGER,
  program_day_id TEXT REFERENCES program_day(id),
  notes          TEXT
);

CREATE TABLE workout_set (
  id          TEXT PRIMARY KEY,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER,
  seq         INTEGER NOT NULL UNIQUE,
  session_id  TEXT NOT NULL REFERENCES workout_session(id),
  exercise_id TEXT NOT NULL REFERENCES exercise(id),
  position    INTEGER NOT NULL,
  weight_kg   REAL NOT NULL,
  reps        INTEGER NOT NULL,
  rpe         REAL,
  completed   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_workout_set_session ON workout_set(session_id);
CREATE INDEX idx_workout_set_exercise ON workout_set(exercise_id);
```

- [ ] **Step 2: `src/db.rs`**

```rust
//! Thin D1 helpers: bind `serde_json` values and read rows back as JSON maps.

use serde_json::{Map, Value};
use wasm_bindgen::JsValue;
use worker::{D1Database, D1PreparedStatement, Result};

/// A database row as a JSON object (column → value).
pub type Row = Map<String, Value>;

/// Converts a JSON scalar to the `JsValue` D1 expects. Arrays/objects are not
/// valid D1 parameters and become NULL.
pub fn to_js(value: &Value) -> JsValue {
    match value {
        Value::Null | Value::Array(_) | Value::Object(_) => JsValue::NULL,
        Value::Bool(b) => JsValue::from_bool(*b),
        Value::Number(n) => n.as_f64().map_or(JsValue::NULL, JsValue::from_f64),
        Value::String(s) => JsValue::from_str(s),
    }
}

/// Prepares `sql` with positional parameters (`?1`, `?2`, …).
pub fn prepare(db: &D1Database, sql: &str, params: &[Value]) -> Result<D1PreparedStatement> {
    let values: Vec<JsValue> = params.iter().map(to_js).collect();
    db.prepare(sql).bind(&values)
}

/// Runs a SELECT and returns every row as a JSON object.
pub async fn query_rows(db: &D1Database, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
    prepare(db, sql, params)?.all().await?.results::<Row>()
}

/// Runs a SELECT and returns one integer column of the first row, if any.
pub async fn query_i64(
    db: &D1Database,
    sql: &str,
    params: &[Value],
    column: &str,
) -> Result<Option<i64>> {
    prepare(db, sql, params)?.first::<i64>(Some(column)).await
}
```

- [ ] **Step 3: `src/sync/table.rs` with unit tests**

```rust
//! Describes one table the sync engine replicates. Modules declare these; the
//! engine only knows column names and kinds.

use serde_json::Value;

use crate::db::Row;

/// SQLite storage class of a domain column.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// TEXT
    Text,
    /// INTEGER (JSON integer)
    Integer,
    /// REAL (any JSON number)
    Real,
}

impl Kind {
    fn describe(self) -> &'static str {
        match self {
            Self::Text => "a string",
            Self::Integer => "an integer",
            Self::Real => "a number",
        }
    }
}

/// One domain column.
#[derive(Debug, Clone, Copy)]
pub struct Column {
    /// SQL column name.
    pub name: &'static str,
    /// Storage class.
    pub kind: Kind,
    /// `true` → NULL/missing is a validation error.
    pub required: bool,
}

impl Column {
    /// TEXT column.
    pub const fn text(name: &'static str, required: bool) -> Self {
        Self { name, kind: Kind::Text, required }
    }
    /// INTEGER column.
    pub const fn integer(name: &'static str, required: bool) -> Self {
        Self { name, kind: Kind::Integer, required }
    }
    /// REAL column.
    pub const fn real(name: &'static str, required: bool) -> Self {
        Self { name, kind: Kind::Real, required }
    }
}

/// Columns every synced table has, in bind order.
pub const BASE_COLUMNS: [&str; 4] = ["id", "updated_at", "deleted_at", "seq"];

/// A synced table: name, domain columns (bind order) and domain validation.
pub struct SyncTable {
    /// SQL table name.
    pub name: &'static str,
    /// Domain columns; base columns are implicit.
    pub columns: &'static [Column],
    /// Domain rules beyond type/presence checks; returns messages.
    pub validate: fn(&Row) -> Vec<String>,
}

impl SyncTable {
    /// Base + type + presence checks, then the table's own rules (only when the
    /// generic checks pass, so domain rules can trust the types).
    pub fn check(&self, row: &Row) -> Vec<String> {
        let mut errors = Vec::new();
        match row.get("id") {
            Some(Value::String(s)) if !s.trim().is_empty() => {}
            _ => errors.push("id must be a non-empty string".to_owned()),
        }
        if !is_non_negative_int(row.get("updated_at")) {
            errors.push("updated_at must be a non-negative integer".to_owned());
        }
        if let Some(v) = row.get("deleted_at") {
            if !v.is_null() && !is_non_negative_int(Some(v)) {
                errors.push("deleted_at must be null or a non-negative integer".to_owned());
            }
        }
        for col in self.columns {
            match row.get(col.name) {
                None | Some(Value::Null) => {
                    if col.required {
                        errors.push(format!("{} is required", col.name));
                    }
                }
                Some(v) if !matches_kind(v, col.kind) => {
                    errors.push(format!("{} must be {}", col.name, col.kind.describe()));
                }
                Some(_) => {}
            }
        }
        if errors.is_empty() {
            errors.extend((self.validate)(row));
        }
        errors
    }
}

fn is_non_negative_int(v: Option<&Value>) -> bool {
    v.and_then(Value::as_i64).is_some_and(|n| n >= 0)
}

fn matches_kind(v: &Value, kind: Kind) -> bool {
    match kind {
        Kind::Text => v.is_string(),
        Kind::Integer => v.is_i64(),
        Kind::Real => v.is_number(),
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    const COLS: [Column; 3] = [
        Column::text("name", true),
        Column::integer("reps", true),
        Column::real("weight_kg", false),
    ];

    fn table() -> SyncTable {
        SyncTable { name: "t", columns: &COLS, validate: |row| {
            if row.get("reps").and_then(Value::as_i64) == Some(0) {
                vec!["reps must be positive".to_owned()]
            } else {
                Vec::new()
            }
        } }
    }

    fn row(v: Value) -> Row {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn valid_row_passes() {
        let r = row(json!({ "id": "a", "updated_at": 5, "deleted_at": null, "name": "x", "reps": 3 }));
        assert!(table().check(&r).is_empty());
    }

    #[test]
    fn reports_base_column_problems() {
        let r = row(json!({ "id": "", "updated_at": -1, "deleted_at": "soon", "name": "x", "reps": 3 }));
        let errors = table().check(&r);
        assert_eq!(errors.len(), 3, "{errors:?}");
    }

    #[test]
    fn reports_missing_required_and_wrong_types() {
        let r = row(json!({ "id": "a", "updated_at": 1, "reps": "many", "weight_kg": "heavy" }));
        let errors = table().check(&r);
        assert!(errors.contains(&"name is required".to_owned()));
        assert!(errors.contains(&"reps must be an integer".to_owned()));
        assert!(errors.contains(&"weight_kg must be a number".to_owned()));
    }

    #[test]
    fn domain_rules_run_only_when_types_are_valid() {
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": 0 }));
        assert_eq!(table().check(&r), vec!["reps must be positive".to_owned()]);
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": "0" }));
        assert!(!table().check(&r).contains(&"reps must be positive".to_owned()));
    }

    #[test]
    fn integer_column_rejects_float_and_accepts_real_for_ints() {
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": 2.5 }));
        assert!(table().check(&r).contains(&"reps must be an integer".to_owned()));
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": 2, "weight_kg": 60 }));
        assert!(table().check(&r).is_empty());
    }
}
```

- [ ] **Step 4: `src/sync/sql.rs` with unit tests**

```rust
//! SQL text for the sync engine. Pure functions so they are unit-tested natively.

use serde_json::Value;

use super::table::{BASE_COLUMNS, SyncTable};
use crate::db::Row;

/// Reads the global cursor.
pub const READ_LAST_SEQ: &str = "SELECT value FROM sync_meta WHERE key = 'last_seq'";
/// Advances the cursor only if nobody else did meanwhile (`?1` new, `?2` expected old).
pub const WRITE_LAST_SEQ: &str =
    "UPDATE sync_meta SET value = ?1 WHERE key = 'last_seq' AND value = ?2";

fn column_names(table: &SyncTable) -> Vec<&'static str> {
    BASE_COLUMNS
        .iter()
        .copied()
        .chain(table.columns.iter().map(|c| c.name))
        .collect()
}

/// One statement implements last-write-wins: insert when new, overwrite when the
/// incoming `updated_at` is newer, otherwise leave the server row untouched.
pub fn upsert_sql(table: &SyncTable) -> String {
    let cols = column_names(table);
    let placeholders: Vec<String> = (1..=cols.len()).map(|i| format!("?{i}")).collect();
    let assignments: Vec<String> =
        cols.iter().skip(1).map(|c| format!("{c} = excluded.{c}")).collect();
    format!(
        "INSERT INTO {t} ({cols}) VALUES ({ph}) ON CONFLICT(id) DO UPDATE SET {set} \
         WHERE excluded.updated_at > {t}.updated_at",
        t = table.name,
        cols = cols.join(", "),
        ph = placeholders.join(", "),
        set = assignments.join(", "),
    )
}

/// Parameters for [`upsert_sql`], in the same order. Missing optional columns bind NULL.
pub fn upsert_params(table: &SyncTable, row: &Row, seq: i64) -> Vec<Value> {
    let mut params = vec![
        row.get("id").cloned().unwrap_or(Value::Null),
        row.get("updated_at").cloned().unwrap_or(Value::Null),
        row.get("deleted_at").cloned().unwrap_or(Value::Null),
        Value::from(seq),
    ];
    params.extend(table.columns.iter().map(|c| row.get(c.name).cloned().unwrap_or(Value::Null)));
    params
}

/// Rows changed after a cursor (`?1` since_seq, `?2` limit).
pub fn pull_sql(table: &SyncTable) -> String {
    format!(
        "SELECT {cols} FROM {t} WHERE seq > ?1 ORDER BY seq LIMIT ?2",
        cols = column_names(table).join(", "),
        t = table.name,
    )
}

/// All active rows, for exports.
pub fn export_sql(table: &SyncTable) -> String {
    format!(
        "SELECT {cols} FROM {t} WHERE deleted_at IS NULL ORDER BY seq",
        cols = column_names(table).join(", "),
        t = table.name,
    )
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use crate::sync::table::Column;
    use serde_json::json;

    const COLS: [Column; 2] = [Column::text("name", true), Column::integer("reps", true)];
    const TABLE: SyncTable = SyncTable { name: "t", columns: &COLS, validate: |_| Vec::new() };

    #[test]
    fn upsert_sql_is_last_write_wins() {
        assert_eq!(
            upsert_sql(&TABLE),
            "INSERT INTO t (id, updated_at, deleted_at, seq, name, reps) VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at, \
             seq = excluded.seq, name = excluded.name, reps = excluded.reps WHERE excluded.updated_at > t.updated_at"
        );
    }

    #[test]
    fn upsert_params_follow_column_order_and_fill_nulls() {
        let row = json!({ "id": "a", "updated_at": 7, "name": "x", "seq": 999 });
        let params = upsert_params(&TABLE, row.as_object().unwrap(), 42);
        assert_eq!(params, vec![json!("a"), json!(7), Value::Null, json!(42), json!("x"), Value::Null]);
    }

    #[test]
    fn pull_and_export_sql() {
        assert_eq!(
            pull_sql(&TABLE),
            "SELECT id, updated_at, deleted_at, seq, name, reps FROM t WHERE seq > ?1 ORDER BY seq LIMIT ?2"
        );
        assert_eq!(
            export_sql(&TABLE),
            "SELECT id, updated_at, deleted_at, seq, name, reps FROM t WHERE deleted_at IS NULL ORDER BY seq"
        );
    }
}
```

- [ ] **Step 5: `src/sync/mod.rs`**

```rust
//! Generic replication engine: table descriptors, SQL builders and the handler.

pub mod sql;
pub mod table;
```

- [ ] **Step 6: `cargo test --lib` → all green; clippy clean (temporarily `#[allow(dead_code)]` on `db` items if clippy complains about unused; remove in Task 7)**

- [ ] **Step 7: Commit** — `git add -A && git commit -m "feat: gym schema migration, D1 helpers, sync table descriptor and SQL builders"`

---

### Task 6: Gym module tables and validation

**Files:**
- Replace: `api/src/modules/mod.rs`
- Create: `api/src/modules/gym/mod.rs`, `api/src/modules/gym/tables.rs`, `api/src/modules/gym/validate.rs`

**Interfaces:**
- Produces: `modules::sync_tables() -> Vec<&'static SyncTable>` (FK order across modules), `modules::routes(Router) -> Router` (gym adds routes in Tasks 9–10), `gym::TABLES: [SyncTable; 6]`.

- [ ] **Step 1: `validate.rs` unit tests**

```rust
#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    fn row(v: serde_json::Value) -> Row {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn exercise_rejects_unknown_enums_and_blank_name() {
        let errors = exercise(&row(json!({ "name": "  ", "muscle_group": "wings", "equipment": "laser" })));
        assert_eq!(errors.len(), 3, "{errors:?}");
        assert!(exercise(&row(json!({ "name": "Bench", "muscle_group": "chest", "equipment": "barbell" }))).is_empty());
    }

    #[test]
    fn program_and_day_rules() {
        assert!(program(&row(json!({ "name": "PPL", "is_active": 2 }))).contains(&"is_active must be 0 or 1".to_owned()));
        assert!(program_day(&row(json!({ "name": "Push", "position": -1 }))).contains(&"position must be >= 0".to_owned()));
    }

    #[test]
    fn program_exercise_targets_must_be_positive() {
        let errors = program_exercise(&row(json!({ "position": 0, "target_sets": 0, "target_reps": 0, "target_weight_kg": -1, "rest_seconds": -5 })));
        assert_eq!(errors.len(), 4, "{errors:?}");
    }

    #[test]
    fn session_finished_after_started() {
        assert!(workout_session(&row(json!({ "started_at": 10, "finished_at": 5 }))).contains(&"finished_at must be >= started_at".to_owned()));
        assert!(workout_session(&row(json!({ "started_at": 10, "finished_at": null }))).is_empty());
    }

    #[test]
    fn set_rules() {
        let errors = workout_set(&row(json!({ "position": 0, "weight_kg": -1, "reps": 0, "rpe": 11, "completed": 3 })));
        assert_eq!(errors.len(), 4, "{errors:?}");
        assert!(workout_set(&row(json!({ "position": 0, "weight_kg": 0, "reps": 1, "rpe": 10, "completed": 0 }))).is_empty());
    }
}
```

- [ ] **Step 2: Implement `validate.rs`**

```rust
//! Domain rules for gym rows. Types and required columns are already checked
//! by `SyncTable::check`, so these functions may trust the JSON types.

use serde_json::Value;

use crate::db::Row;

/// Allowed `exercise.equipment` values.
pub const EQUIPMENT: [&str; 6] = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "other"];
/// Allowed `exercise.muscle_group` values.
pub const MUSCLE_GROUPS: [&str; 14] = [
    "chest", "back", "shoulders", "biceps", "triceps", "forearms", "core", "quads",
    "hamstrings", "glutes", "calves", "full_body", "cardio", "other",
];

pub fn exercise(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    non_blank(row, "name", &mut errors);
    one_of(row, "muscle_group", &MUSCLE_GROUPS, &mut errors);
    one_of(row, "equipment", &EQUIPMENT, &mut errors);
    errors
}

pub fn program(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    non_blank(row, "name", &mut errors);
    flag(row, "is_active", &mut errors);
    errors
}

pub fn program_day(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    non_blank(row, "name", &mut errors);
    min_int(row, "position", 0, &mut errors);
    errors
}

pub fn program_exercise(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    min_int(row, "position", 0, &mut errors);
    min_int(row, "target_sets", 1, &mut errors);
    min_int(row, "target_reps", 1, &mut errors);
    min_num(row, "target_weight_kg", 0.0, &mut errors);
    min_int(row, "rest_seconds", 0, &mut errors);
    errors
}

pub fn workout_session(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    min_int(row, "started_at", 1, &mut errors);
    let started = row.get("started_at").and_then(Value::as_i64);
    let finished = row.get("finished_at").and_then(Value::as_i64);
    if let (Some(s), Some(f)) = (started, finished) {
        if f < s {
            errors.push("finished_at must be >= started_at".to_owned());
        }
    }
    errors
}

pub fn workout_set(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    min_int(row, "position", 0, &mut errors);
    min_num(row, "weight_kg", 0.0, &mut errors);
    min_int(row, "reps", 1, &mut errors);
    if let Some(rpe) = row.get("rpe").and_then(Value::as_f64) {
        if !(1.0..=10.0).contains(&rpe) {
            errors.push("rpe must be between 1 and 10".to_owned());
        }
    }
    flag(row, "completed", &mut errors);
    errors
}

fn non_blank(row: &Row, col: &str, errors: &mut Vec<String>) {
    if row.get(col).and_then(Value::as_str).is_some_and(|s| s.trim().is_empty()) {
        errors.push(format!("{col} must not be blank"));
    }
}

fn one_of(row: &Row, col: &str, allowed: &[&str], errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_str) {
        if !allowed.contains(&v) {
            errors.push(format!("{col} must be one of: {}", allowed.join(", ")));
        }
    }
}

fn flag(row: &Row, col: &str, errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_i64) {
        if v != 0 && v != 1 {
            errors.push(format!("{col} must be 0 or 1"));
        }
    }
}

/// Applies only when the column is present (optional columns may be NULL).
fn min_int(row: &Row, col: &str, min: i64, errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_i64) {
        if v < min {
            errors.push(format!("{col} must be >= {min}"));
        }
    }
}

fn min_num(row: &Row, col: &str, min: f64, errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_f64) {
        if v < min {
            errors.push(format!("{col} must be >= {min}"));
        }
    }
}
```

Add `#![allow(missing_docs)]`? No — give each `pub fn` a one-line doc comment
(`/// Rules for `exercise` rows.` etc.) to satisfy `missing_docs`.

- [ ] **Step 3: `tables.rs`**

```rust
//! Gym tables in foreign-key order. Column order here is the bind order.

use crate::sync::table::{Column, SyncTable};

use super::validate;

const EXERCISE: [Column; 5] = [
    Column::text("name", true),
    Column::text("muscle_group", true),
    Column::text("equipment", true),
    Column::text("image_key", false),
    Column::text("notes", false),
];
const PROGRAM: [Column; 2] = [Column::text("name", true), Column::integer("is_active", true)];
const PROGRAM_DAY: [Column; 3] = [
    Column::text("program_id", true),
    Column::text("name", true),
    Column::integer("position", true),
];
const PROGRAM_EXERCISE: [Column; 7] = [
    Column::text("program_day_id", true),
    Column::text("exercise_id", true),
    Column::integer("position", true),
    Column::integer("target_sets", true),
    Column::integer("target_reps", true),
    Column::real("target_weight_kg", false),
    Column::integer("rest_seconds", false),
];
const WORKOUT_SESSION: [Column; 4] = [
    Column::integer("started_at", true),
    Column::integer("finished_at", false),
    Column::text("program_day_id", false),
    Column::text("notes", false),
];
const WORKOUT_SET: [Column; 7] = [
    Column::text("session_id", true),
    Column::text("exercise_id", true),
    Column::integer("position", true),
    Column::real("weight_kg", true),
    Column::integer("reps", true),
    Column::real("rpe", false),
    Column::integer("completed", true),
];

/// All gym tables, parents before children.
pub static TABLES: [SyncTable; 6] = [
    SyncTable { name: "exercise", columns: &EXERCISE, validate: validate::exercise },
    SyncTable { name: "program", columns: &PROGRAM, validate: validate::program },
    SyncTable { name: "program_day", columns: &PROGRAM_DAY, validate: validate::program_day },
    SyncTable { name: "program_exercise", columns: &PROGRAM_EXERCISE, validate: validate::program_exercise },
    SyncTable { name: "workout_session", columns: &WORKOUT_SESSION, validate: validate::workout_session },
    SyncTable { name: "workout_set", columns: &WORKOUT_SET, validate: validate::workout_set },
];
```

- [ ] **Step 4: `gym/mod.rs` and `modules/mod.rs`**

```rust
//! Gym module: training catalog, programs and workout logs.

pub mod tables;
mod validate;

use worker::Router;

pub use tables::TABLES;

/// Extra HTTP routes owned by this module (export and images, added later).
pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    router
}
```

```rust
//! Module registry. Adding a module = add its tables and routes here.

pub mod gym;

use worker::Router;

use crate::sync::table::SyncTable;

/// Every synced table across modules, parents before children.
pub fn sync_tables() -> Vec<&'static SyncTable> {
    gym::TABLES.iter().collect()
}

/// Mounts every module's routes.
pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    gym::routes(router)
}
```

Wire `modules::routes` into `router.rs` between the core routes and the 404 fallback:

```rust
    let router = Router::new()
        .get("/api/health", |_, _| Response::from_json(&json!({ "ok": true })));
    crate::modules::routes(router)
        .or_else_any_method_async("/*path", |_, _| async { ApiError::NotFound.into_response() })
        .run(req, env)
        .await
```

- [ ] **Step 5: `cargo test --lib` green, clippy clean, `cargo test --test api` still green**

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: gym module tables and validation rules"`

---

### Task 7: Sync handler (push + pull) with integration tests

**Files:**
- Create: `api/src/sync/handler.rs`; Modify: `api/src/sync/mod.rs` (`pub mod handler;`)
- Modify: `api/src/router.rs` (mount `/api/sync`, drop the `dead_code` allow)
- Create: `api/tests/api/sync.rs`; Modify: `api/tests/api/main.rs`

**Interfaces:**
- Produces: `sync::handler::handle(req: Request, env: &Env) -> ApiResult<Response>`; constants `MAX_PUSH_ROWS = 500`, `PULL_LIMIT = 500`.

- [ ] **Step 1: Integration tests `tests/api/sync.rs`**

```rust
//! POST /api/sync — push (LWW) and pull (seq cursor).

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::{Value, json};

use crate::client::{Client, Ctx, TOKEN, find_row};
use crate::fixtures::{exercise, now_ms, uuid, workout_session, workout_set};

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("sync::push_then_pull_returns_row", push_then_pull_returns_row));
    trials.push(ctx.trial("sync::cursor_excludes_older_rows", cursor_excludes_older_rows));
    trials.push(ctx.trial("sync::same_push_twice_is_idempotent", same_push_twice_is_idempotent));
    trials.push(ctx.trial("sync::newer_update_wins", newer_update_wins));
    trials.push(ctx.trial("sync::older_update_is_ignored", older_update_is_ignored));
    trials.push(ctx.trial("sync::soft_delete_propagates", soft_delete_propagates));
    trials.push(ctx.trial("sync::validation_error_rejects_whole_batch", validation_error_rejects_whole_batch));
    trials.push(ctx.trial("sync::unknown_table_is_rejected", unknown_table_is_rejected));
    trials.push(ctx.trial("sync::missing_foreign_key_is_rejected", missing_foreign_key_is_rejected));
    trials.push(ctx.trial("sync::child_and_parent_in_one_push", child_and_parent_in_one_push));
    trials.push(ctx.trial("sync::oversized_push_is_413", oversized_push_is_413));
    trials.push(ctx.trial("sync::malformed_json_is_400", malformed_json_is_400));
    trials.push(ctx.trial("sync::paginates_with_has_more", paginates_with_has_more));
}

async fn push_then_pull_returns_row(c: Client) {
    let id = uuid();
    let (status, body) = c.sync(0, json!({ "exercise": [exercise(&id, "Bench Press", now_ms())] })).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let row = find_row(&body["pull"], "exercise", &id).expect("pushed row echoed back");
    assert_eq!(row["name"], "Bench Press");
    assert!(row["seq"].as_i64().unwrap() > 0);
    assert!(body["seq"].as_i64().unwrap() >= row["seq"].as_i64().unwrap());
    assert_eq!(body["has_more"], false);
}

async fn cursor_excludes_older_rows(c: Client) {
    let a = uuid();
    let (_, first) = c.sync(0, json!({ "exercise": [exercise(&a, "A", now_ms())] })).await;
    let cursor = first["seq"].as_i64().unwrap();
    let b = uuid();
    let (_, second) = c.sync(cursor, json!({ "exercise": [exercise(&b, "B", now_ms())] })).await;
    assert!(find_row(&second["pull"], "exercise", &a).is_none());
    assert!(find_row(&second["pull"], "exercise", &b).is_some());
}

async fn same_push_twice_is_idempotent(c: Client) {
    let id = uuid();
    let row = exercise(&id, "Row", now_ms());
    let (_, first) = c.sync(0, json!({ "exercise": [row.clone()] })).await;
    let (_, second) = c.sync(0, json!({ "exercise": [row] })).await;
    let seq1 = find_row(&first["pull"], "exercise", &id).unwrap()["seq"].clone();
    let seq2 = find_row(&second["pull"], "exercise", &id).unwrap()["seq"].clone();
    assert_eq!(seq1, seq2, "unchanged row must keep its seq");
    let all = c.pull_all(0).await;
    assert_eq!(all["exercise"].as_array().unwrap().iter().filter(|r| r["id"] == id).count(), 1);
}

async fn newer_update_wins(c: Client) {
    let id = uuid();
    let t = now_ms();
    c.sync(0, json!({ "exercise": [exercise(&id, "Old", t)] })).await;
    let (_, body) = c.sync(0, json!({ "exercise": [exercise(&id, "New", t + 1)] })).await;
    assert_eq!(find_row(&body["pull"], "exercise", &id).unwrap()["name"], "New");
}

async fn older_update_is_ignored(c: Client) {
    let id = uuid();
    let t = now_ms();
    c.sync(0, json!({ "exercise": [exercise(&id, "Current", t)] })).await;
    let (_, body) = c.sync(0, json!({ "exercise": [exercise(&id, "Stale", t - 1)] })).await;
    let row = find_row(&body["pull"], "exercise", &id).unwrap();
    assert_eq!(row["name"], "Current");
    assert_eq!(row["updated_at"], t);
}

async fn soft_delete_propagates(c: Client) {
    let id = uuid();
    let t = now_ms();
    c.sync(0, json!({ "exercise": [exercise(&id, "Gone", t)] })).await;
    let mut deleted = exercise(&id, "Gone", t + 1);
    deleted["deleted_at"] = json!(t + 1);
    let (_, body) = c.sync(0, json!({ "exercise": [deleted] })).await;
    assert_eq!(find_row(&body["pull"], "exercise", &id).unwrap()["deleted_at"], t + 1);
}

async fn validation_error_rejects_whole_batch(c: Client) {
    let good = uuid();
    let bad = uuid();
    let mut invalid = exercise(&bad, "Bad", now_ms());
    invalid["equipment"] = json!("laser");
    let (status, body) = c.sync(0, json!({ "exercise": [exercise(&good, "Good", now_ms()), invalid] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
    assert_eq!(body["errors"][0]["table"], "exercise");
    assert_eq!(body["errors"][0]["id"], bad);
    let all = c.pull_all(0).await;
    assert!(find_row(&all, "exercise", &good).is_none(), "valid row must not be written");
}

async fn unknown_table_is_rejected(c: Client) {
    let (status, body) = c.sync(0, json!({ "secrets": [{ "id": "x", "updated_at": 1 }] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["errors"][0]["table"], "secrets");
    assert_eq!(body["errors"][0]["message"], "unknown table");
}

async fn missing_foreign_key_is_rejected(c: Client) {
    let ex = uuid();
    c.sync(0, json!({ "exercise": [exercise(&ex, "Ex", now_ms())] })).await;
    let set = workout_set(&uuid(), &uuid(), &ex, now_ms());
    let (status, body) = c.sync(0, json!({ "workout_set": [set] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
}

async fn child_and_parent_in_one_push(c: Client) {
    let ex = uuid();
    let session = uuid();
    let set = uuid();
    let t = now_ms();
    let (status, body) = c
        .sync(0, json!({
            "workout_set": [workout_set(&set, &session, &ex, t)],
            "workout_session": [workout_session(&session, t, t)],
            "exercise": [exercise(&ex, "Squat", t)]
        }))
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(find_row(&body["pull"], "workout_set", &set).unwrap()["weight_kg"], 62.5);
}

async fn oversized_push_is_413(c: Client) {
    let rows: Vec<Value> = (0..501).map(|i| exercise(&uuid(), &format!("E{i}"), now_ms())).collect();
    let (status, body) = c.sync(0, json!({ "exercise": rows })).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(body["code"], "payload_too_large");
}

async fn malformed_json_is_400(c: Client) {
    let (status, body) = c.post_text("/api/sync", "{not json", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "bad_request");
}

async fn paginates_with_has_more(c: Client) {
    let ids: Vec<String> = (0..500).map(|_| uuid()).collect();
    let rows: Vec<Value> = ids.iter().enumerate().map(|(i, id)| exercise(id, &format!("P{i}"), now_ms())).collect();
    let (status, first) = c.sync(0, json!({ "exercise": rows })).await;
    assert_eq!(status, StatusCode::OK, "{first}");
    let (_, page) = c.sync(0, json!({})).await;
    assert_eq!(page["has_more"], true, "500 pushed + seed rows must exceed one page");
    let all = c.pull_all(0).await;
    let got = all["exercise"].as_array().unwrap();
    for id in &ids {
        assert!(got.iter().any(|r| r["id"] == *id), "missing {id}");
    }
}
```

Register `mod sync;` and `sync::register(&mut trials, &ctx);` in `main.rs`.

- [ ] **Step 2: Run `cargo test --test api` → sync tests fail (404 on `/api/sync`)**

- [ ] **Step 3: Implement `src/sync/handler.rs`**

```rust
//! `POST /api/sync`: validate → atomic push → pull after cursor.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::{D1Database, Env, Request, Response};

use super::sql;
use super::table::SyncTable;
use crate::db::{self, Row};
use crate::error::{ApiError, ApiResult, FieldError};
use crate::modules;

/// Maximum rows accepted in one push.
pub const MAX_PUSH_ROWS: usize = 500;
/// Maximum rows returned in one pull (across all tables).
pub const PULL_LIMIT: usize = 500;
/// One more than [`PULL_LIMIT`], to detect `has_more` with a single query per table.
const PULL_QUERY_LIMIT: i64 = 501;

/// Request body.
#[derive(Deserialize)]
pub struct SyncRequest {
    /// Cursor from the previous response (0 on first sync).
    #[serde(default)]
    pub since_seq: i64,
    /// Dirty rows per table.
    #[serde(default)]
    pub push: BTreeMap<String, Vec<Row>>,
}

/// Response body.
#[derive(Serialize)]
pub struct SyncResponse {
    /// Cursor to send next time.
    pub seq: i64,
    /// `true` when the pull was truncated.
    pub has_more: bool,
    /// Changed rows per table (every table present, possibly empty).
    pub pull: BTreeMap<&'static str, Vec<Row>>,
}

/// HTTP handler.
pub async fn handle(mut req: Request, env: &Env) -> ApiResult<Response> {
    let body: SyncRequest = req
        .json()
        .await
        .map_err(|e| ApiError::BadRequest(format!("invalid JSON body: {e}")))?;
    let db = env.d1("DB")?;
    let tables = modules::sync_tables();
    let response = run(&db, &tables, body).await?;
    Ok(Response::from_json(&response)?)
}

async fn run(db: &D1Database, tables: &[&SyncTable], req: SyncRequest) -> ApiResult<SyncResponse> {
    validate_push(tables, &req.push)?;
    let last_seq = apply_push(db, tables, &req.push).await?;
    pull(db, tables, req.since_seq, last_seq).await
}

fn validate_push(tables: &[&SyncTable], push: &BTreeMap<String, Vec<Row>>) -> ApiResult<()> {
    let total: usize = push.values().map(Vec::len).sum();
    if total > MAX_PUSH_ROWS {
        return Err(ApiError::PayloadTooLarge(format!(
            "push contains {total} rows; the limit is {MAX_PUSH_ROWS}"
        )));
    }
    let mut errors = Vec::new();
    for (name, rows) in push {
        let Some(table) = tables.iter().find(|t| t.name == name) else {
            errors.push(FieldError { table: name.clone(), id: String::new(), message: "unknown table".into() });
            continue;
        };
        for row in rows {
            let id = row.get("id").and_then(Value::as_str).unwrap_or_default().to_owned();
            errors.extend(table.check(row).into_iter().map(|message| FieldError {
                table: name.clone(),
                id: id.clone(),
                message,
            }));
        }
    }
    if errors.is_empty() { Ok(()) } else { Err(ApiError::Validation(errors)) }
}

/// Writes pushed rows in FK order inside one atomic batch; returns the new `last_seq`.
async fn apply_push(
    db: &D1Database,
    tables: &[&SyncTable],
    push: &BTreeMap<String, Vec<Row>>,
) -> ApiResult<i64> {
    let last_seq = read_last_seq(db).await?;
    let mut statements = Vec::new();
    let mut seq = last_seq;
    for table in tables {
        let Some(rows) = push.get(table.name) else { continue };
        let sql = sql::upsert_sql(table);
        for row in rows {
            seq += 1;
            statements.push(db::prepare(db, &sql, &sql::upsert_params(table, row, seq))?);
        }
    }
    if statements.is_empty() {
        return Ok(last_seq);
    }
    statements.push(db::prepare(db, sql::WRITE_LAST_SEQ, &[Value::from(seq), Value::from(last_seq)])?);
    db.batch(statements).await.map_err(map_batch_error)?;
    Ok(seq)
}

async fn read_last_seq(db: &D1Database) -> ApiResult<i64> {
    db::query_i64(db, sql::READ_LAST_SEQ, &[], "value")
        .await?
        .ok_or_else(|| ApiError::Internal("sync_meta.last_seq is missing".into()))
}

/// D1 reports constraint failures as plain text; map the two we expect.
fn map_batch_error(err: worker::Error) -> ApiError {
    let text = err.to_string();
    if text.contains("UNIQUE constraint failed") {
        ApiError::Conflict("another sync is in progress; retry".into())
    } else if text.contains("FOREIGN KEY constraint failed") {
        ApiError::Validation(vec![FieldError {
            table: String::new(),
            id: String::new(),
            message: "a referenced row does not exist".into(),
        }])
    } else {
        ApiError::Internal(text)
    }
}

async fn pull(
    db: &D1Database,
    tables: &[&SyncTable],
    since_seq: i64,
    last_seq: i64,
) -> ApiResult<SyncResponse> {
    let params = [Value::from(since_seq), Value::from(PULL_QUERY_LIMIT)];
    let mut all: Vec<(&'static str, Row)> = Vec::new();
    for table in tables {
        let rows = db::query_rows(db, &sql::pull_sql(table), &params).await?;
        all.extend(rows.into_iter().map(|row| (table.name, row)));
    }
    all.sort_by_key(|(_, row)| row_seq(row));
    let has_more = all.len() > PULL_LIMIT;
    all.truncate(PULL_LIMIT);
    let seq = if has_more {
        all.last().map_or(since_seq, |(_, row)| row_seq(row))
    } else {
        since_seq.max(last_seq)
    };
    let mut pull: BTreeMap<&'static str, Vec<Row>> =
        tables.iter().map(|t| (t.name, Vec::new())).collect();
    for (name, row) in all {
        if let Some(bucket) = pull.get_mut(name) {
            bucket.push(row);
        }
    }
    Ok(SyncResponse { seq, has_more, pull })
}

fn row_seq(row: &Row) -> i64 {
    row.get("seq").and_then(Value::as_i64).unwrap_or(0)
}
```

- [ ] **Step 4: Mount in `router.rs`**

```rust
    let router = Router::new()
        .get("/api/health", |_, _| Response::from_json(&json!({ "ok": true })))
        .post_async("/api/sync", |req, ctx| async move {
            respond(crate::sync::handler::handle(req, &ctx.env).await)
        });
```

Add `pub mod handler;` to `sync/mod.rs`; remove any temporary `dead_code` allows.

- [ ] **Step 5: `cargo test --lib`, `cargo test --test api` green; clippy clean.** If the FK test returns 500 instead of 422, print the D1 error text from the failing test output and adjust the substring in `map_batch_error` (D1 local wording is `FOREIGN KEY constraint failed`).

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: sync endpoint with LWW push and seq-cursor pull"`

---

### Task 8: Built-in exercise catalog seed

**Files:**
- Create: `api/migrations/0002_gym_seed.sql`
- Create: `api/tests/api/gym/mod.rs`, `api/tests/api/gym/catalog.rs`; Modify: `api/tests/api/main.rs`

- [ ] **Step 1: Test `tests/api/gym/catalog.rs`**

```rust
//! Built-in exercise catalog seeded by migration.

use libtest_mimic::Trial;
use serde_json::json;

use crate::client::{Client, Ctx, find_row};
use crate::fixtures::now_ms;

const LAT_PULLDOWN: &str = "64957399-5838-4e90-8d8c-be7c00552f33";

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("gym::catalog::first_pull_contains_builtin_exercises", first_pull_contains_builtin));
    trials.push(ctx.trial("gym::catalog::user_edit_of_builtin_wins", user_edit_of_builtin_wins));
}

async fn first_pull_contains_builtin(c: Client) {
    let all = c.pull_all(0).await;
    let builtin: Vec<_> = all["exercise"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|r| r["image_key"].as_str().is_some_and(|k| k.starts_with("builtin/")))
        .collect();
    assert!(builtin.len() >= 60, "expected the full catalog, got {}", builtin.len());
    assert!(builtin.iter().all(|r| r["updated_at"] == 0));
    let lat = find_row(&all, "exercise", LAT_PULLDOWN).expect("Lat Pulldown seeded");
    assert_eq!(lat["name"], "Lat Pulldown");
    assert_eq!(lat["muscle_group"], "back");
    assert_eq!(lat["equipment"], "cable");
    assert_eq!(lat["image_key"], "builtin/lat-pulldown");
}

async fn user_edit_of_builtin_wins(c: Client) {
    let (_, body) = c
        .sync(0, json!({ "exercise": [{
            "id": LAT_PULLDOWN, "updated_at": now_ms(), "deleted_at": null,
            "name": "Lat Pulldown (wide grip)", "muscle_group": "back", "equipment": "cable",
            "image_key": "builtin/lat-pulldown", "notes": "my note"
        }] }))
        .await;
    assert_eq!(find_row(&body["pull"], "exercise", LAT_PULLDOWN).unwrap()["notes"], "my note");
}
```

`tests/api/gym/mod.rs`:

```rust
//! Gym module tests.

pub mod catalog;

use libtest_mimic::Trial;

use crate::client::Ctx;

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    catalog::register(trials, ctx);
}
```

Register `mod gym;` + `gym::register(&mut trials, &ctx);` in `main.rs`.

- [ ] **Step 2: Run → `first_pull_contains_builtin` fails (0 builtin rows)**

- [ ] **Step 3: Seed migration** — `npx wrangler d1 migrations create DB gym_seed`, then body:

```sql
-- Migration number: 0002 	 2026-09-19T00:00:01.000Z
-- Built-in exercise catalog. updated_at = 0 so any user edit wins. seq continues
-- from sync_meta.last_seq so pulls see these rows like any other change.
WITH v(n, id, name, muscle_group, equipment, slug) AS (VALUES
  (1,  '99a3bbb0-d257-412f-8c8a-c45d4fa23894', 'Barbell Bench Press',          'chest',      'barbell',    'barbell-bench-press'),
  (2,  '6eeda24f-4971-4555-9e83-16a7c3064ba6', 'Incline Barbell Bench Press',  'chest',      'barbell',    'incline-barbell-bench-press'),
  (3,  '1caa83b5-1339-4e32-a2b9-3018770aa048', 'Dumbbell Bench Press',         'chest',      'dumbbell',   'dumbbell-bench-press'),
  (4,  '2e0f45fa-698f-475f-bd50-6bd2e3d8597f', 'Incline Dumbbell Press',       'chest',      'dumbbell',   'incline-dumbbell-press'),
  (5,  '29ec6ed0-8772-4361-96a6-54da27eeeaab', 'Dumbbell Fly',                 'chest',      'dumbbell',   'dumbbell-fly'),
  (6,  '2dd4c9d5-3100-4adb-8616-9ac16f9ab7d4', 'Chest Press Machine',          'chest',      'machine',    'chest-press-machine'),
  (7,  '0be69ef3-8f83-4539-a520-b255f690f7ae', 'Pec Deck',                     'chest',      'machine',    'pec-deck'),
  (8,  '01163315-60d1-4095-bb1f-5dabb00b4bd7', 'Cable Crossover',              'chest',      'cable',      'cable-crossover'),
  (9,  'ad6d638c-5219-4512-b095-cf3659658992', 'Push-Up',                      'chest',      'bodyweight', 'push-up'),
  (10, 'b970fd04-4c10-47a0-b1db-ae575f846a97', 'Dip',                          'chest',      'bodyweight', 'dip'),
  (11, 'bb1b3316-ebc3-4daf-ba15-4418d493d030', 'Barbell Row',                  'back',       'barbell',    'barbell-row'),
  (12, 'ad7ed27d-5fc6-48b3-8621-3aa2122036b7', 'Deadlift',                     'back',       'barbell',    'deadlift'),
  (13, '64957399-5838-4e90-8d8c-be7c00552f33', 'Lat Pulldown',                 'back',       'cable',      'lat-pulldown'),
  (14, '668c7b3a-4b8d-4744-92e0-9baaf0e268ff', 'Seated Cable Row',             'back',       'cable',      'seated-cable-row'),
  (15, '457df00f-5e79-4e2d-a41e-2e230ad6a61a', 'Dumbbell Row',                 'back',       'dumbbell',   'dumbbell-row'),
  (16, '6aac836a-a98e-424b-8992-bf2a4ec7806b', 'T-Bar Row',                    'back',       'machine',    't-bar-row'),
  (17, '91798fd4-7063-45dc-b545-eb70e248a94c', 'Pull-Up',                      'back',       'bodyweight', 'pull-up'),
  (18, '6e45715a-4f73-4499-9329-efa8c89f853b', 'Chin-Up',                      'back',       'bodyweight', 'chin-up'),
  (19, '7a77feb6-9902-41b6-9f16-a12f258b63ae', 'Overhead Press',               'shoulders',  'barbell',    'overhead-press'),
  (20, '393241fb-8328-4132-bf21-ab9bfc80a6a6', 'Dumbbell Shoulder Press',      'shoulders',  'dumbbell',   'dumbbell-shoulder-press'),
  (21, 'f8baf693-2849-4b85-b224-dab15f057194', 'Lateral Raise',                'shoulders',  'dumbbell',   'lateral-raise'),
  (22, '0b5eb1f7-4cc8-47a8-a3df-cef9fb17935c', 'Front Raise',                  'shoulders',  'dumbbell',   'front-raise'),
  (23, '2f55d52e-a015-4d37-b93f-2c4d588e4133', 'Rear Delt Fly',                'shoulders',  'machine',    'rear-delt-fly'),
  (24, '4574373f-3af5-4d8c-95f9-6c2d15d712c9', 'Face Pull',                    'shoulders',  'cable',      'face-pull'),
  (25, '1d6d3a2f-41e1-456f-84a0-7256586427e7', 'Shoulder Press Machine',       'shoulders',  'machine',    'shoulder-press-machine'),
  (26, '0ff6cfec-6ee0-4185-bbed-2091545b6d51', 'Barbell Curl',                 'biceps',     'barbell',    'barbell-curl'),
  (27, '6104b1c2-cc95-4617-99b8-1aaea4c84c89', 'Dumbbell Curl',                'biceps',     'dumbbell',   'dumbbell-curl'),
  (28, '0f86c87b-d522-470f-b720-d065253e8d92', 'Hammer Curl',                  'biceps',     'dumbbell',   'hammer-curl'),
  (29, '7d62115f-1037-4302-8592-c34e3219d1ef', 'Preacher Curl',                'biceps',     'machine',    'preacher-curl'),
  (30, '2c10d44a-40fa-4529-a1b1-07a4b4200b4d', 'Cable Curl',                   'biceps',     'cable',      'cable-curl'),
  (31, 'f5decbc9-d3c8-4f21-87f7-226edc84d366', 'Triceps Pushdown',             'triceps',    'cable',      'triceps-pushdown'),
  (32, 'f71bbe18-835b-4545-9ba0-2b1677a04d48', 'Overhead Triceps Extension',   'triceps',    'dumbbell',   'overhead-triceps-extension'),
  (33, '057a82b6-9b26-4192-bc7b-cd7efcff685d', 'Skull Crusher',                'triceps',    'barbell',    'skull-crusher'),
  (34, 'f9f38e93-db96-4127-8833-86b6c2a1dbe3', 'Close-Grip Bench Press',       'triceps',    'barbell',    'close-grip-bench-press'),
  (35, 'f207e0e9-c035-432e-a847-6909cac30c63', 'Triceps Dip Machine',          'triceps',    'machine',    'triceps-dip-machine'),
  (36, '070e241b-d386-4154-bee3-e1b3b93f09de', 'Wrist Curl',                   'forearms',   'dumbbell',   'wrist-curl'),
  (37, '1e4ffcd5-d3d2-47e6-a1e9-338305d8ecc0', 'Back Squat',                   'quads',      'barbell',    'back-squat'),
  (38, '598fa5a7-ca5d-4afa-8491-36267d5ffd9f', 'Front Squat',                  'quads',      'barbell',    'front-squat'),
  (39, '3f23b7d8-09af-4ff6-99a3-47b48e2d71fe', 'Leg Press',                    'quads',      'machine',    'leg-press'),
  (40, '70403dc4-063f-44e3-a10e-ccaf0dddb70f', 'Leg Extension',                'quads',      'machine',    'leg-extension'),
  (41, 'b13be2bc-8c0f-408c-825c-b56d2654f10b', 'Hack Squat',                   'quads',      'machine',    'hack-squat'),
  (42, '2840a797-d0ff-43b7-aabb-ba7e6d7311d8', 'Bulgarian Split Squat',        'quads',      'dumbbell',   'bulgarian-split-squat'),
  (43, 'd4c25daa-db19-465c-be45-6255a7955ead', 'Lunge',                        'quads',      'dumbbell',   'lunge'),
  (44, 'e3c3f36f-f71c-47a9-95b6-605005588482', 'Romanian Deadlift',            'hamstrings', 'barbell',    'romanian-deadlift'),
  (45, '5abe6e60-f6b6-41fc-b2cd-28c9f947d661', 'Lying Leg Curl',               'hamstrings', 'machine',    'lying-leg-curl'),
  (46, '0ab7b706-86b5-48db-a281-0e6299bc8c5b', 'Seated Leg Curl',              'hamstrings', 'machine',    'seated-leg-curl'),
  (47, '9ad871e7-3a42-4f58-9088-fdaa98e3fc03', 'Hip Thrust',                   'glutes',     'barbell',    'hip-thrust'),
  (48, '79d2caa1-6a13-434f-8211-8e94e64a1ba4', 'Glute Kickback',               'glutes',     'cable',      'glute-kickback'),
  (49, 'ea942f46-ac88-489d-bccd-d5592f19b43a', 'Standing Calf Raise',          'calves',     'machine',    'standing-calf-raise'),
  (50, '9670a516-7cf7-4af8-b62b-b58659dff46e', 'Seated Calf Raise',            'calves',     'machine',    'seated-calf-raise'),
  (51, 'c7c71ff2-2cf1-4c00-9efa-41f64bf1e316', 'Plank',                        'core',       'bodyweight', 'plank'),
  (52, '06c6be35-f60b-4787-a6dd-1f368e9cb265', 'Hanging Leg Raise',            'core',       'bodyweight', 'hanging-leg-raise'),
  (53, '54f6376a-c385-44a6-ad30-b3b1d39d42dd', 'Cable Crunch',                 'core',       'cable',      'cable-crunch'),
  (54, '62cfef79-ff48-4f40-a324-9e5c462431a4', 'Ab Crunch Machine',            'core',       'machine',    'ab-crunch-machine'),
  (55, 'fcb915d3-5e5b-48fb-8775-3ef9263e310d', 'Treadmill',                    'cardio',     'machine',    'treadmill'),
  (56, 'e6223169-d637-45c4-ac0e-ea7e284d1f77', 'Stationary Bike',              'cardio',     'machine',    'stationary-bike'),
  (57, '39673f4e-89e6-4871-9aff-444be7359a46', 'Rowing Machine',               'cardio',     'machine',    'rowing-machine'),
  (58, 'c63a4404-4a5d-469d-bc12-9583c7ea4761', 'Elliptical',                   'cardio',     'machine',    'elliptical'),
  (59, 'a96798b3-4393-4de7-a820-63c9dbb5fe81', 'Kettlebell Swing',             'full_body',  'other',      'kettlebell-swing'),
  (60, '22920bb8-b34c-4674-9244-3284854758cc', 'Farmer''s Walk',               'full_body',  'dumbbell',   'farmers-walk')
)
INSERT INTO exercise (id, updated_at, deleted_at, seq, name, muscle_group, equipment, image_key, notes)
SELECT v.id, 0, NULL, (SELECT value FROM sync_meta WHERE key = 'last_seq') + v.n,
       v.name, v.muscle_group, v.equipment, 'builtin/' || v.slug, NULL
FROM v;

UPDATE sync_meta SET value = value + 60 WHERE key = 'last_seq';
```

- [ ] **Step 4: `cargo test --test api` green** (the harness wipes state and re-applies both migrations)

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: seed built-in exercise catalog"`

---

### Task 9: Export endpoint

**Files:**
- Create: `api/src/modules/gym/export.rs`; Modify: `api/src/modules/gym/mod.rs` (route)
- Create: `api/tests/api/gym/export.rs`; Modify: `api/tests/api/gym/mod.rs`

- [ ] **Step 1: Test**

```rust
//! GET /api/gym/export

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx, TOKEN};
use crate::fixtures::{exercise, now_ms, uuid};

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("gym::export::returns_active_rows_only", returns_active_rows_only));
    trials.push(ctx.trial("gym::export::requires_token", requires_token));
}

async fn returns_active_rows_only(c: Client) {
    let live = uuid();
    let dead = uuid();
    let t = now_ms();
    let mut deleted = exercise(&dead, "Deleted", t);
    deleted["deleted_at"] = json!(t);
    c.sync(0, json!({ "exercise": [exercise(&live, "Live", t), deleted] })).await;

    let (status, body) = c.get("/api/gym/export", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body["exported_at"].as_i64().unwrap() > 0);
    for table in ["exercise", "program", "program_day", "program_exercise", "workout_session", "workout_set"] {
        assert!(body["tables"][table].is_array(), "missing table {table}");
    }
    let rows = body["tables"]["exercise"].as_array().unwrap();
    assert!(rows.iter().any(|r| r["id"] == live));
    assert!(!rows.iter().any(|r| r["id"] == dead));
}

async fn requires_token(c: Client) {
    let (status, _) = c.get("/api/gym/export", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
```

- [ ] **Step 2: Run → 404**

- [ ] **Step 3: Implement `export.rs`**

```rust
//! `GET /api/gym/export`: every active gym row as one JSON document, for analysis.

use std::collections::BTreeMap;

use serde_json::json;
use worker::{Date, Request, Response, RouteContext};

use super::TABLES;
use crate::db::{self, Row};
use crate::error::ApiResult;
use crate::sync::sql;

/// HTTP handler.
pub async fn handle(_req: Request, ctx: RouteContext<()>) -> ApiResult<Response> {
    let db = ctx.env.d1("DB")?;
    let mut tables: BTreeMap<&'static str, Vec<Row>> = BTreeMap::new();
    for table in &TABLES {
        tables.insert(table.name, db::query_rows(&db, &sql::export_sql(table), &[]).await?);
    }
    Ok(Response::from_json(&json!({
        "exported_at": Date::now().as_millis(),
        "tables": tables,
    }))?)
}
```

`gym/mod.rs`:

```rust
pub mod tables;
mod export;
mod validate;

use worker::Router;

pub use tables::TABLES;

use crate::router::respond;

/// Extra HTTP routes owned by this module.
pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    router.get_async("/api/gym/export", |req, ctx| async move { respond(export::handle(req, ctx).await) })
}
```

- [ ] **Step 4: Register test, run green, clippy clean, commit** — `git commit -am "feat: gym export endpoint"` (use `git add -A` first)

---

### Task 10: Exercise images (R2 upload + read)

**Files:**
- Create: `api/src/modules/gym/images.rs`; Modify: `api/src/modules/gym/mod.rs`
- Create: `api/tests/api/gym/images.rs`; Modify: `api/tests/api/gym/mod.rs`

**Interfaces:**
- Produces pure helpers `images::extension_for(content_type) -> Option<&'static str>`, `images::image_key(exercise_id, ext, millis, nonce) -> String`, `images::is_valid_key(&str) -> bool`; handlers `upload`, `serve`.

- [ ] **Step 1: Unit tests (bottom of `images.rs`)**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_content_types_to_extensions() {
        assert_eq!(extension_for("image/jpeg"), Some("jpg"));
        assert_eq!(extension_for("image/png; charset=binary"), Some("png"));
        assert_eq!(extension_for("IMAGE/WEBP"), Some("webp"));
        assert_eq!(extension_for("image/gif"), None);
        assert_eq!(extension_for(""), None);
    }

    #[test]
    fn builds_namespaced_keys() {
        assert_eq!(image_key("abc", "jpg", 1758000000000, 0xdead_beef), "exercises/abc/1758000000000-deadbeef.jpg");
    }

    #[test]
    fn validates_keys() {
        assert!(is_valid_key("exercises/abc/1-00000001.jpg"));
        assert!(!is_valid_key("exercises/../secret"));
        assert!(!is_valid_key("other/abc.jpg"));
        assert!(!is_valid_key("exercises//abc.jpg"));
        assert!(!is_valid_key(""));
    }
}
```

- [ ] **Step 2: Integration tests `tests/api/gym/images.rs`**

```rust
//! PUT /api/gym/exercises/{id}/image and GET /api/gym/images/{key}

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx, TOKEN};
use crate::fixtures::{exercise, now_ms, uuid};

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n fake png body";

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("gym::images::upload_then_read", upload_then_read));
    trials.push(ctx.trial("gym::images::unknown_exercise_is_404", unknown_exercise_is_404));
    trials.push(ctx.trial("gym::images::wrong_type_is_415", wrong_type_is_415));
    trials.push(ctx.trial("gym::images::too_large_is_413", too_large_is_413));
    trials.push(ctx.trial("gym::images::missing_or_bad_key_is_404", missing_or_bad_key_is_404));
    trials.push(ctx.trial("gym::images::requires_token", requires_token));
}

async fn seeded_exercise(c: &Client) -> String {
    let id = uuid();
    let (status, body) = c.sync(0, json!({ "exercise": [exercise(&id, "Photo", now_ms())] })).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    id
}

async fn upload_then_read(c: Client) {
    let id = seeded_exercise(&c).await;
    let (status, body) = c
        .put_bytes(&format!("/api/gym/exercises/{id}/image"), PNG.to_vec(), "image/png", Some(TOKEN))
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let key = body["image_key"].as_str().unwrap().to_owned();
    assert!(key.starts_with(&format!("exercises/{id}/")) && key.ends_with(".png"), "{key}");

    let resp = c.get_raw(&format!("/api/gym/images/{key}"), Some(TOKEN)).await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(resp.headers()["content-type"], "image/png");
    assert!(resp.headers()["cache-control"].to_str().unwrap().contains("immutable"));
    assert_eq!(resp.bytes().await.unwrap().as_ref(), PNG);
}

async fn unknown_exercise_is_404(c: Client) {
    let (status, body) = c
        .put_bytes(&format!("/api/gym/exercises/{}/image", uuid()), PNG.to_vec(), "image/png", Some(TOKEN))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "not_found");
}

async fn wrong_type_is_415(c: Client) {
    let id = seeded_exercise(&c).await;
    let (status, body) = c
        .put_bytes(&format!("/api/gym/exercises/{id}/image"), PNG.to_vec(), "image/gif", Some(TOKEN))
        .await;
    assert_eq!(status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    assert_eq!(body["code"], "unsupported_media_type");
}

async fn too_large_is_413(c: Client) {
    let id = seeded_exercise(&c).await;
    let big = vec![0u8; 5 * 1024 * 1024 + 1];
    let (status, body) = c
        .put_bytes(&format!("/api/gym/exercises/{id}/image"), big, "image/jpeg", Some(TOKEN))
        .await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(body["code"], "payload_too_large");
}

async fn missing_or_bad_key_is_404(c: Client) {
    let (status, _) = c.get("/api/gym/images/exercises/nope/1-00000001.jpg", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = c.get("/api/gym/images/exercises/../wrangler.toml", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

async fn requires_token(c: Client) {
    let (status, _) = c.get("/api/gym/images/exercises/x/1-00000001.jpg", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
```

- [ ] **Step 3: Run → unit compile error / integration 404**

- [ ] **Step 4: Implement `images.rs`**

```rust
//! Custom exercise photos in R2. Built-in images (`builtin/…`) never touch the API.

use serde_json::{Value, json};
use worker::{Date, Headers, HttpMetadata, Request, Response, RouteContext};

use crate::db;
use crate::error::{ApiError, ApiResult};

const MAX_BYTES: usize = 5 * 1024 * 1024;
const BUCKET: &str = "IMAGES";
const CACHE_CONTROL: &str = "private, max-age=31536000, immutable";
const KEY_PREFIX: &str = "exercises/";
const TYPES: [(&str, &str); 3] = [("image/jpeg", "jpg"), ("image/png", "png"), ("image/webp", "webp")];

/// `PUT /api/gym/exercises/:id/image` — stores the body and returns its key.
pub async fn upload(mut req: Request, ctx: RouteContext<()>) -> ApiResult<Response> {
    let id = ctx.param("id").cloned().ok_or(ApiError::NotFound)?;
    let content_type = req.headers().get("content-type")?.unwrap_or_default();
    let ext = extension_for(&content_type).ok_or_else(|| {
        ApiError::UnsupportedMediaType(format!(
            "unsupported content-type '{content_type}'; use image/jpeg, image/png or image/webp"
        ))
    })?;
    let declared = req.headers().get("content-length")?.and_then(|v| v.parse::<usize>().ok());
    if declared.is_some_and(|len| len > MAX_BYTES) {
        return Err(too_large());
    }

    let db = ctx.env.d1("DB")?;
    let exists = db::query_i64(
        &db,
        "SELECT 1 AS one FROM exercise WHERE id = ?1 AND deleted_at IS NULL",
        &[Value::from(id.as_str())],
        "one",
    )
    .await?
    .is_some();
    if !exists {
        return Err(ApiError::NotFound);
    }

    let bytes = req.bytes().await?;
    if bytes.len() > MAX_BYTES {
        return Err(too_large());
    }
    if bytes.is_empty() {
        return Err(ApiError::BadRequest("empty body".into()));
    }

    let key = image_key(&id, ext, Date::now().as_millis(), nonce());
    let mime = mime_of(&content_type);
    ctx.env
        .bucket(BUCKET)?
        .put(&key, bytes)
        .http_metadata(HttpMetadata {
            content_type: Some(mime),
            cache_control: Some(CACHE_CONTROL.to_owned()),
            ..HttpMetadata::default()
        })
        .execute()
        .await?;
    Ok(Response::from_json(&json!({ "image_key": key }))?)
}

/// `GET /api/gym/images/*key` — streams the object back with its content type.
pub async fn serve(_req: Request, ctx: RouteContext<()>) -> ApiResult<Response> {
    let key = ctx.param("key").cloned().unwrap_or_default();
    if !is_valid_key(&key) {
        return Err(ApiError::NotFound);
    }
    let Some(object) = ctx.env.bucket(BUCKET)?.get(&key).execute().await? else {
        return Err(ApiError::NotFound);
    };
    let content_type = object
        .http_metadata()
        .content_type
        .unwrap_or_else(|| "application/octet-stream".to_owned());
    let Some(body) = object.body() else {
        return Err(ApiError::NotFound);
    };
    let bytes = body.bytes().await?;
    let headers = Headers::new();
    headers.set("Content-Type", &content_type)?;
    headers.set("Cache-Control", CACHE_CONTROL)?;
    Ok(Response::from_bytes(bytes)?.with_headers(headers))
}

/// File extension for an accepted image content type (parameters and case ignored).
pub fn extension_for(content_type: &str) -> Option<&'static str> {
    let mime = mime_of(content_type);
    TYPES.iter().find(|(m, _)| *m == mime).map(|(_, ext)| *ext)
}

/// Object key: namespaced per exercise, unique per upload.
pub fn image_key(exercise_id: &str, ext: &str, millis: u64, nonce: u32) -> String {
    format!("{KEY_PREFIX}{exercise_id}/{millis}-{nonce:08x}.{ext}")
}

/// Only keys this module created are served; blocks traversal-looking input.
pub fn is_valid_key(key: &str) -> bool {
    key.starts_with(KEY_PREFIX) && !key.contains("..") && !key.contains("//")
}

fn mime_of(content_type: &str) -> String {
    content_type.split(';').next().unwrap_or_default().trim().to_ascii_lowercase()
}

fn too_large() -> ApiError {
    ApiError::PayloadTooLarge(format!("image exceeds {MAX_BYTES} bytes"))
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn nonce() -> u32 {
    (js_sys::Math::random() * f64::from(u32::MAX)) as u32
}
```

Routes in `gym/mod.rs`:

```rust
mod images;

pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    router
        .get_async("/api/gym/export", |req, ctx| async move { respond(export::handle(req, ctx).await) })
        .put_async("/api/gym/exercises/:id/image", |req, ctx| async move { respond(images::upload(req, ctx).await) })
        .get_async("/api/gym/images/*key", |req, ctx| async move { respond(images::serve(req, ctx).await) })
}
```

If `HttpMetadata` is not re-exported at `worker::HttpMetadata`, import it from
`worker::r2::HttpMetadata` (check with `grep -rn "pub use" ~/.cargo/registry/src/*/worker-0.8.6/src/lib.rs`).

- [ ] **Step 5: Register tests; `cargo test --lib` and `cargo test --test api` green; clippy clean**

Note: the 5 MB upload test relies on `wrangler dev` accepting the body; if the
local server rejects it before the Worker runs (HTTP 413 from workerd), the
test still passes as long as the status is 413 — but assert on `code` only
when the body is JSON; adjust the test to `assert!(body.is_null() || body["code"] == "payload_too_large")`.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: exercise image upload and read via R2"`

---

### Task 11: New-module skill and final docs pass

**Files:**
- Create: `.claude/skills/new-module/SKILL.md`
- Modify: `CLAUDE.md` (only if a command changed during implementation)

- [ ] **Step 1: `SKILL.md`**

```markdown
---
name: new-module
description: Add a new module to api/ (tables synced to the iOS app and/or REST routes). Use when the user asks for a new domain such as servers, network, notes.
---

# Add a module to `api/`

1. **Spec first**: write `docs/specs/<module>.md` (tables with base columns, enums, endpoints, out of scope). Get approval.
2. **Migration**: `npx wrangler d1 migrations create DB <module>` → tables with `id, updated_at, deleted_at, seq INTEGER NOT NULL UNIQUE` first; FK order matters. Seeds use `updated_at = 0` and allocate `seq` from `sync_meta.last_seq` (see `migrations/0002_gym_seed.sql`).
3. **Code** in `src/modules/<module>/`:
   - `tables.rs` — `pub static TABLES: [SyncTable; N]`, parents before children.
   - `validate.rs` — one `fn(&Row) -> Vec<String>` per table (types are already checked).
   - `mod.rs` — `pub use tables::TABLES;` and `pub fn routes(Router) -> Router` for extra endpoints under `/api/<module>/…`.
   - Register in `src/modules/mod.rs`: append tables to `sync_tables()` (respecting cross-module FK order) and chain `routes`.
4. **Tests**: unit tests in `validate.rs`; integration tests in `tests/api/<module>/` registered from `tests/api/main.rs`. Cover: sync round trip, each validation rule, each endpoint's success + auth + error cases.
5. **Docs**: update `CLAUDE.md` only if commands change. Never edit `.claude/rules/sync.md` without changing the spec.
6. `cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test --lib && cargo test --test api`, then commit.

Action modules (things that must be online, e.g. server restart) do not use sync: give them REST routes and their own tables without base columns.
```

- [ ] **Step 2: Commit** — `git add -A && git commit -m "docs: new-module skill"`

---

### Task 12: Deploy workflow and Cloudflare provisioning

**Files:**
- Create: `.github/workflows/api-deploy.yml`
- Modify: `api/wrangler.toml` (real `database_id`)

- [ ] **Step 1: `api-deploy.yml`**

```yaml
name: API Deploy

on:
  workflow_run:
    workflows: ["API CI"]
    types: [completed]
    branches: [main]

concurrency:
  group: api-deploy
  cancel-in-progress: false

jobs:
  deploy:
    if: github.event.workflow_run.conclusion == 'success'
    runs-on: ubuntu-latest
    timeout-minutes: 30
    defaults:
      run:
        working-directory: api
    env:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
    steps:
      - uses: actions/checkout@v6
        with:
          ref: ${{ github.event.workflow_run.head_sha }}
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: api
      - uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: api/package-lock.json
      - run: npm ci
      - run: cargo install worker-build --locked
      - run: npx wrangler d1 migrations apply DB --remote
      - run: npx wrangler deploy
```

- [ ] **Step 2: Human steps (cannot be automated; do them in order, in `api/`)**

```bash
npx wrangler login                                   # browser OAuth once
npx wrangler d1 create personal-api                  # copy database_id into wrangler.toml
npx wrangler r2 bucket create personal-api-images
npx wrangler d1 migrations apply DB --remote
openssl rand -base64 32                              # this is API_TOKEN; keep it for the iOS app
npx wrangler secret put API_TOKEN                    # paste the token
npx wrangler deploy                                  # first deploy also attaches api.akhmadqasim.com
curl https://api.akhmadqasim.com/api/health          # {"ok":true}
```

Then on GitHub: create the public repo `personal-app`, push `main`, and add
secrets `CLOUDFLARE_API_TOKEN` (custom token: Account → Workers Scripts:Edit,
D1:Edit, Workers R2 Storage:Edit; Zone akhmadqasim.com → Workers Routes:Edit)
and `CLOUDFLARE_ACCOUNT_ID` (from the dashboard sidebar).

- [ ] **Step 3: Commit** — `git add -A && git commit -m "ci: deploy workflow after green CI on main"`

---

## Self-review

- Spec coverage: §3 tables → Task 5/6; catalog → Task 8; images → Task 10; §4 endpoints → Tasks 1, 7, 9, 10; 404/401/400/409/413/415/422/500 → Tasks 3, 4, 7, 10; §5 protocol (LWW, seq, 500 limits, has_more, FK order, atomic batch, 409) → Task 7; §6 layout → Tasks 1–11; §7 tests → each task; §8 CI/CD/secrets → Tasks 1, 12.
- Types are consistent: `Row` = `serde_json::Map<String, Value>` everywhere; `SyncTable { name, columns, validate }`; `respond` lives in `router.rs` and is used by `gym/mod.rs`.
- No placeholders remain except the `database_id` in `wrangler.toml`, which is a deliberate human step (Task 12).
