# PAT-2026-09-02-jstack-env-unanchored-grep

**Status:** active
**Tags:** jstack, nginx, sites, site-templates, add-nextjs-site, env-config, 502, silent-failure, shell
**Related:** [PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams]

## Pattern

`jstack.sh --install-site` reads a site's three config values with an **unanchored**
grep (`jstack.sh:118-120`):

```sh
SITE_DOMAIN="$(grep -m1 DOMAIN "$SITE_DIR/.env" | cut -d'=' -f2)"
SITE_PORT="$(grep -m1 PORT   "$SITE_DIR/.env" | cut -d'=' -f2)"
SITE_CONTAINER="$(grep -m1 CONTAINER "$SITE_DIR/.env" | cut -d'=' -f2 ...)"
```

`grep -m1 PORT` matches the first line **containing** the substring `PORT` — not a
line beginning `PORT=`. So `WEB_PORT=`, `SMTP_PORT=`, `PLAYWRIGHT_MCP_PORT=`, or
even a **comment** mentioning the word will win the race if it appears earlier in
the file.

Consequence: jstack generates the nginx vhost against the wrong upstream port. There
is no error — the config is written, `nginx -s reload` succeeds, the cert is
acquired, and `--install-site` reports success. The site simply 502s, and the
generated `.conf` looks plausible because the wrong port is a real port from the
same file.

Two mitigations, in order of preference:

1. **Fix jstack** — anchor the greps: `grep -m1 '^PORT=' ...`. One character each,
   removes the hazard permanently.
2. **Until that lands**, in every site `.env` keep `DOMAIN` / `PORT` / `CONTAINER`
   as the first three lines, with nothing above them containing those substrings —
   comments included.

This matters more than it looks because a jstack site `.env` is usually ALSO the
docker-compose env file for the same directory, so it accumulates `WEB_PORT`,
`SMTP_PORT` and similar as a matter of course.

## Evidence

1. **Mechanism confirmed by direct reading** of `jstack.sh:118-120`; the greps are
   unanchored and `cut -d'=' -f2` will happily return a value from any matching
   line. A comment line without `=` returns the whole line. — 2026-09-02
2. **Deliberately avoided when authoring `sites/apps.odysseyalive.com/.env`**, which
   carries both `WEB_PORT=3050` and `SMTP_PORT=587`. The three jstack keys were
   pinned to lines 1-3 and the explanatory comment below them spells the hazard
   names with a zero (`WEB_P0RT`, `SMTP_P0RT`) so the comment itself cannot win the
   grep. Verified after authoring and again after two later edits to the same file:
   `DOMAIN -> apps.odysseyalive.com`, `PORT -> 3000`, `CONTAINER ->
   odyssey-apps-next-app-1`. — 2026-09-02
3. **The hazard is live, not theoretical** — `sites/y.odysseyalive.com/.env`
   contains `PLAYWRIGHT_MCP_PORT`, and `sites/skul.odysseyalive.com/.env` contains
   `WEB_PORT` and `SMTP_PORT`. Both resolve correctly today only because `PORT=`
   happens to appear first. — 2026-09-02

## Counter-Evidence

1. **No production outage has been caused by this.** All four site `.env` files on
   this VPS are ordered correctly, and `y.odysseyalive.com` resolves `PORT` from
   line 9 (the real key) despite having `PLAYWRIGHT_MCP_PORT` at line 15. This is a
   latent hazard confirmed by mechanism and one deliberate avoidance — NOT a
   post-incident finding. Rated accordingly. — 2026-09-02
2. **A site `.env` with no other `*PORT*` key is unaffected**, and the minimal jstack
   config (`odysseyalive.com` — only `DOMAIN`/`PORT`/`CONTAINER`) cannot trip it at
   all. The exposure scales with how much compose config shares the file. — 2026-09-02

> **"DOMAIN -> apps.odysseyalive.com / PORT -> 3000 / CONTAINER -> odyssey-apps-next-app-1"**

*— Captured 2026-09-02, source: verification run against a `.env` deliberately
containing `WEB_PORT=3050` and `SMTP_PORT=587` below the three anchors. Re-run this
check after ANY edit to a site `.env`; it is one line and it is the only thing that
distinguishes a correct file from a silently wrong one.*

## Applicability

- **When to use:** authoring or editing any `sites/<domain>/.env`, and when
  reviewing `site-templates/` scaffolds or `/add-nextjs-site` output. Also the first
  thing to check when a freshly installed site 502s while its container is healthy
  and reachable.
- **When NOT to use:** not a factor for sites whose `.env` holds only the three
  jstack keys, and irrelevant once the greps in `jstack.sh` are anchored — at which
  point this record should be marked `deprecated`, not merely edited.

## Confidence

MEDIUM — mechanism is certain and trivially verifiable, and the blast radius (a
silent 502 that survives an apparently successful install) is high. Downgraded from
HIGH only because no instance has actually failed in production; every existing
`.env` is ordered correctly by luck rather than by rule.
