# Spec: Gym Tracker (modul pertama akhmadqasim-api)

Tanggal: 2026-09-19 · Status: disetujui (revisi: foto alat, katalog bawaan, bahasa Inggris)

## 1. Tujuan

API pribadi di `api.akhmadqasim.com` untuk satu pengguna. Modul pertama: mencatat
program latihan gym (alat, hari, beban, repetisi) dari app iOS yang bekerja
offline-first dan menyinkronkan data ke server. Sistem dirancang sebagai
*modular monolith* karena modul lain (manajemen server, network, dsb.) akan
menyusul.

Bahasa: seluruh app, nama katalog, pesan error API, kode, komentar, dan dokumen
di dalam repo (CLAUDE.md, rules) memakai bahasa Inggris. Spec dan plan boleh
berbahasa Indonesia.

## 2. Keputusan teknis

| Hal | Pilihan | Alasan |
|---|---|---|
| Bahasa | Rust (`workers-rs`, compile ke WASM) | Toolchain sudah ada di PC; hemat resource |
| Hosting | Cloudflare Workers + D1 + R2 | Gratis, TLS otomatis, domain sudah di Cloudflare |
| Deploy | GitHub Actions → `wrangler deploy` | Otomatis tiap push `main` |
| Auth | Bearer token statis (secret Worker) | Satu pengguna; token disimpan di Keychain iOS |
| Sync | Row-level last-write-wins + cursor `seq` | Robust untuk 1 pengguna/1–2 device, minim mekanisme |
| Client | iOS 26, SwiftUI, GRDB (SQLite) | Skema lokal identik dengan server (repo terpisah) |

Jalur upgrade auth bila perlu: pasang Cloudflare Access di depan Worker tanpa
mengubah kode.

## 3. Model data

Semua tabel yang ikut sync memiliki kolom standar:

```sql
id         TEXT    PRIMARY KEY,          -- UUID v4, dibuat di client
updated_at INTEGER NOT NULL,             -- epoch ms, diisi client saat menulis
deleted_at INTEGER,                      -- soft delete; NULL = aktif
seq        INTEGER NOT NULL UNIQUE       -- diisi server, monoton naik, cursor pull
```

Tabel modul gym (urutan = urutan dependensi FK):

| Tabel | Kolom khusus |
|---|---|
| `exercise` | `name`, `muscle_group`, `equipment` (barbell/dumbbell/machine/cable/bodyweight/other), `image_key` NULL, `notes` NULL |
| `program` | `name`, `is_active` (0/1) |
| `program_day` | `program_id` → program, `name`, `position` |
| `program_exercise` | `program_day_id` → program_day, `exercise_id` → exercise, `position`, `target_sets`, `target_reps`, `target_weight_kg` NULL, `rest_seconds` NULL |
| `workout_session` | `started_at`, `finished_at` NULL, `program_day_id` NULL → program_day, `notes` NULL |
| `workout_set` | `session_id` → workout_session, `exercise_id` → exercise, `position`, `weight_kg` REAL, `reps`, `rpe` NULL, `completed` (0/1) |

Alur pakai: buka hari program → app menyalin `program_exercise` menjadi
`workout_set` dengan `weight_kg`/`reps` diisi dari set terakhir gerakan itu →
pengguna mengedit → simpan lokal → sync.

`seq` diambil dari satu counter global (tabel `sync_meta(key, value)`, key
`last_seq`) sehingga urutan lintas tabel konsisten.

### Katalog bawaan

Migrasi seed mengisi `exercise` dengan katalog gerakan/alat standar (nama
Inggris baku, mis. "Lat Pulldown", "Leg Press") memakai UUID tetap,
`updated_at = 0` (sehingga suntingan pengguna selalu menang), dan
`image_key = "builtin/<slug>"`. App iOS menerima katalog lewat pull pertama
(`since_seq = 0`), jadi tidak perlu menanam data di app.

### Gambar

