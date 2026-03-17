#!/bin/zsh

set -euo pipefail

IDENTITY_NAME="${FLOATREC_SIGNING_IDENTITY:-FloatRec Local Signer}"
KEYCHAIN_PATH="${FLOATREC_SIGNING_KEYCHAIN_PATH:-$HOME/.floatrec-local-signing/FloatRecLocal.keychain-db}"
KEYCHAIN_PASSWORD="${FLOATREC_SIGNING_KEYCHAIN_PASSWORD:-floatrec-local}"
WORK_DIR="$(dirname "$KEYCHAIN_PATH")"
CERT_DIR="$WORK_DIR/generated"
OPENSSL_CONFIG="$CERT_DIR/openssl.cnf"
CERT_PATH="$CERT_DIR/cert.pem"
P12_PATH="$CERT_DIR/cert.p12"

mkdir -p "$CERT_DIR"

ensure_keychain_in_search_list() {
  local -a current_keychains
  current_keychains=("${(@f)$(security list-keychains -d user | tr -d '"')}")

  if [[ ! " ${current_keychains[*]} " == *" ${KEYCHAIN_PATH} "* ]]; then
    security list-keychains -d user -s "$KEYCHAIN_PATH" "${current_keychains[@]}"
  fi
}

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
  fi

  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

  cat > "$OPENSSL_CONFIG" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY_NAME
[ ext ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_PATH" \
    -days 3650 \
    -nodes \
    -config "$OPENSSL_CONFIG" >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -legacy \
    -out "$P12_PATH" \
    -inkey "$CERT_DIR/key.pem" \
    -in "$CERT_PATH" \
    -passout "pass:$KEYCHAIN_PASSWORD" >/dev/null 2>&1

  security import "$P12_PATH" -k "$KEYCHAIN_PATH" -P "$KEYCHAIN_PASSWORD" -T /usr/bin/codesign >/dev/null
  security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN_PATH" "$CERT_PATH" >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
ensure_keychain_in_search_list

echo "$IDENTITY_NAME"
