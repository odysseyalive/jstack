# Nightly backup that runs as jarvis, and per-site container logs

Written 2026-10-10 by jstack-live, at Francis's request relayed by skul-live. Two parts:
**A** makes `backup_restore.sh backup --full` produce a verified archive from jarvis'
crontab. **B** makes every jstack site keep its container logs in `sites/<site>/logs/`,
owned by jarvis.

Francis's constraints (unverified: relayed by skul-live, 2026-10-10): jstack runs as
jarvis; no root crontab, no jobs run as root; root-owned files are reached through a
throwaway `docker run`, never sudo; logs belong "in the user directory, hopefully within
the main site directory site/skul.odysseyalive.com".

## Problem

### A. The nightly backup has never written an archive

- jarvis' crontab runs `cd "/home/jarvis/jstack" && bash scripts/core/backup_restore.sh backup --full`
  at 03:00 (`crontab -l`). Nothing captures the output, so failures are silent.
- `log()` pipes to `tee -a "$LOG_DIR/backup_restore.log"` (`scripts/core/backup_restore.sh:29-32`)
  with `LOG_DIR="$REPO_ROOT/logs"` (`:9`). `logs/` is `root:root 755` (`ls -la logs`), so
  tee fails, `set -e` (`:5`) ends the run, and tar (`:61`) never starts. `ls backups/`
  shows no `jstack_full_*`.
- Even if logging worked, `tar` as jarvis can't read these files (`find . ! -readable`):
  `nginx/certbot/conf/accounts` (root 700), every `privkey*.pem` under
  `nginx/certbot/conf/{archive,live}` (root 600), and `sites/{skul,apps}.odysseyalive.com/data/postgres`
  (uid 999, 700). Transient `data/convex-postgres/tmp/.tmp*/source/*` entries also come and go;
  the `data/*/tmp` exclude covers them. The certbot container recreates the keys as root every renewal
  (`docker-compose.yml:28`: `certbot renew` every 12h).
- Tar-ing a running Postgres data directory doesn't give a consistent database. skul's
  own compose header says the same (`sites/skul.odysseyalive.com/docker-compose.yml:32-41`).
- **apps has no other working backup.** Its `scripts/backup/convex-backup.sh` expects a
  systemd timer and `RESTIC_REPOSITORY` (`:4`, `:34-35`, `:64`). `restic` isn't
  installed (`command -v restic` returns nothing), and there's no matching unit under
  `/etc/systemd/system` and no `~/.config/systemd/user`. So "apps already has restic"
  is not true of this host, and apps needs the jstack-level backup as much as skul does.
- `scripts/core/fix_certbot_permissions.sh:26` (and its sudo fallback, `:34`, plus the hint
  it prints at `:39`) and `full_stack_install.sh:182` run `chmod -R 755` over `archive/`,
  `live/` and `renewal/`, which makes every TLS private key
  world-readable whenever they run. The backup must not copy this approach.

### B. Container logs are unbounded and readable only by root

- `/etc/docker/daemon.json` doesn't exist, and no compose file in `sites/` or
  `site-templates/` sets `logging:` (`grep -rn "logging:"` returns nothing). Every
  container uses json-file under `/var/lib/docker/containers` with no size cap.
- No site has a `logs/` directory (`ls sites/*/`).
- jarvis has no systemd user manager: `loginctl show-user jarvis` reports "not logged
  in or lingering", and `systemctl --user` reports "Failed to connect to bus". A
  `systemd --user` follower would first need `loginctl enable-linger jarvis`, which
  needs root or polkit.
- jstack's own `logs/` is root-owned, and the installed `/etc/logrotate.d/jstack:9`
  says `create 0644 root root` for `logs/*.log`, while the repo template says
  `create 0644 $USER $USER` (`scripts/core/setup_log_rotation.sh:35`). So the installed
  copy was probably generated with `USER=root` (an inference from `:9` against `:35`). If `logs/` is re-owned and nothing else changes,
  the first rotation recreates the file as root and breaks every jarvis writer again.

## jstack's view (Francis asked for it; where it differs from skul-live's draft, Francis chooses)

**Part B, the logs.** Per-site `sites/<site>/logs/`, jarvis-owned and gitignored, is
right, and so are the size cap and the user-level logrotate. **I'd reject the
long-running `docker compose logs -f` follower.** jstack schedules everything with
cron; it has no daemons of its own. The follower would need linger (root, see above),
or a cron `@reboot` plus a watchdog to restart it whenever a compose restart kills it.
I'd use a **cron pull every 5 minutes** instead:
`docker compose logs --no-color --timestamps --since <cursor> --until <now> <service>`,
appended to `logs/<service>.log`, with `<now>` saved as the next cursor. It holds no
state except the cursor and survives reboots without help. The capped json-file buffer
(10m × 3) should hold far more than 5 minutes of output (unverified: measure the log rate in B1). The one gap: lines a container
writes between the last pull and being recreated are lost, so deploy scripts call the
pull right before `up`.

