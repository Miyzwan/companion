import Testing
@testable import CompanionCore

// T4.7 — Quit aman (PRD 56). Companion TIDAK boleh membunuh task Hermes yang
// masih aktif hanya karena user menutup panelnya. Keputusannya domain murni
// supaya bisa di-test; AppDelegate hanya menjalankan rencananya.

@Test func quitTanpaTaskAktifTidakPerluBertanya() {
    for state: TaskState in [.idle, .success, .error, .disconnected] {
        #expect(QuitPolicy.needsConfirmation(state: state) == false)
    }
}

@Test func quitSaatTaskAktifSelaluBertanya() {
    // `stopping` ikut: stop sudah diminta tapi runtime belum mengonfirmasi
    // terminal state, jadi task masih mungkin di tengah operasi (PRD 55).
    for state: TaskState in [.starting, .working, .needsYou(.approval),
                             .needsYou(.clarification), .stopping] {
        #expect(QuitPolicy.needsConfirmation(state: state))
    }
}

@Test func pilihanTeramanAdalahCancel() {
    // PRD 56: default = Cancel — tidak mengubah apa pun.
    #expect(QuitPolicy.safestChoice == .cancel)
    let plan = QuitPolicy.plan(for: .cancel)
    #expect(plan.quits == false)
    #expect(plan.stopsTask == false)
    #expect(plan.stopsOwnedGateway == false)
}

@Test func keepRunningTidakMematikanServerMilikSendiri() {
    // Server yang kita spawn adalah TEMPAT task itu hidup. Mematikannya sama
    // saja membunuh task yang barusan user pilih untuk dibiarkan jalan (D2).
    let plan = QuitPolicy.plan(for: .keepRunning)
    #expect(plan.quits)
    #expect(plan.stopsTask == false)
    #expect(plan.stopsOwnedGateway == false)
}

@Test func stopAndQuitMenghentikanTaskLaluMembersihkanServer() {
    let plan = QuitPolicy.plan(for: .stopAndQuit)
    #expect(plan.quits)
    #expect(plan.stopsTask)
    #expect(plan.stopsOwnedGateway)
}

@Test func quitTanpaTaskAktifTetapMembersihkanServerMilikSendiri() {
    // Tidak ada yang dirugikan → jangan tinggalkan server yatim.
    let plan = QuitPolicy.quitWithoutActiveTask
    #expect(plan.quits)
    #expect(plan.stopsTask == false)
    #expect(plan.stopsOwnedGateway)
}
