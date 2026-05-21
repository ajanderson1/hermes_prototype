"""mitmproxy addon: log every HTTP(S) flow to /audit/mitm.jsonl as JSONL.

Each line is:
  {"ts": <RFC3339>, "kind": "egress", "method": ..., "host": ..., "path": ...,
   "status": ..., "duration_ms": ..., "request_bytes": ..., "response_bytes": ...,
   "actor": "hermes"}

Bodies are intentionally NOT logged (could contain API keys, PII). Headers
likewise excluded; we keep this to flow-level metadata so the audit is
useful without becoming a secondary breach surface.
"""

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from mitmproxy import http  # type: ignore

AUDIT_DIR = Path(os.environ.get("AUDIT_DIR", "/audit"))
AUDIT_FILE = AUDIT_DIR / "mitm.jsonl"


def _ts() -> str:
    return datetime.now(timezone.utc).isoformat()


def _emit(record: dict) -> None:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    with AUDIT_FILE.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, separators=(",", ":")) + "\n")


def request(flow: http.HTTPFlow) -> None:
    flow.metadata["t_start"] = time.monotonic()


def response(flow: http.HTTPFlow) -> None:
    t_start = flow.metadata.get("t_start", time.monotonic())
    duration_ms = int((time.monotonic() - t_start) * 1000)
    req = flow.request
    resp = flow.response
    record = {
        "ts": _ts(),
        "kind": "egress",
        "actor": "hermes",
        "method": req.method,
        "host": req.pretty_host,
        "port": req.port,
        "scheme": req.scheme,
        "path": req.path.split("?", 1)[0],
        "status": resp.status_code if resp else None,
        "duration_ms": duration_ms,
        "request_bytes": len(req.raw_content or b""),
        "response_bytes": len(resp.raw_content or b"") if resp else 0,
    }
    _emit(record)


def error(flow: http.HTTPFlow) -> None:
    record = {
        "ts": _ts(),
        "kind": "egress_error",
        "actor": "hermes",
        "host": flow.request.pretty_host if flow.request else None,
        "path": flow.request.path.split("?", 1)[0] if flow.request else None,
        "error": str(flow.error) if flow.error else "unknown",
    }
    _emit(record)
