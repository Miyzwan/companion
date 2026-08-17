# Technical Design Document — AI Agent Companion

> **Version:** 0.1 · **Scope:** Milestone 0 — Gateway Proof (Product 0.1) · **Status:** Draft untuk eksekusi
> **Canonical location:** `~/Documents/hermesproject/companion/`
> **Induk dokumen:** `Product Requirements Document v3.md` (Revisi 1.3, FROZEN) — dokumen ini menjawab pertanyaan teknis di section 93 PRD dan memecah Milestone 0 jadi task eksekusi.
> **Terminologi:** PRD memakai "TDD" dengan dua makna. Resolusi: dokumen ini = **Tech Design**; "TDD" dalam konteks kode = **Test-Driven Development** (red-green-refactor). Mulai sekarang dua istilah dipakai konsisten begitu.

---

## 1. Tujuan dokumen ini

1. Mencatat **fakta protocol yang sudah diverifikasi** di instalasi lokal (bukan asumsi) — jadi acuan tunggal saat coding.
2. Menjawab pertanyaan arsitektur di PRD section 93 dengan **keputusan (D1–D7)**, bukan spekulasi.
3. Memecah **Milestone 0 (Gateway Proof)** jadi task TDD kecil yang bisa dieksekusi langkah demi langkah + perintah verifikasi.

Milestone 0 sukses saat (PRD section 77):

```text
✓ Hermes detection
✓ Hermes version detection
✓ connect
✓ create session
✓ submit prompt
✓ receive message events
✓ receive tool events
✓ completion
```

---

## 2. Fakta protocol terverifikasi (2026-08-11, instalasi lokal)

Semua fakta di bawah dicek langsung di mesin user (bukan tebakan). Ini contract yang dipakai M0.

### 2.1 Versi & lokasi

```text
Hermes Agent v0.18.0 (2026.7.1) · upstream 370a489f
Binary:  ~/.local/bin/hermes  (wrapper bash → ~/.hermes/hermes-agent/venv/bin/hermes)
Source:  ~/.hermes/hermes-agent/  (tui_gateway/server.py, transport.py, ws.py)
```

### 2.2 Dua transport

| Transport | Cara pakai | Catatan |
|-----------|-----------|---------|
| **stdio** | JSON frame per baris di stdout; dipakai TUI (Ink/Node) via `tui_gateway.entry` | Perlu launch unbuffered (`-u`/`PYTHONUNBUFFERED=1`); entry point ini internal TUI |
| **WebSocket** | `hermes serve` → `ws://127.0.0.1:9119/api/ws` (default) | Headless backend resmi: "the JSON-RPC/WebSocket gateway the desktop app and remote clients connect to" |

**Keputusan D1 — transport M0: WebSocket ke `hermes serve`.**
Alasan: (a) `hermes serve` adalah surface resmi yang didokumentasikan untuk external clients; (b) Swift punya `URLSessionWebSocketTask` native, tanpa dependency; (c) server menangani konteks koneksi per-session (transport routing di `write_json`); (d) stdio butuh spawn gateway internal TUI — rapuh dan bukan surface publik. stdio dicatat sebagai fallback diagnostik, bukan jalur utama.

**Auth WS — DIVERIFIKASI (spike T0.5, 2026-08-12):**
- Handshake TANPA kredensial → **HTTP 403**.
- Kredensial = query param `?token=<value>`, dibanding constant-time dengan `_SESSION_TOKEN` server (`web_server.py:12751-12756`, `_ws_auth_reason`).
- `_SESSION_TOKEN` dibaca dari env `HERMES_DASHBOARD_SESSION_TOKEN` (`web_server.py:269`); kalau tidak diset, server generate random sendiri (kita tidak tahu).
- **Implikasi arsitektur:** saat spawn, Companion WAJIB generate token + inject via env `HERMES_DASHBOARD_SESSION_TOKEN`, lalu pakai token yang sama di URL WS. Attach ke server asing = tidak bisa (token tidak diketahui) → M0: attach hanya untuk server yang kita spawn sendiri (PID+token file).
- Catatan: mode gated (public bind) memakai `?ticket=` single-use / `?internal=` — di luar scope M0 (kita selalu bind loopback).

