#pragma once

#include <chrono>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include <mdnscpp/BrowseResult.h>
#include <nlohmann/json.hpp>

namespace mg {

/** Normalized device record for JSON snapshot API. */
struct DeviceRecord {
  std::string id;
  std::string service = "_oca._tcp";
  std::string domain = "local";
  std::string name;
  std::string host;
  std::vector<std::string> addresses;
  uint16_t port = 0;
  std::map<std::string, std::string> txt;
  std::string interfaceName;
  std::string state = "present";
  bool stale = false;
  int ttlSeconds = 120;
  std::chrono::system_clock::time_point first_seen_tp{};
  std::chrono::system_clock::time_point last_seen_tp{};
};

class DiscoveryCache {
public:
  DiscoveryCache();

  void syncFromBrowseResults(const std::vector<mdnscpp::BrowseResult> &sorted);

  std::vector<DeviceRecord> snapshot() const;

  nlohmann::json devices_json() const;

private:
  mutable std::mutex mutex_;
  std::map<std::string, std::chrono::system_clock::time_point> first_seen_;
  std::vector<DeviceRecord> devices_;
  static constexpr int kDefaultTtlSeconds_ = 120;
};

/** Runs mDNS browser until duration elapses; uses Poll loop or Libuv stop. */
void browse_oca_for(std::chrono::seconds duration, DiscoveryCache &cache);

/** Blocks forever: run mDNS event loop and update cache (for `serve`). */
void run_discovery_forever(DiscoveryCache &cache);

} // namespace mg
