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
                Text("Use a port between 1024 and 65535. If the gateway is running, stop and start it for changes to apply.")
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
