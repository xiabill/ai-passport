#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
app="${root}/FoloVibeBridge.app"
mkdir -p "$app/Contents/MacOS"
cp "$root/Info.plist" "$app/Contents/Info.plist"

package_app() {
    local binary="$1"
    cp "$binary" "$app/Contents/MacOS/FoloVibeBridge"
    echo "built $app"
    echo "run: open \"$app\""
}

# SwiftPM can select a newer SDK than an older standalone Swift toolchain can
# understand. Allow a matching local toolchain/SDK pair without requiring the
# full Xcode app. Set FOLO_VIBE_SWIFTC and FOLO_VIBE_SDKROOT to override the
# auto-detected pair.
toolchain_dir="${FOLO_VIBE_TOOLCHAIN_DIR:-${HOME}/Library/Developer/Toolchains/swift-5.10.1-RELEASE.xctoolchain}"
swiftc_bin="${FOLO_VIBE_SWIFTC:-${toolchain_dir}/usr/bin/swiftc}"
sdkroot="${FOLO_VIBE_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk}"

if [[ -x "$swiftc_bin" && -d "$sdkroot" ]]; then
    build_dir="$(mktemp -d "${TMPDIR:-/tmp}/folo-vibe-bridge.XXXXXX")"
    core_module="$build_dir/FoloVibeCore.swiftmodule"
    core_object="$build_dir/FoloVibeCore.o"
    tests_binary="$build_dir/FoloVibeCoreTests"
    bridge_binary="$build_dir/FoloVibeBridge"

    "$swiftc_bin" -whole-module-optimization \
        -emit-module -emit-object \
        -emit-module-path "$core_module" \
        -o "$core_object" \
        -sdk "$sdkroot" \
        -module-name FoloVibeCore \
        Sources/FoloVibeCore/*.swift

    "$swiftc_bin" -whole-module-optimization \
        -sdk "$sdkroot" \
        -I "$build_dir" \
        -module-name FoloVibeCoreTests \
        Tests/main.swift "$core_object" \
        -o "$tests_binary"
    "$tests_binary"

    "$swiftc_bin" -whole-module-optimization \
        -sdk "$sdkroot" \
        -I "$build_dir" \
        -module-name FoloVibeBridge \
        Sources/App/*.swift "$core_object" \
        -o "$bridge_binary" \
        -Xlinker -lsqlite3
    package_app "$bridge_binary"
    exit 0
fi

swift run FoloVibeCoreTests
swift build -c release --product FoloVibeBridge
package_app "$root/.build/release/FoloVibeBridge"
