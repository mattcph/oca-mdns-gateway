cmake_minimum_required(VERSION 3.16)
project(mdns-gateway VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# mdnscpp (Git submodule at third_party/mdnscpp, or override MDNSCPP_ROOT)
# ---------------------------------------------------------------------------
set(MDNSCPP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/mdnscpp"
    CACHE PATH "Path to the mdnscpp source tree (contains CMakeLists.txt)")
if(NOT EXISTS "${MDNSCPP_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR "mdnscpp not found at '${MDNSCPP_ROOT}'. Clone with submodules: git submodule update --init --recursive")
endif()
add_subdirectory("${MDNSCPP_ROOT}" "${CMAKE_BINARY_DIR}/_deps/mdnscpp-build")

# ---------------------------------------------------------------------------
# cpp-httplib + nlohmann/json (Git submodules under third_party/)
# ---------------------------------------------------------------------------
set(HTTPLIB_USE_OPENSSL_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_ZLIB_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_COMPILE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_INSTALL OFF CACHE BOOL "" FORCE)
set(HTTPLIB_TEST OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/cpp-httplib EXCLUDE_FROM_ALL)

set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
set(JSON_Install OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/json EXCLUDE_FROM_ALL)

add_executable(mdns-gateway
  src/main.cpp
  src/discovery.hpp
  src/discovery.cpp
  src/http_api.hpp
  src/http_api.cpp
  src/util.hpp
  src/util.cpp
)

target_include_directories(mdns-gateway PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")

target_link_libraries(mdns-gateway
  PRIVATE
    libmdnscpp
    httplib::httplib
    nlohmann_json::nlohmann_json
)

if(APPLE)
  target_compile_definitions(mdns-gateway PRIVATE MDNS_GATEWAY_BACKEND_BONJOUR=1)
elseif(WIN32)
  target_compile_definitions(mdns-gateway PRIVATE MDNS_GATEWAY_BACKEND_WIN32=1)
else()
  target_compile_definitions(mdns-gateway PRIVATE MDNS_GATEWAY_BACKEND_AVAHI=1)
endif()
