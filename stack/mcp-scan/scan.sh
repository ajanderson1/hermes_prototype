#!/bin/sh
# Periodically scan all MCP server configs visible to Hermes and emit
# audit records to /audit/mcp-scan.jsonl. Picked up by Promtail.
#
# Uses Invariant Labs' open-source `mcp-scan` tool (https://github.com/invariantlabs-ai/mcp-scan)
# installed on first run via uvx — the upstream Hermes image already
# ships uv, so this is essentially free.
set -eu

AUDIT_DIR="${HERMES_AUDIT_DIR:-/audit}"
OUT="$AUDIT_DIR/mcp-scan.jsonl"
INTERVAL="${MCP_SCAN_INTERVAL:-3600}"  # 1h between scans

mkdir -p "$AUDIT_DIR"

emit() {
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' "{\"ts\":\"$ts\",\"kind\":\"mcp-scan\",\"actor\":\"mcp-scan\",\"message\":\"$1\"}" >> "$OUT"
}

scan_once() {
  emit "scan started"
  # mcp-scan reads ~/.cursor/mcp.json, ~/.config/Claude/mcp.json, and any
  # MCP server config files passed as args. Hermes stores its MCP config
  # under /opt/data/mcp/, so we point the scanner there.
  config_glob="/opt/data/mcp/*.json /opt/data/.cursor/mcp.json /opt/data/.config/Claude/mcp.json"
  # shellcheck disable=SC2086
  if uvx --quiet mcp-scan@latest scan --json $config_glob 2>/dev/null >> "$OUT"; then
    emit "scan completed ok"
  else
    emit "scan failed or no configs found (non-fatal on first run)"
  fi
}

# Run once at startup, then every $INTERVAL seconds.
while true; do
  scan_once || true
  sleep "$INTERVAL"
done
