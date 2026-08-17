import Testing
@testable import CompanionCore

// T4.4 — Model murni compact control panel (PRD 46/47/48).
// App target TIDAK punya test target, jadi aturan enable/disable kontrol hidup
// di paket ini supaya bisa di-test — pola yang sama dengan FloatingPosition
// (geometri panel) dan TaskState+Display (teks bubble).

private let existingFolder = "/Users/dev/Projects/app"

/// Filesystem palsu: hanya satu folder yang "ada" (PRD 48 project context).
private func folderExists(_ path: String) -> Bool { path == existingFolder }

@Test func canStartRequiresNonEmptyPrompt() {
    let model = ControlPanelModel(state: .idle, prompt: "   \n ", projectPath: existingFolder)
    #expect(model.canStart(directoryExists: folderExists) == false)
}

@Test func canStartRequiresExistingProjectFolder() {
    let model = ControlPanelModel(state: .idle, prompt: "rapikan README", projectPath: "/folder/tidak/ada")
    #expect(model.canStart(directoryExists: folderExists) == false)
}

@Test func canStartWhenPromptAndProjectFolderValid() {
    let model = ControlPanelModel(state: .idle, prompt: "rapikan README", projectPath: existingFolder)
    #expect(model.canStart(directoryExists: folderExists))
}

@Test func canStartBlockedWhileTaskMasihJalan() {
    for state: TaskState in [.starting, .working, .needsYou(.approval), .needsYou(.clarification), .stopping] {
        let model = ControlPanelModel(state: state, prompt: "rapikan README", projectPath: existingFolder)
        #expect(model.isBusy)
        #expect(model.canStart(directoryExists: folderExists) == false)
    }
}

@Test func canStartLagiSetelahStateTerminal() {
    // Success/error/disconnected = tidak ada turn berjalan → boleh mulai task baru
    // (ManagedSession.run() me-reset state machine tiap run).
    for state: TaskState in [.idle, .success, .error, .disconnected] {
        let model = ControlPanelModel(state: state, prompt: "rapikan README", projectPath: existingFolder)
        #expect(model.isBusy == false)
        #expect(model.canStart(directoryExists: folderExists))
    }
}

// ── T4.5 — kontrol approval Allow/Deny (PRD 50/51/52) ──

private func approval(allowPermanent: Bool = false) -> ApprovalRequest {
    ApprovalRequest(command: "rm -rf /tmp/build",
                    patternKey: "shell:rm",
                    patternKeys: ["shell:rm"],
                    description: "Membersihkan folder build sebelum rebuild",
                    allowPermanent: allowPermanent)
}

private func panel(state: TaskState,
                   pendingApproval: ApprovalRequest?,
                   approvalAnswered: Bool = false) -> ControlPanelModel {
    ControlPanelModel(state: state, prompt: "", projectPath: existingFolder,
                      pendingApproval: pendingApproval, approvalAnswered: approvalAnswered)
}

@Test func approvalMenampilkanActionDanReasonSaatMenungguKeputusan() {
    // PRD 50: review harus menunjukkan action + context SEBELUM response.
    let model = panel(state: .needsYou(.approval), pendingApproval: approval())
    #expect(model.showsApproval)
    #expect(model.approvalEnabled)
    #expect(model.approvalAction == "rm -rf /tmp/build")
    #expect(model.approvalReason == "Membersihkan folder build sebelum rebuild")
}

@Test func approvalNonInteraktifSetelahDijawab() {
    // PRD 51: klik kedua tidak boleh mengirim apa pun — tapi isinya tetap
    // terbaca supaya user tahu apa yang barusan dia setujui.
    let model = panel(state: .needsYou(.approval), pendingApproval: approval(), approvalAnswered: true)
    #expect(model.showsApproval)
    #expect(model.approvalEnabled == false)
    #expect(model.approvalAction == "rm -rf /tmp/build")
}

@Test func approvalStaleSaatStatePindahDariNeedsYou() {
    // PRD 52: task lanjut/berhenti/gagal → UI TIDAK boleh menawarkan Allow/Deny,
    // walau objek request lama masih tersimpan di controller.
    for state: TaskState in [.working, .stopping, .success, .error, .disconnected, .idle] {
        let model = panel(state: state, pendingApproval: approval())
        #expect(model.showsApproval == false)
        #expect(model.approvalEnabled == false)
        #expect(model.approvalAction == nil)
    }
}

@Test func approvalTidakMunculUntukNeedsYouJenisLain() {
    // Clarification punya kontrolnya sendiri (T4.6) — jangan tawarkan Allow/Deny.
    let model = panel(state: .needsYou(.clarification), pendingApproval: approval())
    #expect(model.showsApproval == false)
}

@Test func approvalTanpaPendingRequestTidakPernahAktif() {
    let model = panel(state: .needsYou(.approval), pendingApproval: nil)
    #expect(model.showsApproval == false)
    #expect(model.approvalEnabled == false)
}

@Test func opsiPermanentHanyaSaatRequestMengizinkan() {
    #expect(panel(state: .needsYou(.approval), pendingApproval: approval(allowPermanent: true)).allowsPermanent)
    #expect(panel(state: .needsYou(.approval), pendingApproval: approval(allowPermanent: false)).allowsPermanent == false)
}

