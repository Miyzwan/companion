//
//  companionApp.swift
//  companion
//
//  Created by Dimas Dwi Ismaunnizam on 12/08/26.
//

import SwiftUI

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

    func applicationWillTerminate(_ notification: Notification) {
        taskController?.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
