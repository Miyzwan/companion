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
