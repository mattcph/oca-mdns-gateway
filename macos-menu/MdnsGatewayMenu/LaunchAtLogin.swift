//
//  LaunchAtLogin.swift
//  MdnsGatewayMenu
//

import Foundation
import ServiceManagement

/// Uses `SMAppService.mainApp` (macOS 13+) to register/unregister this app as a login item.
enum LaunchAtLogin {
    /// Whether launch-at-login is on or awaiting user approval in System Settings.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered:
            return false
        @unknown default:
            return false
        }
    }

    /// User must approve in System Settings before the app actually launches at login.
    static var needsUserApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
