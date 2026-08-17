# Product Requirements Document
# AI Agent Companion — Hermes First

**PRD Revision:** 1.3  
**PRD Status:** Frozen for Technical Design  
**Primary Platform:** macOS  
**Primary Agent:** Hermes Agent  
**Architecture:** Managed Mode First  
**Initial Connectivity:** Local Machine  
**Future Connectivity:** Local Network → Remote  
**Future Product Direction:** Agent-Agnostic AI Companion

## Product Release Plan

- **Product 0.1 — Mac Companion MVP**
  - macOS only
  - one active managed Hermes task
  - full `Working → Needs You → Working → Done` loop
  - floating companion
- **Product 0.2 — Mac Multi-Task**
  - multiple Hermes sessions/tasks
  - Task Center
  - task prioritization
- **Product 0.3 — iPhone Local Companion**
  - LAN pairing
  - monitoring
  - approval
  - clarification
  - stop/control
- **Future**
  - remote internet access
  - push infrastructure
  - observer mode
  - additional agent runtimes

---

# 1. Executive Summary

AI Agent Companion adalah aplikasi yang memungkinkan pengguna membiarkan autonomous AI agent bekerja tanpa harus terus mengawasi Terminal atau UI agent.

Produk pertama berfokus pada **Hermes Agent** dan **macOS**.

Pada Mac, Companion muncul sebagai karakter floating yang persistent di desktop dan menjawab tiga pertanyaan:

1. Apa yang sedang Hermes lakukan?
2. Apakah Hermes membutuhkan pengguna?
3. Apakah pekerjaan sudah selesai?

Companion menggunakan **Managed Mode**.

```text
User
 │
 ▼
AI Agent Companion
 │
 ▼
Hermes Gateway
 │
 ▼
Hermes Runtime
```

Companion tidak mencoba membaca atau menebak kondisi proses Hermes yang berjalan secara independen.

Companion mengelola koneksi/session Hermes melalui integration surface resmi Hermes sehingga state seperti approval dan clarification dapat diterima sebagai protocol event yang eksplisit.

Product 0.1 hanya berfokus pada pengalaman Mac.

iPhone menjadi product release berikutnya setelah core Mac experience stabil.

---

# 2. Product Vision

> **Let autonomous agents work without requiring autonomous-agent babysitting.**

Autonomous agent seharusnya memungkinkan pengguna melakukan pekerjaan lain.

Tetapi jika pengguna masih harus terus mengecek Terminal untuk mengetahui apakah agent bekerja, berhenti, atau membutuhkan bantuan, maka agent tersebut belum benar-benar terasa asynchronous.

Companion bertindak sebagai lapisan:

```text
Agent activity
      ↓
State interpretation
      ↓
Attention filtering
      ↓
Human awareness
```

Bukan:

```text
Agent activity
      ↓
100 log lines
      ↓
Human reads everything
```

---

# 3. Core Product Promise

> **Know what Hermes is doing. Know when it needs you.**

Dalam beberapa detik, pengguna harus dapat mengetahui:

```text
What is Hermes doing?

Does Hermes need me?

Is Hermes done?
```

Jika tiga pertanyaan tersebut dapat dijawab dengan jelas tanpa membuka raw logs, Companion memenuhi fungsi utamanya.

---

# 4. Problem Statement

Workflow autonomous agent saat ini sering berubah menjadi:

```text
Give task
   ↓
Leave agent
   ↓
Wonder what happened
   ↓
Check Terminal
   ↓
Leave
   ↓
Check again
```

Masalah utamanya bukan kekurangan output.

Masalah utamanya adalah **uncertainty**.

Pengguna tidak selalu tahu:

- apakah Hermes masih bekerja;
- apakah Hermes sedang melakukan tool operation;
- apakah Hermes sedang menunggu approval;
- apakah Hermes membutuhkan clarification;
- apakah pekerjaan gagal;
- apakah pekerjaan selesai;
- apakah koneksi ke runtime terputus.

Akibatnya pengguna melakukan manual supervision berulang.

---

# 5. Product Thesis

AI Agent Companion tidak mencoba membuat Hermes lebih autonomous.

Companion membuat hubungan manusia-agent menjadi lebih **asynchronous**.

Target workflow:

```text
Give task
   ↓
Hermes works
   ↓
User does something else
   ↓
Hermes needs user
   ↓
Companion gets attention
   ↓
User responds
   ↓
Hermes continues
   ↓
Companion reports completion
```

---

# 6. Two Meanings of “Multitasking”

Untuk menghindari ambiguity, produk membedakan dua jenis multitasking.

## Human Multitasking

Pengguna melakukan pekerjaan lain ketika satu Hermes task sedang berjalan.

Ini adalah **core requirement Product 0.1**.

Example:

```text
Hermes works
      │
      ├── user writes in Xcode
      ├── user browses Safari
      └── user handles another task
```

## Agent Multitasking

Beberapa Hermes session/task aktif secara bersamaan.

Ini bukan requirement Product 0.1.

Ini masuk **Product 0.2**.