### 2.3 Framing JSON-RPC 2.0 (diverifikasi di `server.py`)

```text
Request : {"jsonrpc":"2.0","id":<int>,"method":"session.create","params":{...}}
Response: {"jsonrpc":"2.0","id":<int>,"result":{...}}
Error   : {"jsonrpc":"2.0","id":<int>,"error":{"code":<int>,"message":"..."}}
Event   : {"jsonrpc":"2.0","method":"event","params":{"type":"<event>","session_id":"<sid>","payload":{...}}}
```

- `id` wajib angka; response mencocokkan `id` request.
- Event TIDAK punya `id` — identifikasi lewat `params.type` + `params.session_id`.
- **`session_id` di params bersifat OPTIONAL** — frame `gateway.ready` tidak membawa `session_id` (diverifikasi spike T0.5); event session-scoped membawanya. Decoder wajib toleran.
- Event dengan `session_id` di-routing ke transport pemilik session (bukan broadcast) — jadi client wajib menyimpan `session_id` hasil `session.create` dan mem-filter event.

### 2.4 Katalog event (diverifikasi di kode)

| Event (`params.type`) | Payload penting | Makna |
|-----------------------|-----------------|-------|
| `gateway.ready` | `{skin, branding}` — TANPA session_id (diverifikasi spike T0.5) | Event PERTAMA setelah connect; siap menerima request |
| `status.update` | `{kind, text}` — kind antara lain `ready`, `status`, `lifecycle`, `compacting` | Status tekstual; `ready` = agent siap |
| `message.start` | — | Turn mulai |
| `message.delta` | `{text?}` | Streaming token (high-frequency — perlu coalescing) |
| `message.complete` | `{text, ...}` | Turn selesai; kandidat pembawa durasi/usage (verifikasi di spike) |
| `tool.start` | `{tool_id, name, args}` | Tool mulai (sumber activity) |
| `tool.started` / `tool.generating` | varian lifecycle tool | Sub-state tool |
| `tool.complete` | `{tool_id, name, args, result?, duration_s?}` | Tool selesai |
| `approval.request` | `{command (sudah di-redact), ...}` | Butuh persetujuan (M1) |
| `clarify.request` | — | Butuh klarifikasi (M1) |
| `error` | `{message}` | Error level session |

**`tool.progress` TIDAK ADA** — sudah dikonfirmasi bukan event yang ada (PRD section 9 konsisten).

### 2.5 Katalog method (diverifikasi di kode)

| Method | Params penting (diverifikasi) | Return |
|--------|-------------------------------|--------|
| `session.create` | `cwd` (wajib eksplisit biar masuk workspace), `title?`, `messages?`, `cols?`, `model?`, `provider?`, `reasoning_effort?`, `fast?`, `close_on_disconnect?`, `source?` | `session_id` (hex 8) |
| `prompt.submit` | `session_id`, `text` | async — hasil lewat event |
| `session.status` | `session_id` | metadata session (dipakai recovery) |
| `session.interrupt` | `session_id` | stop turn (M1) |
| `approval.respond` | `session_id`, + id request | (M1) |
| `clarify.respond` | `session_id`, + teks | (M1) |
| `session.steer` | — | (P1, belum dipakai 0.1) |
| `session.list` / `active_list` | — | 0.2 (multi-task) |

Catatan: `prompt.submit` saat session sibuk TIDAK ditolak — di-queue + interrupt turn berjalan (perilaku `_handle_busy_submit`). Client harus antisipasi itu.

### 2.6 Observasi mesin nyata (penting untuk desain lifecycle)

