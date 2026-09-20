# PAT-2026-05-19-nextjs-standalone-mount-paths

**Status:** active
**Tags:** nextjs, docker, docker-compose, volumes, sites, add-nextjs-site, static-assets

## Pattern

Next.js standalone server expects `public/` and `.next/static/` at specific paths inside the container that do not match where the standalone build deposits them. The docker-compose service must mount the host's `public` and `.next/static` directories *into* the standalone server's expected paths, in addition to the regular app mount:

```yaml
volumes:
  - ./example-app:/app
  - ./example-app/public:/app/.next/standalone/public
  - ./example-app/.next/static:/app/.next/standalone/.next/static
```

Without the second and third mounts, static assets return 404 even though the build produced them.

## Evidence

1. **add-nextjs-site SKILL.md, docker-compose.yml section** — Volume block with both standalone-path mounts and the inline comment *"# Standalone server expects these at specific paths"* — captured 2026-05-19
2. **add-nextjs-site SKILL.md, Troubleshooting** — *"Static assets 404: Verify volume mounts for `/app/.next/standalone/public` and `/app/.next/standalone/.next/static`."* — captured 2026-05-19, source: extracted from CLAUDE.md (post-fix reflection)

## Counter-Evidence

1. **Non-standalone Next.js** — Apps without `output: "standalone"` in `next.config.ts` follow Next.js's default server path layout and do not need these extra mounts. — captured 2026-05-19

> **"Verify volume mounts for `/app/.next/standalone/public` and `/app/.next/standalone/.next/static`."**

*— Captured 2026-05-19, source: CLAUDE.md → add-nextjs-site extraction (troubleshooting checklist implies the issue was hit at least once)*

## Applicability

- **When to use:** Any Next.js app deployed via the jstack `/add-nextjs-site` pattern with `output: "standalone"`.
- **When NOT to use:** Non-standalone Next.js builds, or apps using `next start` directly without the standalone server.

## Confidence

HIGH — encoded both as a positive instruction in the docker-compose template AND as a troubleshooting entry, suggesting the failure mode was observed before being documented.