Pemisahan ini menjaga MVP tetap kecil tanpa mengorbankan visi produk.

---

# 7. Product Positioning

## Category

**AI Agent Companion**

## Initial Positioning

> A persistent Mac companion for Hermes.

## Expanded Positioning

> A persistent Mac companion and iPhone control surface for Hermes.

## Long-Term Positioning

> An attention and control layer for autonomous AI agents.

---

# 8. Architectural Decision — Managed Mode First

Product 0.1 menggunakan:

**Managed Mode**

```text
AI Agent Companion
        │
        │ owns managed session
        ▼
   Hermes Gateway
        │
        ▼
   Hermes Runtime
```

Companion tidak menjadikan stock interactive Hermes process yang kebetulan berjalan di Terminal sebagai source of truth.

Managed Mode dipilih untuk memungkinkan reliable:

- task state;
- streaming activity;
- approval handling;
- clarification handling;
- interruption;
- session lifecycle;
- later steering;
- later multi-session support.

---

# 9. Hermes Gateway Contract

Hermes Adapter menjadi satu-satunya komponen Companion yang memahami Hermes-specific protocol.

Berdasarkan instalasi Hermes yang diverifikasi secara lokal pada **11 Agustus 2026**, integration surface yang relevan mencakup methods seperti:

```text
prompt.submit

session.create
session.list
session.active_list
session.interrupt
session.status

approval.respond
clarify.respond

delegation.status
subagent.interrupt
```

Relevant events mencakup antara lain:

```text
message.delta
message.complete

tool.start
tool.started
tool.generating
tool.complete

approval.request
clarify.request
sudo.request
secret.request
```

`tool.progress` **tidak dianggap sebagai contract Product 0.1**, karena event tersebut tidak ditemukan pada instalasi lokal yang diverifikasi.

---

# 10. Hermes Protocol Stability Requirement

Hermes merupakan dependency yang berkembang aktif.

Companion tidak boleh mengasumsikan protocol Hermes selamanya identik.

Semua Hermes-specific behavior harus diisolasi di:

```text
HermesAdapter
```

Bukan tersebar di:

```text
SwiftUI Views
Task Store
Floating Character
iPhone Client
```

---

# 11. Runtime Compatibility Gate

Saat startup, Companion harus melakukan compatibility check.

```text
Companion launches
       ↓
Find Hermes
       ↓
Read Hermes version
       ↓
Compare with supported range
       ↓
 ┌───────────────┬────────────────┐
 ▼               ▼                ▼
Supported      Missing        Unsupported
 ▼               ▼                ▼
Connect       Setup UI       Compatibility UI
```

## Supported

Companion dapat menjalankan Managed Mode.

## Hermes Missing

Companion menunjukkan setup state.

```text
Hermes isn't available yet.

Install or configure Hermes
before starting a managed task.
```

## Unsupported Hermes Version

Companion tidak boleh diam-diam melanjutkan dengan protocol assumptions yang belum diverifikasi.

UI:

```text
Hermes version isn't verified
with this Companion build.

Installed:
[version]

Supported:
[verified range]
```

TDD menentukan apakah unsupported version:

- diblokir sepenuhnya;
- atau memiliki explicit experimental override.

Default Product 0.1 harus mengutamakan reliability.

---

# 12. Version Pinning Strategy

Setiap Companion release harus mencatat:

```text
Companion Version
Hermes Versions Tested
Hermes Gateway Contract Version
Adapter Tests
```

Example conceptual compatibility manifest:

```text
Companion 0.1
Hermes tested: [verified range]
Adapter contract: 1
```

Tidak perlu mengekspos detail tersebut pada user kecuali terjadi compatibility issue.

---

# 13. Source of Runtime Truth

Untuk live managed tasks:

> **Hermes Gateway adalah integration source of truth.**

Companion tidak menggunakan:

- inactivity timeout sebagai primary state detector;
- PTY prompt scraping;
- Terminal screen scraping;
- legacy JSONL tailing;
- direct SQLite schema inspection.

---

# 14. Hermes State Database Boundary

Hermes dapat menyimpan session data di:

```text
~/.hermes/state.db
```

Tetapi database tersebut adalah **internal persistence milik Hermes**, bukan public Companion API.

Product requirement:

> Companion must not depend on the internal SQLite schema of Hermes for normal runtime operation.

Jika recovery/history membutuhkan persistent Hermes state, access harus dilakukan melalui supported Hermes surfaces bila tersedia.

Direct database access hanya dapat dipertimbangkan kemudian sebagai explicit compatibility feature, bukan architectural foundation.

---

# 15. High-Level Architecture

```text
                         MAC

             ┌───────────────────────┐
             │   Hermes Companion    │
             │                       │
             │   Companion Core      │
             │         │             │
             │         ▼             │
             │   Hermes Adapter      │
             │         │             │
             └─────────┼─────────────┘
                       │
                  JSON-RPC / WS
                       │
                       ▼
                 ┌────────────┐
                 │   Hermes   │
                 │   Serve    │
                 └──────┬─────┘
                        │
                        ▼
                 Hermes Runtime


Companion Core
      │
      ├──── Floating Character
      │
      └──── Mac Control Panel
```

