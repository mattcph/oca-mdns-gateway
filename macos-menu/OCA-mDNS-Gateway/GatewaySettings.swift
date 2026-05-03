import Foundation

struct GatewaySettings: Codable, Equatable {
    var bindHost: String
    var port: Int
    /// Optional; empty means no bearer auth.
    var bearerToken: String?

    static let `default` = GatewaySettings(bindHost: "127.0.0.1", port: 17_670, bearerToken: nil)

    /// Subdirectory under `~/Library/Application Support/` (logs, etc.).
    static let applicationSupportFolderName = "OCA-mDNS-Gateway"

    private static let userDefaultsKey = "OCA-mDNS-Gateway.settings"

    static func load() -> GatewaySettings {
        let decoded: GatewaySettings
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return .default
        }
        do {
            decoded = try JSONDecoder().decode(GatewaySettings.self, from: data)
        } catch {
            return .default
        }
        // Daemon only accepts loopback IPv4; normalize older saved values.
        var s = decoded
        s.bindHost = "127.0.0.1"
        return s
    }

    func save() {
        var copy = self
        copy.bindHost = "127.0.0.1"
        guard let data = try? JSONEncoder().encode(copy) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
