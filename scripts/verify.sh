#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="${1:-}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_TARGET="${SSH_TARGET:-}"

if [[ -z "$HOSTNAME" ]]; then
  echo "usage: $0 <hostname> [SSH_PORT=…] [SSH_TARGET=user@ip]"
  exit 2
fi

fail()  { echo "FAIL: $1"; exit 1; }
pass()  { echo "PASS: $1"; }

# 1. DNS resolves
DNS_IP=$(dig +short "$HOSTNAME" A | head -1)
[[ -n "$DNS_IP" ]] || fail "DNS for $HOSTNAME does not resolve"
pass "DNS for $HOSTNAME -> $DNS_IP"

# 2. TLS valid + Caddy alive
HEALTH=$(curl -sf --max-time 10 "https://$HOSTNAME/health" || true)
[[ "$HEALTH" == "ok" ]] || fail "https://$HOSTNAME/health did not return 'ok' (got: $HEALTH)"
pass "TLS + Caddy serving /health"

# 3. Walled paths return 401 (auth required) — not 5xx
for path in /mitm /graf /hermes; do
  CODE=$(curl -sko /dev/null -w '%{http_code}' --max-time 10 "https://$HOSTNAME$path" || true)
  [[ "$CODE" == "401" ]] || fail "$path returned $CODE (expected 401)"
done
pass "walled paths return 401"

# 4. Containers healthy (over SSH)
if [[ -n "$SSH_TARGET" ]]; then
  STATUS=$(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
    "cd /opt/hermes/stack && docker compose ps --format json" || true)
  if echo "$STATUS" | jq -r '.[].Health' 2>/dev/null | grep -vq '^healthy$'; then
    fail "at least one container is not healthy"
  else
    pass "all containers healthy"
  fi
else
  echo "SKIP: container health (no SSH_TARGET provided)"
fi

echo "All P1 checks passed."
