import Foundation

// T3.2 — ManagedSession: loop tunggal yang menyambungkan event Hermes →
// TaskStateMachine → UI (dipakai app + bisa dipakai CLI). Ekstraksi dari
// ProofRunner (M1). Tanggung jawab:
//   * drain event dari client (setEventHandler → AsyncStream)
//   * update TaskStateMachine + ApprovalGate
//   * surface state & NeedsYou ke UI via callback
//   * auto-respond approval/clarify opsional (UI penuh = M4)
// Thread: loop jalan pada executor pemanggil run(); callback dipanggil dari sana
// (app membungkusnya ke main/actor sesuai kebutuhan).

public protocol ManagedSessionAdapter: Sendable {
    func submitPrompt(sessionID: String, text: String) async throws
    func interrupt(sessionID: String) async throws
    func respondApproval(sessionID: String, choice: ApprovalChoice, resolveAll: Bool) async throws -> Int
    func respondClarify(sessionID: String, requestID: String, answer: String) async throws -> Bool
}

extension HermesAdapter: ManagedSessionAdapter {}

public final class ManagedSession: @unchecked Sendable {
    /// State berubah (UI update karakter/bubble).
    public var onStateChange: (@Sendable (TaskState) -> Void)?
    /// Satu keputusan dibutuhkan (approvalRequest / clarifyRequest — lihat decisionText).
    public var onNeedsYouRequest: (@Sendable (TaskEvent) -> Void)?
    /// Text aktivitas (status.update) — "apa yang Hermes kerjakan" (PRD: Know what Hermes is doing).
    public var onActivity: (@Sendable (String) -> Void)?
    /// Satu langkah selesai (`tool.complete`) — isi blok "Recent" di control
    /// panel (PRD 46). Durasi ikut apa adanya; runtime tidak selalu mengirimnya.
    public var onStepCompleted: (@Sendable (ToolInfo, Double?) -> Void)?
    /// Jawaban akhir agent dari `message.complete` (PRD 22: user-visible message
    /// content). Tidak dipanggil kalau event datang tanpa teks.
    public var onMessage: (@Sendable (String) -> Void)?
    /// Loop berakhir (terminal state).
    public var onFinished: (@Sendable (TaskState) -> Void)?

    /// Kalau tidak nil → ManagedSession menjawab otomatis (spike/demo).
    /// nil → UI yang memutuskan via respondHelpers.
    public var autoRespondApproval: ApprovalChoice?
    /// Jawaban clarify otomatis kalau `autoRespondApproval` diset (default: pilihan pertama).
    public var autoClarifyUseFirstChoice = true
    /// Tunda sebelum auto-respond (detik) — biar request approval/klarifikasi
    /// sempat TERBACA di UI sebelum dijawab (demo/observasi). 0 = langsung.
    public var autoApproveDelay: TimeInterval = 0

    public private(set) var state: TaskState = .idle

    private let adapter: ManagedSessionAdapter
    private let stream: AsyncStream<TaskEvent>
    private let continuation: AsyncStream<TaskEvent>.Continuation
    private var machine = TaskStateMachine(initial: .idle)
    private var gate = ApprovalGate()
    private var pendingClarifyRequestID: String?
    private var awaitingResume = false

    public init(adapter: HermesAdapter) {
        self.adapter = adapter
        let (s, c) = AsyncStream<TaskEvent>.makeStream()
        stream = s
        continuation = c
        adapter.client.setEventHandler { [continuation] env in
            if let ev = EventDecoder.decode(env) {
                continuation.yield(ev)
            }
        }
    }

    init(adapterForTesting: ManagedSessionAdapter) {
        self.adapter = adapterForTesting
        let (s, c) = AsyncStream<TaskEvent>.makeStream()
        stream = s
        continuation = c
    }

    func enqueueTestEvent(_ event: TaskEvent) {
        continuation.yield(event)
    }

    /// Jalankan satu managed task. Return state akhir.
    public func run(sessionID: String, prompt: String) async -> TaskState {
        machine = TaskStateMachine(initial: .idle)
        gate = ApprovalGate()
        pendingClarifyRequestID = nil
        awaitingResume = false
        do {
            try await adapter.submitPrompt(sessionID: sessionID, text: prompt)
            transition(.starting)
        } catch {
            transition(.error)
            finish()
            return state
        }

        for await ev in stream {
            await handle(ev, sessionID: sessionID)
            if case .success = machine.state { break }
            if case .error = machine.state { break }
        }
        continuation.finish()
        finish()
        return state
    }

