//
//  companionApp.swift
//  companion
//
//  Created by Dimas Dwi Ismaunnizam on 12/08/26.
//

import SwiftUI
import CompanionCore

@main
struct companionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Tidak ada WindowGroup — app = panel melayang murni
        // (dikelola AppDelegate → FloatingPanelController + TaskController).
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var taskController: TaskController?
    /// Rencana quit yang dipilih user; dipakai `applicationWillTerminate`
    /// untuk memutuskan apakah server yang kita spawn ikut dimatikan.
    private var quitPlan: QuitPlan = QuitPolicy.quitWithoutActiveTask

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = FloatingPanelController()
        panelController = panel
        let controller = TaskController()
        taskController = controller
        // show() yang membangun content view (karakter/bubble/control panel),
        // jadi bind() WAJIB sesudahnya — sebelum itu control panel belum ada.
        panel.show()
        panel.bind(controller)
    }

    /// T4.7 — quit aman (PRD 56). SEMUA jalur quit lewat sini (menu klik-kanan
    /// karakter, `NSApp.terminate`, logout), jadi task aktif tidak pernah
    /// terbunuh tanpa sengaja.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = taskController,
              QuitPolicy.needsConfirmation(state: controller.state) else {
            quitPlan = QuitPolicy.quitWithoutActiveTask
            return .terminateNow
        }
        let plan = QuitPolicy.plan(for: Dialogs.askQuit())
        quitPlan = plan
        guard plan.quits else { return .terminateCancel }
        guard plan.stopsTask else { return .terminateNow }
        // Interrupt harus benar-benar terkirim sebelum proses mati — kalau app
        // keluar duluan, "stop task" cuma berarti kita berhenti melihatnya.
        Task { @MainActor in
            await Self.stop(controller, timeout: Self.quitStopTimeout)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Gateway yang menggantung tidak boleh membuat app mustahil ditutup:
    /// interrupt diberi batas waktu, lewat dari itu quit tetap dilanjutkan.
    private static let quitStopTimeout: TimeInterval = 3

    private static func stop(_ controller: TaskController, timeout: TimeInterval) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await controller.stop() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskController?.shutdown(plan: quitPlan)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