Product 0.1 berhenti pada boundary tersebut.

Later:

```text
Companion Core
      │
      └──── Local Companion API
                    │
                    ▼
                  iPhone
```

---

# 16. Architectural Layers

```text
Hermes Runtime
      ↓
HermesAdapter
      ↓
Normalized Events
      ↓
Task State Machine
      ↓
Activity Model
      ↓
Personality Renderer
      ↓
macOS Presentation
```

Setiap layer memiliki tanggung jawab berbeda.

---

# 17. Agent Abstraction

Long-term core architecture menggunakan abstraction:

```text
AgentRuntime
     │
     ├── HermesAdapter
     ├── FutureAgentAdapter
     └── FutureAgentAdapter
```

Conceptual capabilities:

```text
startTask()
stopTask()

sendMessage()

approve()
deny()
clarify()

getTaskState()

subscribeToEvents()
```

Product 0.1 hanya mempunyai satu implementation:

```text
HermesAdapter
```

Tidak ada requirement untuk membangun adapter kedua.

---

# 18. Core Domain Model

## Agent

```text
Agent
├── id
├── type
├── name
├── runtimeVersion
├── compatibilityState
└── connectionState
```

Product 0.1:

```text
type = hermes
```

---

# 19. Task Model

```text
Task
├── id
├── agentId
├── sessionId
├── title
├── projectContext
├── state
├── currentActivity
├── startedAt
├── updatedAt
├── finishedAt
├── attentionRequest
├── usage
└── recentActivities
```

Product 0.1 hanya membutuhkan satu active managed Task pada satu waktu.

Model tetap berbentuk collection-friendly agar Product 0.2 dapat menambahkan multiple tasks tanpa redesign besar.

---

# 20. Usage Model

```text
Usage
├── duration
├── costEstimate?
└── additionalMetadata?
```

`costEstimate` bersifat **optional**.

UI tidak boleh mengasumsikan semua provider/runtime selalu mempunyai cost information.

Valid:

```text
Done · 12m 41s · $0.84
```

jika cost tersedia.

Juga valid:

```text
Done · 12m 41s
```

jika cost tidak tersedia.

Missing cost bukan Error.

---

# 21. Activity Model

Activity adalah human-readable indication dari current work.

Example:

```text
Reading files
Editing code
Running tests
Waiting for approval
```

Activity bukan raw event dump.

---

# 22. User-Visible Activity Sources

Product 0.1 harus memprioritaskan stable user-visible signals.

Priority:

```text
Explicit Hermes status/event metadata
            ↓
User-visible message content
            ↓
Lightweight tool-name mapping
```

Companion tidak boleh bergantung pada hidden reasoning atau private chain-of-thought-like content untuk menampilkan status.

Jika Hermes implementation tertentu mempunyai optional user-visible reasoning/status block, Companion boleh memanfaatkannya hanya sebagai enhancement.

Core behavior tidak boleh bergantung padanya.

---

# 23. Lightweight Tool Mapping

MVP normalizer boleh mempunyai mapping sederhana seperti:

```text
read_file
→ Reading files…

search
→ Searching…

patch / edit
→ Editing…

terminal
→ Running command…

browser
→ Working in browser…
```

Mapping harus:

- conservative;
- factual;
- tidak mengarang intent;
- tidak mengarang outcome.

---

# 24. Semantic Activity Synthesis

Contoh activity seperti:

```text
Analyzing authentication architecture…
```

hanya boleh ditampilkan apabila Hermes sendiri memberikan konteks yang cukup untuk mendukungnya.

Companion tidak boleh menyimpulkan semantic intent hanya dari urutan raw tools.

Advanced semantic summarization merupakan P1.

---

# 25. Task State Model

Product 0.1 menggunakan state:

```text
Idle
Starting
Working
NeedsYou
Success
Error
Stopping
Disconnected
```

---

# 26. Idle

Hermes tersedia dan tidak menjalankan managed task.

```text
○ Idle
```

Personality:

```text
Ready when you are.
```

---

# 27. Starting

Task sudah diterima tetapi Hermes belum masuk execution state yang dapat dipercaya.

```text
◌ Starting…
```

---

# 28. Working

Hermes aktif mengerjakan task.

```text
● Working

Running tests…
```

---

# 29. Needs You

Hermes meminta human intervention melalui supported protocol event.

Subtypes:

```text
approval
clarification
sudo
secret
otherSupportedRequest
```

Visual:

```text
⚠ Needs You

Hermes needs your decision.
```

---

# 30. Needs You Detection Contract

Primary detection harus berasal dari explicit Hermes events.

Example:

```text
approval.request
      ↓
NeedsYou.approval
```

```text
clarify.request
      ↓
NeedsYou.clarification
```

Inactivity heuristic tidak boleh menjadi primary Needs You mechanism.

---

# 31. Success

Task selesai secara normal.

```text
✓ Done
```

Optional metadata:

```text
✓ Done
12m 41s
$0.84
```

atau:

```text
✓ Done
12m 41s
```

---

# 32. Error

Task gagal atau runtime memberi failure state yang meaningful.

```text
! Problem
```

Error harus berbeda dengan Disconnected.

---

# 33. Stopping

User meminta task dihentikan tetapi runtime belum mengkonfirmasi terminal state.

```text
◌ Stopping…
```

---

# 34. Disconnected

Connection antara Companion dan managed Hermes runtime terputus.

```text
○ Disconnected
```

Disconnected tidak berarti:

- Success;
- task Error;
- Hermes task pasti berhenti.

UI tidak boleh membuat asumsi tersebut.

---

# 35. State Priority — Product 0.1

Karena Product 0.1 hanya mempunyai satu active managed task:

```text
Needs You
    ↓
Error
    ↓
Working
    ↓
Starting / Stopping
    ↓
Success
    ↓
Idle
```

Product 0.2 akan memperluas priority ini ke multiple tasks.

---

# 36. Attention Model

Hermes dapat menghasilkan banyak events.

Companion harus melakukan compression.

Target conceptual behavior:

```text
100 runtime events
       ↓
State + Activity Normalization
       ↓
Small number of meaningful updates
       ↓
Rare interruptions
```

---

# 37. Attention Levels

## Level 0 — Ambient

```text
Reading files…
```

Tidak ada attention animation.

---

## Level 1 — Significant Progress Change

```text
Running tests…
```

Bubble dapat berubah.

Tidak ada notification.

---

## Level 2 — Completion

```text
✓ Done
```

Subtle success response.

Optional system notification.

---

## Level 3 — Needs You

```text
⚠ Approval required
```

Strong visual state.

System notification.

---

## Level 4 — Important Failure

```text
! Hermes couldn't continue
```

Strong visual state.

System notification.

---

# 38. macOS Product Experience

macOS merupakan primary surface Product 0.1.

User tidak perlu membuka conventional app window setiap kali menggunakan Companion.

Expected startup:

```text
Mac login
   ↓
Companion auto-launches
   ↓
Compatibility check
   ↓
Hermes backend ready
   ↓
Floating character appears
```

---

# 39. Background Application Model

Companion tetap merupakan macOS application, tetapi berperilaku seperti persistent accessory.

User experience:

```text
Mac turns on
      ↓
User logs in
      ↓
Companion is already available
```

Tidak:

```text
Finder
  ↓
Applications
  ↓
Open Companion manually
```

---

# 40. Floating Character

Floating Character adalah primary ambient interface.

Requirements:

- medium size;
- approximately enlarged app-icon visual footprint;
- borderless;
- transparent;
- draggable;
- persistent over normal applications;
- position remembered;
- Space-aware;
- multi-monitor safe;
- does not unnecessarily steal focus;
- does not walk around the desktop autonomously.

---

# 41. Character Asset Strategy

Product 0.1 tidak membutuhkan final mascot art.

Gunakan placeholder renderer:

```text
◉
●
⚠
✓
!
○
```

State machine tidak boleh bergantung pada asset tertentu.

Conceptual abstraction:

```text
CompanionState
      ↓
CharacterRenderer
      ↓
PlaceholderAsset / FinalMascotAsset
```

Dengan demikian visual final dapat diganti tanpa mengubah Hermes integration.

---

# 42. Floating Window Engineering Spike

Floating UI mempunyai engineering risk tersendiri.

Sebelum character polish, engineering spike harus membuktikan:

```text
✓ transparent window
✓ always-on-top behavior
✓ drag
✓ click character
✓ interactive bubble
✓ transparent area doesn't block underlying app
✓ no unwanted focus stealing
✓ Space switching
✓ full-screen behavior documented
✓ multi-monitor behavior
✓ position restoration
✓ display disconnect recovery
```

Character animation tidak menjadi prioritas sebelum spike ini stabil.

---

# 43. Floating Companion Size

Default:

**Medium**

Harus:

- terlihat secara peripheral;
- tidak menghalangi content utama;
- cukup besar untuk menunjukkan state;
- tidak menyerupai full floating chatbot window.

Bubble boleh memperluas footprint sementara.

---

# 44. Character State Presentation

## Idle

```text
   ◉

Ready
```

Almost static.

---

## Working

```text
   ◉

● Working

Running tests…
```

---

## Needs You

```text
   !

   ◉

Needs You
```

Harus unmistakable.

---

## Success

```text
   ✓
   ◉

Done
```

---

## Error

```text
   !
   ◉

Problem
```

---

## Disconnected

```text
   ○
   ◉

Hermes Offline
```

---

# 45. Speech / Status Bubble

Normal:

```text
[character]

● Working
```

Meaningful update:

```text
[character]

● Working
Running tests…
```

Default maximum information:

```text
State
+
1 activity update
```

Done state dapat menampilkan:

```text
duration
+
optional cost
```

Bubble tidak menjadi mini-terminal.

---

# 46. Single Click Interaction

Single click membuka compact control panel.

