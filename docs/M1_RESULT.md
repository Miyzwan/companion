# Milestone 1 — Human-in-the-Loop Proof: HASIL

> **Tanggal:** 2026-08-12 · **Status:** ✅ LULUS — Human-in-the-Loop Proof selesai
> **Lingkungan:** macOS (Apple Silicon) · Hermes Agent v0.18.0 (2026.7.1) · Swift toolchain DEV snapshot 2026-07-11-a (test) · Swift tools-version 6.2
> **Lokasi kode:** `~/Documents/GitHub/companion/` (Xcode app `Companion` + Swift Package `CompanionCore`)
> **Dokumen acuan:** PRD v3 section 78 (Engineering Milestone 1) · Tech Design section 11 (fakta protocol M1)

---

## 1. Acceptance criteria (PRD section 78) — KEDUANYA TERBUKTI

### a) Approval round trip ✅
```text
Working → approval.request → Needs You → approval.respond → Working → Success
```
Bukti E2E (session `2945c012`), jalur state machine nyata:
```text
⬇ starting → working
⚠ NEEDS YOU (approval) · pattern: delete in root path
    command: rm /private/tmp/hello-companion-m1.txt && echo "deleted"; ...
→ approval.respond(choice: .once) — dikirim
→ [exactly-once] respond kedua DITOLAK gate
← server: resolved=1
⬇ working → needsYou(.approval)
⬇ needsYou(.approval) → working
⬇ working → success
hasil: SUCCESS ✅ · approval.request diterima: 1 · ter-resolve: 1
```

### b) Clarify round trip ✅
```text
clarify.request → clarify.respond → Working → Success
```
Bukti E2E (session `6c5f0f05`):
```text
⚠ NEEDS YOU (clarify) · request_id: 8f1277ba
    question: Mau disimpan sebagai format apa?
    choices: Simpan sebagai .txt | Simpan sebagai .md
→ clarify.respond(answer: "Simpan sebagai .txt") — dikirim
← server: ok (diterima)   [bukan 4009 → request_id valid]
⬇ working → needsYou(.clarification)
⬇ needsYou(.clarification) → working
⬇ working → success
hasil: SUCCESS ✅ · clarify.request diterima: 1 · state akhir: success
```
Catatan: run pertama clarify (`ca89f7b6`) membuktikan **multi-ask** — agent mengajukan 2 pertanyaan beruntun, respond pertama & kedua sama-sama diterima (`ok`), tanpa 4009. Frame nyata kedua pertanyaan tersimpan sebagai fixture.

Suite test akhir: **59/59 passed** (`swift test`).

---

## 2. Fakta protocol yang DI-VERIFIKASI lewat source gateway (masuk Tech Design §11)

| Item | Hasil verifikasi |
|------|------------------|
| `approval.request` payload | `{command, pattern_key, pattern_keys[], description, allow_permanent}` — **TIDAK bawa request_id**; di-key per-session, FIFO oldest-first |
| `approval.respond` params | `{session_id, choice, all?}` → `{resolved: Int}`. `choice` ∈ `"once"`/`"session"`/`"always"`/`"deny"` (desktop pakai `once` & `deny`). `"always"` hanya bermakna saat `allow_permanent==true` |
| `clarify.request` payload | `{request_id, question, choices}` — `request_id` = `uuid4().hex[:8]` di-inject oleh `_block` (server.py:1925) |
| `clarify.respond` params | `{request_id, answer}` → `{status:"ok"}`; request_id stale → error `4009` (idempotensi natural) |
| Implikasi exactly-once | Approval TIDAK punya request_id → **PRD 51 WAJIB di sisi client** (ApprovalGate). Clarify aman natural (4009). |

---

## 3. Komponen baru (package `CompanionCore`)