    // ── Respond — UI (M4) atau auto. Gate memastikan exactly-once (PRD 51). ──

    /// Kirim keputusan approval. Return true kalau diterima gate (dikirim ke network).
    public func respondApproval(sessionID: String, choice: ApprovalChoice) async -> Bool {
        guard gate.respond(choice) else { return false }
        do {
            _ = try await adapter.respondApproval(sessionID: sessionID, choice: choice, resolveAll: false)
            awaitingResume = true
            return true
        } catch {
            return false
        }
    }

    /// Hentikan turn melalui `session.interrupt`. State masuk stopping dan
    /// tetap menunggu event runtime berikutnya sebagai konfirmasi terminal.
    public func stop(sessionID: String) async -> Bool {
        guard TaskStateMachine.isLegal(from: machine.state, to: .stopping) else { return false }
        do {
            try await adapter.interrupt(sessionID: sessionID)
            pendingClarifyRequestID = nil
            gate.invalidate()
            transition(.stopping)
            return true
        } catch {
            return false
        }
    }

    /// Kirim jawaban clarify. Return true kalau diterima server (bukan 4009).
    public func respondClarify(sessionID: String, requestID: String, answer: String) async -> Bool {
        guard pendingClarifyRequestID == requestID else { return false }
        let sent = (try? await adapter.respondClarify(sessionID: sessionID, requestID: requestID, answer: answer)) ?? false
        if sent {
            pendingClarifyRequestID = nil
            awaitingResume = true
        }
        return sent
    }

    // ── Loop internal (mirror ProofRunner M1) ──

    private func handle(_ ev: TaskEvent, sessionID: String) async {
        switch ev {
        case .ready, .activity, .messageDelta, .toolStarted, .toolCompleted:
            if machine.state == .starting { transition(.working) }
            if awaitingResume { transition(.working); awaitingResume = false }   // PRD 50: bukti lanjut
            if case .activity(let text) = ev { onActivity?(text) }
            if case .toolCompleted(let tool, let duration) = ev { onStepCompleted?(tool, duration) }

        case .approvalRequest(let req):
            transition(.needsYou(.approval))
            gate.register(req)
            onNeedsYouRequest?(ev)
            if let choice = autoRespondApproval {
                if autoApproveDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(autoApproveDelay * 1_000_000_000))
                }
                let sent = await respondApproval(sessionID: sessionID, choice: choice)
                _ = sent
            }

        case .clarifyRequest(let req):
            pendingClarifyRequestID = req.requestId
            transition(.needsYou(.clarification))
            onNeedsYouRequest?(ev)
            if autoRespondApproval != nil {
                if autoApproveDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(autoApproveDelay * 1_000_000_000))
                }
                let answer = autoClarifyUseFirstChoice ? (req.choices.first ?? "Lanjutkan") : "Lanjutkan"
                let sent = await respondClarify(sessionID: sessionID, requestID: req.requestId, answer: answer)
                _ = sent
            }

        case .messageComplete(let message):
            if case .needsYou = machine.state {
                onNeedsYouRequest?(ev)   // biar UI tahu anomali; tidak crash
            }
            // Teks boleh kosong (event tetap menutup turn) — jangan kirim
            // jawaban kosong ke UI.
            if !message.text.isEmpty { onMessage?(message.text) }
            // Turn yang selesai TANPA event perantara hanya punya message.complete.
            // `starting → success` ilegal (state machine), jadi tanpa promosi ini
            // transisi ditolak, loop tidak pernah break, dan run() menggantung
            // selamanya — memblokir semua task berikutnya. Event ini sendiri sudah
            // bukti runtime menjalankan turn, jadi lewat working dulu (PRD 50 tetap
            // aman: yang dilarang adalah needsYou → success).
            if machine.state == .starting { transition(.working) }
            transition(.success)
            gate.invalidate()            // PRD 52: approval lama non-interaktif

        case .failure(let msg):
            _ = msg
            transition(.error)

        default:
            break
        }
    }

    private func transition(_ next: TaskState) {
        guard machine.state != next else { return }
        if machine.transition(to: next) {
            state = machine.state
            onStateChange?(state)
        } else {
            onStateChange?(machine.state)
        }
    }

    private func finish() {
        onFinished?(state)
    }
}