- **Bawaan**: `image_key` berawalan `builtin/` → app memuat ilustrasi dari aset
  bundel dengan gaya seragam; tidak lewat API.
- **Custom**: pengguna memotret alat → app mengecilkan ke ≤1024 px JPEG →
  `PUT /api/gym/exercises/{id}/image` → server simpan ke R2 dengan key
  `exercises/<exercise_id>/<uuid>.jpg` dan mengembalikan `image_key`; app
  menulis `image_key` ke baris lokal dan menyinkronkannya seperti kolom biasa
  (server tidak menyentuh baris). Gambar dibaca lewat
  `GET /api/gym/images/{key}` (auth, `Cache-Control: private, immutable`).
  Batas 5 MB, tipe `image/jpeg|png|webp`. Objek yatim di R2 dibiarkan.

## 4. Endpoint

```
GET  /api/health                         200 {"ok":true}                tanpa auth
POST /api/sync                           replikasi dua arah              Bearer API_TOKEN
GET  /api/gym/export                     JSON semua tabel gym (aktif)    Bearer API_TOKEN
PUT  /api/gym/exercises/{id}/image       unggah foto → {"image_key"}     Bearer API_TOKEN
GET  /api/gym/images/{key}               baca foto dari R2               Bearer API_TOKEN
```

Tidak ada CRUD REST per tabel: app membaca/menulis SQLite lokal, `/api/sync`
hanya jalur replikasi. Modul aksi di masa depan (mis. `servers`) memakai REST
biasa di `/api/<modul>/…`.

Semua respons error berbentuk `{"code": "<snake_case>", "message": "…"}` dengan
status HTTP yang sesuai: 401 `unauthorized`, 404 `not_found`, 409 `conflict`,
413 `payload_too_large`, 415 `unsupported_media_type`, 422 `validation_failed`
(+ `errors: [{table, id, message}]`), 500 `internal`.

## 5. Protokol sync

Request `POST /api/sync`:

```json
{
  "since_seq": 1234,
  "push": {
    "exercise":    [ { "id": "…", "name": "…", "updated_at": 1758000000000, "deleted_at": null } ],
    "workout_set": [ ]
  }
}
```

Server memproses dalam **satu D1 batch (atomik)**, tabel diurutkan sesuai
dependensi FK. Per baris push:

1. Belum ada di DB → insert, `seq` baru.
2. Ada dan `push.updated_at > db.updated_at` → update seluruh kolom, `seq` baru.
3. Selain itu → abaikan (server menang).
4. Validasi gagal (`reps <= 0`, `weight_kg < 0`, FK tidak ada, enum tak dikenal,
   kolom wajib kosong) → 422 dengan daftar `{table, id, message}`; seluruh
   batch dibatalkan.

Alokasi `seq`: baca `last_seq`, beri nomor `last_seq+1..last_seq+N` ke baris
push, tulis `last_seq+N` kembali dalam batch yang sama. Karena `seq` UNIQUE,
dua sync bersamaan membuat batch kedua gagal → 409 `conflict`, client
mengulang.

Setelah push, server mengembalikan baris dari semua tabel dengan
`seq > since_seq`, diurutkan `seq`, maksimal **500 baris total**; bila
terpotong `has_more = true` dan `seq` = seq baris terakhir yang dikirim, client
mengulang. Baris yang barusan di-push ikut dikembalikan (idempotent; client
menerapkan aturan LWW yang sama).

Response:

```json
{ "seq": 1300, "has_more": false, "pull": { "exercise": [ ], "workout_set": [ ] } }
```

Aturan client:

- Setiap tulis lokal: `dirty = 1`, `updated_at = now`.
- Sukses sync: hapus `dirty` hanya pada baris yang `updated_at`-nya tidak
  berubah selama request; simpan `since_seq = response.seq`.
- Gagal/putus: ulangi; request aman diulang.
- Hapus selalu soft delete; tidak pernah hard delete di kedua sisi.