1. `hermes serve --status` bisa ngasih entri **stale** (PID yang sudah mati) — status list itu advisory, bukan kebenaran.
2. **Proses dashboard jalan ≠ port 9119 listening.** Di mesin user: ada entri proses dashboard tapi `lsof :9119` kosong.
3. `hermes serve` default **build web UI dulu** (butuh npm) — untuk Companion yang headless, WAJIB `--skip-build` biar boot cepat & tanpa dependensi npm.
4. Bind default `127.0.0.1`. **Auth di loopback: WAJIB `?token=`** (lihat 2.2) — handshake tanpa token → 403.

### 2.7 Hasil spike T0.5 (2026-08-12) — WAJIB dibaca sebelum T0.6

1. **Waktu boot `hermes serve --skip-build` di mesin user: ~1.0 detik** (spawn → probe sukses). Timeout 30s di `waitUntilReady` aman.
2. **Event pertama setelah WS connect: `gateway.ready`** — JSON-RPC event, params `{type: "gateway.ready", payload: {skin, branding}}`, TANPA `session_id`. Setelah itu diam sampai client kirim request (tidak ada spam frame).
3. **`Process.environment` di Swift = REPLACE seluruh env, bukan merge!** Setting `process.environment = ["KEY": v]` membuat child kehilangan PATH → `/usr/bin/env` gagal cari `hermes` → child mati. WAJIB merge dari `ProcessInfo.processInfo.environment` (sudah diperbaiki di `GatewayLifecycle.spawnServer`).
4. Frame `gateway.ready` yang direkam (payload skin dipangkas): `{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"skin":{...}}}}` → jadi fixture test pertama (T0.8 akan menambah lebih banyak).
5. Receive loop: setelah `task.cancel()`, callback receive akan memunculkan error "Socket is not connected" — itu normal (bukan bug), cukup jangan dianggap error fatal.

### 2.8 Hasil T0.7 — tool events & approval (2026-08-12) — bahan M1

Task nyata (`write_file` + `rm`) membuktikan:
1. **tool.start**: `{tool_id, name, context}` — TIDAK ada `args` di start (context = deskripsi manusia). Fixture: `tool-start-write_file.jsonl`.
2. **tool.complete**: `{tool_id, name, args, duration_s, result}` — args & result lengkap di sini. Fixture: `tool-complete-write_file.jsonl`.
3. **tool.generating**: `{name}` — sub-state lifecycle (muncul sebelum/bersamaan tool jalan). Fixture: `tool-generating-write_file.jsonl`.
4. **approval.request — TERAMATI NYATA**: perintah `rm /tmp/...` kena pola "delete in root path" → gateway emit `approval.request` dengan payload `{command, pattern_key, pattern_keys[], description, allow_permanent}`. Tanpa respons, agent menunggu selamanya (task timeout 120s di M0 — PERILAKU BENAR, ini tugas M1). Fixture emas: `approval-request-delete-root.jsonl`.
5. **Event lain yang baru teramati** (di luar katalog 2.4, semuanya NOISE untuk M0, tapi jangan di-drop decoder): `reasoning.delta` (sangat high-frequency — 216 frame!), `thinking.delta`, `reasoning.available`, `session.info`, `message.start`.
6. Semua frame di atas tersimpan di `Tests/CompanionCoreTests/Fixtures/` + contract test `FixtureContractTests.swift` (25 test total).

**Implikasi M1:** approval flow butuh (a) deteksi `approval.request` → state NeedsYou, (b) `approval.respond` dengan payload yang tepat (TDD M1 akan menentukannya — kemungkinan butuh id request/`tool_id`), (c) exactly-once (PRD section 51).

---

## 3. Keputusan arsitektur

### D1 — Transport: WebSocket (lihat 2.2)

### D2 — Attach-first, spawn-second

```text
Companion start
     ↓
Probe ws://127.0.0.1:9119/api/ws
     ├── connect OK  → ATTACH (jangan spawn)
     └── gagal       → SPAWN: hermes serve --skip-build --port 9119
                            ↓
                       tunggu ready (probe ulang + timeout) → connect
```

