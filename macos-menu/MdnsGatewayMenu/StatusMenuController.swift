//
//  StatusMenuController.swift
//  MdnsGatewayMenu
//

import AppKit
import Combine

final class StatusMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let gateway = GatewayProcessController.shared
    private let preferences = PreferencesWindowController()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        super.init()
        configureItem()
        statusItem.menu = menu
        rebuildMenu()

        gateway.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateIcon()
            }
            .store(in: &cancellables)

        gateway.$lastMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    private func configureItem() {
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let name = gateway.isRunning ? "network.badge.shield.half.filled" : "network"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "mdns-gateway")?
            .withSymbolConfiguration(config)
        let s = GatewaySettings.load()
        let port = s.port
        if gateway.isRunning {
            button.toolTip = "mdns-gateway — running on \(s.bindHost):\(port)"
        } else {
            button.toolTip = "mdns-gateway — stopped (configured \(s.bindHost):\(port))"
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let running = gateway.isRunning

        let start = menu.addItem(withTitle: "Start Gateway", action: #selector(startGateway), keyEquivalent: "")
        start.target = self
        start.isEnabled = !running

        let stop = menu.addItem(withTitle: "Stop Gateway", action: #selector(stopGateway), keyEquivalent: "")
        stop.target = self
        stop.isEnabled = running

        menu.addItem(.separator())

        let logs = menu.addItem(withTitle: "Open Logs Folder…", action: #selector(openLogs), keyEquivalent: "")
        logs.target = self

        let prefs = menu.addItem(withTitle: "Preferences…", action: #selector(openPrefs), keyEquivalent: ",")
        prefs.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
    }

    @objc private func startGateway() {
        if let err = gateway.start(settings: GatewaySettings.load()) {
            alert(message: err)
        }
    }

    @objc private func stopGateway() {
        gateway.stop()
    }

    @objc private func openLogs() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = appSupport.appendingPathComponent("MdnsGatewayMenu/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func openPrefs() {
        preferences.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func alert(message: String) {
        let a = NSAlert()
        a.messageText = "mdns-gateway"
        a.informativeText = message
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
