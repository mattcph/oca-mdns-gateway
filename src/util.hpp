#pragma once

#include <chrono>
#include <string>
#include <vector>

namespace mg {

struct InterfaceEntry {
  std::string name;
  std::string address;
  bool eligible = true;
};

/** ISO-8601 UTC from system_clock. */
std::string utc_iso8601_now();

std::string utc_iso8601_from_time_point(std::chrono::system_clock::time_point tp);

std::string interface_index_to_name(unsigned long index);

/** Non-loopback IPv4-ish interfaces for diagnostics (best-effort). */
std::vector<InterfaceEntry> list_local_interfaces();

/** Accept only IPv4 loopback literal for HTTP bind. */
bool is_allowed_bind_host(const std::string &host);

std::string discovery_backend_label();

} // namespace mg
