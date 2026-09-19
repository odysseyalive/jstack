# Fleet operations — one change, every site

A jstack host serves several sites from one nginx. The failure this document exists to prevent is
simple and common: a fix gets applied to the site where it was noticed, and never reaches the others
or the next site the stack creates.

Everything below is enforced by scripts in this repository, not by convention.

## The rule

**A change lands where new sites will inherit it, or it does not land.**

Before any edit, answer one question: *if jstack creates a site tomorrow, does it get this?* If the
answer is no, the change is in the wrong file.

| File | Status |
|---|---|
| `scripts/core/setup_service_subdomains_ssl.sh` | **the source of truth for a vhost.** `generate_site_nginx_config()` emits the port-80 block; `upgrade_site_to_https()` emits the 443 block, its security headers, rate limits, buffers and resolver. `jstack.sh` calls both when a site is created, so a change here is on the new-site path by construction |
| `site-templates/*/` | **the source of truth for a new site's own files** — app config, compose settings, file modes |
| `nginx/conf.d/<domain>.conf` | **generated, gitignored, clobbered by domain name.** Edit it and the change survives until that domain is next regenerated, and reaches no other site. Never the place a fix lands |
| `sites/<domain>/*.sh` | **per-site scripts are drift by construction.** A script that patches one site's vhost is folded into the generator as a profile and then deleted |
| `scripts/core/register_sites_nginx.sh` | **legacy, and a live hazard.** It writes a bare 443 block with no security headers and no `$f2b_banned` guard over the real config, keyed on domain name. Running it un-hardens every site in `sites/`. Do not run it |

A genuinely site-specific setting is still written into the generator — as a profile, or as a value
read from that site's `.env` — so that it is *generated* rather than remembered.

## Profiles

One generator, three shapes. A profile is a proxy-tuning variant, never a hardening exemption: every
profile emits the same security headers.

| `SITE_PROFILE` | For | Differs by |
|---|---|---|
| `standard` (default) | a proxied web application | the full CSP, buffered proxying |
| `connector` | an SSE / streaming endpoint | `proxy_buffering off`, long timeouts, streaming-safe buffers |
| `webhook` | an API endpoint that serves no HTML | a minimal CSP with no `'unsafe-inline'` |

Per-site values are read from `sites/<domain>/.env` with an **anchored** grep. Unanchored matching is
how `grep -m1 PORT` once picked `WEB_PORT` and produced a silent 502 — see
`PAT-2026-09-02-jstack-env-unanchored-grep`.

| Key | Effect |
|---|---|
| `SITE_PROFILE` | selects the profile above. An unknown value is a hard error, never a silent fallback |
| `SITE_WWW_REDIRECT=1` | emit a `www.<domain>` → apex 301 block carrying HSTS. Requires the certificate to cover `www` as a SAN |
| `SITE_XFRAME` | `X-Frame-Options` value. Defaults to `SAMEORIGIN`; set `DENY` only where nothing frames itself |
| `SITE_CSP_SCRIPT_EXTRA`, `SITE_CSP_CONNECT_EXTRA`, `SITE_CSP_FRAME_SRC`, `SITE_CSP_FRAME_ANCESTORS` | extra CSP sources for this site |

## Drift, and the two verdicts

Drift is a live file that no longer matches what the generator emits. **Every drift gets one of
exactly two verdicts. There is no third.**

| Verdict | When | What it costs |
|---|---|---|
| **REVERT** | the live file is worse than, or equal to, generator output | regenerate that domain |
| **PROMOTE** | the live file is *better* — stricter, safer, or it fixes something the generator does not know about | the generator learns it, **every** other site gets it, and a check asserts it from then on |

A PROMOTE is finished only when all four hold:

1. the generator emits it, so every future site inherits it;
2. every existing site has it, or is on a profile that deliberately does not;
3. a check asserts it, so it cannot drift back out;
4. nothing broke — proven per domain.

**Leaving a drift alone is not available.** Not "it is harmless", not "it predates us". An
unadjudicated difference is how a fleet stops being congruent.

