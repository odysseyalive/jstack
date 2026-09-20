# Awareness Ledger Index

*Auto-generated. Last updated: 2026-09-19*

## By Tag

### docker
- PAT-2026-05-19-node-slim-not-alpine — Use `node:22-slim` for native-module compatibility (active)
- PAT-2026-05-19-uid-1000-host-alignment — Container uid 1000 must match host jarvis user (active)
- PAT-2026-05-19-nextjs-standalone-mount-paths — Mount standalone server's expected static paths (active)
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)

### nginx
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide (active)
- DEC-2026-09-19-vhost-0600-left-as-is — odysseyalive.com.conf stays 0600; provenance predates every journal on this host (accepted)
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### docker-dns
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)

### upstream-resolution
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)

### 502
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### container-restart
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)

### infrastructure
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)

### site-templates
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### dockerfile
- PAT-2026-05-19-node-slim-not-alpine — Use `node:22-slim` for native-module compatibility (active)
- PAT-2026-05-19-uid-1000-host-alignment — Container uid 1000 must match host jarvis user (active)
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)

### nextjs
- PAT-2026-05-19-node-slim-not-alpine — Use `node:22-slim` for native-module compatibility (active)
- PAT-2026-05-19-nextjs-standalone-mount-paths — Mount standalone server's expected static paths (active)

### add-nextjs-site
- PAT-2026-05-19-node-slim-not-alpine — Use `node:22-slim` for native-module compatibility (active)
- PAT-2026-05-19-uid-1000-host-alignment — Container uid 1000 must match host jarvis user (active)
- PAT-2026-05-19-nextjs-standalone-mount-paths — Mount standalone server's expected static paths (active)
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time (active)
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site (accepted)
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### native-modules
- PAT-2026-05-19-node-slim-not-alpine — Use `node:22-slim` for native-module compatibility (active)

### permissions
- DEC-2026-09-19-vhost-0600-left-as-is — odysseyalive.com.conf stays 0600; provenance predates every journal on this host (accepted)
- PAT-2026-05-19-uid-1000-host-alignment — Container uid 1000 must match host jarvis user (active)

### docker-compose
- PAT-2026-05-19-nextjs-standalone-mount-paths — Mount standalone server's expected static paths (active)
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### static-assets
- PAT-2026-05-19-nextjs-standalone-mount-paths — Mount standalone server's expected static paths (active)

### skills
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site (accepted)

### jstack
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site (accepted)
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### composition
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site (accepted)

### ops
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site (accepted)
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### .claude
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site (accepted)

### install
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### opt-in
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)

### removal
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### architecture
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### services
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### refactor
- DEC-2026-05-21-core-only-default-install — jstack default install is core-only; heavy services are opt-in (superseded)
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting (accepted)

### scaffolding
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)

### build-failure
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)

### pnpm
- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build (active)

### env-config
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### silent-failure
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide (active)
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### shell
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT (active)

### file-permissions
- DEC-2026-09-19-vhost-0600-left-as-is — odysseyalive.com.conf stays 0600; provenance predates every journal on this host (accepted)

### provenance
- DEC-2026-09-19-vhost-0600-left-as-is — odysseyalive.com.conf stays 0600; provenance predates every journal on this host (accepted)

### watchman
- DEC-2026-09-19-vhost-0600-left-as-is — odysseyalive.com.conf stays 0600; provenance predates every journal on this host (accepted)

### backup
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide (active)

### restore
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide (active)

### tar
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide (active)

### data-loss
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide (active)

## By Status

