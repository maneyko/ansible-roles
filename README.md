# maneyko.roles

Personal Ansible collection.

| Role | Purpose |
|---|---|
| `github_release` | Install a binary from a GitHub release tarball |
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

## Why a collection and not a bare roles repo

`ansible-galaxy role install` treats a git repo as exactly one role, so a repo
holding three roles cannot be consumed through the `roles:` key of a
requirements file. Collections are the supported unit for shipping several
roles from one repo, and they namespace `uv` and `rv`, which are otherwise
generic enough to collide.
