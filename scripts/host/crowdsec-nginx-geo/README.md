# crowdsec-nginx-geo

Copies of host-side files, kept here so the repo has a second copy. The live files are
installed and owned by root on the host:

| Repo file | Installed at |
|---|---|
| `crowdsec-nginx-geo-sync` | `/usr/local/sbin/crowdsec-nginx-geo-sync` |
| `nginx-geo-sync.conf` | `/etc/crowdsec/nginx-geo-sync.conf` |
| `nginx-geo-allow.txt` | `/etc/crowdsec/nginx-geo-allow.txt` |
| `systemd/*` | `/etc/systemd/system/` |
| `fail2ban/jstack-nginx-geo.conf` | `/etc/fail2ban/action.d/jstack-nginx-geo.conf` |
| `tmpfiles/jstack-nginx-geo-lock.conf` | `/etc/tmpfiles.d/jstack-nginx-geo-lock.conf` |

The sync mirrors CrowdSec's local ban decisions into `nginx/conf.d/crowdsec-banned.geo`,
which `00-f2b-geo.conf` includes into `geo $f2b_banned`. It and the fail2ban action share
`/run/jstack-nginx-geo.lock` (0644, so a jarvis-side edit to a conf.d geo file can
`flock /run/jstack-nginx-geo.lock <cmd>` on a read-only fd). In `nginx-geo-sync.conf`, the operator's admin IP is
replaced with `<operator-ip>`; the installed copy has the real address.
