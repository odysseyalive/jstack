# DEC-2026-05-21-core-only-default-install

**Status:** superseded-by [[DEC-2026-05-21-remove-services-entirely]]
**Tags:** jstack, install, opt-in, docker-compose, architecture, services, ops, refactor
**Related:** [[DEC-2026-05-21-jstack-skill-delegates-nextjs]], [[DEC-2026-05-21-remove-services-entirely]]

## Context

jstack previously auto-installed n8n, Supabase (7 containers), browserless Chrome, and an n8n MCP proxy as part of `bash jstack.sh --install`. That made the default install heavyweight, slow, and tied to a particular user's workflow (workflow automation + database + headless browser + Claude.ai bridge), even when the actual goal was just "host one or more websites on a server."

On 2026-05-21 the user reshaped the project to focus on per-website hosting. The default install should give a minimal core (nginx + certbot + a deploy workflow for per-site containers). Heavier services should be opt-in.

## Decision Drivers

- New users should get a fast, minimal default that matches the project's stated purpose: per-website server-side hosting.
- Existing live installs must not break — data dirs, running containers, and per-site nginx configs must be preserved.
- Optional services should be first-class: clean install/uninstall, predictable cert handling, and integrated with `up`/`down`/`status`.
- No silent state — which optional services are installed has to be discoverable from the repo.

## Options Considered

### Option A: Strip and ship — make `--install` core-only, no replacement

- Good, because it's the smallest change.
- Bad, because users would have to hand-edit `docker-compose.yml` and write their own nginx configs every time they wanted n8n / supabase / chrome. Loses convenience entirely.

### Option B: Feature flag inside `full_stack_install.sh` (`INSTALL_N8N=true`, etc.)

- Good, because preserves the single-command install for users who want everything.
- Bad, because the install script stays heavyweight and tangled. Toggling a flag still requires touching the file and re-running the full install. Doesn't give clean lifecycle for adding a service after the fact.

### Option C: Split compose + per-service installers + state file (chosen)

- Good, because each optional service has its own `docker-compose.<name>.yml`, its own `scripts/services/install_<name>.sh`, and its own nginx template under `nginx/conf.d.examples/`.
- Good, because `.jstack-services` records which services are installed; `orchestrate.sh` reads it so `up|down|restart|status` automatically picks up the right compose files.
- Good, because existing data dirs are detected and preserved (no destructive migration).
- Bad, because `bash jstack.sh --install` is no longer one-shot for the full historical stack. Users who want n8n + supabase + chrome must run three additional commands.
- Bad, because the user's local `docker-compose.override.yml` may have `depends_on: [n8n, chrome]` style entries that only resolve if `.jstack-services` lists those services — a per-server migration step.

## Decision

Chosen option: **Option C — split compose + per-service installers + state file**, because it preserves convenience (one command per service, with all the secrets / certs / nginx wiring handled), keeps the default install minimal, and makes the architecture honest about what's optional.

> **"I would like to reshape this project to a server side application only, where we are dealing with individual websites. I no longer want to install n8n, supabase, or chrome headless automatically when running the jstack install script the first time. Those should only be options that the user can decide to install separately."**

*— Captured 2026-05-21, source: user, /route invocation reshaping jstack*

## Consequences

- (+) Core install: `nginx + certbot + base-domain cert + fail2ban + log rotation`. Nothing else.
- (+) Each optional service is added with one command:
  - `bash jstack.sh --install-service n8n` → `n8n.${DOMAIN}`
  - `bash jstack.sh --install-service supabase` → `api.${DOMAIN}` + `studio.${DOMAIN}`
  - `bash jstack.sh --install-service chrome` → `chrome.${DOMAIN}`
  - `bash jstack.sh --install-service mcp-proxy` → `mcp.${DOMAIN}` (requires n8n)
- (+) `.jstack-services` (gitignored, one service name per line) drives compose-file inclusion in `orchestrate.sh`, so optional services participate in `up|down|restart|status` automatically.
- (+) Existing odysseyalive subdomain configs in `nginx/conf.d/` are left in place; new installs use generic templates from `nginx/conf.d.examples/` rendered against `${DOMAIN}` via `envsubst` with an allowlist (so nginx `$variables` aren't clobbered).
- (–) Users upgrading from the old layout must create `.jstack-services` themselves (one-line-per-service) so `jstack.sh up|down|status` keeps managing their previously-auto-installed services. Documented in README § "Migrating an existing install".
- (–) `docker-compose.override.yml` references to `depends_on: [n8n, chrome]` will fail-to-merge if those services aren't listed in `.jstack-services` — same migration step covers it.

## Confirmation Criteria

This decision is working if:

- A fresh clone + `bash jstack.sh --install` brings up exactly two containers (nginx, certbot) and acquires one cert (the base domain).
- A fresh clone + `--install` followed by `--install-service supabase` brings up only the 7 supabase containers plus the existing nginx + certbot — no n8n, no chrome.
- The user's pre-existing odysseyalive live setup keeps serving traffic after the refactor; `bash jstack.sh status` after creating a four-line `.jstack-services` returns all previously-running services.

Reconsider if:

- New optional services start needing to be wired into multiple files in ways that don't fit the `docker-compose.<name>.yml` + `install_<name>.sh` + `<sub>.template.conf` pattern (suggests the pattern is too rigid).
- `.jstack-services` drifts out of sync with the actual running stack regularly (suggests state should be derived from `docker compose ls` instead of a file).

## How to apply this decision going forward

- Do NOT re-add n8n/supabase/chrome/mcp-proxy installation logic to `scripts/core/full_stack_install.sh` or to the core `docker-compose.yml`.
- New optional services follow the same pattern: `docker-compose.<name>.yml` + `scripts/services/install_<name>.sh` + `nginx/conf.d.examples/<sub>.template.conf` + `svc_record <name>` into `.jstack-services`.
- Templates use literal `${DOMAIN}` (plus any explicit extra vars passed to `svc_render_template`) and are rendered via `envsubst` with an allowlist so nginx `$variables` aren't clobbered.
