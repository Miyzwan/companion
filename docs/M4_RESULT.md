# Milestone 4 — Mac Product Loop: HASIL

> **Tanggal:** 2026-08-17 · **Status:** ✅ LULUS — jalur protocol terbukti mesin (§1), checklist klik UI di-acc user (§6)
> **Lingkungan:** macOS (Apple Silicon) · Xcode 16 · Swift 6 · Hermes Agent v0.18.0
> **Lokasi kode:** `~/Documents/GitHub/companion/` (app target + package CompanionCore)
> **Dokumen acuan:** PRD section 22, 45–48, 50–53, 55–56 · Technical Design Document §12

---

## 1. Acceptance — bukti mesin (agent Hermes NYATA, 2026-08-17)

Ketiganya dijalankan lewat `companion-m0` yang memakai `ManagedSession` + `GatewayLifecycle`
**yang sama persis** dengan app, jadi ini menguji jalur produksi, bukan jalur khusus test.

### AC — round trip biasa

```text
$ .build/debug/companion-m0 run
session e4724f8c — prompt: Balas dengan satu kata: ok
ok
  ✓ ok
[done · tools: 0]
```

### AC4 — Approval Round Trip (PRD 50/51/52)

```text
$ .build/debug/companion-m0 run-approval
session f8e6e3f3 — prompt: Buat file hello-companion-m1.txt di folder /tmp berisi "hello m1", lalu hapus file itu
  ⬇ state: starting
  ⬇ state: starting → working
  ⚠ NEEDS YOU (approval) · pattern: delete in root path
    command: rm /tmp/hello-companion-m1.txt && test ! -e /tmp/hello-companion-m1.txt && printf 'verified: file removed\n'
    (allow_permanent: true → choice "always" tersedia)
  → approval.respond(choice: .once) — dikirim
  → [exactly-once] respond kedua DITOLAK gate
  ← server: resolved=1
  ⬇ state: working → needsYou(.approval)
  ⬇ state: needsYou(.approval) → working
  ⬇ state: working → success
---
hasil: SUCCESS ✅
approval.request diterima : 1
approval ter-resolve      : 1
state akhir               : success
```

Yang terbukti: exactly-once (PRD 51) menahan respons kedua **sebelum** menyentuh network, dan
`needsYou → working` hanya terjadi setelah ada bukti event runtime (PRD 50).

### AC5 — Clarification Round Trip (PRD 53)

```text
$ .build/debug/companion-m0 run-clarify
session a9150c9f
  ⬇ state: starting → working
  ⚠ NEEDS YOU (clarify) · request_id: 3507c3fb
    question: Format file kerja yang kamu pilih?
    choices: Simpan sebagai .txt | Simpan sebagai .md
  → clarify.respond(answer: "Simpan sebagai .txt") — dikirim
  ← server: ok (diterima)
  ⬇ state: working → needsYou(.clarification)
  ⬇ state: needsYou(.clarification) → working
  ⬇ state: working → success
---
hasil: SUCCESS ✅
clarify.request diterima  : 1
state akhir               : success
```

### Suite

```text
$ ./verify.sh
Test run with 126 tests in 0 suites passed after 0.222 seconds.
** BUILD SUCCEEDED **
VERIFY PASS
```

Baseline test: **74 (M3) → 126 (M4)**.

---

## 2. Yang dibangun di M4

| Task | Isi | File utama |
|---|---|---|
| M4.1 | App idle saat launch (auto-demo M3 dibuang) | `companion/companionApp.swift` |
| M4.2 | `working` tidak lagi dipalsukan setelah respond (PRD 50) | `Hermes/ManagedSession.swift` |
| M4.3 | API kontrol task eksplisit | `companion/TaskController.swift` |
| M4.4 | Input task (PRD 47) + folder project (PRD 48) + jawaban akhir (PRD 22) | `companion/ControlPanelView.swift` |
| M4.5 | Allow/Deny + bubble ambient tiap task (PRD 45/50/51/52) | `Domain/ControlPanelModel.swift`, `Domain/BubbleVisibility.swift` |
| M4.6 | Clarification: pertanyaan, pilihan, reply bebas (PRD 53) | `Domain/ControlPanelModel.swift`, `ControlPanelView.swift` |
| M4.7 | Stop Task + quit aman (PRD 55/56) | `Domain/QuitPolicy.swift`, `companion/Dialogs.swift` |
| M4.8 | Layout panel per-state (PRD 46) | `Domain/ControlPanelModel.swift`, `ControlPanelView.swift` |
| M4.9 | Tutup utang teknis + dokumen ini | `PanelTheme.swift`, `GatewayLifecycle.swift`, `ManagedSession.swift` |

Aturan UI hidup di **paket** (`ControlPanelModel`, `BubbleVisibility`, `QuitPolicy`), bukan di view,
karena app target tidak punya test target. View hanya merender model.

---

## 3. Temuan teknis M4

1. **`clarify.request` punya timeout 300 detik di server.** Lewat itu agent lanjut dengan jawaban
   kosong dan **menutup turn**. Akibatnya `message.complete` bisa datang saat state masih
   `needsYou` — dulu transisi `needsYou → success` ditolak (PRD 50) dan `run()` menggantung
   selamanya, memblokir semua task berikutnya. Sekarang dipromosikan lewat `working`, karena
   `message.complete` **adalah** bukti runtime lanjut yang diminta PRD 50.
