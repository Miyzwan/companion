import Foundation

// T4.4 — ControlPanelModel: sumber kebenaran ketersediaan kontrol compact
// control panel (PRD 46). Murni, tanpa AppKit — view di app hanya MERENDER
// model ini, tidak menyimpan aturan enable/disable sendiri.
// Domain murni: tidak tahu apa pun soal protocol Hermes (D5).

public struct ControlPanelModel: Equatable, Sendable {
    /// State task yang sedang berjalan (mirror TaskController).
    public var state: TaskState
    /// Isi field "What should Hermes do?" (PRD 47).
    public var prompt: String
    /// Folder project yang akan dipakai sebagai `cwd` session (PRD 48).
    public var projectPath: String

    public init(state: TaskState, prompt: String, projectPath: String) {
        self.state = state
        self.prompt = prompt
        self.projectPath = projectPath
    }

    /// Ada turn yang sedang berjalan → form task baru dikunci.
    /// success/error/disconnected TIDAK busy: ManagedSession.run() me-reset
    /// state machine tiap run, jadi task berikutnya boleh langsung dimulai.
    public var isBusy: Bool {
        switch state {
        case .starting, .working, .needsYou, .stopping:
            return true
        case .idle, .success, .error, .disconnected:
            return false
        }
    }

    /// Boleh menekan Start? Folder divalidasi lewat closure yang di-inject
    /// (pola HermesDetector.resolveBinary(in:exists:)) supaya tetap murni.
    public func canStart(directoryExists: (String) -> Bool) -> Bool {
        guard !isBusy else { return false }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return directoryExists(projectPath)
    }
}
