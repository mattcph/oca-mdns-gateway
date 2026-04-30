#include "discovery.hpp"

#include <iomanip>
#include <sstream>

#include <mdnscpp/DefaultLoop.h>
#include <mdnscpp/Platform.h>
#include <mdnscpp/utils.h>

#if defined(LIBMDNS_LOOP_POLL)
#  include <mdnscpp/PollLoop.h>
#endif
#if defined(LIBMDNS_LOOP_LIBUV)
#  include <mdnscpp/LibuvLoop.h>
#  include <uv.h>
#endif

#include <thread>

#include "util.hpp"

namespace mg {

namespace {

std::string make_device_id(const mdnscpp::BrowseResult &r)
{
  return r.getFullname() + "#" + std::to_string(r.getInterface());
}

std::map<std::string, std::string> txt_to_map(const mdnscpp::BrowseResult &r)
{
  std::map<std::string, std::string> m;
  for (const auto &t : r.getTxtRecords())
  {
    if (t.value.has_value())
      m[t.key] = *t.value;
    else
      m[t.key] = "";
  }
  return m;
}

} // namespace

DiscoveryCache::DiscoveryCache() = default;

void DiscoveryCache::syncFromBrowseResults(const std::vector<mdnscpp::BrowseResult> &sorted)
{
  const auto now = std::chrono::system_clock::now();

  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<DeviceRecord> next;
  next.reserve(sorted.size());

  for (const auto &r : sorted)
  {
    const std::string id = make_device_id(r);
    if (first_seen_.find(id) == first_seen_.end())
      first_seen_[id] = now;
    const auto first_tp = first_seen_[id];

    DeviceRecord d;
    d.id = id;
    d.service = "_oca._tcp";
    d.domain = r.getDomain().empty() ? std::string("local") : r.getDomain();
    d.name = r.getName();
    d.host = r.getHostname();
    if (!r.getAddress().empty())
      d.addresses.push_back(r.getAddress());
    d.port = r.getPort();
    d.txt = txt_to_map(r);
    d.interfaceName = interface_index_to_name(static_cast<unsigned long>(r.getInterface()));
    d.state = "present";
    d.stale = false;
    d.ttlSeconds = kDefaultTtlSeconds_;
    d.first_seen_tp = first_tp;
    d.last_seen_tp = now;
    next.push_back(std::move(d));
  }

  devices_ = std::move(next);

  std::vector<std::string> dead;
  for (const auto &kv : first_seen_)
  {
    bool found = false;
    for (const auto &d : devices_)
    {
      if (d.id == kv.first)
      {
        found = true;
        break;
      }
    }
    if (!found)
      dead.push_back(kv.first);
  }
  for (const auto &k : dead)
    first_seen_.erase(k);
}

std::vector<DeviceRecord> DiscoveryCache::snapshot() const
{
  std::lock_guard<std::mutex> lock(mutex_);
  return devices_;
}

nlohmann::json DiscoveryCache::devices_json() const
{
  std::lock_guard<std::mutex> lock(mutex_);
  nlohmann::json arr = nlohmann::json::array();
  const auto now = std::chrono::system_clock::now();
  for (const auto &d : devices_)
  {
    nlohmann::json j;
    j["id"] = d.id;
    j["service"] = d.service;
    j["domain"] = d.domain;
    j["name"] = d.name;
    j["host"] = d.host;
    j["addresses"] = d.addresses;
    j["port"] = d.port;
    j["txt"] = d.txt;
    j["interface"] = d.interfaceName;
    j["state"] = d.state;
    const bool stale = (now - d.last_seen_tp) > std::chrono::seconds(d.ttlSeconds);
    j["stale"] = stale;
    j["ttlSeconds"] = d.ttlSeconds;
    j["firstSeen"] = utc_iso8601_from_time_point(d.first_seen_tp);
    j["lastSeen"] = utc_iso8601_from_time_point(d.last_seen_tp);
    arr.push_back(std::move(j));
  }
  return arr;
}

void browse_oca_for(std::chrono::seconds duration, DiscoveryCache &cache)
{
  mdnscpp::DefaultLoop loop;
  auto platform = mdnscpp::createPlatform(loop);
  auto browser = platform->createBrowser("_oca", "_tcp",
      [&](std::shared_ptr<mdnscpp::Browser> b) {
        cache.syncFromBrowseResults(mdnscpp::getSortedList(b->getResults()));
      },
      "local", 0, mdnscpp::IPProtocol::Both);
  (void)browser;

#if defined(LIBMDNS_LOOP_LIBUV)
  auto &uvLoop = static_cast<mdnscpp::LibuvLoop &>(loop);
  std::thread worker([&]() { loop.run(); });
  std::this_thread::sleep_for(duration);
  uv_stop(uvLoop.getUvLoop());
  worker.join();
#elif defined(LIBMDNS_LOOP_POLL)
  auto &poll = static_cast<mdnscpp::PollLoop &>(loop);
  const auto end = std::chrono::steady_clock::now() + duration;
  while (std::chrono::steady_clock::now() < end)
    poll.runOnce();
#else
#  error "mdns-gateway: unsupported mdnscpp event loop configuration"
#endif
}

void run_discovery_forever(DiscoveryCache &cache)
{
  mdnscpp::DefaultLoop loop;
  auto platform = mdnscpp::createPlatform(loop);
  auto browser = platform->createBrowser("_oca", "_tcp",
      [&](std::shared_ptr<mdnscpp::Browser> b) {
        cache.syncFromBrowseResults(mdnscpp::getSortedList(b->getResults()));
      },
      "local", 0, mdnscpp::IPProtocol::Both);
  (void)browser;
  loop.run();
}

} // namespace mg