### Active
- PAT-2026-09-19-flat-tar-backup-unrestorable — Multiple -C with relative members makes a FLAT tar; restore -C / scatters it and two `-C dir .` collide [backup, restore, tar, scripts/core/backup_restore.sh, nginx/conf.d, certbot, cron, data-loss, silent-failure]
- PAT-2026-05-19-node-slim-not-alpine — Use `node:22-slim` for native-module compatibility [docker, dockerfile, nextjs, native-modules, sites, add-nextjs-site]
- PAT-2026-05-19-uid-1000-host-alignment — Container uid 1000 must match host jarvis user [docker, dockerfile, permissions, uid, sites, add-nextjs-site, jarvis]
- PAT-2026-05-19-nextjs-standalone-mount-paths — Mount standalone server's expected static paths [nextjs, docker, docker-compose, volumes, sites, add-nextjs-site, static-assets]
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams — Use Docker resolver + variable proxy_pass so nginx re-resolves site upstreams at request time [nginx, docker-dns, upstream-resolution, 502, container-restart, infrastructure, sites, add-nextjs-site, site-templates]

- PAT-2026-09-02-sibling-scaffold-file-references — Audit every path a sibling-scaffolded Dockerfile names; inherited COPY/glob refs fail the build [docker, dockerfile, sites, add-nextjs-site, site-templates, scaffolding, build-failure, pnpm]
- PAT-2026-09-02-jstack-env-unanchored-grep — jstack's unanchored `grep -m1 PORT` on a site .env can silently pick WEB_PORT/SMTP_PORT [jstack, nginx, sites, site-templates, add-nextjs-site, env-config, 502, silent-failure, shell]

### Accepted
- DEC-2026-09-19-vhost-0600-left-as-is — odysseyalive.com.conf stays 0600; provenance predates every journal on this host [nginx, nginx/conf.d, file-permissions, odysseyalive.com.conf, scripts/core/nginx_conf_perms.sh, watchman, security-review, provenance]
- DEC-2026-05-21-jstack-skill-delegates-nextjs — /jstack delegates Next.js site creation to /add-nextjs-site [skills, jstack, add-nextjs-site, composition, ops, .claude]
- DEC-2026-05-21-remove-services-entirely — jstack drops n8n/supabase/chrome entirely; pure per-site hosting [jstack, install, removal, docker-compose, architecture, services, ops, refactor]

### Superseded
- DEC-2026-05-21-core-only-default-install — superseded-by DEC-2026-05-21-remove-services-entirely [jstack, install, opt-in, docker-compose, architecture, services, ops, refactor]

### Resolved

*(none yet)*

### Under Review

*(none yet)*

## Relationship Map

- DEC-2026-05-21-remove-services-entirely → supersedes DEC-2026-05-21-core-only-default-install
- DEC-2026-05-21-core-only-default-install → superseded-by DEC-2026-05-21-remove-services-entirely
- DEC-2026-05-21-remove-services-entirely → related to DEC-2026-05-21-jstack-skill-delegates-nextjs (sibling scope-narrowing decisions)
- PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams → related to PAT-2026-05-19-nextjs-standalone-mount-paths (both shape per-site provisioning in /add-nextjs-site and site-templates)

- PAT-2026-09-02-sibling-scaffold-file-references → related to PAT-2026-05-19-node-slim-not-alpine (both govern the per-site Dockerfile)
- PAT-2026-09-02-jstack-env-unanchored-grep → related to PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams (both produce a silent 502 from a healthy container)
- DEC-2026-09-19-vhost-0600-left-as-is → related to PAT-2026-09-02-jstack-env-unanchored-grep (both concern nginx/conf.d, where gitignored files leave no history to consult)
- PAT-2026-09-19-flat-tar-backup-unrestorable → related to DEC-2026-09-19-vhost-0600-left-as-is (the backup is the only copy of nginx/conf.d, which is gitignored)

## Statistics

| Type | Total | Active | Resolved | Deprecated |
|------|-------|--------|----------|------------|
| Incidents | 0 | 0 | 0 | 0 |
| Decisions | 4 | 3 | 0 | 0 |
| Patterns | 7 | 7 | 0 | 0 |
| Flows | 0 | 0 | 0 | 0 |

*(One DEC superseded — not counted as Active.)*
