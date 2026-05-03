import AppKit
import SwiftUI

final class PreferencesViewModel: ObservableObject {
    @Published var port: String = ""
    @Published var token: String = ""
    @Published var launchAtLogin: Bool = false

    func reload() {
        let s = GatewaySettings.load()
        port = String(s.port)
        token = s.bearerToken ?? ""
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func save() {
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portInt = Int(trimmedPort).flatMap { (1024 ... 65_535).contains($0) ? $0 : nil } ?? GatewaySettings.default.port
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        GatewaySettings(
            bindHost: "127.0.0.1",
            port: portInt,
            bearerToken: trimmedToken.isEmpty ? nil : trimmedToken
        ).save()
    }
}

final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel = PreferencesViewModel()

    func show() {
        viewModel.reload()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingView(rootView: PreferencesView(viewModel: viewModel))
        let size = host.fittingSize
        let w = max(460, size.width)
        let h = max(300, size.height)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "OCA mDNS Gateway"
        win.contentView = host
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.save()
    }
}
