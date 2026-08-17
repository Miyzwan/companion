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
    /// Clarification terakhir yang diterima controller (PRD 53). Sama seperti
    /// approval: disimpan bukan berarti boleh ditawarkan — lihat `showsClarify`.
    public var pendingClarify: ClarifyRequest?
    /// Jawaban clarification sudah dikirim → form mati sampai request berikutnya.
    public var clarifyAnswered: Bool
    /// Prompt task yang sedang berjalan — jadi judul panel (PRD 46).
    public var taskTitle: String
    /// Aktivitas terakhir dari runtime (`status.update`), PRD 46 "Current".
    public var currentActivity: String?
    /// Langkah yang sudah selesai, URUTAN LAMA → BARU (PRD 46 "Recent").
    public var recentSteps: [String]
    /// Umur task berjalan dalam detik; jam-nya milik app, bukan model.
    public var elapsedSeconds: Int

    public init(state: TaskState, prompt: String, projectPath: String,
                pendingApproval: ApprovalRequest? = nil,
                approvalAnswered: Bool = false,
                pendingClarify: ClarifyRequest? = nil,
                clarifyAnswered: Bool = false,
                taskTitle: String = "",
                currentActivity: String? = nil,
                recentSteps: [String] = [],
                elapsedSeconds: Int = 0) {
        self.state = state
        self.prompt = prompt
        self.projectPath = projectPath
        self.pendingApproval = pendingApproval
        self.approvalAnswered = approvalAnswered
        self.pendingClarify = pendingClarify
        self.clarifyAnswered = clarifyAnswered
        self.taskTitle = taskTitle
        self.currentActivity = currentActivity
        self.recentSteps = recentSteps
        self.elapsedSeconds = elapsedSeconds
    }

    // ── T4.8 — layout per-state (PRD 46) ──

    /// Panel punya dua wajah: form task baru (PRD 47) dan laporan task yang
    /// sedang berjalan (PRD 46). Bukan dua panel berbeda — satu view yang
    /// menyembunyikan seksi yang tidak relevan.
    public enum PanelMode: Equatable, Sendable {
        case newTask
        case runningTask
    }

    public var mode: PanelMode { state.isActiveTurn ? .runningTask : .newTask }

    /// Input task + project + Start. Disembunyikan (bukan sekadar di-disable)
    /// saat task jalan supaya panel tetap sekecil PRD 43.
    public var showsTaskForm: Bool { mode == .newTask }

    /// Blok Current/Recent hanya bermakna selama task berjalan.
    public var showsProgress: Bool { mode == .runningTask }

    /// Judul panel: task yang sedang jalan, atau judul form saat idle.
    public var panelTitle: String {
        guard showsProgress else { return "New Hermes Task" }
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Hermes Task" : title
    }

    /// Baris status: glyph + kalimat state, plus durasi selama task berjalan
    /// (PRD 46 "● Working · 08:21").
    public var statusText: String {
        let base = "\(state.glyph) \(state.statusLine)"
        guard showsProgress else { return base }
        return "\(base) · \(Self.elapsedText(elapsedSeconds))"
    }

    /// Aktivitas yang sedang berlangsung; nil kalau tidak ada / task selesai.
    public var currentActivityText: String? {
        guard showsProgress else { return nil }
        guard let text = currentActivity, !text.isEmpty else { return nil }
        return text
    }

    /// Langkah terakhir dulu, dibatasi `maxRecentSteps` — panel melaporkan
    /// state, bukan menjadi mini-terminal (PRD 45).
    public static let maxRecentSteps = 3
    public var visibleRecentSteps: [String] {
        guard showsProgress else { return [] }
        return recentSteps.suffix(Self.maxRecentSteps).reversed()
    }

    /// mm:ss, naik ke h:mm:ss setelah satu jam. Detik negatif (clock mundur)
    /// dianggap nol, bukan tampil aneh.
    public static func elapsedText(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Satu baris "Recent" (PRD 46). Durasi hanya ditulis kalau runtime
    /// memang mengirimnya.
    public static func stepText(name: String, duration: Double?) -> String {
        guard let duration else { return "✓ \(name)" }
        return "✓ \(name) · \(String(format: "%.1f", duration))s"
    }

    /// Ada turn yang sedang berjalan → form task baru dikunci.
    /// success/error/disconnected TIDAK busy: ManagedSession.run() me-reset
    /// state machine tiap run, jadi task berikutnya boleh langsung dimulai.
    public var isBusy: Bool { state.isActiveTurn }

    /// Boleh menekan Stop (PRD 55)? Diturunkan dari state machine, bukan daftar
    /// state terpisah: kalau `stopping` tidak legal dari sini, `session.interrupt`
    /// pasti ditolak dan tombolnya cuma bohong.
    public var canStop: Bool { TaskStateMachine.isLegal(from: state, to: .stopping) }

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

    // ── T4.6 — kontrol clarification (PRD 53) ──

    /// Blok pertanyaan + jawaban ditampilkan? Aturannya sama dengan approval:
    /// request yang state-nya sudah pindah berarti STALE (PRD 52) — server pun
    /// menolak request ID lama dengan error 4009.
    public var showsClarify: Bool {
        guard pendingClarify != nil else { return false }
        guard case .needsYou(.clarification) = state else { return false }
        return true
    }

    /// Form jawaban masih bisa dipakai? Sekali terkirim → mati, tapi pertanyaan
    /// tetap terbaca supaya user tahu apa yang barusan dia jawab.
    public var clarifyEnabled: Bool { showsClarify && !clarifyAnswered }

    /// Pertanyaan dari agent (PRD 53).
    public var clarifyQuestion: String? { showsClarify ? pendingClarify?.question : nil }

    /// Pilihan siap-pakai. Boleh kosong — clarify tanpa pilihan tetap sah dan
    /// dijawab lewat teks bebas ("Or type a reply…").
    public var clarifyChoices: [String] { showsClarify ? (pendingClarify?.choices ?? []) : [] }

    /// Jawaban yang akan dikirim, atau nil kalau belum ada yang bisa dikirim.
    /// ATURAN: teks ketikan MENANG atas pilihan — user yang mengetik sedang
    /// menyatakan maksud yang lebih spesifik daripada radio yang tersorot.
    public func clarifyAnswer(selectedChoice: String?, reply: String) -> String? {
        guard clarifyEnabled else { return nil }
        let typed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        guard let choice = selectedChoice, !choice.isEmpty else { return nil }
        return choice
    }

    /// Tombol Send bisa ditekan? (tidak pernah mengirim jawaban kosong)
    public func canSendClarify(selectedChoice: String?, reply: String) -> Bool {
        clarifyAnswer(selectedChoice: selectedChoice, reply: reply) != nil
    }
}
