# MdnsGatewayMenu

macOS menu-bar (accessory) app that starts and stops the [`mdns-gateway`](../README.md) HTTP discovery broker as a subprocess. Settings (**bind address**, **port**, optional **bearer token**) are stored in UserDefaults. When the token is non-empty it is passed via `MDNS_GATEWAY_TOKEN` (not via `ps`-visible argv).

**Launch at login** uses `ServiceManagement` (`SMAppService.mainApp`). macOS may require you to approve the app under **System Settings › General › Login Items** (or **Privacy & Security**) before it actually launches at login. Use a properly signed build for predictable behavior.

## Requirements

- Xcode 15+ (Swift 5)
- macOS 13+
- CMake-built `mdns-gateway` binary at `mdns-gateway/build/mdns-gateway` (relative to the **parent** of this `macos-menu` folder)

Initialize submodules and build the gateway once:

```bash
cd /path/to/mdns-gateway
git submodule update --init --recursive
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

## Build the menu app

Open `macos-menu/MdnsGatewayMenu.xcodeproj` in Xcode and run the **MdnsGatewayMenu** scheme.

The **Embed mdns-gateway** Run Script phase copies `../build/mdns-gateway` into `Contents/MacOS/mdns-gateway`. The Xcode build **fails** if that file is missing—build the C++ project first.

At runtime the app resolves the helper with `Bundle.main.url(forAuxiliaryExecutable: "mdns-gateway")`.

### Command-line build

```bash
cd macos-menu
xcodebuild -scheme MdnsGatewayMenu -configuration Release -destination 'platform=macOS' build
```

## Sandbox

The target is **not** App Sandbox–enabled by default. Enabling sandbox would require entitlements for the bundled helper to bind a local port and possibly network access; for a local developer utility, leaving sandbox off is typical.

## Logs

Gateway stdout/stderr are appended to timestamped files under `~/Library/Application Support/MdnsGatewayMenu/Logs/`. The menu item **Open Logs Folder…** reveals this directory.
