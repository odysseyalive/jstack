# PAT-2026-09-19-flat-tar-backup-unrestorable

**Status:** active
**Tags:** backup, restore, tar, scripts/core/backup_restore.sh, nginx/conf.d, certbot, cron, data-loss, silent-failure
**Related:** [[DEC-2026-09-19-vhost-0600-left-as-is]] (same directory, also unrecoverable if lost — `conf.d/` is gitignored)

## Pattern

`tar` with **multiple `-C` options and relative member names** produces a
**flat** archive. The `-C` is a directory change for the *reader*; it is not
recorded in the archive. Every member's stored path is relative to whichever
`-C` preceded it, so the original tree structure is gone.

Two consequences, and the second is the one that bites:

1. **Extraction cannot rebuild the tree.** `tar xzf archive -C /` writes each
   member at its stored relative path under `/`. A member stored as
   `./site.conf`, archived from `nginx/conf.d`, extracts to `/site.conf`.
2. **Two directories archived as `-C <dir> .` collide.** Both contribute `./`
   members into one namespace, so the second's files land beside the first's
   with no way to tell them apart. **The information is lost at archive time,
   not at restore time** — no smarter restore can recover it.

The failure is silent at every observable point. `tar czf` exits 0. The file
appears with a plausible size. `tar tzf` lists members. Nothing reveals the
problem until someone actually needs the backup, which is the worst possible
moment to discover it.

## Evidence

1. **`scripts/core/backup_restore.sh` `backup_full()` built exactly this shape**
   — `-C "$REPO_ROOT" docker-compose.yml -C "$REPO_ROOT" jstack.config -C
   "$REPO_ROOT/nginx/conf.d" . -C "$REPO_ROOT/nginx/certbot/conf" . -C
   "$REPO_ROOT" sites`. Two of those five are `-C <dir> .`. — read 2026-09-19
2. **Reproduced, not inferred.** The same `tar czf` invocation against a scratch
   tree produced these member names:
   `docker-compose.yml`, `jstack.config`, `./`, `./site.conf`, `sites/`,
   `sites/a/`, `sites/a/.env`. The `nginx/conf.d/` prefix is absent from the
   archive entirely. — scratch reproduction 2026-09-19
3. **`restore_backup()` was `tar xzf "$FILE" -C /`** — so a restore would write
   `site.conf` to the filesystem root, not back into `nginx/conf.d/`. Run as
   root, it scatters across `/`. — read 2026-09-19
4. **It runs nightly, on the live host.** Confirmed in the running crontab, not
   only in the installer that writes it:
   `0 3 * * * cd "/home/jarvis/jstack" && bash scripts/core/backup_restore.sh backup --full`
   — `crontab -l` 2026-09-19
5. **The affected directories are the ones with no other copy.**
   `nginx/conf.d/` and `nginx/certbot/conf/` are both gitignored, which is the
   reason they are in the backup at all. — `.gitignore`, operating-principles #12

## Counter-Evidence

1. **`validate` passes on these archives, correctly.** `validate_backup()` runs
   `tar tzf >/dev/null` and reports integrity OK. That is not a wrong answer —
   the archive *is* a structurally valid gzip tar. It is only a check of the
   container, not of whether the contents can be put back. A green validate here
   is not evidence against this pattern; it is an instance of it.
2. **No restore has been attempted, so no data has been lost** — but not for the
   reason first recorded here. **AMENDED 2026-09-19, later the same day: there
   are no backups at all.** `backups/` contains zero `jstack_*.tar.gz` and
   `logs/backup_restore.log` has never existed. `logs/` is `drwxr-xr-x
   root:root`, empty, dated 2025-09-30; cron runs as `jarvis`, `log()` pipes
   through `tee -a` into that directory, `tee` fails with permission denied, the
   pipeline takes `tee`'s status, and `set -e` kills the script at its FIRST
   `log` call — before any `tar` runs. A second blocker sits behind it:
   `nginx/certbot/conf/accounts` is `drwx------ root:root`, so even with logging
   fixed, `tar` would fail reading it under `set -e`.
   So the archive-shape defect described in this record has never actually been
   exercised on this host. That is not reassurance. It means the nightly job has
   been failing silently since it was installed, and **fixing the tar shape does
   not make a backup exist.** The permissions are the blocking defect; the shape
   was merely the one visible from reading the code.
3. **The flat shape is correct for some archives.** An archive deliberately
   assembling files from several trees into one flat bundle is a legitimate use
   of multiple `-C`. The defect is not `-C` itself; it is pairing it with an
   extraction that assumes a tree the archive never carried.

> **"`tar czf` exits 0, the file has a plausible size, and `tar tzf` lists
> members. Nothing reveals the problem until someone actually needs the
> backup."**

*— Captured 2026-09-19, source: conversation — found while verifying an
unrelated change to the same function's config-file member*

## Applicability

- **When to use:** reviewing any `tar` invocation that pairs several `-C`
  options with relative member names, and any `tar x ... -C /`. Check both
  halves together: the archive shape and the extraction target are one design,
  and reading either alone hides the defect.
- **When to use:** reviewing any backup whose only test is an integrity check.
  Integrity and restorability are different properties; a backup nobody has
  restored is a hypothesis, not a backup.
- **When NOT to use:** as an argument against multiple `-C` in general. A
  deliberately flat bundle is fine. The pattern is about the *mismatch* between
  how an archive is built and how it is extracted.
- **When NOT to use:** as a reason to restore-test on a live host. The way to
  test this is extraction into a scratch directory and a diff against the
  source, never `-C /` on a production machine.

## How to apply this going forward

- Archive with paths relative to one root — `tar czf out.tgz -C "$REPO_ROOT"
  docker-compose.yml jstack.config nginx/conf.d nginx/certbot/conf sites` — so
  members carry their tree, and extract with `-C "$REPO_ROOT"` rather than `/`.
- Keep two directories distinguishable. `-C <dir> .` twice in one archive is the
  specific construct that destroys the distinction.
- Test a backup by extracting it somewhere harmless and diffing, not by trusting
  its exit code.

## Confidence

**HIGH** — the archive shape was reproduced directly rather than reasoned about,
the extraction target was read in the source, and the nightly schedule was
confirmed in the live crontab rather than in the installer alone. The repaired
shape was then round-tripped in a scratch tree: two files sharing a basename,
one in each nginx directory, survive distinct, and `diff -r` between source and
restored tree is clean.

The lesson this record exists for is sharper than the tar mechanics: **a backup
job that has never been verified end to end is a hypothesis.** Everything about
this one looked healthy from the outside — a cron line in the crontab, a script
that passes `bash -n` and `shellcheck`, an archive format that `tar tzf`
validates. What nobody had done was run it and look at the result. Two
independent defects were hiding behind that, and the one found by reading the
code was the less serious of the two.
