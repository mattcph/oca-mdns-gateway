#include "http_api.hpp"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <iostream>
#include <mutex>

#include "discovery.hpp"
#include "util.hpp"

namespace mg {

namespace {

class GlobalTokenBucket {
public:
  GlobalTokenBucket(double capacity, double refill_per_second)
      : capacity_(capacity), refill_per_second_(refill_per_second), tokens_(capacity),
        last_refill_(std::chrono::steady_clock::now())
  {
  }

  bool consume(double amount = 1.0)
  {
    std::lock_guard<std::mutex> lock(mutex_);
    refill_locked();
    if (tokens_ < amount)
      return false;
    tokens_ -= amount;
    return true;
  }

  int retry_after_seconds(double amount = 1.0)
  {
    std::lock_guard<std::mutex> lock(mutex_);
    refill_locked();
    if (tokens_ >= amount)
      return 0;
    const double deficit = amount - tokens_;
    if (refill_per_second_ <= 0.0)
      return 1;
    const auto wait = static_cast<int>(std::ceil(deficit / refill_per_second_));
    return wait > 0 ? wait : 1;
  }

private:
  void refill_locked()
  {
    const auto now = std::chrono::steady_clock::now();
    const auto elapsed = std::chrono::duration<double>(now - last_refill_).count();
    if (elapsed > 0.0)
    {
      tokens_ = std::min(capacity_, tokens_ + elapsed * refill_per_second_);
      last_refill_ = now;
    }
  }

  const double capacity_;
  const double refill_per_second_;
  double tokens_;
  std::chrono::steady_clock::time_point last_refill_;
  std::mutex mutex_;
};

bool token_ok(const HttpServeOptions &opts, const httplib::Request &req)
{
  if (!opts.bearer_token.has_value())
    return true;
  const auto want = std::string("Bearer ") + *opts.bearer_token;
  const auto &have = req.get_header_value("Authorization");
  // Constant-time comparison: avoid short-circuit leaking token length/value
  // via timing side-channel even on loopback.
  if (have.size() != want.size())
    return false;
  bool ok = true;
  for (size_t i = 0; i < want.size(); ++i)
    ok &= (have[i] == want[i]);
  return ok;
}

nlohmann::json diagnostics_json(const HttpServeOptions &opts,
    const DiscoveryCache &cache,
    std::chrono::steady_clock::time_point started_steady)
{
  const auto uptime = std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::steady_clock::now() - started_steady);

  nlohmann::json j;
  j["api"]["bind"] = opts.bind_host;
  j["api"]["port"] = opts.port;
  j["api"]["uptimeSeconds"] = uptime.count();

  j["discovery"]["service"] = "_oca._tcp";
  j["discovery"]["domain"] = "local";
  j["discovery"]["backend"] = discovery_backend_label();
  j["discovery"]["running"] = true;
  j["discovery"]["lastError"] = nullptr;

  nlohmann::json ifs = nlohmann::json::array();
  for (const auto &iface : list_local_interfaces())
  {
    nlohmann::json row;
    row["name"] = iface.name;
    row["address"] = iface.address;
    row["eligible"] = iface.eligible;
    ifs.push_back(std::move(row));
  }
  j["interfaces"] = std::move(ifs);

  nlohmann::json hints = nlohmann::json::array();
  hints.push_back("Empty device list may mean no `_oca._tcp` advertisers, multicast blocked, wrong VLAN, WiFi isolation, or VPN interference.");
  j["hints"] = std::move(hints);

  (void)cache;
  return j;
}

} // namespace

void run_http_server(const HttpServeOptions &opts, DiscoveryCache &cache)
{
  if (!is_allowed_bind_host(opts.bind_host))
  {
    std::cerr << "oca-mdns-gateway: bind host must be 127.0.0.1 (loopback IPv4 only)\n";
    std::exit(2);
  }

  httplib::Server svr;
  svr.set_payload_max_length(65536);

  const auto started = std::chrono::steady_clock::now();
  // Lightweight global limiter for this local API process.
  // Burst: 20 requests. Refill: 5 requests per second.
  GlobalTokenBucket limiter(20.0, 5.0);
  auto check_rate_limit = [&](httplib::Response &res) -> bool {
    if (limiter.consume())
      return true;
    const int retry_after = limiter.retry_after_seconds();
    res.status = 429;
    res.set_header("Retry-After", std::to_string(retry_after));
    res.set_content(R"({"error":"rate_limited"})", "application/json");
    return false;
  };

  svr.Get("/health", [&](const httplib::Request &, httplib::Response &res) {
    if (!check_rate_limit(res))
      return;
    res.set_content(R"({"ok":true})", "application/json");
  });

  svr.Get("/v1/service", [&](const httplib::Request &req, httplib::Response &res) {
    if (!check_rate_limit(res))
      return;
    if (!token_ok(opts, req))
    {
      res.status = 401;
      res.set_content(R"({"error":"unauthorized"})", "application/json");
      return;
    }
    nlohmann::json j;
    j["service"] = "_oca._tcp";
    j["domain"] = "local";
    j["running"] = true;
    j["lastError"] = nullptr;
    res.set_content(j.dump(), "application/json");
  });

  svr.Get("/v1/devices", [&](const httplib::Request &req, httplib::Response &res) {
    if (!check_rate_limit(res))
      return;
    if (!token_ok(opts, req))
    {
      res.status = 401;
      res.set_content(R"({"error":"unauthorized"})", "application/json");
      return;
    }
    nlohmann::json body;
    body["instances"] = cache.devices_json();
    res.set_content(body.dump(), "application/json");
  });

  svr.Get("/v1/browse", [&](const httplib::Request &req, httplib::Response &res) {
    if (!check_rate_limit(res))
      return;
    if (!token_ok(opts, req))
    {
      res.status = 401;
      res.set_content(R"({"error":"unauthorized"})", "application/json");
      return;
    }
    nlohmann::json body;
    body["instances"] = cache.devices_json();
    res.set_content(body.dump(), "application/json");
  });

  svr.Get("/v1/diagnostics", [&](const httplib::Request &req, httplib::Response &res) {
    if (!check_rate_limit(res))
      return;
    if (!token_ok(opts, req))
    {
      res.status = 401;
      res.set_content(R"({"error":"unauthorized"})", "application/json");
      return;
    }
    res.set_content(diagnostics_json(opts, cache, started).dump(), "application/json");
  });

  svr.set_error_handler([](const httplib::Request &, httplib::Response &res) {
    if (res.status == 404)
    {
      res.set_content(R"({"error":"not_found"})", "application/json");
    }
  });

  // Reject non-GET methods explicitly with 405 + Allow header.
  auto method_not_allowed = [](const httplib::Request &, httplib::Response &res) {
    res.status = 405;
    res.set_header("Allow", "GET");
    res.set_content(R"({"error":"method_not_allowed"})", "application/json");
  };
  svr.Post(".*", method_not_allowed);
  svr.Put(".*", method_not_allowed);
  svr.Delete(".*", method_not_allowed);
  svr.Patch(".*", method_not_allowed);

  if (!svr.listen(opts.bind_host, opts.port))
  {
    std::cerr << "oca-mdns-gateway: failed to listen on " << opts.bind_host << ":" << opts.port << "\n";
    std::exit(1);
  }
}

} // namespace mg
