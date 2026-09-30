#!/bin/bash

# Run the Swift test suite with Command Line Tools only (no Xcode required).
#
# Two CLT-specific quirks are handled here:
#   1. The 27.0 SDK turns SwiftUI's @State into a macro whose plugin ships
#      only with full Xcode, so the build fails before it ever reaches our
#      code. Pinning SDKROOT to 26.5 keeps @State macro-free.
#   2. SwiftPM does not pass -load-plugin-library for swift-testing's
#      TestingMacros when no Xcode is installed, so @Test fails to expand.
#      We point the compiler at the plugin bundled with the toolchain.
#
# Caches are kept inside .build so restricted environments (and CI) never
# need to write to ~/Library.
set -e

cd "$(dirname "$0")/.."

SWIFT_FLAGS=()

if [ -z "$SDKROOT" ] && [ ! -d "$HOME/Library/Developer/Xcode" ]; then
    if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
        export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    fi

    SWIFTC_BIN="$(xcrun --find swiftc 2>/dev/null || true)"
    if [ -n "$SWIFTC_BIN" ]; then
        TESTING_MACROS="$(dirname "$SWIFTC_BIN")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
        if [ -f "$TESTING_MACROS" ]; then
            SWIFT_FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_MACROS")
        fi
    fi
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/modulecache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/modulecache}"

exec swift test \
    --disable-sandbox \
    --cache-path .build/pm-cache \
    --config-path .build/pm-config \
    --security-path .build/pm-security \
    "${SWIFT_FLAGS[@]}" \
    "$@"
