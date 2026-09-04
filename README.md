# maneyko.roles

Personal Ansible collection.

| Role | Purpose |
|---|---|
| `github_install_binary` | Install a binary from a GitHub release tarball |
| `uv` | Install `uv` plus a shared, group-writable Python toolchain |
| `rv` | Install `rv` plus a shared, group-writable Ruby toolchain |
| `nginx_common` | The TLS snippets every NGINX site includes |
| `lego` | ACME certificates under `/etc/lego`, renewed by a daily timer |
| `baresip` | Headless SIP client, built from source |
| `ntfy_server` | ntfy behind NGINX, as a pub-sub notification server |
| `journald_vacuum` | Trim the systemd journal on a daily timer |

`github_install_binary`, `uv`, `rv` and `lego` are portable — nothing in them
names a particular host. The other three describe one machine, and are here
because the reasoning below is worth reading rather than because they offer a
stable interface: `nginx_common` deletes Debian's default site and tracks
certbot's `options-ssl-nginx.conf` from `main`, `ntfy_server` wants an NGINX
snippet it does not ship, and `baresip` builds from source against a
hardcoded MQTT topic. Expect to fork those three rather than configure them.

Each role's inputs are declared in `roles/<name>/meta/argument_specs.yaml` and
validated before the role runs:

    ansible-doc -t role -r roles uv

## Use

`requirements.yml`:

```yaml
collections:
  - name: https://github.com/maneyko/ansible-roles.git
    type: git
    version: main
```

```sh
ansible-galaxy collection install -r requirements.yml
```

```yaml
- hosts: all
  roles:
    - role: maneyko.roles.uv
      uv_users: [alice]
```

## How `uv` is wired up

`rv` is wired up the same way; read `uv` below and substitute.

The real binary lives at `/opt/uv/libexec/bin/uv` and `/usr/local/bin/uv` is a
shim:

```sh
#!/bin/sh
umask 0002
export UV_CACHE_DIR=/opt/uv/cache
export UV_LINK_MODE=copy
...
exec /opt/uv/libexec/bin/uv "$@"
```

Everything follows from that. A login shell, a systemd unit and this collection
all get the shared cache and interpreters without naming a `UV_` variable, so
nothing that consumes uv has to know where the toolchain lives. The umask keeps
the cache writable by the group, which it has to be: `uv run` writes an
environment per script, so a read-only shared cache is not a shared cache.

A shell function cannot do this job. `exports` survive into the subprocess an
Ansible module spawns, but shell functions do not, so a `uv()` wrapper in
`/etc/profile.d` silently fails to apply to anything Ansible runs — which is how
the cache first came to be group-readable but not group-writable.

`/opt/uv` is `o=`, so uv is unusable outside the `uv` group rather than usable
but unable to write. Every service that runs Python through uv belongs in
`uv_users`.

`UV_LINK_MODE=copy` because uv otherwise **hardlinks** cache entries into each
venv, which makes a venv file and its cache entry one inode sharing an owner and
a mode. Any app that hands its own checkout to its own group, with its `.venv`
somewhere inside that checkout, then rewrites the shared entries out from under
every other member of the group — locking out every service that is in the `uv`
group but not that app's.

There is no `chown -R` that re-owns a venv and spares the cache, and excluding
the venv from the sweep only moves the problem — `uv sync` runs as the checkout's
owner, so the files it does not hardlink come out unreadable to the *service*
instead. A shared cache and per-app venv ownership cannot share an inode. Copies
cost tens of megabytes and end the argument. `clone` mode is not a cheaper
substitute unless the filesystem supports reflinks; on ext4 it degrades to copy.

## Where `rv` differs from `uv`

**`rv` needs a post-install hook, because the umask is not enough.** RubyGems
chmods every file it extracts to the mode recorded in the gem's tar header
(`Gem::Package#extract_tar_gz`), which `gem build` copies verbatim off the
maintainer's disk — so gems arrive at whatever mode that machine used, usually
`0644`, and `& ~File.umask` on that line can only *clear* bits. No umask widens
it, and the `data_mode` that would override it is unreachable from Bundler.

The role installs `roles/rv/files/rubygems_plugin.rb` into each ruby's
unversioned `site_ruby`, which is on every Ruby's default `$LOAD_PATH` where
`Gem.load_env_plugins` finds it for both `gem` and `bundle` — no ABI version in
the path, no variable to export. It reasserts group access on the gem directory,
the extension directory, the gemspec and the cached `.gem`.

Do not simplify it to `chmod g+w`: gems ship `0600` files, and adding only the
write bit makes those `0620`. And do not drop the gemspec — Bundler truncates
`specifications/<name>.gemspec` in place, so one left at `0644` by one member of
the group stops every other member installing that gem at all, with a
`Gem::FilePermissionError` rather than a mode that merely looks wrong.

