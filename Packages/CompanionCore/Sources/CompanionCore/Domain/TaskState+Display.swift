import Foundation

// T3.1 — Presentasi TaskState untuk floating UI (PRD 44/80) + teks keputusan.
// Murni → mudah di-test. Karakter menerjemahkan state → glif + baris bubble.

public extension TaskState {
    /// Glif placeholder karakter (PRD 41: ◉ ● ⚠ ✓ ! ○).
    var glyph: String {
        switch self {
        case .idle: return "◉"
        case .starting, .stopping, .disconnected: return "○"
        case .working: return "●"
        case .needsYou: return "⚠"
        case .success: return "✓"
        case .error: return "!"
        }
    }

    /// Baris status untuk bubble (PRD 44 "Ready when you are.", §80 Working/Needs You).
    var statusLine: String {
        switch self {
        case .idle:           return "Ready when you are."
        case .starting:       return "Starting…"
        case .working:        return "Working"
        case .needsYou(let c):
            switch c {
            case .approval:      return "Needs your approval"
            case .clarification: return "Needs your input"
            case .sudo:          return "Needs sudo"
            case .secret:        return "Needs a secret"
            case .other:         return "Needs you"
            }
        case .success:        return "Done"
        case .error:          return "Problem"
        case .stopping:       return "Stopping…"
        case .disconnected:   return "Disconnected"
        }
    }
}

public extension TaskEvent {
    /// Teks keputusan yang ditampilkan bubble saat NeedsYou
    /// (perintah approval / pertanyaan clarify). Event lain → nil.
    var decisionText: String? {
        switch self {
        case .approvalRequest(let r): return r.command
        case .clarifyRequest(let r):  return r.question
        default: return nil
        }
    }
}