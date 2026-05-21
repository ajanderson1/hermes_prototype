# hermes_prototype

A single-VM prototype that runs the Nous Research **Hermes Agent** harness as its agentic brain, powered by **Claude** and **Codex** subscriptions, exposed via **Telegram** and **Discord**, with full **mitmproxy** egress audit and a **human-on-the-loop** gated-autonomy control plane.

## Status

Design phase. See [`docs/superpowers/specs/2026-05-21-hermes-prototype-design.md`](docs/superpowers/specs/2026-05-21-hermes-prototype-design.md).

## What this is

- **Hermes Agent**, model-agnostic, pointed at Claude (Anthropic) + Codex (OpenAI).
- **Telegram + Discord** via Hermes's built-in Messaging Gateway.
- **Gated autonomy** — `/plan` for plan approval, `approvals.mode: manual` for risky actions, inline-button cards on Telegram.
- **Full egress interception** — every outbound HTTPS call from the agent goes through mitmproxy.
- **MCP pre-flight scan** — tool manifests validated against policy before Hermes can use them.
- **Single-VM** Docker Compose stack, **OpenTofu** for infra, **GCP↔Hetzner** portable.
- **Spin-up / spin-down** economics — pay only when in session.

## Stack

| Layer | Tool |
|---|---|
| Agent harness | Nous Research Hermes Agent |
| Inference | Claude (Anthropic), Codex (OpenAI) |
| Chat platforms | Telegram, Discord (Hermes Gateway) |
| Egress audit | mitmproxy (mitmweb UI) |
| Logs / dashboards | Loki + Tempo + Grafana |
| Reverse proxy | Caddy |
| Infra | OpenTofu |
| Clouds | GCP (primary, spin-up/spin-down), Hetzner (always-on alternative) |
| DNS | Cloudflare |
| State backend | Hetzner Object Storage (S3-compatible) |
| Secrets | age + cloud Secret Manager |

## License

MIT — see [LICENSE](LICENSE).
