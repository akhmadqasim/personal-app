# personal-api

Rust API on Cloudflare Workers (D1 + R2) for the personal-app gym tracker. It syncs
gym data (exercises, programs, workout sessions/sets) to the iOS app with an
offline-first, last-write-wins protocol, and serves a few extra REST endpoints
(CSV export, exercise images).

## Commands (run in `api/`)
- `npx wrangler dev --var API_TOKEN:dev` — local server with emulated D1/R2
- `cargo test --lib` — unit tests (pure logic, no Cloudflare)
- `cargo test --test api` — integration tests (starts `wrangler dev` itself)
- `cargo fmt --all && cargo clippy --all-targets -- -D warnings` — must pass before commit
- Deploy: push to `main` (CI → D1 migrations → `wrangler deploy`)

## First deploy (one-time, on your machine)

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
