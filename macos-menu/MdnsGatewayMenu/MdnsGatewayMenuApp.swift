//
//  MdnsGatewayMenuApp.swift
//  MdnsGatewayMenu
//

import SwiftUI

@main
struct MdnsGatewayMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
