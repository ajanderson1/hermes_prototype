# Hermes Prototype — Design

**Status:** Draft for review
**Date:** 2026-05-21
**Author:** AJ Anderson (with Claude)
**Scope:** High-level architectural design covering all subsystems. Vision/architecture spec, not implementation-ready spec. Implementation plan will be derived per subsystem.

---

## 1. System overview & goals

A single-VM prototype that runs the Nous Research **Hermes Agent** harness as its agentic brain, points it at **Claude (Anthropic)** and **Codex (OpenAI)** for inference, exposes it to **Telegram** and **Discord** via Hermes's built-in Messaging Gateway, intercepts 100% of egress traffic through a local **mitmproxy**, and gates plan-level decisions behind a human approval flow surfaced in Telegram.

### Why this shape

The brief asked for the "full Hermes capability demo as intended by the Nous Research developers." In 2026, that means the **Hermes Agent harness** (skills, Curator, subagents, MCP client, Messaging Gateway), not the Hermes 4 model weights. The non-negotiable constraint — using existing Claude and Codex subscriptions for inference — makes Hermes's model-agnostic design the centrepiece and removes any need for self-hosted GPU.

### Three first-class subsystems, in priority order

1. **HITL control plane** (stated #1 feature) — gated autonomy. Hermes plans freely, executes freely between gates, but every plan must be human-approved before crossing the gate. Decisions are durable, auditable, replayable.
2. **Audit pipeline** — all outbound HTTP/HTTPS from the agent container is forced through mitmproxy. The MCP "scan" is a startup-time policy validator that inspects every MCP server's advertised tool manifest against an allowlist before Hermes registers it.
3. **Portable infra** — single OpenTofu codebase deploys to GCP or Hetzner with `-var cloud=...`. Both produce the same cloud-init-bootstrapped Docker host.

### Out of scope for v1

- Self-hosting Hermes 4 weights (no GPU node).
- Multi-VM, HA, autoscaling. One VM, one Docker network.
- Custom dashboard frontend. Existing UIs are composed under one reverse proxy.
- Production traffic. Single operator, single tenant.

### Success criteria

- `tofu apply` against GCP produces a working environment in <15 min; same command with `-var cloud=hetzner` produces an equivalent environment.
- Sending a task to the Telegram bot causes Hermes to produce a plan (`/plan` skill) and pause; the human approves via reply (or by editing the plan file); execution then proceeds.
- Risky actions (configurable pattern list) trigger Hermes's shipped inline-button approval card on Telegram.
- Every outbound HTTPS call made during the run is visible in mitmweb with full request/response bodies.
- A Discord user can target the same agent from a different channel and experience the same gate flow.
- All of the above run on a single $20-ish/month VM, **paid only while a session is up** (spin-up/spin-down workflow).

### Operating model: spin-up / spin-down (GCP-as-prototype-cloud)

GCP is the primary target because of per-second billing — the prototype is intended to be **paid for only when in use**. End of session: snapshot + `tofu destroy`. Start of session: `tofu apply` + restore. Hetzner is the "promote to always-on" target for later. The state backend (Hetzner Object Storage) is load-bearing for this workflow — it survives every compute-side `tofu destroy`.

---

## 2. Architecture & components

### Topology

Single VM. Single Docker network (`audit-net`). Caddy on the VM's host network terminates public TLS and reverse-proxies the rest.

```
                        Internet
                            │
                ┌───────────▼────────────┐
                │  Caddy (host network)  │  TLS, basic-auth, IP allowlist
                │   hermes.<your-domain> │
                └─┬──────┬──────┬────────┘
                  │      │      │
              /mitm  /graf  /hermes
                  │      │      │
   ┌──────────────▼──────▼──────▼─────────────────────────┐
   │ Docker network: audit-net                            │
   │                                                      │
   │  ┌───────────────┐  outbound (HTTP_PROXY)            │
   │  │ hermes-agent  │ ───────────►  ┌─────────────────┐ │
   │  │ (Hermes Agent │               │   mitmproxy     │ │
   │  │  + Gateway    │               │  (mitmweb @8081)│ │
   │  │  + skills)    │ ◄─── tools ───┤  CA trusted     │ │
   │  └──────┬────────┘               └───────┬─────────┘ │
   │         │                                │           │
   │         │ webhook in                     ▼ (egress)  │
   │         ▼                            to Internet     │
   │   Telegram + Discord                                 │
   │   (Hermes Gateway: shipped)                          │
   │                                                      │
   │  ┌────────────────────────┐   ┌──────────┐           │
   │  │ mcp-scanner (oneshot)  │   │  Loki    │           │
   │  │ runs before hermes-    │   │ Tempo    │           │
   │  │ agent starts           │   │ Grafana  │           │
   │  └────────────────────────┘   └──────────┘           │
   └──────────────────────────────────────────────────────┘
```

### Components

| Component | Purpose | Inputs | Outputs |
|---|---|---|---|
| **caddy** (host) | Public TLS, basic-auth, IP allowlist for `/mitm` | HTTPS from internet | Reverse-proxies to internal services |
| **hermes-agent** | The Nous Hermes Agent harness. Skills, Curator, Subagents, MCP client, Messaging Gateway (Telegram + Discord enabled) | User messages from Telegram/Discord; tool results | LLM calls to Claude/Codex; tool calls; inline-button approval cards |
| **mitmproxy** | Forced HTTP/HTTPS proxy for every outbound connection from `hermes-agent`. mitmweb exposed at `/mitm`. CA cert trusted only inside the hermes-agent container | All hermes-agent egress | Full request/response stream (UI + structured log to Loki) |
| **mcp-scanner** | Oneshot init container. For each configured MCP server, fetches its tool manifest, validates against `policy.yaml`. Fails the stack if any server violates policy. | `policy.yaml`, MCP server addresses | Pass/fail + structured report to Loki |
| **loki / tempo / grafana** | Standard LGT stack. Ingests container logs + audit events from mitmproxy + Hermes's decision hook | Container logs, structured audit events | Dashboards + alerts |

### Trust boundaries

- The mitmproxy CA is trusted **only** inside `hermes-agent`. Other containers hitting the internet use real CAs — mitmproxy is unbypassable by the agent but doesn't tamper with anyone else's traffic.
- Caddy is the only public ingress. Telegram/Discord webhooks come in via Caddy with a path-scoped secret.
- Docker egress firewall: outbound TCP from `hermes-agent` is only permitted to `mitmproxy:8080`. DNS goes to a pinned resolver and is logged separately.

### Data stores (single-VM appropriate)

- Hermes Agent: its own SQLite (skills, memory, FTS5 — managed by Hermes). Mounted volume.
- Loki + Tempo: filesystem backend, mounted volume, 30-day retention.
- mitmproxy: rolling flow files, mounted volume, 7-day retention.

### Custom code surface area (total)

- 1 mitmproxy addon (~40 LOC) for structured audit events.
- 1 Hermes hook plugin (~30 LOC) for decision audit correlation.
- 1 MCP scanner (~30 LOC orchestration around `mcp-cli` + policy YAML).
- 1 Grafana dashboard (JSON, no code).
- 1 OpenTofu codebase (~300 LOC across both cloud modules).
- A few small bash scripts (`up`, `down`, `verify`, `migrate`).

**Everything else is off-the-shelf.** Hermes, mitmproxy, Caddy, Loki, Grafana, OpenTofu, Docker Compose.

---

## 3. HITL gating model — Hermes-native

**Design principle:** use what Hermes ships. Add the minimum needed to wire it into the audit pipeline. New code only fills holes Hermes genuinely doesn't fill.

### Two gates in v1 (third deferred)

| Gate | Implementation | Custom code? |
|---|---|---|
| **PLAN** | `/plan` slash command + the bundled `software-development-plan` skill writes `~/.hermes/plans/<task>.md`. Human reads it (TUI, web, or via Telegram by asking Hermes to summarise the plan back). Human replies in chat to execute. | **None.** Shipped. |
| **RISKY ACTION** | `approvals.mode: manual` in `~/.hermes/config.yaml`. Hermes intercepts patterns from the curated dangerous-command list plus our additions. On a match, Hermes posts an inline-button approval card to Telegram. Hardline blocklist remains non-overridable. | **None.** Shipped. |
| ~~MILESTONE~~ | Deferred to v2. If/when needed, implement as a `pre_tool_call` hook watching for a sentinel tool call. | n/a |
| ~~ESCALATION~~ | Hermes's existing `clarify` tool with inline keyboards already covers this. | **None.** Shipped. |

### Configuration knobs (the entire "build" for HITL)

`~/.hermes/config.yaml` (excerpt):

```yaml
approvals:
  mode: manual
  command_allowlist:
    - "git status"
    - "git diff*"
    - "ls *"
    - "cat *"
  pattern_extensions:                # ADDED beyond Hermes defaults
    - pattern: "gh pr (merge|close)*"
      action: ask
    - pattern: "gcloud * delete*"
      action: ask
    - pattern: "tofu (apply|destroy)*"
      action: ask
    - pattern: "*--force*"
      action: ask
messaging:
  telegram:
    enabled: true
    allowed_users: ["<your-tg-id>"]
  discord:
    enabled: true
    allowed_users: ["<your-discord-id>"]
plan:
  default_skill: software-development-plan
```

### The one custom piece: audit hook (~30 LOC)

The single Hermes-native gap that matters for this prototype is the **unified decision audit log with `trace_id` correlation to mitmproxy traffic**. Without it, Grafana can't pivot from "this decision" to "this exact LLM call and tool call." So we add one small hook plugin:

```python
# ~/.hermes/hooks/audit_decisions.py  (~30 LOC)
# Registers post_tool_call hook.
# When Hermes records an approval-tool outcome (approve/deny/edit),
# emit a structured JSON line to /var/log/hermes/decisions.log:
#   {ts, gate_type, pattern, decision, operator, tool, args_redacted, trace_id}
# Promtail tails the file into Loki.
```

That's it. One file, ~30 lines. No FastAPI, no SQLite, no HTMX page, no MCP server.

### End-to-end operator experience

1. From Telegram: "Hermes, summarise my unread Gmail and reply to anything from the contractor."
2. Hermes auto-invokes `/plan`, writes plan to `~/.hermes/plans/`, posts a summary to Telegram with: "Plan written. Execute?"
3. Operator replies `yes` (or edits the plan file via Hermes's own `edit` tool, then says yes).
4. Hermes executes. Read-only steps run autonomously. When it hits a configured risky action (e.g. sending an email reply), Hermes posts the inline-button approval card to Telegram.
5. Operator taps **Approve** / **Deny** / **Always**.
6. Every decision lands in Loki via the audit hook, correlated to the mitmproxy `trace_id` of the action it gated.
7. From Grafana: filter to `decision=DENIED` → click trace → see exactly the API request mitmproxy intercepted and the response Hermes was about to act on.

---

## 4. Audit pipeline & MCP scan

Two distinct mechanisms with one shared trace ID: runtime traffic interception (mitmproxy) and pre-flight policy validation (MCP scanner).

### 4a. Egress interception (mitmproxy)

**Choke point.** The `hermes-agent` container has `HTTP_PROXY=http://mitmproxy:8080`, `HTTPS_PROXY=http://mitmproxy:8080`, and `NODE_TLS_CA_FILE` / `REQUESTS_CA_BUNDLE` / `SSL_CERT_FILE` pointed at the mitmproxy CA. Docker network policy denies all egress from `hermes-agent` *except* to `mitmproxy:8080`. No other container is configured to trust the CA.

**What gets captured.** Every outbound HTTPS connection Hermes makes:

- **Inference**: Anthropic API (Claude), OpenAI API (Codex)
- **MCP traffic**: any HTTP-transport MCP server it talks to
- **Built-in tools**: web search, browser fetches, image gen, etc.
- **Gateway egress**: Telegram Bot API, Discord API
- **Skill/tool calls** to third-party APIs (Gmail, GitHub, whatever the skills do)

mitmproxy stores **full request and response bodies** on a mounted volume with 7-day rolling retention.

**Two surfaces:**

1. **mitmweb** at `https://hermes.<your-domain>/mitm` — live waterfall, request/response inspector, replay. Human-readable real-time audit surface.
2. **Structured event stream** — a mitmproxy addon (~40 LOC) emits one JSON line per flow to `/var/log/mitm/flows.log`. Fields: `{ts, trace_id, method, host, path, status, req_bytes, resp_bytes, llm_model?, mcp_server?, redactions[]}`. Promtail tails it into Loki.

**Trace ID stitching.** The addon injects an `X-Hermes-Trace-Id` request header on every outbound flow (generated per Hermes turn). Hermes's audit hook (Section 3) emits decisions with the same `trace_id`. In Grafana a single trace becomes: *plan request → /plan output → approval decision → tool call → LLM call → tool result → next LLM call*, on one filterable line.

**Redaction.** Three classes scrubbed from the structured log but NOT from mitmproxy's raw flow store:

- Bearer tokens & API keys (`Authorization`, `X-Api-Key`, query-string secrets — pattern list)
- Telegram/Discord webhook secrets
- A user-extensible regex list in `mitmproxy/addons/redactions.yaml`

The split is deliberate: raw flows are for the operator (auditable, behind basic-auth + IP allowlist on `/mitm`); the Loki stream feeds dashboards and could in principle be shared.

**What mitmproxy *cannot* see:**

- Anything Hermes does inside its own process between an LLM response and the next tool call (reasoning, skill internals). The decision hook log covers that.
- Anything that bypasses `HTTP(S)_PROXY` — raw sockets, DNS, ICMP. Mitigated by Docker egress firewall.

### 4b. MCP scan (pre-flight policy validation)

**When it runs.** Before `hermes-agent` starts. The `mcp-scanner` init container blocks the Compose `depends_on` chain — if it fails, Hermes never starts.

**What it does.** For each MCP server in `~/.hermes/mcp_servers.yaml`:

1. **Discover.** Boot the server (or contact it if already running) and fetch its tool manifest via the MCP `tools/list` method.
2. **Validate against `policy.yaml`:**
   - Server identity check: does its name + version match the pinned manifest?
   - Tool allowlist: every advertised tool name must match an allowed pattern. New tools that appeared since last scan trigger a **PENDING** state — not auto-approved.
   - Tool description scan: descriptions are LLM-scanned (cheap Haiku call, via mitmproxy, fully logged) for prompt-injection indicators — invisible Unicode, "ignore previous instructions" patterns, embedded URLs, role-confusion language.
   - Schema sanity: argument schemas checked for overly-broad types.
   - Denied operations: any tool whose name or description matches the denied list is rejected.
3. **Emit a structured report** to Loki + human-readable summary to `/var/log/mcp-scan/report-<ts>.md`.
4. **Decision:** all servers PASS → exit 0 → Hermes starts. Any FAIL → exit 1 → stack does not start, operator alerted via Telegram (one-off webhook, since the agent itself isn't up).

**Re-scan triggers:** container restart (every time), configurable cron (default: daily), manual `docker compose run --rm mcp-scanner`.

**Policy file shape (excerpt):**

```yaml
servers:
  gmail-mcp:
    pinned_version: "0.4.2"
    allowed_tools:
      - "list_threads"
      - "read_thread"
      - "draft_reply"
    denied_patterns:
      - "delete_*"
      - "send_*"        # send needs approvals.mode=manual instead
description_scan:
  enabled: true
  model: "claude-haiku-4-5"
  flag_on_score: 0.6
```

**Why it matters.** Tool description poisoning is one of the most credible MCP attack vectors. A malicious MCP server can ship benign-looking tools whose descriptions contain hidden instructions to the LLM. mitmproxy intercepts runtime traffic but won't catch a manifest that *says* "use this for image generation" while semantically instructing the model to exfiltrate secrets. The pre-flight scan is the layer that catches that.

### 4c. Composite Grafana dashboard

Single dashboard with these panels:

- **Live flow rate** (mitmproxy flows/min by host)
- **LLM cost burn** (extracted from Anthropic + OpenAI response headers)
- **Approvals queue** (open inline-button gates from Hermes's own log)
- **Decision history** (approve/deny/edit timeline, by operator)
- **MCP scan status** (latest scan result, drift since last scan)
- **Top traces** (slowest, most-tool-calls, most-tokens) with click-through to mitmweb

Filterable by `trace_id`, `task_id`, `host`, `decision`.

---

## 5. Infrastructure & IaC

### 5a. Repo layout

```
hermes_prototype/
├── infra/                        # OpenTofu
│   ├── main.tf                   # variables, locals, provider selection
│   ├── modules/
│   │   ├── gcp/                  # google_compute_instance, firewall, DNS
│   │   └── hetzner/              # hcloud_server, hcloud_firewall, DNS
│   ├── cloud-init/
│   │   └── userdata.yaml.tftpl   # SHARED between both clouds
│   ├── envs/
│   │   ├── gcp.tfvars
│   │   └── hetzner.tfvars
│   └── backend.tf                # Hetzner Object Storage (S3-compatible)
├── stack/                        # Everything that runs on the VM
│   ├── docker-compose.yml
│   ├── caddy/Caddyfile
│   ├── hermes/
│   │   ├── config.yaml
│   │   ├── mcp_servers.yaml
│   │   ├── hooks/audit_decisions.py
│   │   └── plans/.gitkeep
│   ├── mitmproxy/
│   │   ├── addons/audit.py
│   │   └── redactions.yaml
│   ├── mcp-scanner/
│   │   ├── policy.yaml
│   │   └── scan.py
│   └── grafana/
│       ├── dashboards/hermes.json
│       └── provisioning/
├── scripts/
│   ├── up                        # restore snapshot + tofu apply
│   ├── down                      # snapshot + tofu destroy
│   ├── status                    # is it up? where? cost so far?
│   ├── bootstrap.sh              # called by cloud-init on first boot
│   ├── migrate.sh                # GCP↔Hetzner data move
│   └── verify.sh                 # post-deploy smoke tests
├── docs/
│   └── superpowers/specs/2026-05-21-hermes-prototype-design.md
└── README.md
```

### 5b. OpenTofu provider abstraction

One root module, two implementation modules. `main.tf` selects which module to invoke based on `var.cloud`. Output contracts are identical between modules.

```hcl
# infra/main.tf (excerpt)
variable "cloud" {
  type    = string
  validation {
    condition     = contains(["gcp", "hetzner"], var.cloud)
    error_message = "cloud must be gcp or hetzner"
  }
}

module "gcp" {
  count       = var.cloud == "gcp"     ? 1 : 0
  source      = "./modules/gcp"
  hostname    = var.hostname
  ssh_pubkey  = var.ssh_pubkey
  cloud_init  = data.cloudinit_config.shared.rendered
  region      = var.gcp_region
  machine     = var.machine_size
}

module "hetzner" {
  count       = var.cloud == "hetzner" ? 1 : 0
  source      = "./modules/hetzner"
  hostname    = var.hostname
  ssh_pubkey  = var.ssh_pubkey
  cloud_init  = data.cloudinit_config.shared.rendered
  location    = var.hcloud_location
  server_type = var.machine_size_mapped
}

output "public_ip"  { value = coalesce(try(module.gcp[0].public_ip, ""), try(module.hetzner[0].public_ip, "")) }
output "ssh_target" { value = coalesce(try(module.gcp[0].ssh_target, ""), try(module.hetzner[0].ssh_target, "")) }
```

The same `cloud-init/userdata.yaml.tftpl` is rendered once and passed to whichever module wins. Cloud-specific details (machine type names, firewall syntax) are mapped inside the module.

**Deploy commands:**

```bash
tofu apply -var-file=envs/gcp.tfvars      # GCP (default — spin-up/spin-down)
tofu apply -var-file=envs/hetzner.tfvars  # Hetzner (always-on alternative)
```

### 5c. State backend (load-bearing)

OpenTofu state lives in **Hetzner Object Storage** (S3-compatible) regardless of which cloud the VM is on. This is the persistence layer that survives every `tofu destroy` on the compute side — essential for the spin-up/spin-down model. Volume snapshots (from `scripts/down`) also live here.

### 5d. Cloud-init: the bootstrap contract

`userdata.yaml.tftpl` does five things, identically on both clouds:

1. **Harden SSH** — disable password auth, install pubkey, change port, configure fail2ban.
2. **Install base packages** — Docker, Docker Compose plugin, ufw, git, curl, age.
3. **Pull the stack repo** — clone `hermes_prototype` to `/opt/hermes` at a pinned commit.
4. **Decrypt secrets** — pull age-encrypted `secrets.env` from the repo, decrypt with a key fetched from cloud metadata.
5. **Restore snapshot (if present) + bring up the stack** — `cd /opt/hermes/stack && docker compose up -d`.

No Ansible, no separate config-management layer.

### 5e. Firewall & networking

| Port | Source | Purpose |
|---|---|---|
| 22 (custom) | Operator IP only | SSH |
| 80 / 443 | 0.0.0.0/0 | Caddy → ACME + public ingress |
| Telegram webhook | Telegram IP ranges | Inbound bot webhooks |
| Discord gateway | (outbound only) | Discord uses outbound websocket |
| Everything else | DENY | |

`/mitm` and `/graf` paths have an additional IP allowlist at the Caddy layer (home IP + Tailscale CGNAT range). Only `/` and Telegram/Discord webhook paths are world-reachable.

**Tailscale recommended add-on:** install Tailscale on the VM via cloud-init; lock dashboard paths to Tailscale-only access. Public ports become *just* 80/443 for ACME + webhooks.

### 5f. Spin-up / spin-down workflow

The prototype is intended to be **paid for only when in use**. GCP per-second billing makes it the right primary target.

**`scripts/down`:**

```bash
docker compose stop hermes-agent
docker run --rm -v hermes-data:/data -v $PWD:/backup alpine \
  tar czf /backup/hermes-snapshot-$(date +%s).tar.gz -C /data .
# Upload to Hetzner Object Storage as hermes-latest.tar.gz
# Also upload Caddy ACME state to avoid LE rate-limit on restart
tofu destroy -var-file=envs/gcp.tfvars
```

**`scripts/up`:**

```bash
tofu apply -var-file=envs/gcp.tfvars
# cloud-init reads hermes-latest.tar.gz from Object Storage, restores volume
# Caddy ACME state restored — no new LE issuance
# docker compose up -d
# Cloudflare A-record updated to new VM IP (via tofu Cloudflare provider)
```

**Restore time target:** <5 minutes from `apply` to "Hermes responds in Telegram."

### 5g. Migration (GCP ↔ Hetzner)

`scripts/migrate.sh` uses the same snapshot mechanism. Stateful surface = one Docker named volume (`hermes-data`) plus mitmproxy/Loki volumes if history matters. **DNS via Cloudflare** is the seam — provider switch is a TTL wait, not a registrar change.

### 5h. VM sizing

| Resource | Sized for |
|---|---|
| 2 vCPU | 1 Hermes agent + ~4 concurrent subagents + small services |
| 4 GB RAM | Hermes + mitmproxy + LGT stack |
| 40 GB SSD | mitmproxy 7-day flows ≈ 5-10 GB worst case + logs |

Concrete defaults: **GCP `e2-small`** (cheap with spin-up/spin-down) or **Hetzner CPX21** (~€8/mo always-on).

### 5i. Secrets

`stack/secrets.env.age` is checked in, encrypted with **age**. Decryption key fetched at first boot:

- **GCP**: from Secret Manager via the VM's service account.
- **Hetzner**: from a one-time bootstrap token passed via cloud-init metadata; rotated to a permanent location after first boot.

Secrets in scope: Anthropic API key, OpenAI API key, Telegram bot token, Discord app credentials, Cloudflare DNS API token, Grafana admin password. None ever in git plaintext.

### 5j. Operational footprint

- `tofu apply` — provisions VM + DNS, cloud-init brings up stack — target <15 min.
- `scripts/up` / `scripts/down` — session lifecycle, target <5 min restore.
- `tofu destroy` — leaves nothing on the cloud (snapshot already in Object Storage).
- `scripts/verify.sh` — smoke test after deploy. Green or red, one line.

---

## 6. Testing, verification & "done"

### 6a. Three test layers

| Layer | What it covers | Where it runs | Custom code? |
|---|---|---|---|
| **Infra smoke** | `tofu apply` produces a reachable VM with healthy services | Local after each `apply` | `scripts/verify.sh` (~80 LOC bash) |
| **HITL contract** | Plan→approve→execute flow works end-to-end on Telegram and Discord | Manual + recorded script | Manual checklist in `docs/verification.md` |
| **Audit completeness** | Every outbound call appears in mitmweb + Loki with a `trace_id` | Automated probe + spot-check | Probe is part of `verify.sh` |

**No unit-test suite for v1.** The project is glue around shipped components; integration smoke-tests catch failure modes that unit tests would.

### 6b. `scripts/verify.sh` steps

Run after every `tofu apply`. Exit 0 = green, exit 1 = red with a single-line reason.

1. DNS resolves — `hermes.<domain>` returns the VM's current public IP.
2. TLS valid — Caddy served a real LE cert, not staging.
3. Caddy routes alive — `/` returns 200, `/mitm`, `/graf`, `/hermes` return 401.
4. Auth works — same paths with basic-auth return 200.
5. Containers healthy — over SSH, `docker compose ps` shows every service `Up (healthy)`.
6. MCP scan passed — `/var/log/mcp-scan/report-latest.md` exists and ends with `PASS`.
7. Telegram bot live — sends `/ping`, expects `pong` within 10s.
8. Audit loop closed — sends a benign task, asserts a `trace_id` appears in mitmproxy flows.log, same `trace_id` in `hermes/decisions.log`, Loki returns ≥1 log line for that `trace_id`.
9. Costs sane — queries Anthropic + OpenAI usage endpoints, prints session-to-date $.

Any failure prints the failing step + last 20 lines of the relevant container's log.

### 6c. Manual verification checklist (`docs/verification.md`)

- **Plan-approval feel.** Send a non-trivial task. Is the `/plan` output readable? Does replying `yes` execute it? Does editing the plan file and re-saying yes execute the edit?
- **Risky-action inline button works on Telegram.** Trigger a configured pattern (e.g. ask Hermes to draft a `tofu destroy`) — inline-button card pops.
- **Cross-platform handoff.** Start a task on Telegram, ask about it from Discord — same session?
- **mitmweb is intelligible.** Open `/mitm` during a task. Can you find the LLM call that produced a given decision?
- **Grafana dashboard is useful.** Open `/graf` after a 10-min session. Does it tell a story?
- **MCP scan rejects a bad server.** Point at a deliberately-poisoned MCP server fixture. Scanner refuses to start the stack. Then point at the real one — stack starts.
- **Up/down cycle.** `./scripts/down`, wait 5 min, `./scripts/up`. Send `/ping`. `pong` within 5 min of `up`.
- **Hetzner parity.** `tofu destroy` GCP, `tofu apply` Hetzner with the same snapshot. Smoke test passes. DNS swaps cleanly.

### 6d. Definition of done — v1 ships when

- `tofu apply -var-file=envs/gcp.tfvars` works from a clean clone on a machine that doesn't have project state. <15 min.
- `tofu apply -var-file=envs/hetzner.tfvars` works the same.
- `./scripts/up` and `./scripts/down` round-trip preserves Hermes skills, plans, and Caddy ACME state.
- `verify.sh` all-green on both clouds.
- All items in `docs/verification.md` checked off.
- MCP scanner catches a deliberately-poisoned test fixture.
- README has a one-page "first session" walkthrough.
- Design doc, README, `verification.md` all committed. Repo can be archived and resurrected in 6 months.

### 6e. Explicit non-goals for v1

- No multi-operator support — single human-on-the-loop.
- No HA, no failover, no autoscaling.
- No custom dashboard frontend beyond Caddy reverse-proxy + Grafana JSON.
- No milestone-checkpoint gates — deferred to v2.
- No self-hosted inference — Claude + Codex only.
- No persistent message-platform integrations beyond Telegram + Discord.
- No production-grade secret rotation.
- No CI/CD pipeline — `git pull && docker compose up -d --build` is the deploy mechanism.

### 6f. What v2 looks like (seams preserved)

- **Milestone gates** — `pre_tool_call` hook watching for `gate.checkpoint(label)`. Hook directory + Telegram inline-button reuse.
- **Multi-cloud failover** — both VMs running, Cloudflare LB with health-check failover. State sync via Object Storage.
- **Self-hosted Hermes 4 inference** — add Modal/RunPod GPU backend as a third inference target. mitmproxy still intercepts. No structural change.
- **Programmatic skills** — Hermes's `delegate_task` + Python RPC subagents come for free.
- **Voice mode** — Hermes ships it; v2 is configuration not code.

---

## Decision log (key choices baked into this design)

| Decision | Rationale |
|---|---|
| Hermes Agent harness, model-agnostic (not Hermes 4 weights) | User constraint: must work with Claude + Codex subscriptions. No GPU. |
| Gated autonomy via Hermes-native `/plan` + `approvals.mode: manual` | Hermes ships ~60% of HITL natively. Don't reinvent. |
| Single custom audit hook (~30 LOC) | The only Hermes-native gap is `trace_id` correlation. |
| Full-egress mitmproxy interception | User wants "exactly what is being done." |
| MCP scanner as pre-flight policy validator | Tool-description poisoning is a real attack vector mitmproxy can't catch. |
| OpenTofu over Terraform | Open license, faster cadence, CNCF Sandbox, drop-in for HCL 1.5-era configs. |
| GCP primary, Hetzner secondary | GCP per-second billing matches spin-up/spin-down model. Hetzner = future always-on. |
| Cloudflare DNS broker | Cloud-independent — DNS doesn't need to migrate when compute does. |
| Hetzner Object Storage as state backend | Survives every compute-side `tofu destroy`. Load-bearing for spin-up/spin-down. |
| Composed dashboard (Caddy reverse-proxy over existing UIs) | "Use existing tools, don't reinvent frontends." One custom page rejected after Section 3 redesign. |

---

*End of design.*