Logika merge (aturan 1–3) diwujudkan sebagai satu `INSERT … ON CONFLICT(id) DO
UPDATE … WHERE excluded.updated_at > <tabel>.updated_at` yang dibangun oleh
engine sync dari deskripsi kolom tiap tabel; pembangun SQL dan validasi adalah
fungsi murni yang di-unit-test tanpa Cloudflare.

## 6. Struktur repo

```
akhmadqasim-api/
├── Cargo.toml                 # dependensi + [lints]: clippy pedantic, unwrap dilarang di src/
├── rustfmt.toml
├── package.json               # wrangler sebagai devDependency (dipakai dev & test)
├── wrangler.toml              # nama worker, binding D1 + R2, route api.akhmadqasim.com
├── CLAUDE.md                  # ringkas: apa ini, perintah dev/test/lint/deploy, pointer ke rules
├── .claude/
│   ├── rules/                 # rust.md, sync.md, testing.md
│   └── skills/new-module/     # langkah menambah modul
├── docs/specs/                # spec desain
├── docs/plans/                # implementation plan
├── migrations/                # 0001_gym.sql, 0002_gym_seed.sql
├── src/
│   ├── lib.rs                 # #[event(fetch)] → auth → router
│   ├── router.rs              # /api/health, /api/sync, /api/<modul>/…
│   ├── auth.rs                # Bearer token, perbandingan constant-time
│   ├── error.rs               # ApiError → JSON
│   ├── db.rs                  # helper D1 tipis (bind serde_json → JsValue)
│   ├── sync/{mod,table,sql,handler}.rs
│   └── modules/
│       ├── mod.rs
│       └── gym/{mod,tables,validate,export,images}.rs
├── tests/api/
│   ├── main.rs                # custom harness (libtest-mimic): start wrangler dev → tests → stop
│   ├── server.rs              # spawn `wrangler dev` + D1/R2 lokal, apply migrasi, kill tree
│   ├── client.rs              # helper HTTP + pembuat baris uji
│   ├── health.rs, auth.rs, sync.rs
│   └── gym/{mod,validation,export,images}.rs
└── .github/workflows/{ci,deploy}.yml
```

Kontrak modul: setiap modul mengekspos daftar `SyncTable` (nama tabel, kolom,
validator, urutan FK) dan opsional route tambahan. Engine sync tidak tahu isi
modul.

## 7. Testing

- Unit test (`cargo test --lib`): pembangun SQL upsert/pull, validasi baris,
  pengecekan token, serialisasi error.
- Integration test (`tests/api`): custom harness yang menjalankan `wrangler dev`
  dengan D1 + R2 lokal (state di `.wrangler/test-state`, dihapus tiap run),
  uji lewat HTTP nyata: health, auth ditolak/diterima, push–pull, idempotensi
  (kirim dua kali → hasil sama), konflik LWW, soft delete, paginasi
  `has_more`, 422 membatalkan batch, katalog bawaan ada di pull pertama,
  export, unggah/baca gambar, tolak gambar >5 MB / tipe salah.
- Setiap fitur wajib disertai test; CI merah tidak boleh merge.

## 8. CI/CD & operasional

- Secrets: `API_TOKEN` (secret Worker, `wrangler secret put`),
  `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (GitHub Secrets, izin
  Workers + D1 + R2).
- `ci.yml` (PR & push `main`): `cargo fmt --check` → `cargo clippy -D warnings`
  → unit test → integration test.
- `deploy.yml` (push `main`, setelah CI hijau): `wrangler d1 migrations apply
  DB --remote` → `wrangler deploy`. Rollback: `wrangler rollback`.
- Backup: D1 Time Travel (30 hari) + salinan penuh di SQLite iOS.

## 9. Di luar scope (nanti)

- Dashboard di app iOS.
- Modul aksi (servers/network): perlu agen di LAN yang polling perintah;
  didesain saat modulnya dibuat.
- Cloudflare Access bila butuh auth lebih kuat.
- Multi-pengguna.
