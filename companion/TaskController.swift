//
//  TaskController.swift
//  companion
//
//  M4 Task 3 — public task-control surface for the floating companion.
//  Owns the managed gateway session; UI calls start/stop/respond explicitly.
//

import Foundation
import CompanionCore

@MainActor
final class TaskController {
    /// Bubble text lengkap (glyph + status + aktivitas/keputusan).
    var onBubbleChange: ((String) -> Void)?
    /// State berubah (panel bisa pakai untuk visual karakter nanti).
    var onStateChange: ((TaskState) -> Void)?
    /// Jawaban akhir agent (PRD 22). String kosong = bersihkan hasil lama.
    var onAnswer: ((String) -> Void)?
    /// Approval yang menunggu keputusan + apakah sudah dijawab (PRD 50/51/52).
    /// nil = tidak ada yang perlu ditawarkan ke user.
    var onApprovalChange: ((ApprovalRequest?, Bool) -> Void)?
    /// Clarification yang menunggu jawaban + apakah sudah dikirim (PRD 53).
    var onClarifyChange: ((ClarifyRequest?, Bool) -> Void)?

    private(set) var state: TaskState = .idle
    /// Approval terakhir dari gateway (PRD 50). Kontrolnya hanya boleh tampil
    /// saat state benar-benar `needsYou(.approval)` — lihat ControlPanelModel.
    private(set) var pendingApproval: ApprovalRequest?
    /// Keputusan sudah dikirim → tombol mati (PRD 51).
    private(set) var approvalAnswered = false
    /// Clarification terakhir dari gateway (PRD 53).
    private(set) var pendingClarify: ClarifyRequest?
    /// Jawaban sudah dikirim → form mati sampai request berikutnya.
    private(set) var clarifyAnswered = false
    private var lastActivity: String?
    private var decision: String?
    private var client: JSONRPCClient?
    private var managed: ManagedSession?
    private var runTask: Task<Void, Never>?
    private var sessionID: String?
    private var spawnedPID: Int32?

    // Satu set file server dipakai CLI & app → attach silang tetap bisa.
    private let logURL = URL(fileURLWithPath: "/tmp/companion-serve.log")
    private let pidURL = URL(fileURLWithPath: "/tmp/companion-serve.pid")
    private let tokenURL = URL(fileURLWithPath: "/tmp/companion-serve.token")

    /// Mulai satu managed task dari prompt, dengan `cwd` = folder project yang
    /// dipilih user (PRD 48). Tidak ada auto-approval: approval/clarification
    /// hanya dikirim lewat API respond eksplisit.
    @discardableResult
    func start(prompt: String, cwd: String) -> Bool {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, runTask == nil else { return false }

        // T4.4 — koneksi run sebelumnya jangan dibiarkan menggantung; tiap task
        // memakai client + session baru. Server yang kita spawn TIDAK disentuh
        // (kepemilikannya berumur sepanjang app, lihat stopOwnedGatewayIfNeeded).
        closePreviousRun()
        lastActivity = nil
        decision = nil
        onAnswer?("")            // hasil task sebelumnya dibersihkan
        setApproval(nil)         // approval task lama tidak boleh ikut (PRD 52)
        setClarify(nil)          // idem untuk pertanyaan task lama (PRD 53)
        setState(.starting)
        runTask = Task { [weak self] in
            await self?.run(prompt: prompt, cwd: cwd)
        }
        return true
    }

    /// Minta runtime menghentikan task. State tetap `stopping` sampai event
    /// runtime berikutnya mengonfirmasi terminal state.
    func stop() async -> Bool {
        guard let managed, let sessionID else { return false }
        return await managed.stop(sessionID: sessionID)
    }

    /// Kirim approval yang dipilih user. Tidak ada jalur auto-respond dari UI.
    /// UI dikunci SEBELUM await (klik kedua tidak pernah sampai ke network),
    /// dan tetap terkunci walau pengiriman gagal: `ApprovalGate` sudah
    /// menandai request ini terpakai, jadi percobaan ulang pasti ditolak.
    func respondApproval(choice: ApprovalChoice) async -> Bool {
        guard let managed, let sessionID else { return false }
        guard pendingApproval != nil, !approvalAnswered else { return false }
        setApproval(pendingApproval, answered: true)
        return await managed.respondApproval(sessionID: sessionID, choice: choice)
    }

    /// Kirim jawaban untuk request clarification aktif. ManagedSession menolak
    /// request ID stale sebelum menyentuh gateway.
    func respondClarify(requestID: String, answer: String) async -> Bool {
        guard let managed, let sessionID else { return false }
        return await managed.respondClarify(sessionID: sessionID, requestID: requestID, answer: answer)
    }