- Jangan pernah `hermes serve --stop` untuk server yang TIDAK kita spawn (perintah itu mematikan SEMUA server, termasuk punya Hermes Desktop).
- Shutdown: kalau kita yang spawn → tanya user (PRD section 56: default paling aman = Cancel; opsi Keep Hermes running / Stop task and quit). Kalau attach → jangan sentuh prosesnya.

### D3 — Spawn flags

```text
hermes serve --skip-build --host 127.0.0.1 --port 9119
```

### D4 — Bentuk project: Xcode macOS App + local Swift Package

- **Xcode App project** (bundle `.app` sejak awal) — final product memang Mac app; struktur bundle sudah ada dari M0, UI NSPanel/SwiftUI baru dimulai Milestone 2 (app M0 cukup placeholder).
- **CompanionCore = local Swift Package** di dalam repo (`Packages/CompanionCore`) — berisi library `CompanionCore`, executable `companion-m0`, dan test target. Tetap bisa `swift build` / `swift test` / `swift run companion-m0` dari terminal (mode belajar), dan di-link ke app target.
- Tanpa dependency pihak ketiga: `URLSessionWebSocketTask` native.
- **App Sandbox OFF** (keputusan PRD: perlu spawn `hermes serve` via Process — mulai T0.4).
- Keputusan ini menggantikan versi awal D4 (pure Swift Package).

### D5 — HermesAdapter = satu-satunya layer yang paham protocol Hermes (PRD section 9-10)

Semua tipe Hermes-specific (method name, event type, payload shape) hidup di adapter. Core domain (Task, State, Activity) tidak boleh bocor field Hermes.

### D6 — Version pin & compatibility gate

```text
Pin M0: Hermes v0.18.0 (2026.7.1)
Supported range: diisi dari hasil T0.3 (detect + parse), dimulai dari [0.18.0]
Gate: HermesDetector baca `hermes --version` → parse → bandingkan range → Supported / Missing / Unsupported
```

### D7 — Satu managed session (Product 0.1)

Model Task tetap collection-friendly (PRD section 19), tapi M0 cuma handle satu session aktif. `session_id` disimpan; event difilter per `session_id`.

---

## 4. Struktur package

```text
~/Documents/GitHub/companion/
├── Companion.xcodeproj          # Xcode app project (bundle .app)
├── Companion/                   # app target: CompanionApp.swift, ContentView.swift, Assets.xcassets
├── Packages/
│   └── CompanionCore/           # local Swift Package (bisa swift build/test sendiri)
│       ├── Package.swift
│       ├── Sources/
│       │   ├── CompanionCore/   # library: Hermes/, RPC/, Domain/
│       │   └── companion-m0/    # executable CLI: main.swift
│       └── Tests/
│           └── CompanionCoreTests/
│               └── Fixtures/    # rekaman JSON-RPC nyata (T0.9)
└── .gitignore
```

Catatan: lokasi repo bisa dipindah kalau kamu mau beda — yang penting konsisten dari sini. (Docs tetap di `~/Documents/hermesproject/companion/`.)

---

## 5. Spesifikasi komponen (M0)

### HermesDetector
- Cari binary: `which hermes` → fallback `~/.local/bin/hermes` → fallback PATH scan.
- Baca versi: spawn `hermes --version`, parse `Hermes Agent vX.Y.Z (date)`.
- `Compatibility` enum: `supported(range)` / `missing` / `unsupported(found, supported)`.
- Murni + testable (parsing versi di-unit-test tanpa spawn).

### GatewayLifecycle
- `attach()`: probe WS connect ke `ws://127.0.0.1:9119/api/ws` (timeout ~2s).
- `spawn()`: `Process` → `hermes serve --skip-build --host 127.0.0.1 --port 9119`, stdout/stderr ke log file (bukan console), simpan PID.
- `waitUntilReady(timeout:)`: probe loop (500ms interval, max ~30s) sampai connect sukses ATAU proses mati.
- `stop()`: hanya kalau kita yang spawn → SIGTERM PID anak; tunggu exit (grace ~3s) → SIGKILL kalau bandel.

