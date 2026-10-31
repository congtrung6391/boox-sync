#!/bin/bash
# One-time: create a self-signed code-signing certificate in the login keychain so rebuilt copies of
# BooxSync keep their macOS permissions (Screen Recording, Accessibility, Automation).
# macOS ties those grants to the code signature; an ad-hoc signature changes on every build, this one does not.
# The certificate is not trusted by Gatekeeper and is only meant for local builds.
set -euo pipefail

NAME="BooxSync Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "\"$NAME\" already exists"; exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -config "$WORK/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout pass:tmp
security import "$WORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P tmp -T /usr/bin/codesign
echo "Created \"$NAME\". Run scripts/build-app.sh; macOS will ask for the permissions once more."