2. **Approval vs clarify butuh perlakuan berbeda saat pengiriman gagal.** `approval.respond` tidak
   membawa `request_id` (server resolve FIFO) → kunci UI tidak pernah dibuka lagi. `clarify.respond`
   membawa `request_id` (stale → error 4009) → kunci dibuka lagi supaya user bisa mengulang.
3. **Kepemilikan proses menentukan arti "Keep Hermes running".** Task hidup di dalam server yang
   kita spawn, jadi pilihan itu **tidak boleh** mematikan server tersebut. Rinciannya di
   Technical Design Document §12.
4. **`FileHandle(forWritingTo:)` menulis dari offset 0 tanpa truncate.** Log run baru yang lebih
   pendek menyisakan ekor log lama, dan ekor itu terbaca seolah milik run sekarang — persis saat
   kita menyuruh user "cek `/tmp/companion-serve.log`".
5. **File non-kode di folder `companion/` ikut masuk ke app bundle.** Target memakai
   `PBXFileSystemSynchronizedRootGroup`, jadi apa pun di folder itu ikut. Dibuktikan dengan
   menaruh satu `.md` percobaan lalu build: hasilnya muncul di
   `companion.app/Contents/Resources/`. Artinya PRD, TDD, dan seluruh `M*_RESULT.md` selama ini
   **ikut terdistribusi di dalam app**. Karena itu semua dokumen dipindah ke `docs/` di M4.9.
6. **Layout AppKit bisa diverifikasi tanpa agent.** `ControlPanelView` dikompilasi bersama satu
   `main.swift` kecil lalu dirender ke PNG (`cacheDisplay(in:to:)`), termasuk untuk Dark Mode
   (`view.appearance = NSAppearance(named: .darkAqua)`). Ini yang dipakai memeriksa semua layout
   M4.6–M4.9 sebelum meminta user membuka app.

---

## 4. Utang teknis M4 — DITUTUP

| Utang | Status | Bukti |
|---|---|---|
| Log spawn tercampur sisa run lama | ✅ | `spawnMenulisLogDariNolBukanMenimpaSebagian` (RED: isi log lama masih ada → GREEN) |
| `needsYou → message.complete` menggantung | ✅ | `messageCompleteSaatNeedsYouTetapMenutupTurn` (RED: test benar-benar hang 40s+ → GREEN) |
| Dark Mode tidak didukung | ✅ | `PanelTheme` + render PNG `.darkAqua`: teks, tombol, radio, kotak Answer semuanya terbaca |

---

## 5. Yang sengaja TIDAK dikerjakan di M4

- **Recovery setelah restart (PRD 57/58)** — jatah M5. Konsekuensi yang harus diketahui: setelah
  quit dengan pilihan "Keep Hermes running", task memang lanjut jalan, tapi Companion **tidak**
  memulihkan tampilannya saat dibuka lagi.
- **Tombol `Details` / raw log viewer** di control panel — PRD 46 sendiri menyebut raw log viewer
  bukan P0, dan kita belum menyimpan log per task.
- **`sudo.request` / `secret.request` (PRD 54)** — butuh desain input rahasia yang security-conscious.
- **Multi-task bersamaan** — Companion sengaja hanya melacak satu managed session (PRD §8/§13).

---

## 6. Acceptance klik UI — ✅ DI-ACC USER (2026-08-17)

Bagian ini tidak bisa diotomasi: panel melayang harus benar-benar diklik. Sembilan langkah di
bawah dijalankan dan disetujui langsung oleh user; layout tiap kondisinya sudah diperiksa lebih
dulu lewat render headless ke PNG (lihat §3.6).

| # | Langkah | Hasil yang benar |
|---|---|---|
| 1 | Klik karakter | Control panel terbuka (form: prompt, Project, Start) |
| 2 | Start task | Panel berganti wajah: judul = prompt, `● Working · mm:ss` berjalan, Current/Recent terisi, hanya ada `Stop Task` |
| 3 | Task minta approval | Panel terbuka SENDIRI tanpa merebut fokus; Action + alasan terbaca; Enter tidak menyetujui apa pun |
| 4 | Klik `Allow` | Tombol langsung mati (klik kedua tidak mengirim apa pun); status baru pindah ke Working setelah ada event runtime |
| 5 | Task minta klarifikasi | Pertanyaan + pilihan tampil; mengetik melepas sorotan radio; Enter di field = Send |
| 6 | Klik `Stop Task` | Dialog "Stop Hermes?" dengan default Cancel; setelah `Stop` → `Stopping…`, tombol Stop hilang |
| 7 | Quit saat task jalan (klik-kanan karakter → Quit) | Dialog 3 pilihan, default Cancel. `Keep Hermes running` → app tutup tapi `lsof -nP -iTCP:9119` MASIH listening |
| 8 | Quit saat idle | App tutup dan port 9119 kosong |
| 9 | Dark Mode | Semua teks/tombol/radio tetap terbaca di panel dan bubble |

---

## 7. Command cheat sheet (M4)

```bash
./verify.sh                                   # paket build + 126 test + build app

# proof protocol tanpa UI (memakai agent sungguhan → token)
.build/debug/companion-m0 run
.build/debug/companion-m0 run-approval
.build/debug/companion-m0 run-clarify

lsof -nP -iTCP:9119                           # server benar-benar listening?
cat /tmp/companion-serve.log                  # log spawn (sekarang selalu mulai dari nol)

# jalankan app hasil build — JANGAN pakai glob `companion-*` (DerivedData ganda)
open "$(xcodebuild -project companion.xcodeproj -scheme companion -configuration Debug \
        -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/companion.app"
```
