import AppKit
import SwiftUI

struct PreferencesView: View {
    @State private var bindHost: String
    @State private var port: String
    @State private var token: String
    @State private var launchAtLogin: Bool

    init() {
        let s = GatewaySettings.load()
        _bindHost = State(initialValue: s.bindHost)
        _port = State(initialValue: String(s.port))
        _token = State(initialValue: s.bearerToken ?? "")
        _launchAtLogin = State(initialValue: LaunchAtLogin.isEnabled)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if LaunchAtLogin.needsUserApproval {
                    Text("Approve OCA mDNS Gateway under System Settings › General › Login Items (or Privacy & Security).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Bind address:", text: $bindHost)
                TextField("HTTP port:", text: $port)
            }
            Section {
                SecureField("Bearer token (optional, blank = none):", text: $token)
                Text("Token is passed via MDNS_GATEWAY_TOKEN when non-empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440, minHeight: 280)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onDisappear(perform: save)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                } catch {
                    launchAtLogin = LaunchAtLogin.isEnabled
                    let alert = NSAlert()
                    alert.messageText = "Launch at login"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        )
    }

    private func save() {
        let trimmedBind = bindHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let bind = trimmedBind.isEmpty ? GatewaySettings.default.bindHost : trimmedBind
        let portInt = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? GatewaySettings.default.port
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = GatewaySettings(
            bindHost: bind,
            port: portInt,
            bearerToken: trimmedToken.isEmpty ? nil : trimmedToken
        )
        s.save()
    }
}