**Adjudicate before you reconcile.** Regenerating over an un-adjudicated drift destroys the
difference that might have been the better one. This is not theoretical: on the first real run, three
live vhosts carried a stricter `X-Frame-Options`, a CSP with origins the generator did not know, a
deliberately minimal webhook CSP, and proxy buffer sizes preventing a 502. Reconciling first would
have weakened all three.

## Checks

Each exits non-zero and names the offending block by file, line and `server_name`.

```bash
bash scripts/core/check_vhost_hardening.sh    # headers, CSP, rate limits, resolver, .map guard
bash scripts/core/check_nginx_ban_guard.sh    # every server block enforces fail2ban bans
bash scripts/core/check_nginx_upstreams.sh    # no parse-time upstream hostnames
bash scripts/core/verify_fail2ban.sh          # fail2ban installed and configured
```

They run against the **host's working tree**. `nginx/conf.d/*.conf` is gitignored, so a CI clone
contains no vhosts and every check would pass vacuously.

**Two checks never claim one invariant.** `check_nginx_ban_guard.sh` owns `$f2b_banned`;
`check_vhost_hardening.sh` deliberately does not assert it.

## Putting a change on the live host

Never write `nginx/conf.d/<domain>.conf` by hand, and never reload after an unguarded write.

```bash
bash scripts/core/apply_vhost_change.sh <domain> <new-conf-file> [--dry-run]
```

It records whether the domain answers before the change, backs the live file up and verifies the
backup, applies, runs `nginx -t`, reloads, re-requests the domain, and **restores and reloads again if
any gate fails**. A site that was up before the change is up after it, or the change is not there.

One domain per invocation, deliberately. A rollout is a loop over this command, so a bad change costs
one site and stops. `--dry-run` backs up and diffs and stops. Run it first, every time.

This is not ceremony. On the first real cutover the syntax gate rejected a generated config that
would have stopped nginx from starting at all — every site down, with an error pointing at
`nginx.conf`'s include line rather than the offending vhost. The gate caught it before the reload and
the site never moved.

## Taking a security finding

A finding is actionable when it has five things: the domain it was found on and which others were
checked; the observed request and response, pasted not summarised; the class; the proposed fix **as a
config line**, not as an outcome; and a command whose output changes when it is fixed.

Then: enumerate every affected domain, change the generator, **write the check before the rollout**,
roll one domain at a time, verify, and prove a new site inherits it.

## What is a site

Enumerate; never assume. Some entries in these globs are not per-domain vhosts:

```bash
ls -d sites/*/          | grep -v '/default/$'
ls nginx/conf.d/*.conf  | grep -vE '/(00-f2b-geo|default)\.conf$'
```

`sites/default/` is scaffolding. `00-f2b-geo.conf` is the `geo $f2b_banned` map and holds no server
block. `default.conf` is the catch-all. `*.conf.watchman-bak-*` are dead backups that read like live
config in a grep.

**A module path is not a domain.** `site.example.com/somemodule` is a path on that vhost, with no DNS
record and no vhost of its own. A finding about it is scoped to its parent vhost or to the
application.

## This repository is public

It is the structure that runs and builds any site. The sites are not part of it.

Never tracked: a real domain name in config, CI, or a path; `nginx/conf.d/*.conf` and
`nginx/conf.d-backups/`; `sites/**`; `.env`, `.env.secrets`, `jstack.config`, `nginx/htpasswd`,
`nginx/ssl/*`, `nginx/certbot/`; any real internal path, container name, port map or IP.

Documentation uses `example.com`. A worked example built on a real domain is the same disclosure as a
config entry; it just reads as documentation.

A `.gitignore` entry is a claim to check with `git check-ignore -v`, not a line to write and trust.
And an ignore rule protects only what has not been committed — something already in history stays in
history. Check the whole set rather than a sample: `git grep -In "<your domain>" -- $(git ls-files)`.
The one real leak found this way was in `.github/dependabot.yml`, which nobody thinks of as
configuration.