Gem **directories** matter more than the files, and the hook covers them for a
reason that is easy to miss: they come from `mkdir_p` with no mode, so they take
the caller's umask — and nothing in this role sets it, because `bundle` runs off
`PATH` rather than through the shim. Without the hook, "group-writable and
setgid, enough to create, replace and delete gems" would depend on each user
having `umask 0002` in their own dotfiles, and under `0022` the same `bundle
install` produces `0755` directories nobody else can replace.

The sweep that follows the install carries a gems-scoped line for the same
reason from the other direction: the hook only fires on a gem install, so it
never sees the gems rv's own tarball ships.

Note the split the role maintains on purpose: gem files are group-writable, the
interpreter and its stdlib are not. Sharing a ruby does not mean sharing the
ability to rewrite it.

**`rv` reads `RUBIES_PATH` and nothing else.** The
`RV_INSTALL_PATH` and `RV_CACHE_DIR` its profile used to export were never
consulted by `rv` at all — `rv ruby dir` ignored them and only the explicit
`--install-dir` on the install command was keeping rubies out of
`~/.local/share/rv`. The shim exports the variable that works, so every `rv`
subcommand now agrees on where rubies live.

## How `github_install_binary` works

`uv`, `rv` and `lego` all install the same way: fetch a release tarball from
GitHub, unpack it in a scratch directory, move the binaries out, delete the rest.
The role takes a repo and a `jq` filter that picks the right asset for the
architecture, and `github-download-release.sh` does the fetching.

```yaml
- include_role:
    name: maneyko.roles.github_install_binary
  vars:
    github_install_binary_repo:   astral-sh/uv
    github_install_binary_exec:   uv
    github_install_binary_dest:   /opt/uv/libexec/bin
    github_install_binary_filter: startswith("uv-\($uname_m)-") and endswith("linux-gnu.tar.gz")
    github_install_binary_find:   find */{uv,uvx}
```

`github_install_binary_exec` is what makes the whole thing idempotent — it is the
`creates:` for both the download and the install, so a second run does nothing
and reports nothing. `github_install_binary_version` defaults to `latest`, so
re-running does **not** upgrade an existing install; delete the binary to force
one.

**Three things in this role look like defects and are load-bearing.** Do not
"fix" them; the reasons are in the code too:

- **The `jq` filter is passed on `stdin`, not in the command.** The inventory
  uses `sudo --login`, which adds a second shell expansion pass that strips
  quoting and eats `$uname_m`.
- **`# noqa: risky-file-permissions` on the dest directory.** The task only
  asserts the directory exists. `uv` and `rv` pass a dest they created
  `g+srw,o=` themselves, so a `mode:` here would fight them and both roles would
  report `changed` against each other forever.
- **`# noqa: risky-shell-pipe` on the install.** `set -o pipefail` would fail
  any install whose `_find` ends in `head -1`, as lego's does, because the find
  is then killed by SIGPIPE.

## What to know before touching `baresip`

Built from source because Debian's package is too old to carry the `mqtt`
module, which is the only reason this role exists — MQTT is how a companion
process learns about call and voicemail events. `install-baresip.sh` is the one step that wants CPU,
so build on a larger machine type and downsize afterwards.

Four things that have each cost real debugging time:

- **A config key is dead unless its module is loaded.** Nothing in baresip loads
  implicitly. `cons_listen`, `ctrl_tcp_listen` and `http_listen` sat in this
  config for months reading like three unauthenticated control ports and bound
  nothing at all, because `cons.so`, `ctrl_tcp.so` and `httpd.so` were never in
  the `module` list. Check the module list before believing a port is open, or
  that a setting does anything.
- **`sip_trans_def tcp` is a fix, not a preference.** An inbound PSTN INVITE
  carries a STIR/SHAKEN `Identity:` header that pushes it past the MTU; over UDP
  it arrives IP-fragmented, the firewall cannot match the later fragments to a
  conntrack entry, and baresip is handed *nothing* — so it neither logs nor
  replies. `REGISTER` and `NOTIFY` fit in one datagram, so registration and MWI
  look perfectly healthy the whole time. RTP stays UDP.
- **The handler is load-bearing.** The role copies the config and then asks
  systemd for `state: started`, which is a no-op where baresip already runs — so
  without `notify: Restart baresip` a changed module line sits on disk unloaded.
- **The mqtt module connects once and never retries.** On a refused connection
  it unloads itself and baresip carries on registered and silent, which
  `Restart=on-failure` cannot catch because nothing fails. The unit declares
  `Wants=` and `After=mosquitto.service` for that reason.

