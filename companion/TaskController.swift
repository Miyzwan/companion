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

    private(set) var state: TaskState = .idle
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

    /// Mulai satu managed task dari prompt. Tidak ada auto-approval:
    /// approval/clarification hanya dikirim lewat API respond eksplisit.
    @discardableResult
    func start(prompt: String) -> Bool {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, runTask == nil else { return false }

        lastActivity = nil
        decision = nil
        setState(.starting)
        runTask = Task { [weak self] in
            await self?.run(prompt: prompt)
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
    func respondApproval(choice: ApprovalChoice) async -> Bool {
        guard let managed, let sessionID else { return false }
        return await managed.respondApproval(sessionID: sessionID, choice: choice)
    }

    /// Kirim jawaban untuk request clarification aktif. ManagedSession menolak
    /// request ID stale sebelum menyentuh gateway.
    func respondClarify(requestID: String, answer: String) async -> Bool {
        guard let managed, let sessionID else { return false }
        return await managed.respondClarify(sessionID: sessionID, requestID: requestID, answer: answer)
    }

    func shutdown() {
        runTask?.cancel()
        client?.close()
        stopOwnedGatewayIfNeeded()
    }

    private func run(prompt: String) async {
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
            let sid = try await adapter.createSession(
                cwd: FileManager.default.homeDirectoryForCurrentUser.path
            )
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
                    self.refreshBubble()
                }
            }
            managed.onActivity = { [weak self] text in
                Task { @MainActor in
                    self?.lastActivity = text
                    self?.refreshBubble()
                }
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
        onStateChange?(s)
        refreshBubble()
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