    /// Jawab clarification yang sedang menunggu (PRD 53). Form dikunci SEBELUM
    /// await supaya klik ganda tidak mengirim dua jawaban. Kalau pengiriman
    /// GAGAL kuncinya dibuka lagi — beda dengan approval: `clarify.respond`
    /// membawa `request_id`, jadi percobaan ulang tidak bisa nyasar ke request
    /// lain (request lama ditolak server dengan error 4009).
    @discardableResult
    func respondClarify(answer: String) async -> Bool {
        guard let request = pendingClarify, !clarifyAnswered else { return false }
        setClarify(request, answered: true)
        let sent = await respondClarify(requestID: request.requestId, answer: answer)
        if !sent, pendingClarify == request { setClarify(request, answered: false) }
        return sent
    }

    /// Bagian quit yang sinkron (PRD 56). `plan.stopsTask` TIDAK diurus di sini:
    /// interrupt harus di-await sebelum app benar-benar keluar — lihat
    /// AppDelegate.applicationShouldTerminate.
    func shutdown(plan: QuitPlan = QuitPolicy.quitWithoutActiveTask) {
        runTask?.cancel()
        client?.close()
        // "Keep Hermes running": task hidup di dalam server yang kita spawn,
        // jadi servernya sengaja ditinggal hidup (PID/token file tetap ada →
        // launch berikutnya attach ke sana).
        if plan.stopsOwnedGateway { stopOwnedGatewayIfNeeded() }
    }

    /// Tutup client/session run sebelumnya (bukan gateway-nya).
    private func closePreviousRun() {
        client?.close()
        client = nil
        managed = nil
        sessionID = nil
    }

    private func run(prompt: String, cwd: String) async {
        guard let connection = GatewayLifecycle.attachOrSpawn(
            logURL: logURL, pidURL: pidURL, tokenURL: tokenURL
        ) else {
            setState(.error)
            bubble("! Gateway tidak tersedia — cek /tmp/companion-serve.log")
            runTask = nil
            return
        }
        guard let token = connection.token else {
            setState(.error)
            bubble("! Server jalan tapi bukan milik Companion")
            runTask = nil
            return
        }
        if let pid = connection.pid { spawnedPID = pid }

        let client = JSONRPCClient(url: URL(string: GatewayLifecycle.wsURL(token: token))!)
        self.client = client
        client.connect()
        let adapter = HermesAdapter(client: client)

        do {
            let sid = try await adapter.createSession(cwd: cwd)
            sessionID = sid
            let managed = ManagedSession(adapter: adapter)
            managed.autoRespondApproval = nil
            managed.onStateChange = { [weak self] state in
                Task { @MainActor in self?.setState(state) }
            }
            managed.onNeedsYouRequest = { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    self.decision = event.decisionText
                    if case .approvalRequest(let req) = event { self.setApproval(req) }
                    if case .clarifyRequest(let req) = event { self.setClarify(req) }
                    self.refreshBubble()
                }
            }
            managed.onActivity = { [weak self] text in
                Task { @MainActor in
                    self?.lastActivity = text
                    self?.refreshBubble()
                }
            }
            managed.onMessage = { [weak self] text in
                Task { @MainActor in self?.onAnswer?(text) }
            }
            self.managed = managed
            _ = await managed.run(sessionID: sid, prompt: prompt)
        } catch {
            setState(.error)
            bubble("! Session gagal: \(error)")
        }
        runTask = nil
    }

    private func setState(_ s: TaskState) {
        state = s
        if case .needsYou = s {} else {
            decision = nil
        }
        // PRD 52: begitu task lanjut/berhenti/gagal, approval lama STALE dan
        // tidak boleh ditawarkan lagi. Aman terhadap urutan callback: state
        // `needsYou` tidak pernah menghapus approval yang baru saja masuk.
        if case .needsYou(.approval) = s {} else if pendingApproval != nil {
            setApproval(nil)
        }
        // Aturan stale yang sama untuk clarification (PRD 53): begitu turn
        // lanjut/berhenti, request ID lama pasti ditolak server (4009).
        if case .needsYou(.clarification) = s {} else if pendingClarify != nil {
            setClarify(nil)
        }
        onStateChange?(s)
        refreshBubble()
    }

    /// Satu-satunya tempat approval pending berubah → UI selalu ikut.
    private func setApproval(_ request: ApprovalRequest?, answered: Bool = false) {
        pendingApproval = request
        approvalAnswered = answered
        onApprovalChange?(request, answered)
    }

    /// Satu-satunya tempat clarification pending berubah → UI selalu ikut.
    private func setClarify(_ request: ClarifyRequest?, answered: Bool = false) {
        pendingClarify = request
        clarifyAnswered = answered
        onClarifyChange?(request, answered)
    }

    private func refreshBubble() {
        var text = "\(state.glyph) \(state.statusLine)"
        if let d = decision {
            text += "\n\(d)"
        } else if let a = lastActivity, state == .working {
            text += "\n\(a)"
        }
        bubble(text)
    }

    private func bubble(_ text: String) { onBubbleChange?(text) }

    private func stopOwnedGatewayIfNeeded() {
        guard let pid = spawnedPID else { return }
        _ = GatewayLifecycle.stopPID(pid, grace: 3)
        try? FileManager.default.removeItem(at: pidURL)
        try? FileManager.default.removeItem(at: tokenURL)
        spawnedPID = nil
    }
}