### JSONRPCClient
- Framing: encode request (auto-increment id), decode response/error/event.
- Event callback: `onEvent(EventEnvelope)` — `EventEnvelope { type, sessionId, payload }`.
- Reconnect (dasar): kalau koneksi drop → backoff 1s/2s/4s/… max 30s; setelah konek ulang, client TIDAK menganggap state cached benar (PRD section 58) — recovery state penuh = M5, M0 cukup reconnect + log.
- Antrian request saat koneksi belum siap (opsional M0 — bisa disederhanakan: request hanya setelah ready).

### HermesAdapter (D5)
Typed wrapper, misal:
```swift
func createSession(cwd: String, title: String?) async throws -> String  // session_id
func submitPrompt(sessionID: String, text: String) async throws
func sessionStatus(sessionID: String) async throws -> SessionStatus
func interrupt(sessionID: String) async throws
```
Semua nama method/event string hidup DI SINI saja. Domain layer tidak pernah lihat `"prompt.submit"` mentah.

### EventDecoder → TaskEvent (domain)
```swift
enum TaskEvent {
    case ready                       // status.update kind == "ready"
    case activity(String)            // status.update text (activity language)
    case messageDelta(String)
    case messageComplete(MessageComplete)   // text + usage? (verifikasi spike)
    case toolStarted(ToolInfo)              // {toolId, name}
    case toolCompleted(ToolInfo, duration: Double?)
    case failure(String)             // event type "error"
}
```
Mapping aturan (PRD section 22-23): surface status.update/message content; tool mapping ringan (read_file → "Reading…", patch → "Editing…", terminal → "Running…") — conservative, tanpa mengarang intent.

### companion-m0 (CLI proof)
```text
companion-m0 run "Ketik hello world"
  → attach/spawn otomatis
  → create session (cwd = current dir)
  → submit prompt
  → print tiap event (type + ringkasan payload) sampai message.complete
  → exit 0
companion-m0 doctor
  → deteksi Hermes + versi + status server (buat debugging cepat)
companion-m0 serve-status
  → probe 9119 + hermes serve --status
```

---

## 6. Mapping acceptance M0 (PRD section 77)

| PRD | Dibuktikan oleh |
|-----|-----------------|
| Hermes detection | T0.3 `HermesDetectorTests` + `companion-m0 doctor` |
| Hermes version detection | T0.3 (parse + range) |
| connect | T0.5 (WS handshake + ready) |
| create session | T0.6 (`session.create` → `session_id` valid) |
| submit prompt | T0.6 (`prompt.submit` → event mengalir) |
| receive message events | T0.6 (`message.delta`/`message.complete` teramati) |
| receive tool events | T0.7 (task coding → `tool.start`/`tool.complete` teramati) |
| completion | T0.6/T0.7 (`message.complete` + session idle) |

---

## 7. Task breakdown (TDD — eksekusi oleh user, Hermes memandu)

> Prinsip: tiap task 2–5 menit fokus; test dulu (RED) → implement (GREEN) → commit. Jangan lanjut ke task berikutnya sebelum verifikasi lulus.

### T0.1 — Init project + git
- `swift package init --name CompanionCore --type library` di `~/Documents/GitHub/companion/` + target executable `companion-m0` di Package.swift.
- Git init + `.gitignore` (`.build/`, `DerivedData`, `*.xcodeproj/xcuserdata`).
- Verify: `swift build` sukses. Commit: `chore: init companion package`.

### T0.2 — JSONRPC framing (RED-GREEN)
- Test: encode request (id increment, jsonrpc 2.0, params), decode response, decode error, decode event envelope.
- Fixture JSON ditulis manual dari skema section 2.3.
- Verify: `swift test`. Commit: `feat: jsonrpc framing`.

