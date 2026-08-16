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
    /// Approval terakhir yang diterima controller. TIDAK otomatis berarti
    /// kontrolnya boleh tampil — lihat `showsApproval` (PRD 52).
    public var pendingApproval: ApprovalRequest?
    /// Keputusan approval sudah dikirim (PRD 51). Penjaga sebenarnya tetap
    /// `ApprovalGate` di ManagedSession; ini hanya lapisan UI.
    public var approvalAnswered: Bool

    public init(state: TaskState, prompt: String, projectPath: String,
                pendingApproval: ApprovalRequest? = nil,
                approvalAnswered: Bool = false) {
        self.state = state
        self.prompt = prompt
        self.projectPath = projectPath
        self.pendingApproval = pendingApproval
        self.approvalAnswered = approvalAnswered
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

    // ── T4.5 — kontrol approval (PRD 50/51/52) ──

    /// Blok Allow/Deny ditampilkan? Request lama yang state-nya sudah pindah
    /// (task lanjut, berhenti, gagal) adalah STALE → tidak boleh ditawarkan
    /// lagi (PRD 52), walau objeknya masih tersimpan di controller.
    public var showsApproval: Bool {
        guard pendingApproval != nil else { return false }
        guard case .needsYou(.approval) = state else { return false }
        return true
    }

    /// Tombol Allow/Deny bisa ditekan? Sekali dijawab → mati (PRD 51),
    /// tapi isinya tetap terbaca supaya user tahu apa yang dia setujui.
    public var approvalEnabled: Bool { showsApproval && !approvalAnswered }

    /// Perintah yang dimintakan izin (PRD 50 "Action").
    public var approvalAction: String? { showsApproval ? pendingApproval?.command : nil }

    /// Alasan dari gateway (PRD 50 "Context / reason").
    public var approvalReason: String? { showsApproval ? pendingApproval?.description : nil }

    /// Gateway mengizinkan keputusan disimpan permanen untuk pola ini.
    public var allowsPermanent: Bool { showsApproval && pendingApproval?.allowPermanent == true }

    /// Terjemahan checkbox "permanen" → choice protocol. Deny tidak pernah
    /// permanen, jadi tidak ada varian-nya di sini.
    public static func allowChoice(permanent: Bool) -> ApprovalChoice {
        permanent ? .always : .once
    }
}
