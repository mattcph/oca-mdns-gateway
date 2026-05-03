import AppKit
import Combine

final class StatusMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let gateway = GatewayProcessController.shared
    private let preferences: PreferencesWindowController
    private var cancellables = Set<AnyCancellable>()

    init(preferences: PreferencesWindowController) {
        self.preferences = preferences
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
        let assetName = gateway.isRunning ? "MenubarRunning" : "MenubarStopped"
        if let image = NSImage(named: assetName) {
            button.image = Self.statusBarScaledCopy(of: image)
        } else {
            let fallback = gateway.isRunning ? "network.badge.shield.half.filled" : "network"
            button.image = Self.symbolImage(systemName: fallback)
        }
        let s = GatewaySettings.load()
        let port = s.port
        if gateway.isRunning {
            button.toolTip = "OCA mDNS Gateway — running on \(s.bindHost):\(port)"
        } else {
            button.toolTip = "OCA mDNS Gateway — stopped (configured \(s.bindHost):\(port))"
        }
    }

    private static func symbolImage(systemName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return NSImage(systemSymbolName: systemName, accessibilityDescription: "OCA mDNS Gateway")?
            .withSymbolConfiguration(config)
    }

    /// PDF-backed catalog images often use a large intrinsic size; cap height to match other menu bar items.
    private static func statusBarScaledCopy(of image: NSImage) -> NSImage {
        let targetHeight: CGFloat = 18
        guard let copy = image.copy() as? NSImage else { return image }
        let w = image.size.width
        let h = image.size.height
        if w <= 0 || h <= 0 {
            copy.size = NSSize(width: targetHeight, height: targetHeight)
            return copy
        }
        let scale = targetHeight / h
        copy.size = NSSize(width: w * scale, height: targetHeight)
        return copy
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if gateway.isRunning {
            let stop = menu.addItem(withTitle: "Stop OCA mDNS Gateway", action: #selector(stopGateway), keyEquivalent: "")
            stop.target = self
        } else {
            let start = menu.addItem(withTitle: "Start OCA mDNS Gateway", action: #selector(startGateway), keyEquivalent: "")
            start.target = self
        }

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
        let dir = appSupport.appendingPathComponent("\(GatewaySettings.applicationSupportFolderName)/Logs", isDirectory: true)
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
        a.messageText = "OCA mDNS Gateway"
        a.informativeText = message
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
