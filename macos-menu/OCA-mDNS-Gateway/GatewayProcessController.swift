import Combine
import Darwin
import Foundation

final class GatewayProcessController: ObservableObject {
    static let shared = GatewayProcessController()
    private static let launchAgentLabel = "de.deuso.ocamdnsgateway.service"
    private static let managedLogFileName = "oca-mdns-gateway-launchd.log"
    private static let managedArchiveLogFileName = "oca-mdns-gateway-launchd.log.1"
    private static let maxLaunchLogBytes: UInt64 = 1024 * 1024

    @Published private(set) var isRunning = false
    @Published private(set) var isLaunchdManaged = false
    @Published private(set) var lastMessage: String = ""

    private var reconcileTimer: Timer?

    private init() {
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reconcileState()
        }
    }

    private func reconcileState() {
        let port = GatewaySettings.load().port
        let healthy = isServiceHealthy(port: port)
        let managed = isLaunchAgentLoaded()
        isRunning = healthy
        isLaunchdManaged = managed
    }

    /// Starts the launchd-managed gateway service. Returns an error message for the user, or nil on success.
    func start(settings: GatewaySettings) -> String? {
        guard let exe = Bundle.main.url(forAuxiliaryExecutable: "oca-mdns-gateway") else {
            return "Bundled oca-mdns-gateway helper not found. Build the C++ project (cmake) so the Run Script can copy the binary into the app bundle."
        }

        guard (1024 ... 65_535).contains(settings.port) else {
            return "Port must be between 1024 and 65535."
        }

        let token = settings.bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isServiceHealthy(port: settings.port) {
            isRunning = true
            isLaunchdManaged = isLaunchAgentLoaded()
            if isLaunchdManaged {
                lastMessage = "Gateway already running."
            } else {
                lastMessage = "Gateway already running in external process on \(settings.port)."
            }
            return nil
        }

        let appSupportDir = Self.applicationSupportDirectory()
        let logsDir = appSupportDir.appendingPathComponent("\(GatewaySettings.applicationSupportFolderName)/Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            return "Failed to create Logs directory: \(error.localizedDescription)"
        }
        let launchLog = logsDir.appendingPathComponent(Self.managedLogFileName)
        if !FileManager.default.fileExists(atPath: launchLog.path) {
            FileManager.default.createFile(atPath: launchLog.path, contents: Data())
        }

        let agentPath = Self.launchAgentPlistPath()
        do {
            try Self.writeLaunchAgentPlist(
                to: agentPath,
                helperExecutablePath: exe.path,
                port: settings.port,
                token: token.isEmpty ? nil : token,
                logPath: launchLog.path
            )
        } catch {
            return "Failed writing LaunchAgent plist: \(error.localizedDescription)"
        }

        _ = launchctl(["bootout", launchdDomainWithLabel()])
        do {
            try Self.rotateLaunchLogIfNeeded(logsDir: logsDir)
        } catch {
            return "Failed to rotate launch log: \(error.localizedDescription)"
        }

        let bootstrap = launchctl(["bootstrap", launchdDomain(), agentPath.path])
        if bootstrap.exitCode != 0 && !bootstrap.stderr.contains("already loaded") {
            return "launchctl bootstrap failed: \(nonEmpty(bootstrap.stderr, fallback: bootstrap.stdout))"
        }
        let kickstart = launchctl(["kickstart", "-k", launchdDomainWithLabel()])
        if kickstart.exitCode != 0 {
            return "launchctl kickstart failed: \(nonEmpty(kickstart.stderr, fallback: kickstart.stdout))"
        }

        let started = waitForHealth(port: settings.port, expectHealthy: true, timeout: 3.0)
        isRunning = started
        isLaunchdManaged = isLaunchAgentLoaded()
        let ts = Self.nowDisplay()
        if started {
            lastMessage = "Started: \(ts)"
            return nil
        }
        Thread.sleep(forTimeInterval: 0.2)
        if Self.launchLogTailContainsListenFailure() {
            let msg = "Port \(settings.port) is already in use by another process. Choose a different port or stop the other service."
            lastMessage = msg
            return msg
        }
        let fallback = "Start requested, but /health did not respond yet."
        lastMessage = fallback
        return fallback
    }

    func stop() {
        if !isLaunchAgentLoaded() && isServiceHealthy(port: GatewaySettings.load().port) {
            isRunning = true
            isLaunchdManaged = false
            lastMessage = "Gateway is running in external process; stop it from that terminal."
            return
        }
        let result = launchctl(["bootout", launchdDomainWithLabel()])
        if result.exitCode != 0 && !result.stderr.contains("Could not find service") {
            lastMessage = "launchctl bootout failed: \(nonEmpty(result.stderr, fallback: result.stdout))"
            return
        }
        let stopped = waitForHealth(port: GatewaySettings.load().port, expectHealthy: false, timeout: 3.0)
        isRunning = !stopped
        isLaunchdManaged = isLaunchAgentLoaded()
        lastMessage = stopped
            ? "Stopped (launchd) at \(Self.nowDisplay())"
            : "Stop requested, but service still appears active."
    }

    func stopForTermination() {
        stop()
    }

    private static func nowDisplay() -> String {
        DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private static func managedLaunchLogURL() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("\(GatewaySettings.applicationSupportFolderName)/Logs/\(managedLogFileName)")
    }

    /// After `bootout`, safe to rename the log the job used. At 1 MiB: move active → `.log.1` (overwrite archive), recreate empty active file.
    private static func rotateLaunchLogIfNeeded(logsDir: URL) throws {
        let fm = FileManager.default
        let active = logsDir.appendingPathComponent(managedLogFileName)
        let archive = logsDir.appendingPathComponent(managedArchiveLogFileName)
        guard fm.fileExists(atPath: active.path) else { return }
        let attrs = try fm.attributesOfItem(atPath: active.path)
        let size = (attrs[.size] as? NSNumber).map { $0.uint64Value } ?? 0
        guard size >= maxLaunchLogBytes else { return }
        if fm.fileExists(atPath: archive.path) {
            try fm.removeItem(at: archive)
        }
        try fm.moveItem(at: active, to: archive)
        guard fm.createFile(atPath: active.path, contents: Data()) else {
            throw NSError(
                domain: "OCAMDNSGateway",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not recreate empty launch log."]
            )
        }
    }

    /// Reads the tail of the launchd-managed helper log (stderr/stdout) for bind/listen failure lines from the C++ server.
    private static func launchLogTailContainsListenFailure() -> Bool {
        let url = managedLaunchLogURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size: UInt64 = (attrs[.size] as? NSNumber).map { $0.uint64Value } ?? 0
        guard size > 0 else { return false }
        let maxTail: UInt64 = 24_576
        let offset = size > maxTail ? size - maxTail : 0
        do {
            try fh.seek(toOffset: offset)
            guard let data = try fh.readToEnd(), !data.isEmpty else { return false }
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.contains("failed to listen")
        } catch {
            return false
        }
    }

    private static func launchAgentPlistPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    private static func writeLaunchAgentPlist(
        to path: URL,
        helperExecutablePath: String,
        port: Int,
        token: String?,
        logPath: String
    ) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [helperExecutablePath, "serve", "--bind", "127.0.0.1", "--port", "\(port)"],
            "RunAtLoad": false,
            "KeepAlive": false,
            "WorkingDirectory": FileManager.default.homeDirectoryForCurrentUser.path,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
            "ProcessType": "Background",
        ]
        if let token, !token.isEmpty {
            plist["EnvironmentVariables"] = ["MDNS_GATEWAY_TOKEN": token]
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: path, options: .atomic)
    }

    private func launchdDomain() -> String {
        "gui/\(getuid())"
    }

    private func launchdDomainWithLabel() -> String {
        "\(launchdDomain())/\(Self.launchAgentLabel)"
    }

    private func isLaunchAgentLoaded() -> Bool {
        launchctl(["print", launchdDomainWithLabel()]).exitCode == 0
    }

    private func launchctl(_ args: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }
        let stdoutData = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? err.fileHandleForReading.readToEnd()) ?? Data()
        return (
            p.terminationStatus,
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func isServiceHealthy(port: Int) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 0.8)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.dataTask(with: req) { data, res, _ in
            defer { sem.signal() }
            guard let http = res as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let data, let body = String(data: data, encoding: .utf8), body.contains("\"ok\":true") {
                ok = true
            }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 1.0)
        task.cancel()
        return ok
    }

    private func waitForHealth(port: Int, expectHealthy: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isServiceHealthy(port: port) == expectHealthy {
                return true
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return isServiceHealthy(port: port) == expectHealthy
    }

    private func nonEmpty(_ primary: String, fallback: String) -> String {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { return p }
        let f = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? "unknown error" : f
    }
}

