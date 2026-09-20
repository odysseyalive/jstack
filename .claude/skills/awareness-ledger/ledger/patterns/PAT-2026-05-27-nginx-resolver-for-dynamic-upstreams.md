# PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams

**Status:** active
**Tags:** [nginx, docker-dns, upstream-resolution, 502, container-restart, infrastructure, sites, add-nextjs-site, site-templates]
**Related:** [PAT-2026-05-19-nextjs-standalone-mount-paths]

## Pattern

When nginx in jstack proxies to a per-site container by Docker service name (e.g. `proxy_pass http://odyssey-alive:3000;`), the long-running `jstack_nginx_1` worker processes resolve that hostname **once at worker-init time** and cache the IP. If the site container is later rebuilt or restarted, Docker assigns it a new IP on `jstack_default`, and nginx will keep dialing the dead old IP — yielding `connect() failed (113: No route to host)` and a public 502 — until nginx is reloaded.

To prevent this, every per-site nginx config (and the site-template scaffold used by `/add-nextjs-site`) MUST use Docker's embedded DNS resolver and reference the upstream through a variable so nginx re-resolves the hostname at request time instead of at config-load time:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;   # Docker embedded DNS
set $upstream_odyssey http://odyssey-alive:3000;
proxy_pass $upstream_odyssey;
```

Key rules:
- `127.0.0.11` is Docker's built-in DNS, reachable from any container on a user-defined network (such as `jstack_default`).
- `valid=10s` caps how long nginx caches a resolution. Lower = faster recovery on restart, slightly more DNS chatter; 10s is a good default.
- `ipv6=off` avoids `AAAA` lookup failures on stacks where the service isn't dual-stacked.
- The `set $var` + `proxy_pass $var` indirection is what flips nginx from init-time to request-time resolution. Bare `proxy_pass http://name:port;` is what triggers the bug.

## Evidence

1. **Today's outage (2026-05-27 ~22:00 UTC)** — odysseyalive.com returned 502 publicly. nginx error log: `connect() failed (113: No route to host) while connecting to upstream, upstream: "http://172.18.0.6:3000/"` — odyssey-alive container had been rebuilt and was on a different IP. Direct `curl http://odyssey-alive:3000` from inside `jstack_nginx_1` returned 200; `docker exec jstack_nginx_1 nginx -s reload` immediately restored service. — source: this session, /home/jarvis/jstack
2. **nginx upstream-resolution semantics (documented behavior)** — Without a `resolver` directive and with a literal hostname in `proxy_pass`, nginx resolves the hostname only at config (re)load. The `set $var` + variable-form `proxy_pass` is the documented escape hatch for runtime resolution.
3. **Docker embedded DNS at 127.0.0.11** — Docker's default behavior on user-defined networks: every container has `nameserver 127.0.0.11` in `/etc/resolv.conf`, served by Docker itself. This is what makes service-name resolution work inside the container at all.

## Counter-Evidence

1. **Static, never-restarted upstreams** — If a backend container truly never restarts (e.g. a long-lived shared service whose lifecycle is independent), bare `proxy_pass` works fine. But site containers DO get rebuilt regularly (deploys, env-var changes, image bumps), so this exception does not apply to the per-site case.
2. **External upstreams** — When proxying to a host outside Docker (e.g. an external API), the resolver should point at a real DNS server (`8.8.8.8`, `1.1.1.1`, or the host's resolver), not `127.0.0.11`. The pattern still applies; only the resolver IP changes.

> **"connect() failed (113: No route to host) while connecting to upstream, upstream: 'http://172.18.0.6:3000/' ... fix that resolved the immediate outage: docker exec jstack_nginx_1 nginx -s reload."**

*— Captured 2026-05-27, source: this session diagnosing odysseyalive.com 502*

## Applicability

- **When to use:** Every per-site nginx config in `nginx/conf.d/` whose upstream is a Docker service name on `jstack_default` (or any user-defined Docker network). The `site-templates/` scaffolds and the `/add-nextjs-site` skill MUST emit configs that follow this pattern by default.
- **When NOT to use:** Upstreams that are IP literals, Unix sockets, or stable external hostnames managed by long-TTL public DNS. Don't add `resolver 127.0.0.11` in configs that have no Docker-service upstream — it's noise.

## Confidence

HIGH — Direct evidence (today's outage + verified fix), corroborating documented nginx behavior, and a clean mechanical mitigation. Counter-evidence is narrow and well-bounded.

## Mitigation — Concrete Diffs

### 1. `nginx/conf.d/odysseyalive.com.conf` (apply now)

In the `server { listen 443 ssl; server_name odysseyalive.com; ... }` block, replace the bare `proxy_pass` with the resolver + variable form. Diff:

```diff
 server {
     listen 443 ssl;
     server_name odysseyalive.com;

+    resolver 127.0.0.11 valid=10s ipv6=off;
+
     # ... ssl + security headers unchanged ...

     location / {
-        proxy_pass http://odyssey-alive:3000;
+        set $upstream_odyssey http://odyssey-alive:3000;
+        proxy_pass $upstream_odyssey;
         proxy_set_header Host $host;
         # ... rest unchanged ...
     }
 }
```

The `resolver` directive belongs at the `server {}` (or `http {}`) scope. The `set` + variable `proxy_pass` belongs inside the `location` block. After editing: `docker exec jstack_nginx_1 nginx -t && docker exec jstack_nginx_1 nginx -s reload`.

### 2. `site-templates/` (apply now, prevents recurrence on every new site)

Whichever site-template files contain a `proxy_pass http://<service>:<port>;` line must be updated to the resolver + variable form. The variable name should be derived from the service name (e.g. `$upstream_<slug>`).

### 3. `/add-nextjs-site` skill (apply now, locks in the default)

`.claude/skills/add-nextjs-site/SKILL.md` (and any scaffold reference files it consumes) must reflect the same pattern, so every future Next.js site provisioned through the skill is immune by default.

## Prevention

- This PAT itself is the institutional record.
- The site-templates and `/add-nextjs-site` updates above are the structural prevention — they make it impossible to ship a new per-site config that has the bug.
- A follow-up audit (`/jstack` health-style sweep) over existing `nginx/conf.d/*.conf` for the bare `proxy_pass http://<name>:` pattern would catch any other already-deployed configs with the same latent issue.
