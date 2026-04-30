#include "util.hpp"

#include <chrono>
#include <cstring>
#include <iomanip>
#include <sstream>

#if defined(__APPLE__) || defined(__linux__)
#  include <net/if.h>
#endif

#if defined(__APPLE__) || defined(__linux__)
#  include <arpa/inet.h>
#  include <ifaddrs.h>
#  include <netinet/in.h>
#endif

namespace mg {

std::string utc_iso8601_now()
{
  return utc_iso8601_from_time_point(std::chrono::system_clock::now());
}

std::string utc_iso8601_from_time_point(std::chrono::system_clock::time_point tp)
{
  using clock = std::chrono::system_clock;
  const auto t = clock::to_time_t(tp);
  std::tm tm{};
#if defined(_WIN32)
  gmtime_s(&tm, &t);
#else
  gmtime_r(&t, &tm);
#endif
  std::ostringstream os;
  os << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
  return os.str();
}

std::string interface_index_to_name(unsigned long index)
{
#if defined(__APPLE__) || defined(__linux__)
  char buf[IF_NAMESIZE]{};
  if (if_indextoname(static_cast<unsigned>(index), buf))
  {
    return std::string(buf);
  }
#elif defined(_WIN32)
  // Best-effort: map index to friendly name on Windows (DNS-SD uses interface index).
  (void)index;
#endif
  return std::string("if") + std::to_string(index);
}

bool is_allowed_bind_host(const std::string &host)
{
  return host == "127.0.0.1";
}

std::string discovery_backend_label()
{
#if defined(MDNS_GATEWAY_BACKEND_BONJOUR)
  return "bonjour";
#elif defined(MDNS_GATEWAY_BACKEND_WIN32)
  return "win32";
#elif defined(MDNS_GATEWAY_BACKEND_AVAHI)
  return "avahi";
#else
  return "unknown";
#endif
}

std::vector<InterfaceEntry> list_local_interfaces()
{
  std::vector<InterfaceEntry> out;

#if defined(__APPLE__) || defined(__linux__)
  ifaddrs *head = nullptr;
  if (getifaddrs(&head) != 0)
  {
    return out;
  }
  for (ifaddrs *ifa = head; ifa != nullptr; ifa = ifa->ifa_next)
  {
    if (!ifa->ifa_addr)
      continue;
    const int family = ifa->ifa_addr->sa_family;
    if (family != AF_INET)
      continue;
    const auto *sa = reinterpret_cast<sockaddr_in *>(ifa->ifa_addr);
    char buf[INET_ADDRSTRLEN]{};
    if (!inet_ntop(AF_INET, &sa->sin_addr, buf, sizeof(buf)))
      continue;
    const std::string ip(buf);
    if (ip == "127.0.0.1")
      continue;
    InterfaceEntry e;
    e.name = ifa->ifa_name ? ifa->ifa_name : "";
    e.address = ip;
    e.eligible = true;
    out.push_back(std::move(e));
  }
  freeifaddrs(head);
#elif defined(_WIN32)
  (void)out; // v1: optional; avoid Winsock init complexity in the helper
#endif
  return out;
}

} // namespace mg
