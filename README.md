# maneyko.roles

Personal Ansible collection.

| Role | Purpose |
|---|---|
| `github_install_binary` | Install a binary from a GitHub release tarball |
| `uv` | Install `uv` plus a shared, group-writable Python toolchain |
| `rv` | Install `rv` plus a shared, group-writable Ruby toolchain |
| `docker` | Install Docker from Docker's own apt repository |
| `nginx_common` | The TLS snippets every NGINX site includes |
| `lego` | ACME certificates under `/etc/lego`, renewed by a daily timer |
| `baresip` | Headless SIP client, built from source |

Each role's inputs are declared in `roles/<name>/meta/argument_specs.yaml` and
validated before the role runs:

    ansible-doc -t role -M roles maneyko.roles.uv

## Use

`requirements.yml`:

```yaml
collections:
  - name: git@github.com:maneyko/ansible-roles.git
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
roles from one repo, and they namespace generic names like `uv`, `docker` and
`lego`, which would otherwise collide.
