//
//  AppDelegate.swift
//  MdnsGatewayMenu
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuController = StatusMenuController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GatewayProcessController.shared.stopForTermination()
    }
}
