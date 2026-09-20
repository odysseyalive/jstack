# PAT-2026-09-02-sibling-scaffold-file-references

**Status:** active
**Tags:** docker, dockerfile, sites, add-nextjs-site, site-templates, scaffolding, build-failure, pnpm
**Related:** [PAT-2026-05-19-node-slim-not-alpine]

## Pattern

When a new jstack site is scaffolded by copying a sibling site's `Dockerfile` /
`docker-compose.yml` / `.dockerignore`, the copy carries **hard references to files
that exist only in the source repo**. These fail at the earliest build stage and
the failure text points at a path the reader cannot find, because the surrounding
comments still describe the source application.

Two failure shapes, both seen in the same file:

1. **`COPY` of a file the new repo does not have.** `COPY` fails hard on a missing
   source — the build dies before installing anything.
2. **A shell guard whose glob matches nothing.** `for f in public/modules/*/play.gblorb`
   with no match runs the loop body **once on the literal unexpanded pattern**, so
   `wc -c < "$f"` errors and fails the stage. A guard written to protect the source
   repo becomes an unconditional build failure in the new one.

The rule: copy the structure, then audit **every line that names a path** against
the new repo. `git log -- <path>` is the cheap check — if it returns nothing, the
file was never tracked here and the line is inherited, not intentional.

## Evidence

1. **apps.odysseyalive.com could not build at all** — its `Dockerfile` was a
   near-verbatim copy of `skul.odysseyalive.com`'s. `COPY package.json pnpm-lock.yaml
   .npmrc pnpm-workspace.yaml ./` referenced `pnpm-workspace.yaml`, which
   `git log -- pnpm-workspace.yaml` shows was never tracked in apps (skul has it).
   The LFS guard globbed `public/modules/*/play.gblorb`; skul has 1 such file, apps
   has 0 and has never tracked `public/modules/` at all. — 2026-09-02, this session
2. **The comments actively misled.** The header described "the playable game",
   `nsayka-wawa`, and a 52MB Inform story file, in a repo whose modules are Holdfast
   and SignMe — MDX under `content/modules/` with no binary payload. `.dockerignore`
   likewise still listed `Nsayka Wawa.inform` / `Nsayka Wawa.materials`. A reader
   debugging the failure is told to install git-lfs and re-clone, which would not
   have helped. — 2026-09-02
3. **Fix verified end-to-end**, not just "the error went away": image builds, runs
   as non-root uid 1001, serves HTTP 200 with the real homepage, and
   `require('sharp')` loads. — 2026-09-02
4. **A third inherited defect surfaced only once the first two were cleared** — the
   lockfile was stale against `package.json` (`@anthropic-ai/sdk` `^0.120.0` in the
   lock vs pinned `0.120.0` in the manifest), so `--frozen-lockfile` refused. Each
   inherited fault masks the next; expect to iterate rather than fix once. — 2026-09-02

## Counter-Evidence

1. **Most of the copy was correct and needed no change** — multi-stage layout, the
   pinned `PNPM_VERSION=10.24.0` (and the reason for the pin), the standalone
   `public/` + `.next/static` copy steps, and the non-root runner all transferred
   cleanly. This is not an argument against scaffolding from a sibling; the damage
   is confined to lines naming specific files. — 2026-09-02
2. **The source Dockerfile is not defective.** skul's builds and runs in production
   today. "Works" is relative to the repo it was written for — which is exactly why
   the inherited lines look trustworthy and get left alone. — 2026-09-02

> **"why don't you rebuild the image using the same image from skul.odysseyalive.com which works?"**

*— Captured 2026-09-02, source: user. The intuition this pattern corrects: the
sibling's build "working" is not transferable evidence, because what it depends on
is the sibling's file tree, not the Dockerfile's logic. (Separately, the built
image itself is never reusable across sites — a Next.js standalone image contains
that site's compiled bundle, so running skul's image would serve skul's website.)*

## Applicability

- **When to use:** any new site scaffolded from an existing one — `/add-nextjs-site`
  output, a hand-copied `sites/<domain>/`, or a `site-templates/` scaffold. Audit
  `COPY`/`ADD` sources, glob-based guards, `.dockerignore` entries, and comments.
- **When NOT to use:** do not read this as "never copy a sibling's Dockerfile."
  Copying is the right starting point. The pattern is about the audit step after,
  not about avoiding the copy.

## Confidence

HIGH — direct evidence (a total build failure with three distinct inherited causes,
each verified against `git log`), a verified fix, and clearly bounded
counter-evidence.
