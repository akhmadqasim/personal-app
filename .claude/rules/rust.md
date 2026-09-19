# Rust conventions (api/)

- No `unwrap`/`expect` in `src/` (clippy denies). Return `ApiError`; `?` converts `worker::Error`.
- Pure logic (SQL text, validation, token check) never imports Cloudflare types, so it runs in `cargo test --lib`.
- Handlers are thin: parse → call pure function → run I/O → respond.
- One responsibility per file; a module folder is `mod.rs` (wiring) + focused files.
- Doc comment on every public item. Comments explain why, not what.
- Format + clippy pedantic clean before every commit.
- `[profile.release] strip` stays `"debuginfo"`: `strip = true` also drops the `target_features` section, so `wasm-bindgen` loses `reference-types` and fails with `externref table required for catch wrappers`.
