import Foundation

// T4.5b — Kapan bubble status terlihat (PRD 44/45).
// Bubble adalah permukaan status DEFAULT karakter, bukan opsi yang harus
// dinyalakan user tiap kali submit task. Murni, tanpa AppKit — panel hanya
// menerapkan hasilnya.

/// Preferensi user terhadap bubble. `auto` = biarkan state yang menentukan.
public enum BubblePreference: Equatable, Sendable {
    case auto
    case forcedOn      // user membuka lewat menu klik-kanan
    case forcedOff     // user menutup lewat menu klik-kanan
}

public struct BubbleVisibility: Equatable, Sendable {
    public var preference: BubblePreference
    public var state: TaskState
    /// Control panel sedang terbuka — panel sudah menampilkan status yang sama,
    /// jadi keduanya tidak pernah tampil bersamaan.
    public var controlPanelOpen: Bool

    public init(preference: BubblePreference, state: TaskState, controlPanelOpen: Bool) {
        self.preference = preference
        self.state = state
        self.controlPanelOpen = controlPanelOpen
    }

    public var isVisible: Bool {
        guard !controlPanelOpen else { return false }
        switch preference {
        case .forcedOff: return false
        case .forcedOn:  return true
        // PRD 44: Idle "almost static" (karakter saja); state lain punya sesuatu
        // untuk dilaporkan → tampil sendiri, setiap task.
        case .auto:      return state != .idle
        }
    }

    /// Hasil klik "Toggle Bubble": kebalikan dari yang terlihat SEKARANG.
    public func toggled() -> BubblePreference {
        isVisible ? .forcedOff : .forcedOn
    }

    /// Task baru mengembalikan perilaku otomatis — keputusan user untuk menutup
    /// bubble berlaku untuk task itu saja, tidak seumur hidup app.
    public static let preferenceForNewTask: BubblePreference = .auto
}
