import Testing
@testable import CompanionCore

// T4.5b — Aturan tampil/sembunyi bubble status (PRD 44/45).
// Bubble adalah permukaan status DEFAULT, bukan sesuatu yang harus dinyalakan
// user tiap kali submit task. Aturannya hidup di paket karena app target tidak
// punya test target (pola yang sama dengan FloatingPosition & ControlPanelModel).

private func bubble(_ preference: BubblePreference,
                    _ state: TaskState,
                    panelOpen: Bool = false) -> BubbleVisibility {
    BubbleVisibility(preference: preference, state: state, controlPanelOpen: panelOpen)
}

@Test func bubbleMunculOtomatisTiapTaskBukanHanyaYangPertama() {
    // Regresi: flag sekali-pakai sisa spike M3 membuat bubble hanya terbuka
    // untuk task pertama; task berikutnya berjalan tanpa progres terlihat.
    for state: TaskState in [.starting, .working, .needsYou(.approval), .stopping, .success, .error] {
        #expect(bubble(.auto, state).isVisible, "state \(state) harus terlihat otomatis")
    }
}

@Test func bubbleSembunyiSaatIdle() {
    // PRD 44 Idle: "almost static" — karakter saja, tanpa bubble.
    #expect(bubble(.auto, .idle).isVisible == false)
}

@Test func bubbleSembunyiSelamaControlPanelTerbuka() {
    // Control panel sudah menampilkan status yang sama; keduanya tidak pernah
    // tampil bersamaan.
    #expect(bubble(.auto, .working, panelOpen: true).isVisible == false)
    #expect(bubble(.forcedOn, .working, panelOpen: true).isVisible == false)
}

@Test func bubbleKembaliTerlihatSetelahControlPanelDitutup() {
    #expect(bubble(.auto, .working, panelOpen: true).isVisible == false)
    #expect(bubble(.auto, .working, panelOpen: false).isVisible)
}

@Test func userMenutupBubbleTetapTertutupSampaiTaskBerikutnya() {
    let shown = bubble(.auto, .working)
    #expect(shown.toggled() == .forcedOff)                       // user menutup
    #expect(bubble(.forcedOff, .working).isVisible == false)
    #expect(bubble(.forcedOff, .needsYou(.approval)).isVisible == false)
    // Task baru mengembalikan perilaku otomatis — user tidak perlu ingat
    // menyalakan ulang.
    #expect(BubbleVisibility.preferenceForNewTask == .auto)
}

@Test func userMembukaBubbleWalauIdle() {
    let hidden = bubble(.auto, .idle)
    #expect(hidden.toggled() == .forcedOn)
    #expect(bubble(.forcedOn, .idle).isVisible)
}
