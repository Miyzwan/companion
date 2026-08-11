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
        // Tidak ada WindowGroup — app M2 adalah panel melayang murni
        // (dikelola AppDelegate → FloatingPanelController).
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = FloatingPanelController()
        panelController?.show()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
