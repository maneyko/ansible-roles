# maneyko.roles

Personal Ansible collection.

| Role | Purpose |
|---|---|
| `github_install_binary` | Install a binary from a GitHub release tarball |
| `uv` | Install `uv` plus a shared, group-writable Python toolchain |
| `rv` | Install `rv` plus a shared, group-writable Ruby toolchain |

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

## Why a collection and not a bare roles repo

`ansible-galaxy role install` treats a git repo as exactly one role, so a repo
holding three roles cannot be consumed through the `roles:` key of a
requirements file. Collections are the supported unit for shipping several
roles from one repo, and they namespace `uv` and `rv`, which are otherwise
generic enough to collide.
