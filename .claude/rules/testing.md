# Testing

- Pure functions → unit tests next to the code (`#[cfg(test)]`), no Cloudflare.
- HTTP behaviour → `tests/api/` (single binary, custom harness that boots `wrangler dev`).
- Every test uses fresh UUIDs; tests share one local DB and must not depend on order.
- Add a test for every behaviour you add or fix; a bug fix starts with a failing test.
- `cargo test --lib` and `cargo test --test api` must both be green before commit.
