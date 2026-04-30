#include "http_api.hpp"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <iostream>

#include "discovery.hpp"
#include "util.hpp"

namespace mg {

namespace {

bool token_ok(const HttpServeOptions &opts, const httplib::Request &req)
{
  if (!opts.bearer_token.has_value())
    return true;
  const auto want = std::string("Bearer ") + *opts.bearer_token;
  return req.get_header_value("Authorization") == want;
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
  hints.push_back("Empty device list may mean no `_oca._tcp` advertisers, multicast blocked, wrong VLAN, Wi‑Fi isolation, or VPN interference.");
  j["hints"] = std::move(hints);

  (void)cache;
  return j;
}

} // namespace

void run_http_server(const HttpServeOptions &opts, DiscoveryCache &cache)
{
  if (!is_allowed_bind_host(opts.bind_host))
  {
    std::cerr << "mdns-gateway: bind host must be 127.0.0.1 (loopback IPv4 only)\n";
    std::exit(2);
  }

  httplib::Server svr;
  svr.set_payload_max_length(65536);

  const auto started = std::chrono::steady_clock::now();

  svr.Get("/health", [](const httplib::Request &, httplib::Response &res) {
    res.set_content(R"({"ok":true})", "application/json");
  });

  svr.Get("/v1/service", [&](const httplib::Request &req, httplib::Response &res) {
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
    if (!token_ok(opts, req))
    {
      res.status = 401;
      res.set_content(R"({"error":"unauthorized"})", "application/json");
      return;
    }
    res.set_content(diagnostics_json(opts, cache, started).dump(), "application/json");
  });

  if (!svr.listen(opts.bind_host, opts.port))
  {
    std::cerr << "mdns-gateway: failed to listen on " << opts.bind_host << ":" << opts.port << "\n";
    std::exit(1);
  }
}

} // namespace mg
