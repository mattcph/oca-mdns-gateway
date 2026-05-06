SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(ROOT_DIR)/build
CONFIG ?= Release
JOBS ?= 4
DERIVED_DATA ?= $(ROOT_DIR)/macos-menu/.derivedData

# Optional Xcode signing overrides (unset = use values from the Xcode project).
CODE_SIGN_IDENTITY ?=
DEVELOPMENT_TEAM ?=
CODE_SIGN_STYLE ?=
PROVISIONING_PROFILE_SPECIFIER ?=
# Relative to macos-menu (Xcode SRCROOT), e.g. OCA-mDNS-Gateway/entitlements.plist
CODE_SIGN_ENTITLEMENTS ?=

XCODE_SIGN_ARGS :=
ifneq ($(strip $(CODE_SIGN_IDENTITY)),)
XCODE_SIGN_ARGS += CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)"
endif
ifneq ($(strip $(DEVELOPMENT_TEAM)),)
XCODE_SIGN_ARGS += DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"
endif
ifneq ($(strip $(CODE_SIGN_STYLE)),)
XCODE_SIGN_ARGS += CODE_SIGN_STYLE="$(CODE_SIGN_STYLE)"
endif
ifneq ($(strip $(PROVISIONING_PROFILE_SPECIFIER)),)
XCODE_SIGN_ARGS += PROVISIONING_PROFILE_SPECIFIER="$(PROVISIONING_PROFILE_SPECIFIER)"
endif
ifneq ($(strip $(CODE_SIGN_ENTITLEMENTS)),)
XCODE_SIGN_ARGS += CODE_SIGN_ENTITLEMENTS="$(CODE_SIGN_ENTITLEMENTS)"
endif

.PHONY: help all submodules configure cli menu clean distclean list-identities

help:
	@echo "Targets:"
	@echo "  make all        Build CLI and macOS menu app (default)"
	@echo "  make cli        Build only the C++ CLI (oca-mdns-gateway)"
	@echo "  make menu       Build macOS menu app (depends on cli)"
	@echo "  make clean      Clean CLI + menu app build artifacts"
	@echo "  make distclean  Remove build and derived-data directories"
	@echo ""
	@echo "Options:"
	@echo "  CONFIG=Release|Debug (default: Release)"
	@echo "  JOBS=<n>               (default: 4)"
	@echo "  BUILD_DIR=<path>       (default: ./build)"
	@echo "  DERIVED_DATA=<path>    (default: ./macos-menu/.derivedData)"
	@echo ""
	@echo "Optional signing (passed to xcodebuild when set):"
	@echo "  CODE_SIGN_IDENTITY=\"Apple Development\""
	@echo "  DEVELOPMENT_TEAM=<Team ID>"
	@echo "  CODE_SIGN_STYLE=Automatic|Manual"
	@echo "  PROVISIONING_PROFILE_SPECIFIER=<profile name>"
	@echo "  CODE_SIGN_ENTITLEMENTS=<path>   (SRCROOT-relative; default from Xcode project)"
	@echo ""
	@echo "  make list-identities   Show codesigning identities on this Mac"

all: menu

submodules:
	git submodule update --init --recursive

configure: submodules
	cmake -S "$(ROOT_DIR)" -B "$(BUILD_DIR)" -DCMAKE_BUILD_TYPE="$(CONFIG)"

cli: configure
	cmake --build "$(BUILD_DIR)" --config "$(CONFIG)" -j"$(JOBS)"

menu: cli
	xcodebuild \
		-project "$(ROOT_DIR)/macos-menu/OCA mDNS Gateway.xcodeproj" \
		-scheme "OCA mDNS Gateway" \
		-configuration "$(CONFIG)" \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(XCODE_SIGN_ARGS) \
		build

clean:
	@if [ -d "$(BUILD_DIR)" ]; then cmake --build "$(BUILD_DIR)" --target clean || true; fi
	xcodebuild \
		-project "$(ROOT_DIR)/macos-menu/OCA mDNS Gateway.xcodeproj" \
		-scheme "OCA mDNS Gateway" \
		-configuration "$(CONFIG)" \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		clean || true

distclean: clean
	rm -rf "$(BUILD_DIR)" "$(DERIVED_DATA)"

list-identities:
	security find-identity -v -p codesigning
