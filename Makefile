SHELL := /bin/sh

SWIFT_REPO := $(CURDIR)
DEMUCS_REPO ?= $(abspath ../demucs-rs)
MANIFEST := $(DEMUCS_REPO)/demucs-ffi/Cargo.toml
BINDGEN_MANIFEST := $(DEMUCS_REPO)/uniffi-bindgen/Cargo.toml
BINDGEN := $(DEMUCS_REPO)/target/release/uniffi-bindgen
APPLE_TARGET_DIR := $(DEMUCS_REPO)/target/apple
LIB_NAME := libdemucs_ffi.a

IOS_DEPLOYMENT_TARGET ?= 16.0
MACOS_DEPLOYMENT_TARGET ?= 14.0
TVOS_DEPLOYMENT_TARGET ?= 16.0
VISIONOS_DEPLOYMENT_TARGET ?= 1.0

LOCAL_DIR := $(SWIFT_REPO)/.local
GENERATED_DIR := $(LOCAL_DIR)/generated/Demucs
HEADERS_DIR := $(LOCAL_DIR)/Headers
FRAMEWORK_DIR := $(SWIFT_REPO)/DemucsFramework.xcframework
SWIFT_GLUE := $(SWIFT_REPO)/Sources/Demucs/demucs_ffi.swift

# demucs-rs's .cargo/config.toml builds macOS with `-C target-cpu=native`;
# clear it so a local framework behaves like the released one.
export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS :=

# $(call rustc,<target>,<deployment env>,<extra cargo args>)
rustc = $(2) cargo $(3) rustc --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target $(1) --release --lib --crate-type staticlib
lib = $(APPLE_TARGET_DIR)/$(1)/release/$(LIB_NAME)

.PHONY: help validate ios macos tvos visionos build-bindgen prepare generate-swift clean

help:
	@printf '%s\n' \
	  'Demucs Swift local builds' \
	  '' \
	  'make ios | macos | tvos | visionos' \
	  'Set DEMUCS_REPO=/path/to/demucs-rs when the repositories are not siblings.'

validate:
	@test -f "$(MANIFEST)" || { echo "Could not find demucs-rs at $(DEMUCS_REPO)"; exit 1; }

build-bindgen: validate
	cargo build --manifest-path "$(BINDGEN_MANIFEST)" --release

prepare:
	@rm -rf "$(FRAMEWORK_DIR)" "$(GENERATED_DIR)" "$(HEADERS_DIR)"
	@mkdir -p "$(GENERATED_DIR)" "$(HEADERS_DIR)"

generate-swift:
	@test -n "$(BINDGEN_INPUT)" || { echo "BINDGEN_INPUT is required"; exit 1; }
	cd "$(DEMUCS_REPO)" && "$(BINDGEN)" generate "$(BINDGEN_INPUT)" --crate demucs_ffi --language swift --out-dir "$(GENERATED_DIR)"
	cp "$(GENERATED_DIR)/demucs_ffi.swift" "$(SWIFT_GLUE)"
	cp "$(GENERATED_DIR)/demucs_ffiFFI.h" "$(HEADERS_DIR)/demucs_ffiFFI.h"
	cp "$(GENERATED_DIR)/demucs_ffiFFI.modulemap" "$(HEADERS_DIR)/module.modulemap"

ios: build-bindgen prepare
	$(call rustc,aarch64-apple-ios,IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET))
	$(call rustc,aarch64-apple-ios-sim,IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET))
	$(MAKE) generate-swift BINDGEN_INPUT="$(call lib,aarch64-apple-ios)"
	xcodebuild -create-xcframework \
	  -library "$(call lib,aarch64-apple-ios)" -headers "$(HEADERS_DIR)" \
	  -library "$(call lib,aarch64-apple-ios-sim)" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

macos: build-bindgen prepare
	$(call rustc,aarch64-apple-darwin,MACOSX_DEPLOYMENT_TARGET=$(MACOS_DEPLOYMENT_TARGET))
	$(MAKE) generate-swift BINDGEN_INPUT="$(call lib,aarch64-apple-darwin)"
	xcodebuild -create-xcframework \
	  -library "$(call lib,aarch64-apple-darwin)" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

# tvOS and visionOS are tier 3 targets: no prebuilt std, so nightly + build-std.
tvos: build-bindgen prepare
	$(call rustc,aarch64-apple-tvos,TVOS_DEPLOYMENT_TARGET=$(TVOS_DEPLOYMENT_TARGET),+nightly -Z build-std)
	$(call rustc,aarch64-apple-tvos-sim,TVOS_DEPLOYMENT_TARGET=$(TVOS_DEPLOYMENT_TARGET),+nightly -Z build-std)
	$(MAKE) generate-swift BINDGEN_INPUT="$(call lib,aarch64-apple-tvos)"
	xcodebuild -create-xcframework \
	  -library "$(call lib,aarch64-apple-tvos)" -headers "$(HEADERS_DIR)" \
	  -library "$(call lib,aarch64-apple-tvos-sim)" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

visionos: build-bindgen prepare
	$(call rustc,aarch64-apple-visionos,XROS_DEPLOYMENT_TARGET=$(VISIONOS_DEPLOYMENT_TARGET),+nightly -Z build-std)
	$(call rustc,aarch64-apple-visionos-sim,XROS_DEPLOYMENT_TARGET=$(VISIONOS_DEPLOYMENT_TARGET),+nightly -Z build-std)
	$(MAKE) generate-swift BINDGEN_INPUT="$(call lib,aarch64-apple-visionos)"
	xcodebuild -create-xcframework \
	  -library "$(call lib,aarch64-apple-visionos)" -headers "$(HEADERS_DIR)" \
	  -library "$(call lib,aarch64-apple-visionos-sim)" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

clean:
	rm -rf "$(FRAMEWORK_DIR)" "$(LOCAL_DIR)"
