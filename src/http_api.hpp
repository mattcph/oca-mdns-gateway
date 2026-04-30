#pragma once

#include <chrono>
#include <optional>
#include <string>

namespace mg {

class DiscoveryCache;

struct HttpServeOptions {
  std::string bind_host = "127.0.0.1";
  int port = 17670;
  /** When set, require Authorization Bearer header for /v1 endpoints. */
  std::optional<std::string> bearer_token;
};

/**
 * Blocks until the HTTP server stops (normally never).
 * Reads only from `cache`; must not start mDNS itself.
 */
void run_http_server(const HttpServeOptions &opts, DiscoveryCache &cache);

} // namespace mg
