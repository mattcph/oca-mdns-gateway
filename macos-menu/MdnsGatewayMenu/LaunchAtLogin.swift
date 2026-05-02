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
        case .enabled:
            return true
        case .requiresApproval:
            return true
        case .notRegistered:
            return false
        case .notFound:
            return false
        @unknown default:
            // Be conservative for any future cases we don't explicitly handle.
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

