# Game Co-Op (`game-coop` — RomM + EmulatorJS)

## Architecture & Runtime
- Self-hosted RomM + EmulatorJS web retro gaming & duo co-op Netplay portal for `https://play.andresptr.site`.
- Single Docker container `romm` (`rommapp/romm`, pinned version tag) bound strictly to `127.0.0.1:8085` (`-> 8080/tcp`), attached to external Docker network `1panel-network` with strict resource caps (`1.0` vCPU, `1024m` RAM).
- Database: dedicated PostgreSQL database `romm` and dedicated role `romm` on existing `1Panel-postgresql-3oWY` (`postgres:18.7-alpine`, `1panel-network`), using `ROMM_DB_DRIVER=postgresql` (with fallback path to isolated `mariadb:11` documented in `PLAN.md`).
- Reverse proxy via 1Panel OpenResty (`play.andresptr.site`, HTTPS/2 + ACME SSL) with required Cross-Origin Isolation headers (`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`) for `SharedArrayBuffer`, WebSocket upgrade, and unlimited upload body size (`client_max_body_size 0`).
- Cross-Wi-Fi duo Netplay configured in `config/config.yml` via `emulatorjs.netplay` using **Cloudflare Realtime STUN/TURN** (auto-refreshed daily via `scripts/refresh-turn.sh` to stay well inside Cloudflare's 48-hour max credential TTL).
- Game cover art & story synopsis scraping enabled from day one via **Hasheous** (`HASHEOUS_API_ENABLED=true`) and **ScreenScraper** (`SCREENSCRAPER_USER` / `SCREENSCRAPER_PASSWORD` in `.env`).

## Verification Commands
- Validate compose: `docker compose config --quiet`
- Container status & resource usage: `docker compose ps` and `docker stats --no-stream romm`
- Local port binding check: `ss -tlnp | grep 8085` (must show `127.0.0.1:8085`, never `0.0.0.0`)
- Local HTTP check: `curl -fsSI http://127.0.0.1:8085`
- Public HTTPS + COOP/COEP headers check: `curl -fsSI https://play.andresptr.site | grep -iE 'http/|cross-origin-opener-policy|cross-origin-embedder-policy'`

## Guardrails
- Never echo, log, or commit `.env`, `config/config.yml`, `CLOUDFLARE_TURN_API_TOKEN`, `SCREENSCRAPER_PASSWORD`, or generated TURN credentials from scripts/cron or shell commands.
- Keep RomM bound strictly to `127.0.0.1:8085` behind 1Panel OpenResty; never expose port `8080`/`8085` on `0.0.0.0`.
- Always keep Docker CPU/RAM limits active (`cpus: "1.0"`, `mem_limit: 1024m`) to protect production services (`bubu`, `n8n`, `waha`, `rekapal`, `aet-api`, `postgresql`, `openresty`).
- Never access, modify, or drop any non-`romm` database on `1Panel-postgresql-3oWY`.
- Always run `pg_dump` on the `romm` database before upgrading the pinned RomM container image tag.
- Protect `data/` (ROMs, saves, states, assets) and `backups/` from destructive operations; never commit ROM, BIOS, or save files to Git.
