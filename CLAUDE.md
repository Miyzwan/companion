# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Dokumen ini, komentar kode, dan dokumen milestone di repo ini memakai **Bahasa Indonesia**. Ikuti gaya itu saat menambah komentar/dokumen. Subject commit boleh Inggris (conventional commits), sesuai riwayat.

## Perintah

Verifikasi kanonik (paket build + test + build app) — jalankan dari root repo:

```bash
./verify.sh
```

`swift test` **wajib** memakai toolchain DEV snapshot; Swift Testing tidak tersedia di `/usr/bin/swift` stock:

```bash
TOOL=~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a.xctoolchain/usr/bin/swift
cd Packages/CompanionCore
$TOOL build
$TOOL test
$TOOL test --filter startSubmitsPromptAndAutoApprovalIsDisabledByDefault   # satu test
```

Build app — **wajib `-scheme`, bukan `-target`** (`-target` tidak me-resolve paket SPM: "Unable to resolve module dependency: CompanionCore"):

```bash
xcodebuild -project companion.xcodeproj -scheme companion -configuration Debug build
# Jalankan app hasil build — JANGAN pakai glob `companion-*`: di mesin ini ada
# LEBIH DARI SATU folder DerivedData `companion-…` dan glob bisa memilih build
# basi (pernah menyebabkan salah verifikasi manual).
open "$(xcodebuild -project companion.xcodeproj -scheme companion -configuration Debug \
        -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/companion.app"
```

CLI proof driver (`companion-m0`) — jalur tercepat menguji protocol tanpa UI:

```bash
.build/debug/companion-m0 doctor          # deteksi hermes + versi + compat gate
.build/debug/companion-m0 serve-status    # probe 127.0.0.1:9119
.build/debug/companion-m0 serve-spawn     # spawn `hermes serve --skip-build`
.build/debug/companion-m0 serve-stop      # stop HANYA server milik companion (via PID file)
.build/debug/companion-m0 ws-spike        # dump frame WS mentah
.build/debug/companion-m0 run "<prompt>"          # round trip penuh
.build/debug/companion-m0 run-approval "<prompt>" # pemicu approval.request
.build/debug/companion-m0 run-clarify "<prompt>"  # pemicu clarify.request
lsof -nP -iTCP:9119                       # cek server benar-benar listening
```

Catatan: `verify.sh` menulis `Companion.xcodeproj` (huruf besar) padahal direktori aslinya `companion.xcodeproj` — jalan hanya karena filesystem macOS case-insensitive.

## Arsitektur

Dua unit build dalam satu repo:

```text
companion.xcodeproj  → target app `companion/`  (Swift 5 mode, sandbox OFF, hardened runtime ON, .accessory app)
Packages/CompanionCore → local SPM package     (tools 6.2 → Swift 6 strict concurrency)
                          ├── library CompanionCore  (semua logic)
                          ├── executable companion-m0 (CLI proof)
                          └── CompanionCoreTests      (Swift Testing + fixture kontrak)
```

Aliran data (PRD §16):

```text
hermes serve (JSON-RPC/WS :9119)
   → JSONRPCClient           RPC/JSONRPCClient.swift    · framing, id-match, receive loop
   → HermesAdapter           Hermes/HermesAdapter*.swift · SATU-SATUNYA yang tahu nama method
   → EventDecoder            Hermes/EventDecoder.swift   · envelope → TaskEvent (domain)
   → TaskStateMachine        Domain/TaskState.swift      · transisi legal + priority
   → ManagedSession          Hermes/ManagedSession.swift · loop event→state, dipakai app DAN CLI
   → TaskController          companion/TaskController.swift · @MainActor bridge
   → FloatingPanelController companion/FloatingPanel.swift  · NSPanel + karakter + bubble
```

### Aturan yang tidak boleh dilanggar

1. **D5 — isolasi protocol.** String method/event Hermes (`"prompt.submit"`, `"approval.request"`, …) hanya boleh muncul di `HermesAdapter*.swift` dan `EventDecoder.swift`. Domain dan UI tidak pernah melihatnya.
2. **D2 — attach-first, spawn-second.** `GatewayLifecycle.attachOrSpawn` adalah satu-satunya sumber kebenaran (dipakai app + CLI). JANGAN pernah `hermes serve --stop` (mematikan SEMUA server termasuk milik Hermes Desktop) dan jangan mematikan server yang bukan kita spawn — hanya `stopPID` untuk PID milik sendiri.
3. **Auth WS wajib token.** Handshake tanpa `?token=` → HTTP 403. Token di-generate saat spawn dan diinject via env `HERMES_DASHBOARD_SESSION_TOKEN`, lalu dipakai di URL. Konsekuensi: server asing tidak bisa di-attach — `attachOrSpawn` mengembalikan `(nil, nil)` yang artinya "server UP tapi bukan milik kita".
4. **Exactly-once approval ada di client.** `approval.request` TIDAK membawa `request_id` dan server me-resolve FIFO paling tua → kirim dua kali berisiko meresolusi approval BARU. `ApprovalGate` mengunci sampai ada request baru; jangan bypass, jangan tambahkan id buatan sendiri. `clarify.request` punya `request_id` (stale → error 4009, aman).
5. **`needsYou → success` ILEGAL** (PRD 50). Setelah user menjawab, state hanya boleh kembali `working` setelah ada bukti event runtime — itulah guna flag `awaitingResume` di `ManagedSession`. Jangan memalsukan `working` di sisi UI. Sebaliknya `starting → needsYou` LEGAL (agent bisa minta keputusan di awal turn).
6. **Decoder toleran.** Event tak dikenal → `nil`, jangan crash (PRD 36). `message.complete` bisa datang TANPA `text` — tetap harus di-decode, kalau di-drop run tidak akan pernah tahu turn selesai.
7. **`Process.environment` me-REPLACE seluruh env, bukan merge.** Selalu mulai dari `ProcessInfo.processInfo.environment`, kalau tidak child kehilangan PATH dan mati.
8. **Managed session saja.** Companion hanya melacak session yang ia buat sendiri; sesi Hermes interaktif di Terminal lain sengaja diabaikan (PRD §8/§13).

