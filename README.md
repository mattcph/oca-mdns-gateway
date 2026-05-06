# OCA mDNS Gateway

**OCA mDNS Gateway** is a local discovery broker for `**_oca._tcp`** (AES70/OCA over DNS-SD/mDNS). This repository (`oca-mdns-gateway`) continuously browses the LAN via [mdnscpp](https://github.com/arneg/mdnscpp) (Git submodule) and exposes a **loopback-only** JSON HTTP API ([cpp-httplib](https://github.com/yhirose/cpp-httplib), submodule) for clients on the same machine.

## Getting the sources

This repo uses **Git submodules** under `third_party/`. Clone with submodules:

```bash
git clone --recurse-submodules git@github.com:mattcph/oca-mdns-gateway.git
cd oca-mdns-gateway
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

Pinned revisions are listed in [DEPENDENCIES.md](DEPENDENCIES.md).

## Updating dependencies

Bump a submodule deliberately and commit the new gitlink:

```bash
cd third_party/mdnscpp
git fetch origin
git checkout <tag-or-sha>
cd ../..
git add third_party/mdnscpp
git commit -m "Bump mdnscpp to …"
```

Repeat for `cpp-httplib` or `json` as needed, then update [DEPENDENCIES.md](DEPENDENCIES.md).

Override path for local experiments:

```bash
cmake -B build -DMDNSCPP_ROOT=/path/to/other/mdnscpp
```

## Requirements

- CMake 3.16+
- C++17 compiler
- **Submodules initialized** (see above); default `**MDNSCPP_ROOT`** is `third_party/mdnscpp`
- Platform mDNS stack: Bonjour / `dns_sd` (macOS), Avahi (Linux), or Windows DNS-SD APIs
- Optional: **libuv** (often used by mdnscpp when available)

## Build

```bash
cd oca-mdns-gateway
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
```

Built CLI binary: `build/oca-mdns-gateway`

### One-command build (CLI + macOS menu app)

From repo root:

```bash
make all
```

Useful variants:

```bash
make cli
make menu
make all CONFIG=Debug
make clean
```

## Commands


| Command                        | Purpose                                                           |
| ------------------------------ | ----------------------------------------------------------------- |
| `oca-mdns-gateway serve`       | Run background `_oca._tcp` browse + HTTP API on `127.0.0.1:17670` |
| `oca-mdns-gateway browse`      | One-shot browse (~10s), text or `--json`                          |
| `oca-mdns-gateway status`      | `GET /v1/service` against the local API                           |
| `oca-mdns-gateway diagnostics` | `GET /v1/diagnostics`                                             |


### `serve` options

- `--bind 127.0.0.1` (only loopback IPv4 is allowed)
- `--port N` (default `17670`)
- `--token SECRET` — if set, `/v1/*` requires header `Authorization: Bearer SECRET` (`/health` stays open)

### `status` / `diagnostics` options

- `--host`, `--port` — API location (default `127.0.0.1` / `17670`)
- `--token SECRET` — when the server was started with `--token`

## HTTP API (same machine)


| Method | Path              | Notes                                                      |
| ------ | ----------------- | ---------------------------------------------------------- |
| GET    | `/health`         | `{"ok":true}`                                              |
| GET    | `/v1/service`     | Service type and browse state                              |
| GET    | `/v1/devices`     | `{ "instances": [ … ] }`                                   |
| GET    | `/v1/browse`      | Same as `/v1/devices`                                      |
| GET    | `/v1/diagnostics` | API uptime, backend label, interfaces (best-effort), hints |


Normalized device fields match the v1 plan (`id`, `service`, `domain`, `name`, `host`, `addresses`, `port`, `txt`, `interface`, `state`, `stale`, `ttlSeconds`, `firstSeen`, `lastSeen`).

## Example

```bash
./build/oca-mdns-gateway serve --bind 127.0.0.1 --port 17670 &
curl -s http://127.0.0.1:17670/health
curl -s http://127.0.0.1:17670/v1/devices
```

## macOS menu-bar launcher

Optional **OCA mDNS Gateway** Xcode app under [`macos-menu/`](macos-menu/README.md): starts and stops the bundled broker CLI (`oca-mdns-gateway`) from the menu bar. Preferences cover **HTTP port**, optional **bearer token**, and **launch at login**; the API stays **loopback-only** (`127.0.0.1`). Details and a plain `xcodebuild` recipe are in that README.

Build everything from the repo root with `make all` (see **Build → One-command build** above).

### Makefile: user-selectable signing for xcodebuild

The `menu` target runs `xcodebuild`. By default it uses whatever **Code Signing** settings are stored in the Xcode project. You can override signing by passing Make variables; each one is forwarded to `xcodebuild` only when set:


| Make variable                    | Purpose                                                                                       |
| -------------------------------- | --------------------------------------------------------------------------------------------- |
| `CODE_SIGN_IDENTITY`             | Identity string (e.g. `Apple Development`, `Developer ID Application: …`, or `-` for ad hoc). |
| `DEVELOPMENT_TEAM`               | Apple Developer Team ID (10 characters).                                                      |
| `CODE_SIGN_STYLE`                | `Automatic` or `Manual`.                                                                      |
| `PROVISIONING_PROFILE_SPECIFIER` | Profile name when using manual provisioning.                                                  |
| `CODE_SIGN_ENTITLEMENTS`         | Path relative to `macos-menu/` (Xcode `SRCROOT`); if unset, the project uses `OCA-mDNS-Gateway/entitlements.plist`, which Xcode applies when signing (equivalent to `codesign --entitlements`). |

The app target’s entitlements live at [`macos-menu/OCA-mDNS-Gateway/entitlements.plist`](macos-menu/OCA-mDNS-Gateway/entitlements.plist) and are wired via the **`CODE_SIGN_ENTITLEMENTS`** build setting in Xcode.


Examples:

```bash
make menu CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=ABCDE12345
make menu CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

```

List codesigning identities on this machine:

```bash
make list-identities
```

Run `make help` for all Makefile options (including `CONFIG`, `JOBS`, and derived-data paths).

## Windows

Use the same CMake steps with MSVC. mdnscpp uses the Win32 DNS-SD backend; libuv may be fetched or installed separately depending on your environment.