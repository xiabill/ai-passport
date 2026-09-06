#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
app="${root}/FoloVibeBridge.app"
install_app="${FOLO_VIBE_INSTALL_APP:-/Applications/FoloVibeBridge.app}"
mkdir -p "$app/Contents/MacOS"
cp "$root/Info.plist" "$app/Contents/Info.plist"

# Stamp the version from the git tag. Hand-maintained versions drift: the
# plist still said 0.2.2 several releases later, which makes an updater
# unable to tell whether it is current.
version="$(git -C "$root" describe --tags --always 2>/dev/null | sed 's/^v//; s/-vibe-typeless//')"
if [[ -n "$version" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
        "$app/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" \
        "$app/Contents/Info.plist" >/dev/null 2>&1 || true
    echo "version $version"
fi

# A stable signing identity keeps the macOS permission grants across upgrades.
# An ad-hoc signature ties them to the binary's cdhash, which changes on every
# build, so every upgrade looked like a different app and lost its grants.
# ./create-signing-identity.sh sets one up; without it we just warn.
sign_identity="${FOLO_VIBE_SIGN_IDENTITY:-FoloVibe Bridge Local}"

sign_app() {
    if ! security find-identity -p codesigning 2>/dev/null | grep -qF "$sign_identity"; then
        echo "note: no stable signing identity, so macOS will ask for permissions"
        echo "      again after each upgrade. Run ./create-signing-identity.sh once."
        return
    fi
    if codesign --force --sign "$sign_identity" \
        --identifier "dev.folovibe.bridge" "$1" >/dev/null 2>&1; then
        echo "signed with $sign_identity"
    else
        echo "warning: signing failed; keeping the ad-hoc signature" >&2
    fi
}

package_app() {
    local binary="$1"
    cp "$binary" "$app/Contents/MacOS/FoloVibeBridge"
    # Sign before copying so the installed bundle carries the signature too.
    sign_app "$app"
    if [[ "${FOLO_VIBE_SKIP_INSTALL:-0}" != "1" ]]; then
        mkdir -p "$(dirname -- "$install_app")"
        ditto --rsrc --extattr --acl "$app" "$install_app"
        echo "installed $install_app"
        echo "run: open \"$install_app\""
    else
        echo "built $app"
        echo "run: open \"$app\""
    fi
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
