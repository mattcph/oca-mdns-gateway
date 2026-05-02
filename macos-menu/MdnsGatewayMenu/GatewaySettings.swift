//
//  GatewaySettings.swift
//  MdnsGatewayMenu
//

import Foundation

struct GatewaySettings: Codable, Equatable {
    var bindHost: String
    var port: Int
    /// Optional; empty means no bearer auth.
    var bearerToken: String?

    static let `default` = GatewaySettings(bindHost: "127.0.0.1", port: 17_670, bearerToken: nil)

    private static let userDefaultsKey = "MdnsGatewayMenu.settings"

    static func load() -> GatewaySettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(GatewaySettings.self, from: data)
        } catch {
            return .default
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