### T0.3 — HermesDetector
- Test: parse `"Hermes Agent v0.18.0 (2026.7.1)"` → (0,18,0); range check supported/unsupported/missing; resolusi PATH (mock `which`).
- Implement `detect()` + `compatibility()`.
- Verify: `companion-m0 doctor` nunjukin v0.18.0 + Supported. Commit: `feat: hermes detection + version`.

### T0.4 — GatewayLifecycle spawn/stop
- Test: (unit) command line yang dibangun benar (flags D3); (manual) spawn → proses muncul → stop → proses hilang.
- Verify: `companion-m0 serve-status` → spawn dulu, cek `lsof :9119`, stop, cek hilang. Commit: `feat: gateway lifecycle`.

### T0.5 — WS connect + ready (SPIKE — hasilnya wajib dicatat)
- Implement `attach()` probe + `waitUntilReady` + connect + terima frame pertama.
- **Spike items yang harus dijawab & dicatat di doc ini:**
  1. Apakah `ws://127.0.0.1:9119/api/ws` butuh auth header saat bind loopback? (catat frame apa yang server kirim duluan — apakah ada `gateway.ready` / event `ready`?)
  2. Event apa yang muncul tepat setelah connect, sebelum session dibuat?
  3. Berapa lama boot `hermes serve --skip-build` di mesinmu (untuk timeout tuning)?
- Verify: konek ke server yang kita spawn → dapat frame valid. Commit: `feat: ws connect` + update section 2 doc dengan hasil spike.

### T0.6 — session.create + prompt.submit round trip
- Test: (integration) spawn → create session → submit `"Balas dengan satu kata: ok"` → kumpulkan events sampai `message.complete` → assert ada `message.delta` ATAU `message.complete`, `session_id` konsisten.
- Perhatian: event difilter per `session_id` (section 2.3).
- Verify: `companion-m0 run "Balas ok"` exit 0 + log event lengkap. Commit: `feat: session round trip`.

### T0.7 — Tool events (proof nyata)
- `companion-m0 run "Buat file hello.txt berisi hello di folder temp, lalu hapus"` → pastikan `tool.start`/`tool.complete` muncul dengan nama tool (Read/Write/Terminal).
- Assert di test: minimal satu `tool.start` teramati.
- Verify + catat bentuk payload asli di fixtures. Commit: `feat: tool events observed`.

### T0.8 — Fixtures untuk contract tests
- Simpan 3-5 baris event NYATA (dari T0.6/T0.7, tanpa rahasia) ke `Tests/CompanionCoreTests/Fixtures/` sebagai JSON.
- Test decoder terhadap fixtures (bukan cuma buatan tangan) → contract test (PRD section 12: adapter contract version 1).
- Commit: `test: protocol fixtures`.

### T0.9 — E2E acceptance (M0 selesai)
- Jalankan seluruh acceptance section 6 sekali jalan: `doctor` → `run` → cek tool events → completion.
- Tulis hasil di `~/Documents/hermesproject/companion/M0_RESULT.md` (tanggal, versi, temuan, capture event).
- Commit: `docs: m0 proof result`.

---

## 8. Perintah verifikasi cepat (cheat sheet)

```bash
swift build                      # compile
swift test                       # unit + integration tests
companion-m0 doctor              # detect + version + compatibility
companion-m0 serve-status        # probe 9119 + status server
companion-m0 run "Balas ok"      # round trip penuh
lsof -nP -iTCP:9119              # cek server beneran listening
```

---

## 9. Risiko & open items

