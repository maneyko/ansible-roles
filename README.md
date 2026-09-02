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

The one asymmetry: `rv` reads `RUBIES_PATH` and nothing else. The
`RV_INSTALL_PATH` and `RV_CACHE_DIR` its profile used to export were never
consulted by `rv` at all — `rv ruby dir` ignored them and only the explicit
`--install-dir` on the install command was keeping rubies out of
`~/.local/share/rv`. The shim exports the variable that works, so every `rv`
subcommand now agrees on where rubies live.

## Which NGINX files belong to the host

The test is whether a file would still make sense if the site that first needed
it were deleted. If yes it belongs here, in `nginx_common`; if no it belongs to
the site's own repo.

| Owner | Files |
|---|---|
| `nginx_common` | `options-ssl-nginx.conf`, `ssl-dhparams.pem`, `proxy-headers.conf`, `conf.d/log-formats.conf`, `default-cert.conf`, `zz-fallback.conf` |
| the site repo | `<domain>.conf`, `snippets/ssl-<domain>.conf`, `config/deploy.yaml` |
| a role, from a variable | `ntfy.local.conf`, `pyapp.local.conf` and anything else holding a secret |
| the `nginx-common` Debian package | `fastcgi-php.conf` |

Three of those moved out of the `maneyko.com` repo, where they had ended up
because that is where they were first needed. `proxy-headers.conf` names no
site. `log_format apm` is an `http`-level directive that only worked from a
site config because `sites-enabled/*` loads alphabetically and that file sorted
early; from `conf.d/` it is available to everyone. The catch-all `zz-fallback`
server is a property of the machine, and was never linked at all.

`default-cert.conf` is the certificate for services that belong to the host
rather than to a site -- ntfy, pyapp, the catch-all. They include it by name, so
none of them depends on a website repo being deployed first.

## Why `lego` renews from `renew.d` and not from `certificates`

`/etc/lego/renew.d/<domain>.env` names a domain's SANs and its DNS provider;
`/etc/lego/certificates/` holds what was actually issued. Renewal is driven
from the first, because the second cannot answer the question. A certificate
records its domains (`certificates/<domain>.json` has a `domains` key) but
*nothing* records which DNS provider proved them, and a host serving both
Cloudflare and IONOS domains needs that to renew either. A directory of
certificates is also, by definition, missing any domain whose issuance failed —
so renewal driven from it can never retry.

`/etc/lego` is hardcoded throughout, in the role and in the renewal script.

## Why a collection and not a bare roles repo

`ansible-galaxy role install` treats a git repo as exactly one role, so a repo
holding several roles cannot be consumed through the `roles:` key of a
requirements file. Collections are the supported unit for shipping several
roles from one repo, and they namespace generic names like `uv`, `rv` and
`lego`, which would otherwise collide.
