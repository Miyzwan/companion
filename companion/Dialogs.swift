//
//  Dialogs.swift
//  companion
//
//  M4 Task 7 — konfirmasi Stop Task (PRD 55) dan quit aman (PRD 56).
//  App `.accessory` tidak pernah "aktif", jadi alert HARUS didahului
//  `NSApp.activate()` — kalau tidak, dialognya muncul di belakang app yang
//  sedang dipakai dan user tidak pernah melihatnya (pola yang sama dengan
//  NSOpenPanel di FloatingPanel.chooseProject).
//  Tombol PERTAMA sebuah NSAlert = tombol default (Return), jadi urutannya
//  selalu dimulai dari aksi paling aman.
//

import AppKit
import CompanionCore

enum Dialogs {
    /// PRD 55. Return = Cancel: menghentikan task tidak boleh terjadi hanya
    /// karena refleks menekan Enter.
    static func confirmStopTask() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop Hermes?"
        alert.informativeText = "Hermes may currently be in the middle of an operation."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Stop")
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// PRD 56. Tiga pilihan, default = Cancel (`QuitPolicy.safestChoice`).
    /// Semua respons lain (mis. alert ditutup paksa) juga jatuh ke pilihan aman.
    static func askQuit() -> QuitChoice {
        let alert = NSAlert()
        alert.messageText = "Hermes is still working."
        alert.informativeText = "Quitting Companion does not have to stop the task."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Keep Hermes running")
        alert.addButton(withTitle: "Stop task and quit")
        NSApp.activate()
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .keepRunning
        case .alertThirdButtonReturn: return .stopAndQuit
        default: return QuitPolicy.safestChoice
        }
    }
}
