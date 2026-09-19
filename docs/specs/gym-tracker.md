# Spec: Gym Tracker (modul pertama akhmadqasim-api)

Tanggal: 2026-09-19 · Status: disetujui

## 1. Tujuan

API pribadi di `api.akhmadqasim.com` untuk satu pengguna. Modul pertama: mencatat
program latihan gym (alat, hari, beban, repetisi) dari app iOS yang bekerja
offline-first dan menyinkronkan data ke server. Sistem dirancang sebagai
*modular monolith* karena modul lain (manajemen server, network, dsb.) akan
menyusul.

## 2. Keputusan teknis

| Hal | Pilihan | Alasan |
|---|---|---|
| Bahasa | Rust (`workers-rs`, compile ke WASM) | Toolchain sudah ada di PC; hemat resource |
| Hosting | Cloudflare Workers + D1 | Gratis, TLS otomatis, domain sudah di Cloudflare |
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
| `exercise` | `name`, `muscle_group`, `equipment` (barbell/dumbbell/machine/cable/bodyweight), `notes` |
| `program` | `name`, `is_active` |
| `program_day` | `program_id` → program, `name`, `position` |
| `program_exercise` | `program_day_id` → program_day, `exercise_id` → exercise, `position`, `target_sets`, `target_reps`, `target_weight_kg` NULL, `rest_seconds` NULL |
| `workout_session` | `started_at`, `finished_at` NULL, `program_day_id` NULL → program_day, `notes` |
| `workout_set` | `session_id` → workout_session, `exercise_id` → exercise, `position`, `weight_kg` REAL, `reps`, `rpe` NULL, `completed` (0/1) |

Alur pakai: buka hari program → app menyalin `program_exercise` menjadi
`workout_set` dengan `weight_kg`/`reps` diisi dari set terakhir gerakan itu →
pengguna mengedit → simpan lokal → sync.

`seq` diambil dari satu counter global (tabel `sync_meta(key, value)`, key
`last_seq`) sehingga urutan lintas tabel konsisten.

## 4. Endpoint

```
GET  /api/health       200 {"ok":true}                        tanpa auth
POST /api/sync         replikasi dua arah                     Bearer API_TOKEN
GET  /api/gym/export   JSON semua tabel gym (untuk analisis)  Bearer API_TOKEN
```

Tidak ada CRUD REST per tabel: app membaca/menulis SQLite lokal, `/api/sync`
hanya jalur replikasi. Modul aksi di masa depan (mis. `servers`) memakai REST
biasa di `/api/<modul>/…`.

Semua respons error berbentuk `{"code": "<snake_case>", "message": "…"}` dengan
status HTTP yang sesuai (401 `unauthorized`, 422 `validation_failed`, 500
`internal`).

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
4. Validasi gagal (`reps <= 0`, `weight_kg < 0`, FK tidak ada, enum tak dikenal)
   → 422 dengan daftar `{table, id, message}`; seluruh batch dibatalkan.

Setelah push, server mengembalikan semua baris dengan `seq > since_seq`,
termasuk yang barusan di-push (idempotent; client menerapkan aturan LWW yang
sama). Pull dibatasi 500 baris per tabel; bila terpotong `has_more = true` dan
`seq` = seq terbesar yang dikirim, client mengulang.

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

Logika merge (aturan 1–3) ditulis sebagai fungsi murni tanpa I/O di
`src/sync/merge.rs` agar bisa di-unit-test tanpa Cloudflare.

## 6. Struktur repo

```
akhmadqasim-api/
├── Cargo.toml                 # dependensi + [lints]: clippy pedantic, unwrap dilarang di src/
├── rustfmt.toml
├── wrangler.toml              # nama worker, binding D1, route api.akhmadqasim.com
├── CLAUDE.md                  # ringkas: apa ini, perintah dev/test/lint/deploy, pointer ke rules
├── .claude/
│   ├── rules/                 # rust.md, sync.md, testing.md
│   └── skills/new-module/     # langkah menambah modul
├── docs/specs/                # spec desain
├── migrations/0001_gym.sql
├── src/
│   ├── lib.rs                 # #[event(fetch)] → router
│   ├── router.rs              # /api/health, /api/sync, /api/<modul>/…
│   ├── auth.rs                # Bearer token, perbandingan constant-time
│   ├── error.rs               # ApiError → JSON
│   ├── db.rs                  # helper D1 tipis
│   ├── sync/{mod,merge,handler}.rs
│   └── modules/
│       ├── mod.rs
│       └── gym/{mod,model,export}.rs
├── tests/api/
│   ├── main.rs, helpers.rs    # satu binary; TestApp start `wrangler dev` + D1 lokal
│   ├── auth.rs, sync.rs
│   └── gym/{mod,exercises,programs,sessions}.rs
└── .github/workflows/{ci,deploy}.yml
```

Kontrak modul: setiap modul mengekspos daftar `SyncTable` (nama tabel, kolom,
validasi, urutan FK) dan opsional route tambahan. Engine sync tidak tahu isi
modul.

## 7. Testing

- Unit test (`cargo test --lib`): aturan merge, validasi, parsing token.
- Integration test (`tests/api`): start `wrangler dev` dengan D1 lokal, uji
  lewat HTTP nyata: auth ditolak/diterima, push–pull, idempotensi (kirim dua
  kali → hasil sama), konflik LWW, soft delete, paginasi `has_more`,
  validasi 422 membatalkan batch, export.
- Setiap fitur wajib disertai test; CI merah tidak boleh merge.

## 8. CI/CD & operasional

- Secrets: `API_TOKEN` (secret Worker, `wrangler secret put`),
  `CLOUDFLARE_API_TOKEN` (GitHub Secrets, izin Workers + D1).
- `ci.yml` (PR & push `main`): `cargo fmt --check` → `cargo clippy -D warnings`
  → unit test → integration test.
- `deploy.yml` (push `main`, setelah CI hijau): `wrangler d1 migrations apply
  --remote` → `wrangler deploy`. Rollback: `wrangler rollback`.
- Backup: D1 Time Travel (30 hari) + salinan penuh di SQLite iOS.

## 9. Di luar scope (nanti)

- Dashboard di app iOS.
- Modul aksi (servers/network): perlu agen di LAN yang polling perintah;
  didesain saat modulnya dibuat.
- Cloudflare Access bila butuh auth lebih kuat.
- Multi-pengguna.
