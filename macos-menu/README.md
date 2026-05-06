# OCA mDNS Gateway

macOS menu-bar (accessory) app for **OCA mDNS Gateway**. It starts and stops the HTTP discovery broker service (CLI executable `oca-mdns-gateway`; broker overview in [main README](../README.md)) through `launchctl` as a user LaunchAgent. Settings (**bind address**, **port**, optional **bearer token**) are stored in UserDefaults. When the token is non-empty it is passed via `MDNS_GATEWAY_TOKEN` in the generated LaunchAgent plist.

**Launch at login** uses `ServiceManagement` (`SMAppService.mainApp`). macOS may require you to approve **OCA mDNS Gateway** under **System Settings › General › Login Items** (or **Privacy & Security**) before it actually launches at login. Use a properly signed build for predictable behavior.

### Preferences

Port and token are saved when you **close** the Preferences window (`windowWillClose`). If the gateway is already running and you change port or token, **Stop** from the menu, close Preferences (to persist), then **Start** again so the LaunchAgent plist picks up the new values.

## Requirements

- Xcode 15+ (Swift 5)
- macOS 13+
- **OCA mDNS Gateway** CLI binary (`oca-mdns-gateway`) built at `oca-mdns-gateway/build/oca-mdns-gateway` (relative to the **parent** of this `macos-menu` folder)

Initialize submodules and build the gateway once:

```bash
cd /path/to/oca-mdns-gateway
git submodule update --init --recursive
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

## Build the menu app

Open `macos-menu/OCA mDNS Gateway.xcodeproj` in Xcode and run the **OCA mDNS Gateway** scheme.

The Run Script phase (**Embed oca-mdns-gateway**) copies `../build/oca-mdns-gateway` into `Contents/MacOS/oca-mdns-gateway`. The Xcode build **fails** if that file is missing. Build the C++ project first.

At runtime the app resolves the helper with `Bundle.main.url(forAuxiliaryExecutable: "oca-mdns-gateway")`.

The menu app writes `~/Library/LaunchAgents/de.deuso.ocamdnsgateway.service.plist` and controls it via:
- `launchctl bootstrap` + `launchctl kickstart -k` on Start
- `launchctl bootout` on Stop

This enforces a single launchd-owned runtime for menu control.

### Command-line build

Use the `**OCA mDNS Gateway`** scheme (matches the app/target name). 

```bash
cd macos-menu
xcodebuild -scheme "OCA mDNS Gateway" -configuration Release -destination 'platform=macOS' build
```

Run `**xcodebuild -list -project "OCA mDNS Gateway.xcodeproj"**` to see schemes.

## Sandbox

The target is **not** App Sandbox–enabled by default. Enabling sandbox would require entitlements for the bundled helper to bind a local port and possibly network access; for a local developer utility, leaving sandbox off is typical.

## Code signing entitlements

The **OCA mDNS Gateway** target sets **`CODE_SIGN_ENTITLEMENTS`** to [`OCA-mDNS-Gateway/entitlements.plist`](OCA-mDNS-Gateway/entitlements.plist). Xcode uses it during the Code Sign phase (equivalent to passing `--entitlements` to `codesign`).

## Logs

Launchd-managed gateway stdout/stderr are appended to:

`~/Library/Application Support/OCA-mDNS-Gateway/Logs/oca-mdns-gateway-launchd.log`

When logs should be written:
- A launchd log file is created before Start.
- Output is written while the launchd-managed helper runs.
- Stop/start cycles continue writing to the same launchd log path.

When the active log exceeds **1 MiB**, the next **Start** from the menu (after `launchctl bootout`) moves it to `oca-mdns-gateway-launchd.log.1`, overwriting any previous `.1`, then starts a new empty `oca-mdns-gateway-launchd.log`.

The menu item **Open Logs Folder…** reveals this directory.

## Mixed launch behavior

- Menu **Start/Stop** controls the launchd-managed service.
- If another external `serve` process already owns the configured port, menu Start reports an external-process status instead of spawning competing processes.