| Komponen | File | Status |
|----------|------|--------|
| Task State Machine (PRD 25-34) + priority (35) | `Domain/TaskState.swift` | ✅ 12 test |
| Domain events + `ApprovalRequest`/`ClarifyRequest` | `Domain/TaskEvent.swift` | ✅ |
| `EventDecoder` envelope → `TaskEvent` (unknown → nil, PRD 36) | `Hermes/EventDecoder.swift` | ✅ 8 test |
| `HermesAdapter` respondApproval/respondClarify/interrupt + param-builder murni | `Hermes/HermesAdapter+Respond.swift` | ✅ 7 test |
| `ApprovalGate` — exactly-once (PRD 51) + stale (PRD 52) | `Domain/ApprovalGate.swift` | ✅ 7 test |
| CLI proof `run-approval` / `run-clarify` (AsyncStream + ProofState) | `Sources/companion-m0/ProofRunner.swift` | ✅ E2E |
| Fixture clarify.request NYATA | `Fixtures/clarify-request-choices.jsonl` | ✅ contract test |

File modif: `RPC/JSONRPC.swift` (extension accessor JSONValue), `companion-m0/main.swift` (subcommand baru).

---

## 4. Temuan teknis baru (M1)

1. **`approval.respond` tidak punya request_id** — jadi exactly-once sepenuhnya tanggung jawab client. Kirim dua kali berisiko men-resolve approval BARU yang masuk berikutnya (FIFO), bukan cuma no-op. `ApprovalGate` mengunci respons sampai ada `approval.request` baru — terbukti di E2E (`respond kedua DITOLAK gate`, `resolved=1` bukan 2).
2. **Clarify multi-ask nyata**: agent bisa mengajukan >1 `clarify.request` beruntun; tiap request_id unik, semua diterima. Gate clarify per-request_id.
3. **Strict concurrency Swift 6**: `Task {}` di dalam event callback + var mutable local → data race. Solusi: (a) `AsyncStream<TaskEvent>` (onEvent non-blocking, satu async loop drain), (b) mutable state dibungkus class `@unchecked Sendable` (`ProofState`).
4. **Makro `#expect` + member mutating** (Swift Testing) memunculkan "cannot use mutating member on immutable '$0'" — solusi: tangkap hasil `.transition()`/`.respond()` ke `let` lokal, lalu `#expect(let)`.
5. Trigger approval nyata: perintah yang kena pola **"delete in root path"** (contoh `rm /tmp/...`) → `allow_permanent=true`. Trigger clarify nyata: prompt yang menyuruh agent pakai **tool clarify sekali** lalu lanjut.

---

## 5. Yang sudah diketahui & sengaja ditunda

- **Interrupt/Stop task** (`session.interrupt`) sudah ada di adapter tapi belum dipakai di proof — masuk Milestone 4 (Mac Product Loop) / diuji saat verify stop.
- **Reconnect/recovery penuh** → Milestone 5 (M1: state dianggap invalid setelah disconnect).
- **UI (NSPanel, floating companion, Allow/Deny interface)** → Milestone 2 spike.
- **`choice` lain** (`session`, `always`) dan `resolveAll` sudah didukung API, belum ada E2E dedicated — dipakai nanti di UI.
- TaskState machine cakup handling, peristiwa `sudo.request`/`secret.request` mengenal `NeedsYouCase.sudo/.secret` di domain tapi belum ada respond method (secret security, PRD 54 — M5).

---

## 6. Command cheat sheet (M1)

```bash
swift test                                              # 59/59 unit + contract
.build/debug/companion-m0 run-approval                  # proof approval round trip
.build/debug/companion-m0 run-approval "<prompt>"       # prompt custom pemantik rm /tmp
.build/debug/companion-m0 run-clarify                   # proof clarify round trip / 1 nanya
.build/debug/companion-m0 run-clarify "<prompt>"        # prompt custom pemantik clarify
.build/debug/companion-m0 doctor                        # detect + compat (M0)
```

Catatan: `swift test` WAJIB pakai toolchain snapshot (Testing framework tidak ada di `/usr/bin/swift` stock standar):
```bash
~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a.xctoolchain/usr/bin/swift test
```

---

*Dokumen ini adalah bukti Milestone 1. Lanjut ke Milestone 2 (macOS Window Spike — transparent/draggable/click-through panel, PRD section 79) setelah commit + review.*