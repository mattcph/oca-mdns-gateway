# mdns-gateway

Local discovery broker for `**_oca._tcp**` (AES70/OCA over DNS-SD/mDNS). It continuously browses the LAN via [mdnscpp](https://github.com/arneg/mdnscpp) (Git submodule) and exposes a **loopback-only** JSON HTTP API ([cpp-httplib](https://github.com/yhirose/cpp-httplib), submodule) for clients on the same machine.

## Getting the sources

This repo uses **Git submodules** under `third_party/`. Clone with submodules:

```bash
git clone --recurse-submodules git@github.com:mattcph/mdns-gateway.git
cd mdns-gateway
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
cd mdns-gateway
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
```

Binary: `build/mdns-gateway`

## Commands


| Command                    | Purpose                                                           |
| -------------------------- | ----------------------------------------------------------------- |
| `mdns-gateway serve`       | Run background `_oca._tcp` browse + HTTP API on `127.0.0.1:17670` |
| `mdns-gateway browse`      | One-shot browse (~10s), text or `--json`                          |
| `mdns-gateway status`      | `GET /v1/service` against the local API                           |
| `mdns-gateway diagnostics` | `GET /v1/diagnostics`                                             |


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
./build/mdns-gateway serve --bind 127.0.0.1 --port 17670 &
curl -s http://127.0.0.1:17670/health
curl -s http://127.0.0.1:17670/v1/devices
```

## macOS menu-bar launcher

Optional Xcode app under [`macos-menu/`](macos-menu/README.md): starts/stops the built `mdns-gateway` binary from the menu bar with configurable bind address, port, and bearer token.

## Windows

Use the same CMake steps with MSVC. mdnscpp uses the Win32 DNS-SD backend; libuv may be fetched or installed separately depending on your environment.