```text
╭──────────────────────────────╮
│ Authentication              │
│                             │
│ ● Working · 08:21           │
│                             │
│ Current                     │
│ Running tests…              │
│                             │
│ Recent                      │
│ ✓ Updated login flow        │
│ ✓ Saved changes             │
│                             │
│ [Details]          [Stop]   │
╰──────────────────────────────╯
```

Raw log viewer bukan P0.

---

# 47. Starting a Task

Managed Mode membutuhkan entry point untuk task.

Product 0.1:

```text
╭──────────────────────────────╮
│ New Hermes Task              │
│                              │
│ What should Hermes do?       │
│                              │
│ [________________________]   │
│                              │
│ Project                      │
│ ~/Projects/my-app            │
│                              │
│              [Start]         │
╰──────────────────────────────╯
```

Conceptual flow:

```text
User submits
     ↓
session.create
     ↓
prompt.submit
     ↓
Starting
     ↓
Working
```

---

# 48. Project Context

Product 0.1 harus memungkinkan user menentukan project/folder context sebelum memulai task.

UI tidak perlu menjadi file manager lengkap.

Minimal:

```text
Project
~/Projects/my-app

[Choose…]
```

Companion harus menampilkan context yang akan digunakan sebelum task dimulai.

---

# 49. Needs You Interaction

Ketika Hermes meminta user:

```text
⚠ Needs You

I need your decision on this one.

[Review]
```

Needs You harus lebih visible daripada normal progress.

---

# 50. Approval UX

Review harus menunjukkan action/context sebelum response.

```text
╭──────────────────────────────╮
│ Hermes Needs Approval        │
│                              │
│ Action                       │
│ npm install package          │
│                              │
│ Context / reason             │
│ Required for this task       │
│                              │
│ [Deny]             [Allow]   │
╰──────────────────────────────╯
```

Setelah response:

```text
approval.respond
      ↓
Await runtime acknowledgement/state
      ↓
Working
```

Companion tidak boleh mengubah state menjadi Working hanya karena user menekan Allow sebelum runtime benar-benar melanjutkan.

---

# 51. Approval Exactly-Once Requirement

Approval response adalah control action.

Companion harus mencegah:

```text
double click
network retry
UI duplicate
reconnect replay
```

menghasilkan approval yang dikirim dua kali.

TDD harus mendefinisikan idempotency strategy.

---

# 52. Stale Approval Requirement

Approval memiliki lifecycle.

Jika request:

- sudah dijawab;
- expired;
- task berhenti;
- session berubah;

UI tidak boleh tetap menawarkan Allow/Deny.

Stale request harus berubah menjadi non-interactive state.

---

# 53. Clarification UX

```text
╭──────────────────────────────╮
│ Hermes Needs Your Input      │
│                              │
│ Which implementation         │
│ should I use?                │
│                              │
│ ○ Keep existing approach     │
│ ○ Replace implementation     │
│                              │
│ Or type a reply…             │
│                              │
│ [Send]                       │
╰──────────────────────────────╯
```

Response:

```text
clarify.respond
      ↓
runtime continues
```

---

# 54. Sudo and Secret Requests

Jika Hermes Gateway mengirim supported:

```text
sudo.request
secret.request
```

Companion dapat menggunakan `Needs You` umbrella state.

Namun secret handling harus dirancang secara security-conscious.

Product requirement:

> Sensitive values must not be displayed, logged, persisted, or echoed unnecessarily.

Exact secure input lifecycle termasuk TDD/security design.

---

# 55. Stop Task

User dapat memilih:

```text
Stop Task
```

Confirmation:

```text
Stop Hermes?

Hermes may currently be in the
middle of an operation.

[Cancel]     [Stop]
```

State:

```text
Working
   ↓
Stopping
   ↓
terminal state
```

---

# 56. Companion Quit Behavior

Companion tidak boleh secara tidak sengaja membunuh active Hermes task.

Jika user memilih Quit ketika task aktif:

```text
Hermes is still working.

○ Keep Hermes running
○ Stop task and quit
● Cancel
```

Default safest action:

```text
Cancel
```

Exact managed process ownership and detach behavior harus ditentukan di TDD.

---

# 57. Crash / Restart Behavior

Companion crash atau restart tidak boleh otomatis dianggap sebagai task failure.

Recovery flow:

```text
Companion restarts
      ↓
Reconnect Hermes
      ↓
Query canonical runtime/session state
      ↓
Reconstruct UI state
```

Recovery capability harus dibuktikan sebelum release 0.1.

---

# 58. Reconnection Model

```text
Connection lost
      ↓
Disconnected
      ↓
Retry connection
      ↓
Recover authoritative state
      ↓
Working / Needs You / Done / Error
```

Client tidak boleh menganggap cached state tetap benar setelah disconnect.

---

# 59. Terminal Relationship

Product 0.1 tidak menggantikan Terminal sebagai general developer tool.

Tetapi managed session Companion tidak sama dengan stock Hermes CLI process terpisah.

Product 0.1 workflow:

```text
Companion UI
     ↓
Hermes Gateway
```

Future:

```text
Companion CLI
     ↓
Companion Core
     ↓
Hermes Gateway
```

