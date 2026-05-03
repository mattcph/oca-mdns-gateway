//
//  AppDelegate.swift
//  MdnsGatewayMenu
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if resignIfDuplicateInstance() {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        menuController = StatusMenuController()
    }

    /// Quit if another process with this bundle ID is already running; otherwise false so startup continues.
    private func resignIfDuplicateInstance() -> Bool {
        guard let bid = Bundle.main.bundleIdentifier else { return false }
        let pid = ProcessInfo.processInfo.processIdentifier
        let peers = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bid && $0.processIdentifier != pid
        }
        guard let existing = peers.first else { return false }
        existing.activate(options: [.activateIgnoringOtherApps])
        NSApp.terminate(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GatewayProcessController.shared.stopForTermination()
    }
}