| Risiko | Mitigasi |
|--------|----------|
| Auth loopback belum diverifikasi | Spike T0.5; kalau butuh token → baca config `~/.hermes/config.yaml` (mekanisme auth gateway), catat di doc |
| `hermes serve` berat (web_server 13k+ baris) | `--skip-build`; kalau boot >30s di mesinmu, evaluasi jalur stdio (fallback) di T0.4 |
| Status list `--status` stale | Jangan percaya; probe koneksi nyata (D2) |
| Event flood `message.delta` | Coalescing di client (buffer + flush timer ~30fps, lihat WSTransport di Hermes sebagai referensi) — cukup untuk UI nanti; M0 cukup print |
| `prompt.submit` di-queue saat sibuk | M0 single-task, risiko rendah; antisipasi di adapter (jangan submit saat session `running`) |
| Protocol berubah di versi Hermes baru | Compatibility gate (D6) + contract fixtures (T0.8) + pin versi di manifest |
| Recovery state setelah reconnect | M0: reconnect + log saja; recovery penuh = Milestone 5 (PRD section 82) |

## 10. Preview Milestone 1 (setelah M0 hijau)

M1 = Human-in-the-Loop Proof: approval round trip (approval.request → UI → approval.respond → Working → Success) + clarify. Ini butuh: TaskStateMachine beneran (state model PRD section 25-34), Needs You detection (PRD section 30), exactly-once (PRD section 51). M1 belum mulai sebelum M0 acceptance lulus.

---

## 11. Fakta protocol M1 terverifikasi (2026-08-12 · source `~/.hermes/hermes-agent/`)

> Bagian ini menjawab item terbuka di section 2.5/2.8: bentuk persis `approval.respond` & `clarify.respond`. Diverifikasi dari `tui_gateway/server.py` (`_block`, `_respond`, handler `@method`), `tools/approval.py`, dan desktop `apps/desktop/src/store/*`. Ini contract yang dipakai M1.

### 11.1 `approval.request` (payload) — TIDAK bawa `request_id`
```text
{command, pattern_key, pattern_keys[], description, allow_permanent}
```
Backend meng-key approval **per-session** (satu in-flight approval per sesi), resolved via `approval.respond {choice, session_id}`. TIDAK ada `request_id` (beda dari sudo/secret yang pakai `_block`). — konfirmasi comment `apps/desktop/src/store/native-notifications.ts`.

### 11.2 `approval.respond` (method · server.py:9819)
```python
@method("approval.respond")
... _sess(params) → resolve_gateway_approval(session_key, choice, all)
```
- params: `session_id` (wajib), `choice` (default `"deny"`), `all` (bool, default False → resolve_all).
- return: `{resolved: <int>}` — jumlah approval ter-resolve (0 = tidak ada pending → server-idempotent untuk re-send).
- **choice valid:** `"once"` (baris ini saja) · `"session"` · `"always"` (permanent; hanya bermakna kalau `allow_permanent == true`) · `"deny"`. (dari `slash_commands.py:4349`, `cli.py:11605`, desktop test `{choice:"once"}`/`{choice:"deny"}`.)
- Semantik FIFO oldest-first; `all:true` → resolve SEMUA pending approval sesi itu.
- Error `5004` kalau resolve gagal.

### 11.3 `clarify.request` (payload) — MEMBAWA `request_id`
```text
server.py:3706 clarify_callback → _block("clarify.request", sid, {question, choices})
_block (server.py:1925) → payload["request_id"] = uuid4().hex[:8]
```
payload: `{request_id, question, choices}`. `_block` default timeout 300s; jawaban dipop setelah respond; kalau timeout → jawaban kosong.

### 11.4 `clarify.respond` (method · server.py:9798)
- params: `request_id` (wajib, dicocokkan ke `_pending`), `answer` (teks, default `""`).
- return `{status:"ok"}`; error **4009** `"no pending clarify request"` kalau request_id tak dikenal/stale → idempotency natural (kirim ulang → 4009, bukan crash).

### 11.5 Implikasi desain M1
- **Approval → exactly-once (PRD 51) WAJIB di sisi client.** Karena tidak ada `request_id`, `approval.respond` dikirim dua kali berisiko men-resolve approval BARU yang kebetulan masuk (FIFO resolves yang paling tua), bukan cuma no-op. Butuh `ApprovalGate` per-session: kunci respons setelah satu `approval.request` dijawab, sampai ada `approval.request` baru.
- **Clarify → aman natural** (request_id + 4009), tapi tetap gate di client biar UX bersih.
- `choice:"always"` hanya diekspos saat `allow_permanent == true`.

