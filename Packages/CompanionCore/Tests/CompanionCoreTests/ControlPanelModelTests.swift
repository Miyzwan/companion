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