@Test func choiceAllowIkutOpsiPermanent() {
    // Checkbox menentukan scope izin; Deny tidak pernah permanen.
    #expect(ControlPanelModel.allowChoice(permanent: false) == .once)
    #expect(ControlPanelModel.allowChoice(permanent: true) == .always)
}

// ── T4.7 — Stop Task (PRD 55) ──

@Test func stopHanyaSaatRuntimeMemangBisaDihentikan() {
    // Ditawarkan hanya kalau transisi ke `stopping` legal — kalau tidak,
    // tombolnya bohong: `session.interrupt` akan ditolak state machine.
    // `starting` sengaja TIDAK termasuk (belum ada turn yang berjalan).
    for state: TaskState in [.working, .needsYou(.approval), .needsYou(.clarification)] {
        #expect(panel(state: state, pendingApproval: nil).canStop)
    }
    for state: TaskState in [.idle, .starting, .stopping, .success, .error, .disconnected] {
        #expect(panel(state: state, pendingApproval: nil).canStop == false)
    }
}

// ── T4.6 — kontrol clarification (PRD 53) ──

private func clarify(choices: [String] = ["Keep existing approach", "Replace implementation"]) -> ClarifyRequest {
    ClarifyRequest(requestId: "req-1",
                   question: "Which implementation should I use?",
                   choices: choices)
}

private func clarifyPanel(state: TaskState,
                          pendingClarify: ClarifyRequest?,
                          clarifyAnswered: Bool = false) -> ControlPanelModel {
    ControlPanelModel(state: state, prompt: "", projectPath: existingFolder,
                      pendingClarify: pendingClarify, clarifyAnswered: clarifyAnswered)
}

@Test func clarifyMenampilkanPertanyaanDanPilihanSaatMenungguJawaban() {
    // PRD 53: pertanyaan + pilihan harus terbaca sebelum user menjawab.
    let model = clarifyPanel(state: .needsYou(.clarification), pendingClarify: clarify())
    #expect(model.showsClarify)
    #expect(model.clarifyEnabled)
    #expect(model.clarifyQuestion == "Which implementation should I use?")
    #expect(model.clarifyChoices == ["Keep existing approach", "Replace implementation"])
}

@Test func clarifyStaleSaatStatePindahDariNeedsYouClarification() {
    // Request lama tidak boleh ditawarkan lagi; server juga menolaknya (4009).
    for state: TaskState in [.working, .stopping, .success, .error, .disconnected, .idle,
                             .needsYou(.approval)] {
        let model = clarifyPanel(state: state, pendingClarify: clarify())
        #expect(model.showsClarify == false)
        #expect(model.clarifyEnabled == false)
        #expect(model.clarifyQuestion == nil)
        #expect(model.clarifyChoices.isEmpty)
    }
}

@Test func clarifyNonInteraktifSetelahDijawab() {
    let model = clarifyPanel(state: .needsYou(.clarification), pendingClarify: clarify(),
                             clarifyAnswered: true)
    #expect(model.showsClarify)                 // pertanyaan tetap terbaca
    #expect(model.clarifyEnabled == false)
    #expect(model.clarifyAnswer(selectedChoice: "Replace implementation", reply: "") == nil)
}

@Test func clarifyTanpaPendingRequestTidakPernahAktif() {
    let model = clarifyPanel(state: .needsYou(.clarification), pendingClarify: nil)
    #expect(model.showsClarify == false)
    #expect(model.clarifyEnabled == false)
}

@Test func jawabanKetikanMenangAtasPilihan() {
    // Teks bebas = maksud yang lebih spesifik daripada radio yang tersorot.
    let model = clarifyPanel(state: .needsYou(.clarification), pendingClarify: clarify())
    #expect(model.clarifyAnswer(selectedChoice: "Keep existing approach",
                                reply: "  pakai pendekatan ketiga  ") == "pakai pendekatan ketiga")
    #expect(model.clarifyAnswer(selectedChoice: "Keep existing approach", reply: "   ")
            == "Keep existing approach")
}

@Test func clarifyTanpaPilihanTetapBisaDijawabTeksBebas() {
    // Beberapa clarify.request datang tanpa `choices` — form teks harus cukup.
    let model = clarifyPanel(state: .needsYou(.clarification), pendingClarify: clarify(choices: []))
    #expect(model.clarifyChoices.isEmpty)
    #expect(model.canSendClarify(selectedChoice: nil, reply: "pakai folder A"))
    #expect(model.clarifyAnswer(selectedChoice: nil, reply: "pakai folder A") == "pakai folder A")
}

@Test func sendMatiSaatBelumAdaJawaban() {
    let model = clarifyPanel(state: .needsYou(.clarification), pendingClarify: clarify())
    #expect(model.canSendClarify(selectedChoice: nil, reply: "") == false)
    #expect(model.canSendClarify(selectedChoice: nil, reply: "\n  ") == false)
    #expect(model.clarifyAnswer(selectedChoice: nil, reply: "") == nil)
}
