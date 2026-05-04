#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# Idempotently generates a self-signed PKCS12 keystore at
# .devcontainer/james-conf/keystore for the apache/james:memory-3.9.0
# image. James ships imapserver.xml with TLS enabled and references
# /root/conf/keystore, but no keystore is bundled in the image —
# without one, James fails at startup with NoSuchFileException.
#
# The keystore is a self-signed test fixture with the hardcoded
# password james72laBalle (the value James's bundled imapserver.xml
# expects). It is NOT intended for production use; it exists solely
# so the IMAP TLS port can bind during James startup. Our integration
# tests target HTTP JMAP only and never exercise IMAP/TLS.
#
# Generation runs inside a one-shot container with --platform
# linux/amd64 so the script behaves identically on arm64 and amd64
# hosts (PKCS12 keystores are byte-portable across architectures).
set -euo pipefail

KEYSTORE_DIR="$(dirname "$0")/../james-conf"
KEYSTORE_PATH="$KEYSTORE_DIR/keystore"

if [ -s "$KEYSTORE_PATH" ]; then
  exit 0
fi

mkdir -p "$KEYSTORE_DIR"

GEN_NAME="james-keystore-gen-$$"
trap 'docker rm -f "$GEN_NAME" >/dev/null 2>&1 || true' EXIT

echo "Generating self-signed James IMAP keystore at $KEYSTORE_PATH..."
docker run --name "$GEN_NAME" --platform linux/amd64 \
  --entrypoint keytool apache/james:memory-3.9.0 \
  -genkeypair -alias james -keyalg RSA -storetype PKCS12 \
  -keystore /tmp/keystore \
  -storepass james72laBalle -keypass james72laBalle \
  -dname 'CN=james,OU=test,O=test,L=test,S=test,C=US' \
  -validity 3650 -noprompt >/dev/null

docker cp "$GEN_NAME:/tmp/keystore" "$KEYSTORE_PATH"

if [ ! -s "$KEYSTORE_PATH" ]; then
  echo "ERROR: keystore generation produced empty file at $KEYSTORE_PATH" >&2
  exit 1
fi

echo "Keystore ready ($(wc -c < "$KEYSTORE_PATH") bytes)"
