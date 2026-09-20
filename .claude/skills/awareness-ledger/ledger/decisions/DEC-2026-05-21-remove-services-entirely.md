# DEC-2026-05-21-remove-services-entirely

**Status:** accepted
**Tags:** jstack, install, removal, docker-compose, architecture, services, ops, refactor
**Related:** [[DEC-2026-05-21-core-only-default-install]] (superseded), [[DEC-2026-05-21-jstack-skill-delegates-nextjs]]

## Context

Earlier the same day, [[DEC-2026-05-21-core-only-default-install]] made n8n,
Supabase, browserless Chrome, and the n8n MCP proxy **opt-in** rather than
auto-installed. The user then decided opt-in still wasn't the right fit: those
services are no longer part of jstack's purpose at all. jstack is purely a
per-website hosting tool. If a site needs a database, a queue, or a headless
browser, that's the site's responsibility — bundled in its own
`sites/<domain>/docker-compose.yml`.

## Decision Drivers

- The opt-in pattern still implied jstack "supports" these services. It
  shipped compose files, installers, and nginx templates for them — which
  carries maintenance burden (image upgrades, secret prompts, cert handling).
- The user is not running these as a shared platform service anyway. The
  containers were running for personal use of the same machine. With them
  gone, those workflows move elsewhere (or into a single site that owns
  them).
- Removing them clears ~5K lines of templates, scripts, and docs that exist
  to support services jstack no longer ships.

## Options Considered

### Option A: Keep opt-in (status quo from earlier today)

- Good, because installers are already written.
- Bad, because they're maintenance debt for features the user isn't using.

### Option B: Remove from scripts but keep cloned source dirs

- Good, because the user could re-add them later.
- Bad, because `supabase/`, `n8n-mcp-proxy/`, etc. still sit in the repo
  without serving anything.

### Option C: Remove entirely — scripts, compose files, templates, data, source dirs (chosen)

- Good, because jstack becomes a much smaller, more honest tool.
- Good, because removes ambiguity: there's no "supported" service catalog
  beyond nginx + certbot.
- Bad, because deletes ~113MB of live data (n8n workflows + Postgres data +
  edge functions) — user confirmed this with typed "delete".
- Bad, because user's `docker-compose.override.yml` has stale
  `depends_on: [n8n, chrome]` entries that no longer resolve (manual fix).

## Decision

Chosen option: **Option C — remove entirely**.

> **"I'd like to remove n8n, supabase and chrome headless entirely"** *— user, /route invocation, 2026-05-21*
>
> **"Skip backup — just delete"** *— user, explicit confirmation, 2026-05-21*

## Consequences

- (+) Core stack is exactly two containers: nginx + certbot. Nothing else.
- (+) `jstack.sh` simplifies: no `--install-service`, no `--functions`, no
  `--workflows` flags.
- (+) `scripts/services/` contains only `site_template_lifecycle.sh`.
- (+) Documentation focuses on per-site deployment (`--install-site`).
- (–) Live containers for n8n, Supabase (7), Chrome, and MCP proxy were
  stopped and removed.
- (–) ~113 MB of live data permanently deleted: `data/n8n/` (27 MB), `data/supabase/` (86 MB), `data/chrome/`, 9 edge functions in `supabase/functions/`, exported workflow `n8n-workflows/mcp-server.json`, and `n8n-mcp-proxy/` build context.
- (–) The 5 live Let's Encrypt certs (api/studio/n8n/chrome/mcp.odysseyalive.com)
  are intentionally left in `nginx/certbot/conf/` to expire naturally; no
  active nginx config references them anymore.
- (–) User's `docker-compose.override.yml` still has
  `nginx.depends_on: [n8n, chrome, odyssey-alive]` and a wrong
  `./sites/odyssey-alive` build path — gitignored, user-local, needs manual
  cleanup.

## How to apply this decision going forward

- Do NOT reintroduce n8n, Supabase, browserless Chrome, MCP proxy, or any
  "general-purpose service" into `docker-compose.yml` or `scripts/core/`.
- A site that needs a database, queue, or browser bundles them in its own
  `sites/<domain>/docker-compose.yml`. nginx proxies to those containers by
  container name on the shared docker network — same as any other site.
- New site templates can ship with such services (see `site-templates/lamp-mariadb/`
  as an example of a site that brings its own database).

## Confirmation Criteria

This decision is working if:

- `docker-compose -f docker-compose.yml config --services` returns exactly
  `nginx` and `certbot`.
- `scripts/services/` contains only `site_template_lifecycle.sh`.
- `bash jstack.sh --install` brings up a clean stack with no n8n / supabase /
  chrome containers.
- `bash jstack.sh --install-site sites/<domain>` deploys a site without
  needing any of the removed services.

Reconsider if:

- A real new use case for a shared service appears (e.g., every site on the
  server needs the same Postgres instance). At that point, evaluate adding it
  back as an opt-in or making it part of a specific site template — not as
  unconditional core.
