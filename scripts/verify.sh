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

# 3b. With valid basic-auth credentials, walled paths reach the upstream
# (200, 302, or 401 from the upstream itself are all "the proxy works").
# This requires BASICAUTH_USER + BASICAUTH_PASS env vars.
if [[ -n "${BASICAUTH_USER:-}" && -n "${BASICAUTH_PASS:-}" ]]; then
  for spec in "graf:200 302" "mitm:200 401" "hermes:200 302 401 502"; do
    path="${spec%%:*}"; allowed="${spec#*:}"
    CODE=$(curl -sko /dev/null -w '%{http_code}' --max-time 10 \
      -u "$BASICAUTH_USER:$BASICAUTH_PASS" "https://$HOSTNAME/$path/" || true)
    # shellcheck disable=SC2076
    if [[ " $allowed " =~ " $CODE " ]]; then
      pass "/$path reaches upstream (code=$CODE)"
    else
      fail "/$path with auth returned $CODE (expected one of: $allowed)"
    fi
  done
else
  echo "SKIP: authenticated upstream probes (set BASICAUTH_USER + BASICAUTH_PASS)"
fi

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
