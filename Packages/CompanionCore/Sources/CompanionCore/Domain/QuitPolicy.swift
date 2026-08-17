import Foundation

// T4.7 — Quit aman (PRD 56). PRD menyerahkan "exact managed process ownership
// and detach behavior" ke TDD; keputusannya ada di sini supaya bisa di-test dan
// tidak tersebar di AppDelegate.
// Domain murni: tidak tahu apa pun soal protocol Hermes (D5).

/// Pilihan user di dialog quit saat task masih aktif (PRD 56).
public enum QuitChoice: Equatable, Sendable {
    case cancel          // tidak jadi quit
    case keepRunning     // Companion tutup, task Hermes dibiarkan jalan
    case stopAndQuit     // hentikan task dulu, baru tutup
}

/// Rencana yang harus dijalankan app untuk sebuah pilihan quit.
public struct QuitPlan: Equatable, Sendable {
    /// Kirim `session.interrupt` sebelum keluar.
    public let stopsTask: Bool
    /// Server yang KITA spawn ikut dimatikan (D2: hanya milik sendiri, lewat
    /// PID file — tidak pernah menyentuh server milik Hermes Desktop).
    public let stopsOwnedGateway: Bool
    /// App benar-benar keluar.
    public let quits: Bool

    public init(stopsTask: Bool, stopsOwnedGateway: Bool, quits: Bool) {
        self.stopsTask = stopsTask
        self.stopsOwnedGateway = stopsOwnedGateway
        self.quits = quits
    }
}

public enum QuitPolicy {
    /// Dialog quit hanya muncul kalau ada turn yang sedang berjalan (PRD 56).
    public static func needsConfirmation(state: TaskState) -> Bool { state.isActiveTurn }

    /// Aksi paling aman = tidak melakukan apa-apa (PRD 56 "Default safest action").
    public static let safestChoice: QuitChoice = .cancel

    /// Tidak ada task aktif: keluar langsung, tapi server yang kita spawn tetap
    /// dibersihkan supaya tidak meninggalkan proses yatim.
    public static let quitWithoutActiveTask = QuitPlan(stopsTask: false,
                                                       stopsOwnedGateway: true,
                                                       quits: true)

    public static func plan(for choice: QuitChoice) -> QuitPlan {
        switch choice {
        case .cancel:
            return QuitPlan(stopsTask: false, stopsOwnedGateway: false, quits: false)
        case .keepRunning:
            // Task hidup DI DALAM server yang kita spawn → servernya harus
            // ditinggal hidup juga, kalau tidak "keep running" bohong.
            // PID/token file sengaja dibiarkan: launch berikutnya attach ke sana.
            return QuitPlan(stopsTask: false, stopsOwnedGateway: false, quits: true)
        case .stopAndQuit:
            return QuitPlan(stopsTask: true, stopsOwnedGateway: true, quits: true)
        }
    }
}
