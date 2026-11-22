# Game Co-Op (`game-coop`)

**Status:** `Planned — not yet deployed`

Self-hosted private retro gaming & duo co-op portal for `https://play.andresptr.site`, powered by **RomM** and **EmulatorJS**. Designed for single-player story progression with cloud saves and cross-Wi-Fi 2-player co-op Netplay from laptops.

## Directory Structure

- `AGENTS.md` — Operational context, verification commands, and guardrails for AGY / Codex CLI.
- `PLAN.md` — Complete architecture evaluation, PostgreSQL isolation analysis, STUN/TURN strategy, and phased deployment guide.
- `.env.example` — Environment template for RomM container configuration.
- `config/config.example.yml` — EmulatorJS Netplay & ICE (STUN/TURN) configuration template.
- `deploy/openresty-play.andresptr.site.conf.example` — 1Panel OpenResty HTTPS reverse proxy snippet with required `COOP`/`COEP` headers.
- `scripts/` — Reserved for post-deploy backup and maintenance scripts.

## Using with AGY CLI

Open a dedicated session inside this repo so `AGENTS.md` loads automatically:

```bash
cd /opt/apps/game-coop && agy
```

See [PLAN.md](./PLAN.md) before executing deployment steps.
