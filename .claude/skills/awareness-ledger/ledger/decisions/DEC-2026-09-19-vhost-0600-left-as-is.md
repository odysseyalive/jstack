# DEC-2026-09-19-vhost-0600-left-as-is

**Status:** accepted
**Tags:** nginx, nginx/conf.d, file-permissions, odysseyalive.com.conf, scripts/core/nginx_conf_perms.sh, watchman, security-review, provenance
**Related:** [[PAT-2026-09-02-jstack-env-unanchored-grep]] (same directory, same gitignored-so-no-history problem)

## Context

`nginx/conf.d/odysseyalive.com.conf` is mode `0600`. All seven sibling vhosts in
the same directory are `0644`. The watchman session raised this on 2026-09-19 as
finding #939 and proposed `chmod 644`, reading the 600 as a umask artifact of the
2026-09-19 00:42 write.

`nginx/conf.d/` is gitignored, so there is no history to consult. The mode had to
be established from surviving artifacts on the host, and three separate
hypotheses were put forward for who set it. **All three were tested and all three
failed.** Nobody involved can say who set it or why.

## Decision Drivers

- The directory is gitignored. `git log` cannot answer this and never could.
- The change proposed is a **widening** of file permissions. When intent cannot
  be established, widening is the direction that cannot be undone by inference
  later — the 600 is at least evidence that *something* tightened it once.
- It has **no operational effect today.** nginx's master process runs as root and
  reads the file either way. The only argument for changing it is cosmetic
  consistency across the eight vhosts.
- Left unrecorded, a future scan re-raises it as fresh drift and the same
  investigation runs again from zero. That cost is the real one.

## Options Considered

### Option A: `chmod 644` to match the siblings

- Good, because all eight vhosts would then be consistent, and a scan that
  checks for uniformity stops flagging this one.
- Good, because it removes a latent failure: if the container ever drops to a
  non-root user, a 600 vhost fails to load while the other seven keep working.
- Bad, because it widens permissions on the basis of "we could not find a
  reason for them", which is not the same as "there is no reason".
- Bad, because the live file alone is not the whole fix. `_conf_target_mode()`
  would carry the drift forward on the next rewrite regardless, so a chmod
  without a matching change to that function is cosmetic and temporary.

### Option B: Leave it at 600, record nothing

- Good, because it is free and changes nothing on a live host.
- Bad, because #939 stays parked in-review forever and the next scanner — or the
  next session — re-derives this entire investigation from scratch.

### Option C: Leave it at 600 and record why (chosen)

- Good, because it preserves whatever the original intent was, at zero
  operational cost.
- Good, because it converts an unexplained mode into a **documented** one. The
  finding closes as ignored rather than parked, and the next scan has an answer
  to read instead of a question to re-open.
- Bad, because the eight vhosts stay inconsistent, and anyone auditing for
  uniformity has to read this record to learn why.

## Decision

Chosen option: **Option C — leave it at 600 and record why**, because the mode
predates every journal on this machine and no evidence available here can
establish intent, so preserving it costs nothing and widening it would discard
the only signal that exists.

> **"Leave 600, record why"** *— user, selecting among three options after the
> investigation below was presented, 2026-09-19*

*— Captured 2026-09-19, source: conversation between the jstack-dev session, the
watchman session, and the user*

## What was actually checked, and where the evidence stops

The three hypotheses, in the order they were proposed and eliminated:

**1. "A umask artifact of the 2026-09-19 00:42 write."** (watchman #939, original)
Fails. The 600 is present in artifacts long predating that write:

| Mode | Date | Artifact |
|---|---|---|
| `0600` | 2026-06-19 | pre-edit backup recorded in watchman #907 |
| `0600` | 2026-09-08 00:01 | `odysseyalive.com.conf.watchman-bak-20260908` |
| `0600` | 2026-09-16 16:22 | `nginx/conf.d-backups/pre-cutover-20260918T194500Z/` |
| `0600` | 2026-09-16 16:22 | `nginx/conf.d-backups/20260919T004225Z/` |

The 00:42 write **inherited** the mode rather than setting it: `cat >` truncates
in place and keeps the existing mode, which is exactly what
`nginx_conf_perms.sh:46-49` says.

**2. "A deliberate operator tightening, recorded by `nginx_conf_perms.sh`."**
(this session's first reading)
Fails, and this was the weaker citation of the two. That script's comment reads
the 600 as something "an operator had deliberately tightened" — but the script
only *preserves* the mode it finds, and its comment infers intent from the very
same observed 600 that watchman's finding inferred accident from. Both documents
sit downstream of one unexplained mode. Neither establishes intent. The comment
was written 2026-09-18, months after the mode it describes.

**3. "An earlier watchman session set it."**
Fails, on two independent lines:

- *No record.* watchman's first contact with this host of any kind was run 1,
  `audit`, 2026-06-19 00:52:50. A watchman fix session did edit this vhost that
  night between 01:50 and 02:53 to add `Referrer-Policy` — but the pre-edit
  backup was **already 0600**, and backups are taken before the edit.
- *No mechanism.* No watchman code path can chmod a vhost. Its only `chmod 600`
  targets its own SMTP config; there is no `umask` call anywhere in its tree.

watchman's backups are mode-, owner- and mtime-preserving, which is provable
from an artifact in **this** tree rather than taken on trust:
`nginx/nginx.conf.watchman-bak-20260619` carries mtime `2025-09-29 22:39:39.942`
— a year earlier than its own filename. Only `cp -p` produces that. So the 0600
on the 06-19 backup is the file's genuine pre-edit mode, not an artifact of how
the copy was made.

**Where the evidence stops.** The 600 originates before 2026-06-19 00:52:50,
which is earlier than any journal on this machine reaches — jstack's and
watchman's floors are the same date. The only `chmod 600` in the jstack
toolchain is `scripts/core/setup_ssl_certbot.sh:28`, and it targets
`nginx/ssl/*.key`, not vhosts. Nothing on either side explains it.

## Consequences

- (+) No change was made to a live vhost. Nothing was chmod'd at any point.
- (+) watchman #939 closes as **ignored** rather than sitting in-review.
- (+) `_conf_target_mode()` keeps preserving the 600 through future rewrites,
  which is now the recorded intent rather than an accident of implementation.
- (–) `nginx/conf.d/` holds seven `0644` vhosts and one `0600`, permanently and
  deliberately. Any check asserting uniform modes across that directory will
  flag this file and should be pointed at this record.
- (–) The latent risk watchman identified is accepted, not eliminated: if the
  nginx container is ever changed to drop to a non-root user, this one vhost
  fails to load while the other seven keep working. That is the trigger to
  reconsider, below.

## How to apply this decision going forward

- **Do not `chmod 644` this file** to satisfy a consistency check. Link this
  record instead.
- A scanner or reviewer finding the mode asymmetry has an answer here; it is not
  fresh drift and should not be re-reported as such.
- If a future change *does* require uniform modes, the live file and
  `_conf_target_mode()` in `scripts/core/nginx_conf_perms.sh` change **together**
  — changing one without the other is temporary by construction.
- Per operating-principles #12, any edit to this file still takes a
  `.bak-$(date +%Y%m%d%H%M%S)` copy first. `conf.d/` is gitignored; `git
  checkout` will not bring it back. That is what made this investigation as
  expensive as it was.

## Confirmation Criteria

This decision is working if:

- `stat -c '%a' nginx/conf.d/odysseyalive.com.conf` returns `600`, and no
  session has re-raised the asymmetry as a new finding.
- `_conf_target_mode()` still returns the existing mode for a file that exists,
  so a vhost rewrite does not silently widen it.

Reconsider if:

- The nginx container is changed to run its master as a non-root user. At that
  point the 600 stops being cosmetic and becomes a real load failure for this
  one vhost, and the mode should be normalized — along with
  `_conf_target_mode()`, in the same change.
- Evidence surfaces that actually establishes who set the mode and why. Three
  hypotheses have been eliminated; a fourth with real evidence behind it would
  reopen this.
