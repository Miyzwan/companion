import Foundation

// T1.4 — ApprovalGate: exactly-once (PRD 51) + stale (PRD 52).
// Karena `approval.request` TIDAK membawa request_id (server.py, §11.1),
// satu-satunya tempat memastikan "dijawab tepat satu kali" ada di client.
// FIFO server me-resolve approval paling tua; double-send berisiko men-resolve
// approval BARU. Gate ini mengunci respons sampai ada `approval.request` baru.
public struct ApprovalGate: Sendable {
    /// Approval yang sedang menunggu keputusan (untuk UI/audit).
    public private(set) var pendingApproval: ApprovalRequest?
    /// Sudah dijawab → terkunci sampai ada request baru (exactly-once).
    public private(set) var consumed = false

    public init() {}

    /// Boleh mengirim keputusan sekarang?
    public var canRespond: Bool {
        pendingApproval != nil && !consumed
    }

    /// Terima `approval.request` baru dari gateway. Mengganti pending lama.
    public mutating func register(_ request: ApprovalRequest) {
        pendingApproval = request
        consumed = false
    }

    /// Tandai satu keputusan dikirim. Return false kalau tidak boleh
    /// (tidak ada pending / sudah dijawab / sudah invalidate) → caller
    /// JANGAN mengirim ke network. (PRD 51: double click, retry, replay.)
    public mutating func respond(_ choice: ApprovalChoice) -> Bool {
        guard canRespond else { return false }
        consumed = true
        return true
    }

    /// Invalidasi (PRD 52): task berhenti / session berubah / terminal state.
    /// UI tidak boleh lagi menawarkan Allow/Deny sampai approval baru.
    public mutating func invalidate() {
        pendingApproval = nil
        consumed = false
    }
}