Example future command:

```text
$ companion run "Fix authentication"
```

---

# 60. Observer Mode

Observer Mode bukan P0.

Future:

```text
$ hermes
   ↓
Stock Hermes CLI
   ↓
Companion plugin/hooks
   ↓
Floating Character
```

Potential capabilities:

- session awareness;
- tool activity;
- completion;
- Needs You notification.

Observer Mode tidak dijanjikan mempunyai control parity dengan Managed Mode.

---

# 61. Personality Architecture

Personality berada di atas reliable state.

```text
Hermes Event
    ↓
Normalized State
    ↓
Activity
    ↓
Personality Renderer
    ↓
Character + Text
```

Tidak:

```text
Random mascot dialogue
```

---

# 62. Character Personality

Character harus terasa:

- calm;
- competent;
- observant;
- concise;
- slightly expressive;
- supportive;
- not childish;
- not needy;
- not artificially enthusiastic.

Karakter adalah partner kerja.

Bukan virtual pet.

---

# 63. Personality Examples

## Starting

```text
On it.
```

## Reading

```text
Getting familiar with the project.
```

## Editing

```text
Working through the changes.
```

## Running tests

```text
Checking the changes now.
```

## First failure

```text
A test failed. I'm checking why.
```

## Repeated failure

```text
Still fighting the same test.
```

## Approval

```text
I need your decision on this one.
```

## Clarification

```text
I need a little context before I continue.
```

## Success

```text
Done. Everything checks out.
```

## Error

```text
I couldn't get past this one.
```

## Idle

```text
Ready when you are.
```

---

# 64. Personality Safety Rules

Character must not:

- generate constant chatter;
- interrupt for trivial activity;
- guilt the user;
- fabricate progress;
- claim success before runtime confirms it;
- hide errors with humor;
- misrepresent security-sensitive actions;
- invent reasons for approval requests.

Personality enhances truth.

It never replaces truth.

---

# 65. Animation Specification

## Idle

Almost static.

Optional subtle breathing.

## Working

Subtle loop.

No constant bouncing.

## Needs You

One clear attention animation.

Then settles.

## Success

Short acknowledgement.

## Error

Visible but restrained.

No aggressive flashing.

---

# 66. macOS Notifications

Product 0.1 system notification triggers:

- Needs You;
- important Error;
- Success.

Do not notify for:

- every file read;
- every command;
- every tool event;
- normal activity transitions.

---

# 67. Hide Behavior

Context menu:

```text
Open Control Panel

Hide Companion
Hide for 1 Hour

Pause Notifications

Settings
Quit
```

If hidden and Hermes enters Needs You:

Default behavior:

```text
System notification
+
optionally restore character visibility
```

Exact preference can be configured later.

---

# 68. Design Direction

Visual language should prioritize:

- restrained UI;
- premium monochrome-first aesthetic;
- strong state contrast;
- distinctive mascot identity;
- minimal visual noise;
- intentional typography;
- compact information hierarchy.

The product should not look like a generic AI dashboard.

---

# 69. Product 0.1 P0 Scope

## Hermes Core

- detect Hermes installation;
- detect Hermes version;
- compatibility gate;
- launch/manage backend;
- establish Gateway connection;
- create session;
- submit prompt;
- consume supported runtime events;
- Working state;
- Needs You state;
- approval request;
- approval response;
- clarification request;
- clarification response;
- interruption;
- completion;
- Error;
- Disconnected;
- reconnect/recovery.

## macOS

- auto-launch architecture;
- floating placeholder character;
- transparent window;
- drag;
- saved position;
- compact bubble;
- task start UI;
- current task panel;
- Needs You panel;
- Stop Task;
- completion metadata;
- macOS notifications;
- hide/quit behavior.

---

# 70. Product 0.1 Explicit Non-Goals

Not P0:

- multiple simultaneous managed tasks;
- Task Center with many tasks;
- iPhone;
- device pairing;
- local Companion network server;
- internet access;
- push infrastructure;
- observer mode;
- arbitrary stock Hermes CLI monitoring;
- JSONL tailing;
- PTY prompt detection;
- Terminal emulator;
- raw remote shell;
- multiple Macs;
- multiple agent runtimes;
- full code editor;
- full file browser;
- automatic approvals;
- advanced semantic activity summaries;
- character progression;
- game mechanics;
- virtual-pet systems.

---

# 71. Product 0.2 — Mac Multi-Task

After Product 0.1 is stable:

- multiple managed Hermes sessions;
- task list;
- Task Center;
- attention priority;
- multiple Needs You handling;
- session switching;
- history improvements.

Example:

```text
HERMES

1 NEEDS YOU
2 WORKING
4 DONE

⚠ Build iOS App
   Approval required

● Authentication
   Running tests

● API Research
   Reading documentation
```

---

# 72. Product 0.3 — iPhone Local Companion

iPhone becomes:

> **Remote Attention & Control Surface**

Mac remains source of truth.

Architecture:

```text
iPhone
  │
  │ Companion Protocol
  ▼
Mac Companion
  │
  │ Hermes Protocol
  ▼
Hermes Gateway
```