---

---

## 12. Managed process ownership & detach saat quit (2026-08-17 · T4.7)

> PRD section 56 menyerahkan "exact managed process ownership and detach behavior" ke TDD. Ini keputusannya. Implementasi: `Domain/QuitPolicy.swift` (murni, ada testnya) + `companion/companionApp.swift` (`applicationShouldTerminate`).

### 12.1 Apa yang benar-benar dimiliki Companion

Companion hanya memiliki **server yang ia spawn sendiri**, ditandai `/tmp/companion-serve.pid` + `.token`. Server milik Hermes Desktop (atau siapa pun) tidak pernah disentuh — konsisten dengan D2 (attach-first) dan larangan `hermes serve --stop`. Kalau attach mendapati server asing (token bukan milik kita), `attachOrSpawn` mengembalikan `(nil, nil)` dan tidak ada kepemilikan apa pun.

Konsekuensi penting: **task hidup DI DALAM server itu.** Jadi "biarkan task jalan" dan "matikan server kita" saling bertentangan — tidak boleh dilakukan bersamaan.

### 12.2 Rencana per pilihan quit (PRD 56)

| Pilihan | `stopsTask` | `stopsOwnedGateway` | `quits` |
|---|---|---|---|
| Cancel (**default**) | – | – | tidak |
| Keep Hermes running | tidak | **tidak** | ya |
| Stop task and quit | ya (`session.interrupt`) | ya | ya |
| *(tidak ada task aktif)* | tidak | ya | ya |

- `keepRunning` sengaja **meninggalkan** PID/token file: launch Companion berikutnya akan attach ke server yang sama dan bisa memakai sesi Hermes yang masih hidup.
- Dialog quit hanya muncul kalau `TaskState.isActiveTurn` (satu definisi dipakai bersama `ControlPanelModel.isBusy`, supaya UI dan quit tidak pernah berbeda pendapat soal "task masih aktif"). `stopping` termasuk aktif: interrupt sudah dikirim tapi runtime belum mengonfirmasi terminal state.

### 12.3 Urutan eksekusi

`applicationShouldTerminate` → dialog → `QuitPolicy.plan(for:)`:

- `quits == false` → `.terminateCancel`.
- `stopsTask == false` → `.terminateNow`; `applicationWillTerminate` menjalankan `shutdown(plan:)` (tutup WS client, matikan gateway hanya kalau `stopsOwnedGateway`).
- `stopsTask == true` → `.terminateLater`, kirim interrupt, baru `NSApp.reply(toApplicationShouldTerminate: true)`. Kalau app keluar duluan, "stop task" cuma berarti kita berhenti melihatnya.

**Batas waktu 3 detik** untuk interrupt: gateway yang menggantung tidak boleh membuat app mustahil ditutup. Lewat dari itu quit tetap dilanjutkan (task bisa saja tetap jalan — trade-off yang disengaja: app yang tidak bisa di-quit lebih buruk).

### 12.4 Stop Task (PRD 55)

Tombol Stop diturunkan dari `TaskStateMachine.isLegal(from:to:.stopping)`, bukan daftar state terpisah — kalau transisinya ilegal, `session.interrupt` pasti ditolak dan tombolnya cuma bohong. Efeknya: Stop TIDAK ditawarkan saat `starting` (belum ada turn berjalan) dan saat `stopping` (sudah diminta). Konfirmasi memakai NSAlert dengan tombol pertama = `Cancel`, karena tombol pertama NSAlert adalah tombol default (Return).

---

*Dokumen ini hidup — hasil spike T0.5, temuan T0.6-T0.9, dan keputusan baru di-append/revisi di sini (dengan tanggal), bukan cuma di chat.*
