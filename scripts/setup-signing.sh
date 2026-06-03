#!/usr/bin/env bash
# Create a STABLE self-signed code-signing identity for local development.
#
# Why: WarpSpeed uses the Accessibility API (for window-focus cycling). macOS's
# permission system (TCC) keys the grant to the app's code-signing identity.
# Ad-hoc signatures (`codesign -s -`) get a fresh hash every build, so macOS
# treats each rebuild as a new app and drops the Accessibility grant — you'd
# have to re-grant on every update. Signing with a stable self-signed cert keeps
# the grant across rebuilds.
#
# This identity is local to your machine and is NOT in the repo. It is untrusted
# by Gatekeeper (same as ad-hoc) — that's fine; quarantine removal still applies.
# For cross-user distribution, a Developer ID cert + notarization is the real fix
# (future work). Run once: scripts/setup-signing.sh

set -euo pipefail

KC="$HOME/Library/Keychains/warpspeed-signing.keychain-db"
KCPW="${WARPSPEED_KEYCHAIN_PW:-warpspeed-local}"
CN="WarpSpeed Self-Signed"
P12PW="transient-p12-pw"

if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$CN"; then
    echo "Identity '$CN' already exists in $KC — nothing to do."
    security find-identity -p codesigning "$KC" | grep "$CN"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = WarpSpeed Self-Signed
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

echo "Generating self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -nodes -config "$WORK/cert.cnf" 2>/dev/null

# -legacy + sha1 MAC: macOS `security` can't import OpenSSL 3's modern PKCS#12 MAC.
# A non-empty password avoids an empty-password MAC-verification quirk in `security`.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout "pass:$P12PW" -macalg sha1 2>/dev/null

echo "Creating dedicated keychain and importing..."
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$KCPW" "$KC"
# Append to the user keychain search list so codesign can find the identity.
security list-keychains -d user -s "$KC" $(security list-keychains -d user | sed 's/"//g')
security import "$WORK/id.p12" -k "$KC" -P "$P12PW" -T /usr/bin/codesign
# Let codesign use the private key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null 2>&1

echo "Done. Identity:"
security find-identity -p codesigning "$KC" | grep "$CN"
echo
echo "build.sh will now sign with '$CN' automatically."