Do not reach for `catchall=true` to fix an unmatched INVITE. It makes one UA
accept everything, which looks like a fix and is not: a consumer of these
events has only `accountaor` to derive the destination number from, so every
call would be attributed to whichever account carries the flag.

## Which NGINX files belong to the host

The test is whether a file would still make sense if the site that first needed
it were deleted. If yes it belongs here, in `nginx_common`; if no it belongs to
the site's own repo.

| Owner | Files |
|---|---|
| `nginx_common` | `options-ssl-nginx.conf`, `ssl-dhparams.pem`, `proxy-headers.conf`, `conf.d/log-formats.conf`, `default-cert.conf`, `zz-fallback.conf` |
| the site repo | `<domain>.conf`, `snippets/ssl-<domain>.conf`, `config/deploy.yaml` |
| a role, from a variable | `ntfy.local.conf` and anything else holding a secret |
| the `nginx-common` Debian package | `fastcgi-php.conf` |

Three of those moved out of the `maneyko.com` repo, where they had ended up
because that is where they were first needed. `proxy-headers.conf` names no
site. `log_format apm` is an `http`-level directive that only worked from a
site config because `sites-enabled/*` loads alphabetically and that file sorted
early; from `conf.d/` it is available to everyone. The catch-all `zz-fallback`
server is a property of the machine, and was never linked at all.

`default-cert.conf` is the certificate for services that belong to the host
rather than to a site -- ntfy, the catch-all, any locally-proxied app. They
include it by name, so
none of them depends on a website repo being deployed first.

## Why `lego` renews from `renew.d` and not from `certificates`

`/etc/lego/renew.d/<domain>.env` names a domain's SANs and its DNS provider;
`/etc/lego/certificates/` holds what was actually issued. Renewal is driven
from the first, because the second cannot answer the question. A certificate
records its domains (`certificates/<domain>.json` has a `domains` key) but
*nothing* records which DNS provider proved them, and a host whose domains are
spread across two providers needs that to renew either. A directory of
certificates is also, by definition, missing any domain whose issuance failed —
so renewal driven from it can never retry.

`/etc/lego` is hardcoded throughout, in the role and in the renewal script.

## The two smaller roles

**`journald_vacuum`** installs `journalctl-vacuum.service` and a daily timer.
The retention only means anything where the journal is **persistent** — with
`/var/log/journal` absent, journald keeps logs under `/run` and a reboot
discards them whatever the retention says, which would make the whole role
decorative. The arg spec says so.

`journald_vacuum_time` is a variable because there are already two answers, `7d`
on the fractal hosts and `2d` on a 10 GiB cloud disk. The schedule is not,
because there is still only one. The role is named for what it manages, matching
`nginx_common` and `ntfy_server`, while the *units* keep the
`journalctl-vacuum` names the fractal hosts already use — so the same unit is
called the same thing on every host, whatever the role wrapping it is called.

**`ntfy_server`** puts ntfy behind NGINX. It takes its certificate include as
`ntfy_server_cert_snippet`, defaulting to `snippets/default-cert.conf`, so
`nginx_common` is the *default* provider rather than a hard prerequisite — the
role's only tie to it was two `include` lines of one file. The upstream it
proxies to is passed in as a variable rather than committed.

## House style

- **Every role has `meta/argument_specs.yaml`**, and Ansible validates it before
  the role runs. That file is the role's interface and its documentation; a new
  input is not done until it is declared there. Read one with
  `ansible-doc -t role -r roles <name>` in this repo, or
  `ansible-doc -t role maneyko.roles.<name>` where the collection is installed.
  Note `-M` is `--module-path` and will print nothing while exiting 0.
- **`galaxy.yml` gets bumped on every commit** — patch for a change to an
  existing role, minor for a new one, major for removing one. There are no git
  tags; consumers track `main`, so the version is documentation rather than a
  pin.
- **`ansible-lint` passes at the `production` profile.** Run it with
  `uvx --from ansible-lint ansible-lint --offline`. `.ansible-lint` records the
  three rules deliberately skipped, so anything else it reports is a real
  finding. Two in-task `# noqa` comments exist and are explained above.
- **Module names are shorthand, not FQCN**, and keys are aligned by padding
  after the colon. Both are why `fqcn` and `yaml[colons]` are skipped.
- **A role that writes a config file a daemon reads needs a handler.** Asking
  systemd for `state: started` is a no-op on a host where the daemon is already
  running, so the new config sits unloaded. `baresip`, `nginx_common` and
  `ntfy_server` all carry one for this reason.

## Why a collection and not a bare roles repo

`ansible-galaxy role install` treats a git repo as exactly one role, so a repo
holding several roles cannot be consumed through the `roles:` key of a
requirements file. Collections are the supported unit for shipping several
roles from one repo, and they namespace generic names like `uv`, `rv` and
`lego`, which would otherwise collide.
