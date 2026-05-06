# OCA mDNS Gateway

macOS menu-bar (accessory) app for **OCA mDNS Gateway**. It starts and stops the HTTP discovery broker subprocess (CLI executable `oca-mdns-gateway`; broker overview in [main README](../README.md)). Settings (**bind address**, **port**, optional **bearer token**) are stored in UserDefaults. When the token is non-empty it is passed via `MDNS_GATEWAY_TOKEN` (not via `ps`-visible argv).

**Launch at login** uses `ServiceManagement` (`SMAppService.mainApp`). macOS may require you to approve **OCA mDNS Gateway** under **System Settings › General › Login Items** (or **Privacy & Security**) before it actually launches at login. Use a properly signed build for predictable behavior.

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

Gateway stdout/stderr are appended to timestamped files under `~/Library/Application Support/OCA-mDNS-Gateway/Logs/` (filenames like `oca-mdns-gateway-*.log`). The menu item **Open Logs Folder…** reveals this directory.