### Catatan runtime & UI

- Spawn selalu `hermes serve --skip-build --host 127.0.0.1 --port 9119` (tanpa `--skip-build` server build web UI dulu, butuh npm). Boot ±1 detik.
- File koordinasi dipakai bersama CLI & app supaya attach silang bekerja: `/tmp/companion-serve.pid`, `.token`, `.log`.
- Event frekuensi tinggi: `reasoning.delta` (216 frame untuk satu task) dan `message.delta` — coalesce sebelum menyentuh UI.
- Click-through panel memakai `PassThroughContainer.hitTest → nil`, **bukan** `ignoresMouseEvents` (itu mematikan tracking area juga).
- `NSApp.setActivationPolicy(.accessory)` + `.nonactivatingPanel` = tidak pernah mencuri fokus; konsekuensinya Cmd+Q tidak berfungsi → Quit lewat menu klik-kanan karakter.
- Layout panel diturunkan dari satu konstanta `characterSize` di `FloatingPanel.swift`.
- Versi Hermes di-pin: `HermesDetector.defaultSupportedRange` = 0.18.0…0.18.999.

## Dokumen sumber kebenaran

- `companion/Product Requirements Document v3.md` — **FROZEN**. Komentar kode merujuknya lewat nomor section (`// PRD 51`); pertahankan kebiasaan itu saat menambah kode.
- `companion/Technical Design Document.md` — **dokumen hidup**. Fakta protocol hasil spike dan keputusan arsitektur baru di-append ke sini beserta tanggal, bukan hanya diceritakan di chat.
- `companion/M0_RESULT.md` … `M3_RESULT.md` — bukti acceptance per milestone (temuan teknis + command cheat sheet).
- `Tests/CompanionCoreTests/Fixtures/*.jsonl` — frame JSON-RPC NYATA hasil rekaman; `FixtureContractTests.swift` yang menangkap duluan kalau bentuk payload Hermes berubah. Tambahkan fixture baru saat mengamati event baru.

## Cara kerja (workflow)

Pekerjaan dipecah per **milestone** (M0 Gateway Proof → M1 Human-in-the-Loop → M2 Window Spike → M3 Floating Companion → M4 Mac Product Loop), tiap milestone dipecah lagi jadi task kecil:

1. Kerjakan **satu task**, dan hanya setelah user memberi instruksi eksplisit — jangan lanjut sendiri ke task berikutnya.
2. TDD ketat: tulis satu test yang GAGAL dulu (RED) → implementasi terkecil (GREEN) → jalankan test fokus, lalu suite penuh.
3. Jalankan `./verify.sh` kalau perubahan menyentuh integrasi app↔paket.
4. Commit dengan conventional commit (`feat:`, `fix:`, `chore:`, `test:`, `docs:`).
5. Laporkan file, test, commit, dan hasil verifikasi manual.

Di akhir milestone: tulis `companion/M<N>_RESULT.md` berisi bukti acceptance (output command nyata), temuan teknis, dan hal yang sengaja ditunda.

## Status

**M0–M3 LULUS. M4 (Mac Product Loop) sedang berjalan.**

| Task | Status | Isi |
|---|---|---|
| M4.1 | ✅ | app idle saat launch (auto-demo M3 dibuang) |
| M4.2 | ✅ | `ManagedSession` tidak memalsukan `working` setelah respond (PRD 50) |
| M4.3 | ✅ | `TaskController` mengekspos `start`/`stop`/`respondApproval`/`respondClarify` |
| M4.4 | ✅ | control panel: input task (PRD 47) + folder project (PRD 48) + jawaban akhir (PRD 22) |
| M4.5 | ✅ | kontrol approval Allow/Deny (PRD 50/51/52) + bubble ambient tiap task (PRD 45) |
| M4.6 | ⬜ | kontrol clarification (PRD 53) |
| M4.7 | ⬜ | Stop Task + quit aman (PRD 55/56) |
| M4.8 | ⬜ | layout panel per-state (PRD 46) |
| M4.9 | ⬜ | acceptance E2E + `companion/M4_RESULT.md` |

Baseline test: **102** (paket). Verifikasi manual E2E memakai agent Hermes sungguhan → menghabiskan token, minta konfirmasi user dulu.

### Utang teknis yang sudah diketahui (tutup di M4.9)

- `GatewayLifecycle.spawnServer` membuka log via `FileHandle(forWritingTo:)` → menulis dari offset 0 tanpa truncate, isi log bisa tercampur sisa run lama.
- Jalur anomali `needsYou → message.complete` masih bisa menggantung: `needsYou → success` ilegal (PRD 50) jadi transisi ditolak dan loop `run()` tidak pernah break. Jalur `starting → message.complete` sudah ditutup (promosi lewat `working`); yang ini menyentuh aturan PRD 50 jadi sengaja belum diubah.
- Dark Mode belum didukung: control panel + bubble dikunci `NSAppearance(named: .aqua)` karena latarnya digambar terang.
