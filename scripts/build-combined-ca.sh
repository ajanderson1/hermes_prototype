#!/usr/bin/env bash
# Build a combined CA bundle that trusts both:
#   - the system's public CAs (so Hermes can reach Telegram, GitHub, etc. directly)
#   - mitmproxy's auto-generated CA (so mitmproxy-intercepted HTTPS works)
#
# Output: /opt/hermes/data/ca/combined-ca.pem (mode 644, mounted into hermes)
#
# Run this once after the first `docker compose up` brings mitmproxy up, so the
# mitmproxy CA file exists in the named volume. The compose file then mounts
# the combined bundle into the hermes container at /etc/ssl/certs/combined-ca.pem
# and exports SSL_CERT_FILE / REQUESTS_CA_BUNDLE pointing to it.
set -euo pipefail

OUT_DIR="${OUT_DIR:-/opt/hermes/data/ca}"
OUT_FILE="$OUT_DIR/combined-ca.pem"

sudo mkdir -p "$OUT_DIR"
sudo docker run --rm \
  -v hermes_mitm_data:/mitm:ro \
  -v "$OUT_DIR:/out" \
  debian:13-slim \
  sh -c 'apt-get update -qq \
    && apt-get install -y --no-install-recommends ca-certificates -qq >/dev/null 2>&1 \
    && cat /etc/ssl/certs/ca-certificates.crt /mitm/mitmproxy-ca-cert.pem > /out/combined-ca.pem'

sudo chmod 0644 "$OUT_FILE"
echo "wrote $OUT_FILE ($(sudo stat -c %s "$OUT_FILE") bytes)"
