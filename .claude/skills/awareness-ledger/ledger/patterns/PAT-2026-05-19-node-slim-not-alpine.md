# PAT-2026-05-19-node-slim-not-alpine

**Status:** active
**Tags:** docker, dockerfile, nextjs, native-modules, sites, add-nextjs-site
**Related:** —

## Pattern

When building containers for Node.js apps in jstack, use `node:22-slim` (Debian-based, glibc) rather than `node:22-alpine` (Alpine, musl). Match the host Node major version. Native modules compiled against glibc do not run on musl, so apps using `better-sqlite3` and other native dependencies fail at runtime on Alpine.

## Evidence

1. **add-nextjs-site SKILL.md, Dockerfile section** — Explicit warning: *"Use `node:22-slim` (or match host Node version) to ensure native modules like `better-sqlite3` are compatible. Alpine images use musl which causes binary incompatibilities."* — captured 2026-05-19, source: extracted from CLAUDE.md
2. **add-nextjs-site SKILL.md, Troubleshooting section** — *"Native module errors (better-sqlite3, etc.): Ensure Dockerfile Node version matches host: `node --version`. Use `-slim` image, not `-alpine` (glibc vs musl)."* — captured 2026-05-19, source: extracted from CLAUDE.md

## Counter-Evidence

1. **Alpine is smaller** — A `-slim` image is larger than `-alpine`. For apps with zero native dependencies, Alpine remains viable. The pattern only fires when native modules are involved. — captured 2026-05-19

> **"Use `node:22-slim` (or match host Node version) to ensure native modules like `better-sqlite3` are compatible. Alpine images use musl which causes binary incompatibilities."**

*— Captured 2026-05-19, source: CLAUDE.md → add-nextjs-site extraction*

## Applicability

- **When to use:** Any Node.js container in jstack that imports a package with a native binding (`better-sqlite3`, `bcrypt`, `sharp`, `node-canvas`, etc.).
- **When NOT to use:** Pure-JS apps with no native dependencies — Alpine is acceptable and smaller.

## Confidence

HIGH — directive is encoded in the skill itself; reflects already-paid pain from past breakage that motivated writing the rule down.
