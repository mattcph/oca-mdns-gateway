#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <optional>
#include <string>
#include <thread>

#include <httplib.h>
#include <nlohmann/json.hpp>

#include "discovery.hpp"
#include "http_api.hpp"
#include "util.hpp"

namespace {

void print_usage()
{
  std::cerr
      << "oca-mdns-gateway local `_oca._tcp` discovery broker (loopback HTTP API)\n\n"
      << "Usage:\n"
      << "  oca-mdns-gateway serve [--bind 127.0.0.1] [--port N] [--token SECRET]\n"
      << "  oca-mdns-gateway browse [--json]\n"
      << "  oca-mdns-gateway status [--host 127.0.0.1] [--port N] [--token SECRET]\n"
      << "  oca-mdns-gateway diagnostics [--host 127.0.0.1] [--port N] [--token SECRET]\n"
      << "\nToken:\n"
      << "  Set MDNS_GATEWAY_TOKEN env var to avoid exposing the secret in process\n"
      << "  listings and shell history. --token overrides the env var when both are set.\n"
      << "\nmacOS menu app note:\n"
      << "  The menu app controls a launchd-managed service. Use `serve` manually only for\n"
      << "  explicit terminal/debug sessions, not alongside the menu-controlled runtime.\n";
}

/** Read token: --token arg takes precedence over MDNS_GATEWAY_TOKEN env var. */
std::optional<std::string> resolve_token(const std::optional<std::string> &cli_override)
{
  if (cli_override.has_value())
    return cli_override;
  const char *env = std::getenv("MDNS_GATEWAY_TOKEN");
  if (env && env[0] != '\0')
    return std::string(env);
  return std::nullopt;
}

bool parse_cli_kv(int argc, char **argv, int &i, const char *key, std::string &out)
{
  if (std::strcmp(argv[i], key) != 0)
    return false;
  if (i + 1 >= argc)
  {
    std::cerr << "missing value for " << key << "\n";
    std::exit(2);
  }
  out = argv[++i];
  return true;
}

bool parse_cli_kv_int(int argc, char **argv, int &i, const char *key, int &out)
{
  if (std::strcmp(argv[i], key) != 0)
    return false;
  if (i + 1 >= argc)
  {
    std::cerr << "missing value for " << key << "\n";
    std::exit(2);
  }
  try
  {
    out = std::stoi(argv[++i]);
  }
  catch (...)
  {
    std::cerr << "invalid integer for " << key << "\n";
    std::exit(2);
  }
  if (std::strcmp(key, "--port") == 0 && (out < 1024 || out > 65535))
  {
    std::cerr << "--port must be in range 1024-65535 (got " << out << ")\n";
    std::exit(2);
  }
  return true;
}

int cmd_serve(int argc, char **argv)
{
  mg::HttpServeOptions opts;
  for (int i = 2; i < argc; ++i)
  {
    std::string s;
    int p = 0;
    if (parse_cli_kv(argc, argv, i, "--bind", s))
      opts.bind_host = std::move(s);
    else if (parse_cli_kv_int(argc, argv, i, "--port", p))
      opts.port = p;
    else if (parse_cli_kv(argc, argv, i, "--token", s))
      opts.bearer_token = std::move(s);
    else
    {
      std::cerr << "unknown argument: " << argv[i] << "\n";
      print_usage();
      return 2;
    }
  }

  if (!mg::is_allowed_bind_host(opts.bind_host))
  {
    std::cerr << "serve: --bind must be 127.0.0.1\n";
    return 2;
  }

  opts.bearer_token = resolve_token(opts.bearer_token);

  mg::DiscoveryCache cache;
  std::thread mdns([&]() { mg::run_discovery_forever(cache); });
  mdns.detach();

  mg::run_http_server(opts, cache);
  return 0;
}

int cmd_browse(int argc, char **argv)
{
  bool json = false;
  for (int i = 2; i < argc; ++i)
  {
    if (std::strcmp(argv[i], "--json") == 0)
      json = true;
    else
    {
      std::cerr << "unknown argument: " << argv[i] << "\n";
      print_usage();
      return 2;
    }
  }

  mg::DiscoveryCache cache;
  mg::browse_oca_for(std::chrono::seconds(10), cache);

  if (json)
  {
    nlohmann::json root;
    root["instances"] = cache.devices_json();
    std::cout << root.dump(2) << "\n";
    return 0;
  }

  const auto snap = cache.snapshot();
  std::cout << "_oca._tcp browse (" << snap.size() << " instance(s)):\n";
  for (const auto &d : snap)
  {
    std::cout << "  - " << d.name << " @ " << d.host << ":" << d.port;
    if (!d.addresses.empty())
      std::cout << " [" << d.addresses[0] << "]";
    std::cout << " [" << d.interfaceName << "]\n";
  }
  return 0;
}

int http_get_print(const std::string &host, int port, const std::string &path,
    const std::optional<std::string> &token)
{
  httplib::Client cli(host, port);
  cli.set_connection_timeout(2, 0);
  cli.set_read_timeout(5, 0);
  httplib::Headers headers;
  if (token.has_value())
    headers.emplace("Authorization", std::string("Bearer ") + *token);
  const auto r = headers.empty() ? cli.Get(path.c_str()) : cli.Get(path.c_str(), headers);
  if (!r)
  {
    std::cerr << "request failed (is `oca-mdns-gateway serve` running?)\n";
    return 1;
  }
  std::cout << r->body;
  if (!r->body.empty() && r->body.back() != '\n')
    std::cout << "\n";
  return r->status >= 400 ? 1 : 0;
}

int cmd_status(int argc, char **argv)
{
  std::string host = "127.0.0.1";
  int port = 17670;
  std::optional<std::string> token;
  for (int i = 2; i < argc; ++i)
  {
    std::string s;
    int p = 0;
    if (parse_cli_kv(argc, argv, i, "--host", host))
      continue;
    if (parse_cli_kv_int(argc, argv, i, "--port", p))
    {
      port = p;
      continue;
    }
    if (parse_cli_kv(argc, argv, i, "--token", s))
    {
      token = std::move(s);
      continue;
    }
    std::cerr << "unknown argument: " << argv[i] << "\n";
    print_usage();
    return 2;
  }
  return http_get_print(host, port, "/v1/service", token);
}

int cmd_diagnostics(int argc, char **argv)
{
  std::string host = "127.0.0.1";
  int port = 17670;
  std::optional<std::string> token;
  for (int i = 2; i < argc; ++i)
  {
    std::string s;
    int p = 0;
    if (parse_cli_kv(argc, argv, i, "--host", host))
      continue;
    if (parse_cli_kv_int(argc, argv, i, "--port", p))
    {
      port = p;
      continue;
    }
    if (parse_cli_kv(argc, argv, i, "--token", s))
    {
      token = std::move(s);
      continue;
    }
    std::cerr << "unknown argument: " << argv[i] << "\n";
    print_usage();
    return 2;
  }
  return http_get_print(host, port, "/v1/diagnostics", token);
}

} // namespace

int main(int argc, char **argv)
{
  if (argc < 2)
  {
    print_usage();
    return 1;
  }

  const std::string cmd = argv[1];
  if (cmd == "serve")
    return cmd_serve(argc, argv);
  if (cmd == "browse")
    return cmd_browse(argc, argv);
  if (cmd == "status")
    return cmd_status(argc, argv);
  if (cmd == "diagnostics")
    return cmd_diagnostics(argc, argv);

  print_usage();
  return 1;
}