iPhone never receives raw Hermes Gateway access.

---

# 73. iPhone Local Scope

Product 0.3:

- pairing;
- Mac discovery;
- connection status;
- task list;
- task detail;
- live status;
- Needs You;
- approval;
- clarification;
- stop;
- reconnect.

LAN only.

No internet relay.

---

# 74. iPhone Security Boundary

Every paired device must have:

- unique device credential;
- secure credential storage;
- revocation;
- authenticated control connection;
- no unauthenticated command endpoint;
- duplicate/replay protection.

No device receives access merely because it is on the same Wi-Fi.

---

# 75. Remote Access Future

Later architecture:

```text
Mac at home
     │
Secure Remote Layer
     │
Internet
     │
iPhone anywhere
```

Requires separate security design covering:

- hardened authentication;
- encryption;
- relay/VPN-style connectivity;
- stolen-device handling;
- push notifications;
- remote threat model.

Not part of Product 0.1–0.3 unless explicitly promoted later.

---

# 76. Multi-Agent Future

Long-term:

```text
Hermes
Agent B
Agent C
   │
   ▼
Companion Core
```

No second runtime will be implemented until Hermes-first experience proves valuable.

---

# 77. Engineering Milestone 0 — Gateway Proof

No character.

No iPhone.

Goal:

```text
Hermes Gateway
      ↓
Swift Prototype
```

Must prove:

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

# 78. Engineering Milestone 1 — Human-in-the-Loop Proof

Must prove:

```text
Working
   ↓
approval.request
   ↓
Needs You
   ↓
approval.respond
   ↓
Working
   ↓
Success
```

Also:

```text
clarify.request
      ↓
clarify.respond
```

This milestone validates the core product thesis.

---

# 79. Engineering Milestone 2 — macOS Window Spike

Must prove independently:

```text
✓ transparent panel
✓ draggable
✓ click-through behavior
✓ interactive character
✓ interactive bubble
✓ focus behavior
✓ Space switching
✓ full-screen behavior documented
✓ multi-monitor
✓ monitor disconnect recovery
```

No final mascot required.

---

# 80. Engineering Milestone 3 — Floating Companion

Combine:

```text
Hermes state
     +
Floating UI
```

Result:

```text
[character]

● Working
Running tests…
```

and:

```text
[character]

⚠ Needs You
```

---

# 81. Engineering Milestone 4 — Mac Product Loop

Implement complete Mac flow:

```text
start task
   ↓
Working
   ↓
progress
   ↓
Needs You
   ↓
approve / clarify
   ↓
Working
   ↓
Done
```

This is feature-complete Product 0.1 candidate.

---

# 82. Engineering Milestone 5 — macOS Hardening

Before Product 0.1 release, test:

- Hermes missing;
- unsupported Hermes version;
- Hermes backend restart;
- Companion restart;
- stale approval;
- duplicate approval action;
- Mac sleep/wake;
- process disconnect;
- reconnect;
- task completion during disconnect;
- app quit with active task;
- full-screen apps;
- Space switching;
- monitor disconnect;
- character off-screen recovery.

Only after M5 passes does Product 0.1 ship.

---

# 83. Engineering Milestone 6 — Multi-Task

Product 0.2:

- multiple sessions;
- task priority;
- task switching;
- Task Center;
- multiple Needs You requests;
- multiple completion states.

---

# 84. Engineering Milestone 7 — iPhone Local Companion

Product 0.3:

```text
pair
connect
sync
monitor
approve
clarify
stop
```

over LAN.

---

# 85. Engineering Milestone 8 — Cross-Device Hardening

Test:

- Wi-Fi changes;
- iPhone disconnect;
- Mac sleep;
- Mac reconnect;
- stale remote approval;
- duplicate remote commands;
- revoked device;
- authentication failure;
- completion during disconnect;
- multiple task updates.

---

# 86. Primary User Journey — Product 0.1

## Step 1

User logs into Mac.

```text
[character]

Ready when you are.
```

## Step 2

User starts task.

```text
Fix authentication and run all tests.
```

## Step 3

Character:

```text
● Working

Getting familiar with the project.
```

## Step 4

User switches to another app.

Character remains visible.

## Step 5

Activity changes.

```text
● Working

Checking the changes now.
```

## Step 6

Hermes requests approval.

```text
⚠ Needs You

I need your decision on this one.
```

## Step 7

User clicks Review.

```text
Hermes wants to perform:
...

[Deny] [Allow]
```

## Step 8

User approves.

Hermes continues.

```text
● Working

Continuing.
```

## Step 9

Hermes completes.

```text
✓ Done

Everything checks out.

12m 41s
```

Cost appears only if available.

User did not have to locate a Terminal window to monitor the task.

---

# 87. North Star Acceptance Test

Given:

- Companion is running;
- Hermes version is supported;
- managed runtime is connected;
- user starts a task.

The task must successfully perform:

```text
Start
 ↓
Working
 ↓
multiple runtime events
 ↓
Needs You
 ↓
user response
 ↓
Working
 ↓
Success
```

