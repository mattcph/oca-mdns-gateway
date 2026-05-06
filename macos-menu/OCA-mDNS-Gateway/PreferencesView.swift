import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section {
                Text("The HTTP API listens only on this Mac at 127.0.0.1 (not reachable from other machines).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if LaunchAtLogin.needsUserApproval {
                    Text("Approve OCA mDNS Gateway under System Settings › General › Login Items (or Privacy & Security).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("HTTP port:", text: $viewModel.port)
                Text("Ports 1024-65535. Changes save when you close this window. If the gateway is already running, stop it from the menu, close Preferences, then Start again so port and token apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                SecureField("Bearer token (optional, blank = none):", text: $viewModel.token)
                Text("Token is passed via MDNS_GATEWAY_TOKEN when non-empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440, minHeight: 300)
        .onAppear {
            viewModel.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    viewModel.launchAtLogin = LaunchAtLogin.isEnabled
                } catch {
                    viewModel.launchAtLogin = LaunchAtLogin.isEnabled
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
}
