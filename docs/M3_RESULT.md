# Milestone 3 — Floating Companion: HASIL

> **Tanggal:** 2026-08-12 · **Status:** ✅ LULUS — State Hermes + Floating UI tergabung
> **Lingkungan:** macOS (Apple Silicon) · Xcode 16 · Swift 6 · Hermes Agent v0.18.0
> **Lokasi kode:** `~/Documents/GitHub/companion/` (app target + package CompanionCore)
> **Dokumen acuan:** PRD section 80 (Engineering Milestone 3) + section 41 (Character Asset Strategy)

---

## 1. Acceptance (PRD section 80) — TERBUKTI

```text
[character]          [character]
● Working            ⚠ Needs You
Running tests…       [request]
```

Bukti: demo task Hermes NYATA dijalankan dari floating UI (app launch → spawn `hermes serve` → managed session → prompt `rm /tmp/...` → approval.request → auto-approve → selesai). Siklus state yang tampil di bubble karakter (diverifikasi user):

```text
◌ Starting…
● Working                 (status.activity ikut tampil di baris kedua)
⚠ Needs your approval     (baris kedua: perintah rm /tmp/hello-companion-m3.txt …)
● Working
✓ Done                    ← posisi akhir saat user konfirmasi
```

Bukti mesin: app relaunch → `hermes serve` ke-spawn (HERMES_BACKEND_READY) → file `/tmp/hello-companion-m3.txt` dibuat lalu DIHAPUS (jalur approval nyata kena, auto-approve `.once`, exactly-once gate aktif dari M1).

Suite: **74/74 test** + app build (`./verify.sh`).

---

## 2. Komponen baru

| Komponen | File | Peran |
|----------|------|-------|
| `ManagedSession` | `CompanionCore/Hermes/ManagedSession.swift` | Loop event→state REUSABLE (ekstraksi ProofRunner M1): drain AsyncStream, TaskStateMachine + ApprovalGate, callback `onStateChange`/`onNeedsYouRequest`/`onActivity`/`onFinished`, auto-respond opsional |
| `GatewayLifecycle.attachOrSpawn` | `CompanionCore/Hermes/GatewayLifecycle.swift` | Satu sumber kebenaran attach-first/spawn-second (D2) — CLI & app pakai sama (ProofRunner di-refactor ke sana, E2E ulang: SUCCESS) |
| `setEventHandler` | `RPC/JSONRPCClient.swift` | Handler event dinamis (wiring ManagedSession) |
| `TaskState+Display` | `Domain/TaskState+Display.swift` | `glyph` (◉●⚠✓!○) + `statusLine` + `decisionText` — murni, 4 test |
| `TaskController` | app `companion/TaskController.swift` | @MainActor: lifecycle gateway + session + ManagedSession → bubble text |
| Bubble multi-baris + bind | `companion/FloatingPanel.swift` | Bubble 2 baris (state + aktivitas/keputusan), auto-buka sekali saat state ≠ idle, ukuran mengikuti teks |

---

## 3. Temuan teknis (dipakai M4)

1. **Managed Session ≠ mengikuti sesi Terminal user.** PRD §8/§13: Companion hanya men-track session yang DIA manage. Sesi Hermes interaktif yang kebetulan jalan di Terminal lain bukan source of truth — sengaja diabaikan. User diklarifikasi langsung (ekspektasi "karakter ikutin session saya" → benar: session yang dikasih lewat Companion, mulai M4).
2. **Ekstraksi ManagedSession** dari CLI proof → class reusable: state machine + ApprovalGate + event drain dalam satu tempat. CLI (run-approval) tetap jalan (E2E SUCCESS pasca-refactor) dan app memakai loop yang sama → tidak ada dua implementasi state logic.
3. **Auto-demo on launch** (spike): app launch langsung spawn hermes + jalanin agent nyata (makan token). Untuk M4 ini diganti: user ketik task → baru spawn. Flag keputusan ada di AppDelegate `startDemoTask()`.
4. **Threading**: callback ManagedSession (@Sendable) → `Task { @MainActor in … }` di TaskController; panel menerima bubble text via closure. Tidak ada race (semua UI state di main actor).
5. Bubble 2 baris: `glyph + statusLine` di baris 1, `decisionText` (perintah/pertanyaan) ATAU activity saat Working di baris 2 — "Know what Hermes is doing" tanpa raw logs.

---

## 4. Yang sengaja ditunda (ke M4 — Mac Product Loop, PRD 81)

- UI input task (ketik prompt ke companion) + tombol Start/Stop.
- Keputusan approval/clarify DARI UI (Allow/Deny + pilihan clarify) — sekarang auto-respond `.once` (spike); `ManagedSession.respondApproval/respondClarify` sudah siap dipanggil UI.
- Per-state asset (idle/working/needsYou/success → gambar beda) — `CharacterRenderer` sudah siap.
- Activity coalescing (reasoning.delta 216 frame — jangan flood bubble).
- App jadi idle di launch (tanpa auto-demo) — bagian dari M4 flow.

---

## 5. Command cheat sheet (M3)

```bash
./verify.sh                              # 74 test + app build (kanonik)
.build/debug/companion-m0 run-approval   # CLI proof (tetap jalan pasca-refactor)
open ~/Library/Developer/Xcode/DerivedData/companion-*/Build/Products/Debug/companion.app
# app launch → spawn hermes serve → demo task → bubble: Starting→Working→NeedsYou→Working→Done
```

---

*Dokumen ini adalah bukti Milestone 3. Lanjut ke Milestone 4 (Mac Product Loop — start task dari UI, approve/clarify dari UI, PRD section 81) setelah commit + review.*
