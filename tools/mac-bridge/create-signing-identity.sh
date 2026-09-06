#!/usr/bin/env bash
# Creates a local, self-signed code signing identity for the Bridge.
#
# Without it the app is ad-hoc signed, and its designated requirement is the
# binary's cdhash. Every rebuild changes that hash, so macOS treats the new
# build as a different app and drops the Accessibility, Bluetooth, and Input
# Monitoring grants — which is why permissions had to be granted again after
# every upgrade. Signing with a stable identity makes the requirement depend on
# the identifier and this certificate instead, so grants survive rebuilds.
#
# Run once. macOS will ask for your login password to store the key.
set -euo pipefail

name="${FOLO_VIBE_SIGN_IDENTITY:-FoloVibe Bridge Local}"
keychain="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -qF "$name"; then
    echo "signing identity already present: $name"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -subj "/CN=${name}" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# macOS's security(1) cannot read a PKCS#12 built with modern defaults, so ask
# for the older algorithms it does understand. A non-empty password is used
# because an empty one trips the MAC check on some toolchains.
pass="folovibe"
openssl pkcs12 -export -out "$tmp/id.p12" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -passout "pass:${pass}"

echo "Importing the identity — macOS will ask for your login password."
security import "$tmp/id.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign

# Let codesign use the key without prompting on every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "" "$keychain" >/dev/null 2>&1 || true

if security find-identity -p codesigning 2>/dev/null | grep -qF "$name"; then
    echo "created: $name"
    echo "It is listed as untrusted, which is expected for a self-signed"
    echo "certificate and affects neither signing nor the permission grants."
    echo "Rebuild with ./build.sh, then grant permissions once more."
    echo "They will persist across later upgrades."
else
    echo "the identity was not created; the app will stay ad-hoc signed" >&2
    exit 1
fi
