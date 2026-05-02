//
//  GatewayProcessController.swift
//  MdnsGatewayMenu
//

import Combine
import Darwin
import Foundation

final class GatewayProcessController: ObservableObject {
    static let shared = GatewayProcessController()

    @Published private(set) var isRunning = false
    @Published private(set) var lastMessage: String = ""

    private var process: Process?
    private var reconcileTimer: Timer?

    private init() {
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reconcileState()
        }
    }

    private func reconcileState() {
        if let p = process, !p.isRunning, isRunning {
            isRunning = false
            process = nil
        }
    }

    /// Starts the bundled gateway. Returns an error message for the user, or nil on success.
    func start(settings: GatewaySettings) -> String? {
        if let p = process, p.isRunning {
            return "Gateway is already running."
        }

        guard let exe = Bundle.main.url(forAuxiliaryExecutable: "mdns-gateway") else {
            return "Bundled mdns-gateway not found. Build the C++ project (cmake) so the Run Script can copy the binary into the app bundle."
        }

        let bind = settings.bindHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bind.isEmpty else {
            return "Bind address cannot be empty."
        }

        guard (1024 ... 65_535).contains(settings.port) else {
            return "Port must be between 1024 and 65535."
        }

        let p = Process()
        p.executableURL = exe
        p.arguments = [
            "serve",
            "--bind", bind,
            "--port", "\(settings.port)",
        ]

        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        if env["PATH"] == nil {
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        let token = settings.bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            env.removeValue(forKey: "MDNS_GATEWAY_TOKEN")
        } else {
            env["MDNS_GATEWAY_TOKEN"] = token
        }
        p.environment = env

        p.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let logURL = Self.makeLogFileURL()
        captureOutput(pipe: pipe, logURL: logURL)

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.process = nil
                let code = proc.terminationStatus
                let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                self.lastMessage = "Exited (status \(code)) at \(ts)"
            }
        }

        do {
            try p.run()
        } catch {
            return error.localizedDescription
        }

        process = p
        isRunning = true
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lastMessage = "Started at \(ts)"
        return nil
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let proc = self.process, proc.isRunning else { return }
            Darwin.kill(proc.processIdentifier, SIGKILL)
        }
    }

    func stopForTermination() {
        stop()
    }

    private static func makeLogFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("MdnsGatewayMenu/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        return dir.appendingPathComponent("mdns-gateway-\(stamp).log")
    }

    private func captureOutput(pipe: Pipe, logURL: URL?) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
                if let last = lines.last {
                    self?.lastMessage = String(last).isEmpty ? self?.lastMessage ?? "" : String(last)
                }
            }
            if let logURL, let out = try? FileHandle(forWritingTo: logURL) {
                try? out.seekToEnd()
                if let d = chunk.data(using: .utf8) {
                    try? out.write(contentsOf: d)
                }
                try? out.close()
            }
        }
    }
}