without requiring Hermes' original interactive Terminal UI.

If this flow is unreliable, Product 0.1 is not complete.

---

# 88. Critical Acceptance Criteria — Product 0.1

## AC1 — Compatibility

Companion correctly identifies whether installed Hermes is supported.

## AC2 — Reliable Working State

When Hermes is actively processing the managed session, Companion reports Working.

## AC3 — Reliable Needs You

Supported explicit Hermes human-intervention events produce Needs You.

No inactivity heuristic is the primary detector.

## AC4 — Approval Round Trip

User can inspect an approval and submit exactly one response.

## AC5 — Clarification Round Trip

User can answer clarification and Hermes continues the same task.

## AC6 — Completion Integrity

When task finishes, Companion no longer displays Working.

## AC7 — Disconnection Integrity

Connection loss displays Disconnected, not Success or task Error.

## AC8 — Recovery Integrity

After reconnect/restart, Companion recovers authoritative current state where Hermes supports recovery.

## AC9 — Window Usability

Floating UI does not materially interfere with normal interaction in other applications.

## AC10 — Human Readability

Without raw logs, the user can determine:

```text
what Hermes is doing
whether Hermes needs them
whether Hermes is done
```

## AC11 — Truthful Activity

Activity text must not claim intent, outcome, or progress unsupported by runtime information.

## AC12 — Optional Usage Metadata

Missing cost information must not break or degrade successful completion state.

---

# 89. Product 0.1 Release Blockers

Do not ship if:

- Needs You can silently disappear;
- approval can execute twice;
- stale approval can be submitted;
- Working remains after confirmed completion;
- Disconnected is incorrectly shown as Error;
- unsupported Hermes version silently proceeds as supported;
- reconnect creates contradictory state;
- task dies because Companion quits unexpectedly;
- Companion restart cannot recover a reasonable current state;
- character regularly steals focus;
- character can become permanently off-screen;
- activity text frequently misrepresents runtime state;
- successful tasks fail UI completion because cost metadata is unavailable.

---

# 90. Success Metrics — Product 0.1

Early success is behavioral.

## Primary Metric

Reduction in manual agent checking.

Question:

> After starting a Hermes task, how often does the user open another Hermes surface purely to check whether it is still working?

Desired answer:

**Rarely.**

---

# 91. Secondary Metrics

- percentage of Needs You events successfully surfaced;
- approval completion success rate;
- clarification completion success rate;
- state accuracy;
- reconnect success rate;
- number of Companion-triggered interventions;
- number of tasks completed without opening another Hermes UI;
- user-reported distraction level of floating character.

Multi-task and iPhone metrics are not Product 0.1 metrics.

---

# 92. Product Quality Principle

> **Boringly reliable underneath. Alive on the surface.**

Underneath:

```text
explicit protocol events
deterministic state machine
compatibility checks
safe approvals
recovery
reconnection
```

On the surface:

```text
character
personality
subtle animation
human language
```

Never reverse these priorities.

---

# 93. Technical Design Questions

These questions belong in TDD, not further PRD expansion.

## Hermes Lifecycle

- Does Companion spawn `hermes serve` as a child process?
- Can it safely detach active managed tasks?
- What is the exact recovery contract after Companion restarts?

## Gateway Transport

- stdio or WebSocket for local Mac integration?
- What reconnect behavior is available?
- What event uniquely identifies approval and clarification requests?

## Usage

- Which Gateway response reliably contains duration?
- Which providers expose cost?
- What is the fallback when cost is absent?

## macOS Window

- exact `NSPanel` style;
- click-through implementation;
- focus behavior;
- full-screen behavior;
- Spaces behavior;
- multi-display behavior.

## Compatibility

- exact supported Hermes version range for Product 0.1;
- how adapter contract tests are run;
- whether experimental unsupported mode exists.

These questions must be answered through implementation spikes and Hermes protocol verification, not assumptions.

---

# 94. PRD Freeze Rule

After Revision 1.3:

Do not add new Product 0.1 features unless one of these is true:

1. The feature is required to make the North Star flow work.
2. The feature fixes a safety/reliability problem.
3. A technical spike proves an existing requirement impossible and forces a scope correction.

New ideas otherwise go to:

```text
Product 0.2
Product 0.3
Future Backlog
```

---

# 95. Final Product 0.1 Definition

Product 0.1 succeeds when this experience feels natural:

> I log into my Mac and the Companion is already there. I give Hermes a task through the Companion and continue doing something else. The character quietly tells me what Hermes is doing without forcing me to read logs. When Hermes genuinely needs a decision, the character clearly tells me. I can review the request and respond directly. Hermes continues working. When the task finishes, the character tells me and shows duration, plus cost if Hermes provides it. I do not need to repeatedly check another Hermes interface just to know what is happening.

That is Product 0.1.

Not a new Terminal.

Not a multi-agent fleet manager.

Not an iPhone app yet.

Not a virtual pet.

Not an AI dashboard full of logs.

**Hermes works.  
The Companion watches.  
The human intervenes only when necessary.**