No log driver solves this better: every driver (json-file, local, journald, syslog)
writes as root (unverified: Docker's documented driver behaviour, not tested here). Having each app write into a bind-mounted `./logs` the way nginx does
(`docker-compose.yml:15`) means changing every app and fighting container UIDs; nginx's
files already come out as uid 101 (`ls -la nginx/logs`).

**Part A, the backup.** Running as jarvis, `docker exec pg_dump`, `convex export`, and
streaming certbot through a docker tar are all right for jstack. Where I differ from
the draft:

1. **Keep `sites/*/data/convex-postgres` in the tar** (excluding only its `tmp/`). It
   holds the backend's file storage (`sites/skul.odysseyalive.com/docker-compose.yml:15-17`), it's small
   (13M apps, 7.8M skul, `du -sh`), and the export it would be "covered by" has never
   had a restore tested. Keeping it costs almost nothing.
2. **apps gets the jstack export too.** Its restic path isn't running (see Problem).
3. **Nest the certbot stream inside the one archive** as `nginx/certbot-conf.tar`,
   rather than writing a second file. One archive per night, and the member stays
   under the `nginx/` root `_assert_restorable` already accepts
   (`backup_restore.sh:124`).
4. **Exclude `node_modules` and `.next`.** They take about 2.4G of node_modules and
   about 370M of `.next` across the three Next sites (`du -sh`). Both are rebuilt from
   the lockfile and source that stay in the archive.
5. **Env store:** skul-live says the export doesn't carry the function env store.
   skul's compose header says it "travels with either backup"
   (`sites/skul.odysseyalive.com/docker-compose.yml:40-41`). Unresolved (unverified:
   neither tested). Keeping both pg_dump and the export makes the question moot for
   the backup; the restore drill settles it.
6. **Dumps go to a staging dir under `backups/`** and enter the archive as
   `sites/<site>/db-dumps/…` via `tar --transform`. That keeps plaintext dumps out of
   the live site directories between runs, which the draft's
   `sites/<site>/data/db-dumps/` doesn't.

Everything else in skul-live's draft I'd keep: best-effort `log()`,
`set -eE -o pipefail` plus the ERR trap, `umask 077`, validating at the end, and the
`DB_DUMPS` list shape.

## Approach

### A

`backup_full()` becomes these steps. A failure in any step fails the run, and the ERR
trap names the step:

1. `umask 077`; `mkdir -p backups && chmod 700 backups`; take a `flock` on
   `backups/.lock` so two runs can't overlap.
2. **Dumps** into `backups/.stage-$TS/` (0700), one per `DB_DUMPS` entry:
   - `pg`: `docker exec <container> pg_dump -U <user> -d <db> -Fc > …/<db>.pgdump`
   - `convex-export`: `( cd sites/<site> && CONVEX_TMPDIR=.tmp npx convex export --include-file-storage --path … )`,
     then `convex_zip_check` from that site's `scripts/lib/convex-zip.sh` with
     `UNZIP_DISABLE_ZIPBOMB_DETECTION=TRUE`.
3. **Certbot:** `docker run --rm -v "$REPO_ROOT/nginx/certbot/conf:/c:ro" alpine tar -C / -cf - c > stage/certbot-conf.tar`.
   The tar is created as root inside the container, so keys and `accounts/` keep their
   owner and mode.
4. **Main tar:**
   `tar czf FILE -C REPO_ROOT --warning=no-file-changed --ignore-failed-read EXCLUDES docker-compose.yml CONFIG nginx/conf.d sites -C stage …`
   with `--transform` mapping staged files to `sites/<site>/db-dumps/…` and
   `nginx/certbot-conf.tar`. `nginx/certbot/conf` itself leaves the plain tar list.
   - Excludes: `sites/*/data/postgres`, `sites/*/data/*/tmp`, `sites/*/.tmp`,
     `*/node_modules`, `*/.next`.
5. **Validate** (extending `validate_backup`): gzip and member listing, then
   `_assert_restorable`, then every expected dump member is present and non-empty,
   each `.pgdump` passes `pg_restore -l` (through `docker exec -i <container> pg_restore -l < file`),
   each export passes `convex_zip_check`, and `nginx/certbot-conf.tar` lists
   `c/accounts` and `c/live`.
6. Remove the stage dir (an EXIT trap does it on failure too).

`restore_backup` keeps its contract and adds one step: if the archive has
`nginx/certbot-conf.tar`, it's unpacked by
`docker run --rm -v …/nginx/certbot/conf:/c alpine tar -C / -xpf -`, so the keys come
back root-owned. DB dumps are restored by hand, following the runbook (Step A6). A
plain restore never loads a database by itself.

Cron line (`setup_cron_jobs.sh:34`) gains `>> "$JSTACK_ROOT/backups/cron.log" 2>&1`.
jarvis' installed crontab gets the same edit; it's jarvis' own crontab, so no sudo.

### B

- `scripts/core/site_logs.sh` (new; a jstack core script because the pattern is
  jstack-wide): `pull` walks `sites/*/docker-compose.yml`, and for each site with
  running services appends new lines per service to `sites/<site>/logs/<service>.log`
  and advances `sites/<site>/logs/.cursor`. `rotate` runs `/usr/sbin/logrotate -s
  "$REPO_ROOT/logs/logrotate.state"` against a jstack-owned `scripts/core/site_logs.logrotate`
  (daily, rotate 14, compress, delaycompress, missingok, notifempty, `su`-free since it
  runs as jarvis) covering `sites/*/logs/*.log` and `logs/*.log`.
- Cron (jarvis): `*/5 * * * * … site_logs.sh pull` and `30 0 * * * … site_logs.sh rotate`,
  installed by `setup_cron_jobs.sh` beside the backup jobs.
- The size cap: every service in each site's compose gets
  `logging: {driver: json-file, options: {max-size: "10m", max-file: "3"}}` (via an
  `x-logging` anchor). It also goes into all three `site-templates/*/docker-compose.yml`,
  so every site jstack creates later inherits it.
- New sites: the site generator and `--install-site` (`jstack.sh:41`) create
  `sites/<site>/logs/`. Each site repo's `.gitignore` gains `logs/`. jstack's own
  `.gitignore` already ignores `sites/` and `logs/` (`.gitignore:61-63`).
- jstack's own `logs/`: re-own it with
  `docker run --rm -v "$REPO_ROOT:/r" alpine chown 1000:1000 /r/logs` and keep it as
  jstack's log dir. The user logrotate above covers it. **One sudo line for Francis:**
  delete the `logs/*.log` stanza from `/etc/logrotate.d/jstack` (`:1-13`), because its
  `create 0644 root root` would undo the chown at the first rotation. Its nginx and n8n
  stanzas stay. Fix `setup_log_rotation.sh` so it no longer writes that stanza.

## Steps

Part A first (it's a defect with no backup behind it); then B.

- **A1.** `scripts/core/backup_restore.sh`: `set -eE -o pipefail` plus the ERR and EXIT
  traps; best-effort `log()`; `DB_DUMPS` with
  `apps|pg|odyssey-apps-convex-postgres-1|convex|odyssey_apps`,
  `skul|pg|odyssey-skul-convex-postgres-1|convex|odyssey_skul`, and one
  `convex-export` entry per site. Then the staging, certbot, tar, and validate flow
  above. Check: `bash -n` and `shellcheck`.
- **A2.** `restore_backup` gets the docker-based certbot unpack, and
  `_assert_restorable` gets the new member names. Check: restore into a scratch
  `REPO_ROOT` copy, never the live tree (see Verification).
- **A3.** `scripts/core/setup_cron_jobs.sh`: the cron line gets the `cron.log`
  redirect, and `create_backup_dir` sets `chmod 700 backups`.
- **A4.** Fix `fix_certbot_permissions.sh:26,34,39` and `full_stack_install.sh:182`: drop
  the recursive 755 on `archive/` and `live/` so private keys keep 600. This is gated
  on Open question 3.
- **A5.** Run one backup by hand as jarvis, then `validate` it. Edit jarvis' crontab
  line to add the redirect.
- **A6.** Restore drill into a scratch directory: unpack, list the certbot tar, load
  each `.pgdump` into a throwaway `postgres` container, and import each export zip into
  a throwaway Convex backend if one can be stood up as jarvis. Record the result and a
  short restore runbook in `docs/` (ops-guide-writer).
- **B1.** Add `scripts/core/site_logs.sh` and `scripts/core/site_logs.logrotate`, then
  run `pull` by hand and check `sites/*/logs/*.log` appear owned by jarvis.
- **B2.** Docker-chown `logs/` to jarvis. **Francis:** remove the `logs/` stanza from
  `/etc/logrotate.d/jstack` (sudo). Fix `setup_log_rotation.sh` to match.
- **B3.** `setup_cron_jobs.sh` installs the pull and rotate jobs; install them in
  jarvis' crontab.
- **B4.** Add the `x-logging` block to the three `site-templates/*/docker-compose.yml`,
  and add `logs/` creation to the generator path behind `jstack.sh --install-site`.
- **B5.** Add the `logging:` block to each live site's compose (apps, skul,
  odysseyalive.com, y, appshook, skulhook) and `logs/` to each site repo's
  `.gitignore`. These are edits inside site repos. skul's and apps' changes go through
  their own repos' commit flow.
- **B6.** **Gate (Francis picks the time):** recreate each site's containers
  (`docker compose up -d` with that site's usual profile flags) so the cap takes
  effect. One site at a time, with a health check after each.

## Files touched

- Edit: `scripts/core/backup_restore.sh`, `scripts/core/setup_cron_jobs.sh`,
  `scripts/core/setup_log_rotation.sh`, `scripts/core/fix_certbot_permissions.sh` (A4),
  `scripts/core/full_stack_install.sh` (A4), `jstack.sh` or the site-generator script
  it calls (B4), `site-templates/{basic-landing,lamp-mariadb,node-mdx-tailwind}/docker-compose.yml`.
- New: `scripts/core/site_logs.sh`, `scripts/core/site_logs.logrotate`, a restore
  runbook under `docs/`.
- Outside the jstack repo: `sites/*/docker-compose.yml` and `sites/*/.gitignore` (site
  repos); jarvis' crontab; `/etc/logrotate.d/jstack` (Francis, sudo).
- Ownership only: `logs/` (via docker chown).
- Never touched: `sites/skul.odysseyalive.com/data/convex` (the frozen SQLite rollback,
  per skul-live), or anything under `nginx/certbot/conf` except through the
  read-only mount.

## Verification

- `bash scripts/core/backup_restore.sh backup --full; echo $?` as jarvis exits 0 and
  writes `backups/jstack_full_*.tar.gz`, mode 600, in `backups/` mode 700.
- `bash scripts/core/backup_restore.sh validate <file>` exits 0, and
  `tar tzf <file> | grep -E 'db-dumps|certbot-conf.tar'` lists one pgdump and one
  export zip per site plus the certbot tar.
- `tar xzOf <file> nginx/certbot-conf.tar | tar tvf - | grep privkey` shows root-owned
  600 keys.
- Restore drill (A6) is recorded as passed before Part A is called done.
- The next 03:00 run appends a success line to `backups/cron.log`.
- After B: `ls -la sites/*/logs/` shows jarvis-owned `<service>.log` growing every 5
  minutes. `docker inspect -f '{{.HostConfig.LogConfig}}' <container>` shows
  `max-size:10m max-file:3` on every recreated container.
- The day after B2: `logs/*.log` is still owned by jarvis.

## Open questions

1. **Follower or cron pull (B).** Recommend the cron pull: no linger, no daemon, the
   same scheduling model as everything else here. Taking the follower means one sudo
   line (`loginctl enable-linger jarvis`) plus a `systemd --user` unit per site.
2. **Exclude `node_modules`/`.next`.** Recommend excluding them; it cuts about 2.8G a
   night.
3. **Fix the 755-on-private-keys scripts (A4) now or separately.** Recommend now: it's
   the pattern this backup deliberately avoids, and it's a small change (four lines across two files).
4. **Retention.** The existing Sunday cleanup (`setup_cron_jobs.sh:37`, `-mtime +7`)
   lets up to 14 nightlies build up. No archive has ever been written, so the size per night is unknown (unverified: estimate it from the first A5 run) against 79G
   free (`df -h`). Recommend leaving it as is.
5. **Outage window for B6.** Francis picks.

## Risks

- **The archive holds every site's `.env`, the database dumps, and the TLS private
  keys.** It's mode 600 in a 700 dir, but it's still one file with everything; an
  off-box copy should be encrypted. Off-box copies are out of scope here.
- **The convex export runs `npx` from each site dir.** A site's dependency changes
  could break the backup. It fails loudly, and the pg_dump and the
  `data/convex-postgres` files are still in the tar.
- **The cron pull loses lines** written between the last pull and a container being
  recreated (deploys call pull first to close this). It also double-counts nothing,
  because `--since/--until` windows don't overlap. If Docker's `--until` handling is
  not exclusive, the boundary line can appear twice (unverified: Docker CLI behaviour,
  check in B1).
- **B6 is downtime**, a few seconds per site per recreate. Reversible: drop the
  `logging:` block and recreate again.
- **Restore writes into the live tree.** The drill uses a scratch copy only, and the
  runbook says so.
