//
//  TaskController.swift
//  companion
//
//  Created by Dimas Dwi Ismaunnizam on 12/08/26.
//
//  M3 — Floating Companion (PRD 80): jembatan state Hermes → floating UI.
//  Owns: lifecycle gateway (attach/spawn D2), session, ManagedSession loop.
//  Output: bubble text + state (dikonsumsi FloatingPanelController).

import Foundation
import AppKit
import CompanionCore

@MainActor
final class TaskController {
    /// Bubble text lengkap (glif + status + aktivitas/keputusan).
    var onBubbleChange: ((String) -> Void)?
    /// State berubah (panel bisa pakai untuk visual karakter nanti).
    var onStateChange: ((TaskState) -> Void)?

    private(set) var state: TaskState = .idle
    private var lastActivity: String?
    private var decision: String?

    private var client: JSONRPCClient?
    private var managed: ManagedSession?
    private var runTask: Task<Void, Never>?
    private var spawnedPID: Int32?

    // Satu set file server dipakai CLI & app → attach silang tetap bisa.
    private let logURL = URL(fileURLWithPath: "/tmp/companion-serve.log")
    private let pidURL = URL(fileURLWithPath: "/tmp/companion-serve.pid")
    private let tokenURL = URL(fileURLWithPath: "/tmp/companion-serve.token")

    /// Prompt demo M3: memicu approval nyata (rm /tmp → "delete in root path").
    static let demoPrompt = "Buat file hello-companion-m3.txt di folder /tmp berisi \"hello m3\", lalu hapus file itu"

    func startDemoTask() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.runDemo()
        }
    }

    func shutdown() {
        runTask?.cancel()
        client?.close()
        if let pid = spawnedPID {
            _ = GatewayLifecycle.stopPID(pid, grace: 3)
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: tokenURL)
        }
    }

    private func runDemo() async {
        bubble("◌ Starting…")
        guard let r = GatewayLifecycle.attachOrSpawn(logURL: logURL, pidURL: pidURL, tokenURL: tokenURL) else {
            setState(.error); bubble("! Gateway tidak tersedia — cek /tmp/companion-serve.log")
            return
        }
        if r.pid == nil && r.token == nil {
            setState(.error); bubble("! Server jalan tapi bukan milik kita (serve-stop dulu)")
            return
        }
        spawnedPID = r.pid
        let client = JSONRPCClient(url: URL(string: GatewayLifecycle.wsURL(token: r.token!))!)
        self.client = client
        client.connect()
        let adapter = HermesAdapter(client: client)

        let sid: String
        do {
            sid = try await adapter.createSession(cwd: FileManager.default.homeDirectoryForCurrentUser.path)
        } catch {
            setState(.error); bubble("! session.create gagal: \(error)")
            return
        }

        let managed = ManagedSession(adapter: adapter)
        managed.autoRespondApproval = .once   // spike: auto-approve; keputusan UI = M4
        managed.onStateChange = { [weak self] s in
            Task { @MainActor in self?.setState(s) }
        }
        managed.onNeedsYouRequest = { [weak self] ev in
            Task { @MainActor in
                self?.decision = ev.decisionText
                self?.refreshBubble()
            }
        }
        managed.onActivity = { [weak self] text in
            Task { @MainActor in
                self?.lastActivity = text
                self?.refreshBubble()
            }
        }
        self.managed = managed
        let final = await managed.run(sessionID: sid, prompt: Self.demoPrompt)
        _ = final
    }

    private func setState(_ s: TaskState) {
        state = s
        if case .needsYou = s {} else { decision = nil }   // keputusan hanya relevan saat NeedsYou
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
}
