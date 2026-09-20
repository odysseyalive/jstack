# DEC-2026-05-21-jstack-skill-delegates-nextjs

**Status:** accepted
**Tags:** skills, jstack, add-nextjs-site, composition, ops, .claude
**Related:** —

## Context

The operator wanted a single skill that can maintain, test, and create new hosting options for the jstack stack. The existing `/add-nextjs-site` skill already covers Next.js site scaffolding end-to-end (Dockerfile, docker-compose, nginx config, certbot wiring). The question was whether the new operations skill should absorb that logic or delegate to it.

## Decision Drivers

- Avoid duplicating working code that already lives in `/add-nextjs-site`.
- Keep each skill single-purpose per skill-builder principles.
- Trade single-entry-point convenience against the cost of stripping a proven skill.
- Minimize maintenance burden — one place to update Next.js scaffolding when it changes.

## Options Considered

### Option A: Absorb `/add-nextjs-site` into `/jstack`

- Good, because the operator has only one slash command to remember for all hosting-option creation.
- Good, because the catalog is smaller.
- Bad, because it duplicates working logic and forces stripping a battle-tested skill (`/add-nextjs-site` is the original entry point on this stack).
- Bad, because deleting and reimplementing a single-purpose skill that already works is gratuitous risk.

### Option B: `/jstack` delegates Next.js site creation to `/add-nextjs-site`; handles other option types itself

- Good, because zero duplication — `/add-nextjs-site` remains the single source of truth for Next.js scaffolding.
- Good, because `/jstack` stays focused on ops (health, test, maintain) plus the option types `/add-nextjs-site` doesn't cover: static sites, reverse-proxy entries, supabase functions, generic Docker services.
- Good, because the operator can invoke either skill directly — `/route` dispatches correctly in both directions.
- Bad, because there are now two skills the operator must remember (mitigated by `/route`).

### Option C: Keep `/jstack` purely for health/test/maintain; do not handle new-option creation at all

- Good, because the smallest possible scope.
- Bad, because it doesn't address the "create new options" requirement the operator asked for.

## Decision

Chosen option: **Option B**, because it avoids duplicating proven code, preserves `/add-nextjs-site` as the authoritative Next.js path, and gives `/jstack` a clear non-overlapping mandate (ops + everything-not-Next.js).

> **"Delegate to it — When 'new nextjs site' is requested, dispatch back through /route to /add-nextjs-site. No duplication."**

*— Captured 2026-05-21, source: operator response in /skill-builder new jstack composition question*

## Consequences

- `/jstack new nextjs-site` is a thin dispatcher: it invokes `/route` with the user's domain and lets `/route` hand off to `/add-nextjs-site`. No Next.js scaffolding code lives inside `/jstack`.
- Future improvements to Next.js scaffolding land in `/add-nextjs-site` only; `/jstack` inherits them automatically through the dispatch.
- `/jstack new` handles four non-Next.js option types directly: `static-site`, `proxy-entry`, `supabase-function`, `docker-service`. Each has its own procedure block in `.claude/skills/jstack/reference.md`.
- The operator has two valid entry points for new Next.js sites: `/add-nextjs-site [domain]` direct, or `/jstack new nextjs-site [domain]`. Both resolve through `/route`.

## Confirmation Criteria

- `/jstack new nextjs-site` MUST dispatch to `/add-nextjs-site` without duplicating any setup step.
- If `/jstack` later grows Next.js scaffolding code of its own, this decision should be revisited — that drift is the signal that the delegation boundary leaked.
- If `/add-nextjs-site` is ever stripped or merged, this decision is superseded; record a follow-up DEC.
