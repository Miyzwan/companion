# Milestone 0 — Gateway Proof: HASIL

> **Tanggal:** 2026-08-12 · **Status:** ✅ LULUS — Milestone 0 selesai
> **Lingkungan:** macOS (Apple Silicon) · Hermes Agent v0.18.0 (2026.7.1) · Swift DEV snapshot 2026-07-11-a (toolchain test) / Xcode 6.3.3 · Swift tools-version 6.2
> **Lokasi kode:** `~/Documents/GitHub/companion/` (Xcode app `Companion` + Swift Package `CompanionCore`)

---

## 1. Acceptance criteria (PRD section 77) — semua TERBUKTI

| PRD | Bukti | Command |
|-----|-------|---------|
| Hermes detection | `Hermes v0.18.0 — Supported` | `companion-m0 doctor` |
| Hermes version detection | parse `v0.18.0` dari `hermes --version`; range check | `companion-m0 doctor` + unit test `HermesDetectorTests` |
| connect | WS handshake sukses dengan `?token=`; `gateway.ready` diterima | `companion-m0 ws-spike` |
| create session | `session 7813af87` (hex 8, valid) | `companion-m0 run "…"` |
| submit prompt | delta stream "ok" mengalir setelah submit | `companion-m0 run "Balas dengan satu kata: ok"` |
| receive message events | `message.delta` + `message.complete` teramati (raw: 14 delta frames) | frames log `/tmp/companion-m0-frames.jsonl` |
| receive tool events | `tool.start` + `tool.complete` + `tool.generating` (write_file, terminal) | `companion-m0 run "Berapa baris …"` → `[done · tools: 1]` |
| completion | `[done]` setelah `message.complete` | `companion-m0 run` |

Suite test akhir: **25/25 passed** (`swift test`).

---

## 2. Hasil spike & temuan teknis (detail di Tech Design section 2.2–2.8)

1. **Auth WS loopback WAJIB `?token=`** — handshake tanpa token → HTTP 403; token dibanding constant-time dengan `_SESSION_TOKEN` server. Token di-inject via env `HERMES_DASHBOARD_SESSION_TOKEN` saat spawn.
2. **Event pertama setelah connect = `gateway.ready`** (payload skin/branding, TANPA session_id) → `EventParams.session_id` dibuat optional.
3. **Boot `hermes serve --skip-build`: ~1.0 detik.**
4. **`Process.environment` = REPLACE env** (bukan merge) — child kehilangan PATH → mati. Sudah diperbaiki (merge dari `ProcessInfo`).
5. **approval.request TERAMATI NYATA** — `rm /tmp/...` kena pola "delete in root path"; tanpa respons, agent menunggu selamanya. Ini bahan utama M1 (approval flow + `approval.respond` + exactly-once).
6. **Event high-frequency yang harus dikoalesing di UI nanti**: `reasoning.delta` (216 frame untuk 1 task!), `message.delta`.
7. **Prompt.submit saat session sibuk tidak ditolak** — di-queue + interrupt turn berjalan (perilaku `_handle_busy_submit` di gateway).
8. `hermes serve --status` bisa stale; "proses dashboard jalan ≠ port listening" — selalu probe koneksi nyata (D2 attach-first).

---

## 3. Fixture protocol (contract tests — PRD section 12)

`Tests/CompanionCoreTests/Fixtures/` + `FixtureContractTests.swift` (4 test):

- `tool-start-write_file.jsonl` — `{tool_id, name, context}` (start TIDAK bawa args)
- `tool-complete-write_file.jsonl` — `{tool_id, name, args, duration_s, result}`
- `tool-generating-write_file.jsonl` — `{name}`
- `approval-request-delete-root.jsonl` — `{command, pattern_key, pattern_keys[], description, allow_permanent}` (emas buat M1)

Adapter contract version: **1** (terikat ke Hermes v0.18.0 / 2026.7.1).

---

## 4. Komponen yang jadi (package `CompanionCore`)

| Komponen | File | Status |
|----------|------|--------|
| JSON-RPC framing (request/response/event/value) | `RPC/JSONRPC.swift` | ✅ |
| JSON-RPC client over WS (id match, receive loop, raw hook) | `RPC/JSONRPCClient.swift` | ✅ |
| Deteksi Hermes + versi + compat gate | `Hermes/HermesDetector.swift` | ✅ |
| Lifecycle server (attach/spawn/stop/wait, token) | `Hermes/GatewayLifecycle.swift` | ✅ |
| Typed adapter (session.create, prompt.submit) | `Hermes/HermesAdapter.swift` | ✅ |
| CLI proof | `companion-m0` (doctor, serve-*, ws-spike, run) | ✅ |
| Contract tests + fixtures | `Tests/CompanionCoreTests/` | ✅ 25 test |

---

## 5. Yang sudah diketahui & sengaja ditunda

- **Approval flow** → Milestone 1 (sudah ada fixture nyata + jalur `approval.respond` di gateway).
- **Clarification flow** → Milestone 1.
- **Reconnect/recovery penuh** → Milestone 5 (M0: reconnect dasar + log; state tidak dianggap benar setelah disconnect).
- **Multi-task** → Product 0.2 (model Task sudah collection-friendly).
- **UI (NSPanel, maskot placeholder)** → Milestone 2 spike.

---

## 6. Command cheat sheet

```bash
companion-m0 doctor              # deteksi + versi + compat
companion-m0 serve-status        # probe port 9119
companion-m0 serve-spawn         # spawn hermes serve (token di-inject)
companion-m0 serve-stop          # stop server milik companion (D2)
companion-m0 ws-spike            # observasi frame mentah WS
companion-m0 run "<prompt>"      # round trip penuh: session → prompt → events → done
```

---

*Dokumen ini adalah bukti Milestone 0. Lanjut ke Milestone 1 (Human-in-the-Loop Proof) setelah commit + review.*
