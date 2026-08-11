import Foundation

// T1.1 — Task State Model (PRD section 25-34) + priority (section 35).
// Domain murni: tidak tahu apa-apa soal protocol Hermes (D5).

/// Subtype `Needs You` (PRD section 29).
public enum NeedsYouCase: String, Equatable, Sendable {
    case approval
    case clarification
    case sudo
    case secret
    case other
}

/// State machine task managed (PRD section 25).
public enum TaskState: Equatable, Sendable {
    case idle                 // Hermes siap, tidak ada managed task (26)
    case starting             // task diterima, belum eksekusi (27)
    case working              // agent aktif mengerjakan (28)
    case needsYou(NeedsYouCase) // butuh manusia via protocol event (29)
    case success              // selesai normal (31)
    case error                // gagal / failure meaningful (32)
    case stopping             // user minta stop, belum konfirmasi (33)
    case disconnected         // koneksi putus (34)
}

/// Transisi legal antar state. Transisi ilegal ditolak (return false).
public struct TaskStateMachine: Sendable {
    public private(set) var state: TaskState

    public init(initial: TaskState = .idle) {
        self.state = initial
    }

    /// Coba pindah state. Kalau ilegal → false, state tidak berubah.
    @discardableResult
    public mutating func transition(to next: TaskState) -> Bool {
        guard Self.isLegal(from: state, to: next) else { return false }
        state = next
        return true
    }

    public static func isLegal(from current: TaskState, to next: TaskState) -> Bool {
        switch (current, next) {
        // ── dari Idle ──
        case (.idle, .starting): return true
        case (.idle, .disconnected): return true

        // ── dari Starting ──
        case (.starting, .working): return true
        case (.starting, .error): return true
        case (.starting, .disconnected): return true

        // ── dari Working ──
        case (.working, .needsYou): return true
        case (.working, .success): return true
        case (.working, .error): return true
        case (.working, .stopping): return true
        case (.working, .disconnected): return true

        // ── dari NeedsYou ──
        // PRD 50: sukses TIDAK boleh terjadi selama masih nunggu jawaban.
        // Setelah respond, agent benar-benar lanjut → working.
        case (.needsYou, .working): return true
        case (.needsYou, .error): return true
        case (.needsYou, .stopping): return true
        case (.needsYou, .disconnected): return true

        // ── dari Stopping ──
        case (.stopping, .success): return true   // runtime konfirmasi terminal
        case (.stopping, .error): return true
        case (.stopping, .disconnected): return true

        // ── dari Success (terminal) ──
        case (.success, .idle): return true       // reset buat task berikutnya
        case (.success, .disconnected): return true

        // ── dari Error ──
        case (.error, .idle): return true
        case (.error, .disconnected): return true

        // ── dari Disconnected (M5: recovery penuh; M1: fresh) ──
        case (.disconnected, .idle): return true

        default: return false
        }
    }

    /// Priority untuk render (PRD section 35): NeedsYou > Error > Working
    /// > Starting/Stopping > Success > Idle.
    public static func priority(_ s: TaskState) -> Int {
        switch s {
        case .needsYou: return 6
        case .error: return 5
        case .working: return 4
        case .starting, .stopping: return 3
        case .success: return 2
        case .idle: return 1
        case .disconnected: return 0
        }
    }
}
