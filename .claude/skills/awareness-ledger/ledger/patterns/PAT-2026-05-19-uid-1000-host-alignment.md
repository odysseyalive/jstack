# PAT-2026-05-19-uid-1000-host-alignment

**Status:** active
**Tags:** docker, dockerfile, permissions, uid, sites, add-nextjs-site, jarvis

## Pattern

Containers that mount host directories must run as uid 1000 to match the `jarvis` host user. In jstack's Node.js Dockerfile this means `USER node` (the node:22-slim built-in `node` user is uid 1000). When the container's uid does not match the host file owner, writes from inside the container produce root-owned files on the host and writes from the host appear as permission-denied inside the container.

## Evidence

1. **add-nextjs-site SKILL.md, Dockerfile section** — Comment: *"# Use built-in node user (uid 1000) to match host user"* — captured 2026-05-19
2. **add-nextjs-site SKILL.md, Key Points** — *"uid 1000 - Container runs as `node` user matching host `jarvis` user for permissions"* — captured 2026-05-19
3. **add-nextjs-site SKILL.md, Troubleshooting** — *"Permission denied errors: Check container runs as uid 1000 (`USER node`). Host files should be owned by jarvis (uid 1000)."* — captured 2026-05-19

## Counter-Evidence

1. **Read-only containers** — When a container only reads mounted volumes (no writes), uid mismatch is tolerable but still discouraged. — captured 2026-05-19

> **"Container runs as `node` user matching host `jarvis` user for permissions."**

*— Captured 2026-05-19, source: CLAUDE.md → add-nextjs-site extraction*

## Applicability

- **When to use:** Any container in jstack that bind-mounts a directory from the jarvis-owned home (`/home/jarvis/jstack/sites/...`).
- **When NOT to use:** Containers using only named Docker volumes or read-only mounts.

## Confidence

HIGH — uid alignment is baked into both the Dockerfile pattern and the troubleshooting checklist.
