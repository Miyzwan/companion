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
    private var spawnedPID: Int32?

    // Satu set file server dipakai CLI & app → attach silang tetap bisa.
    private let logURL = URL(fileURLWithPath: "/tmp/companion-serve.log")
    private let pidURL = URL(fileURLWithPath: "/tmp/companion-serve.pid")
    private let tokenURL = URL(fileURLWithPath: "/tmp/companion-serve.token")

    func shutdown() {
        client?.close()
        if let pid = spawnedPID {
            _ = GatewayLifecycle.stopPID(pid, grace: 3)
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: tokenURL)
        }
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
