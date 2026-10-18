# molecule_generic — design

Date: 2026-10-18

## Goal

One Ansible role, `molecule_generic`, that Molecule scenarios call to create and
destroy test instances. A single input parameter selects which backend role does
the work:

| Driver      | Backend role                                                        |
|-------------|---------------------------------------------------------------------|
| `docker`    | [eclipse-slm/molecule_docker](https://github.com/eclipse-slm/molecule_docker)       |
| `kubevirt`  | [eclipse-slm/molecule_kubevirt](https://github.com/eclipse-slm/molecule_kubevirt)   |
| `openstack` | [eclipse-slm/molecule_openstack](https://github.com/eclipse-slm/molecule_openstack) |

Success: a scenario that today calls `molecule_docker` or `molecule_kubevirt`
with `tasks_from: create.yml` / `destroy.yml` can call `molecule_generic` the same
way instead, and choose the backend with one variable.

## Decisions

- **Dependency delivery:** the three backend roles are installed from git via
  `requirements.yml` (Molecule's `dependency: galaxy` step), pinned to `main` —
  no upstream repo publishes tags yet. They are *not* listed in
  `meta/main.yml` `dependencies`, because that would execute all three roles.
- **Driver selection:** role variable `molecule_generic_driver`, defaulting to the
  `MOLECULE_DRIVER` environment variable, falling back to `openstack`.
- **No per-platform mixing:** one driver per Molecule run.

## Interface

Entry points (run on `localhost`, like the backend roles):

```yaml
- ansible.builtin.include_role:
    name: molecule_generic
    tasks_from: create.yml   # or destroy.yml
```

Variables:

| Variable                  | Default                                                                  | Purpose                          |
|---------------------------|--------------------------------------------------------------------------|----------------------------------|
| `molecule_generic_driver` | `{{ lookup('env', 'MOLECULE_DRIVER') \| default('openstack', true) }}`   | Selects the backend              |
| `molecule_generic_driver_roles` (vars) | `{docker: molecule_docker, kubevirt: molecule_kubevirt, openstack: molecule_openstack}` | Driver → role map |

Everything else (`molecule_yml.platforms`, `molecule_ephemeral_directory`,
`molecule_instance_config`, `molecule_kubevirt_*`, …) passes through untouched
to the selected role. Each backend keeps its own inventory mechanism (Docker
writes `molecule_inventory.yml`; KubeVirt writes the instance config).

## Layout

```
requirements.yml        # 3 roles (git) + community.docker, kubernetes.core
defaults/main.yml       # molecule_generic_driver
vars/main.yml           # molecule_generic_driver_roles
tasks/validate.yml      # assert driver is a key of molecule_generic_driver_roles
tasks/create.yml        # validate → include_role <role> tasks_from create.yml
tasks/destroy.yml       # validate → include_role <role> tasks_from destroy.yml
meta/main.yml
molecule/default/       # shared converge/destroy/verify; driver from env (default openstack)
molecule/docker/        # ubuntu:24.04 platforms, MOLECULE_DRIVER=docker, prepare installs python3
molecule/kubevirt/      # containerdisk platforms, MOLECULE_DRIVER=kubevirt
README.md
```

## Error handling

- Unknown driver → `assert` fails before any backend work, listing valid drivers.
- `openstack` while the upstream role has no tasks → Ansible's own
  "could not find tasks/create.yml" error. No stub here, so nothing needs
  changing once upstream lands.

## Testing

- `ansible-lint` and `ansible-playbook --syntax-check` on the role and scenarios.
- Negative check: an invalid `MOLECULE_DRIVER` fails in `validate.yml`.
- `molecule test -s docker` end to end, if Docker is available locally.
- KubeVirt and OpenStack scenarios are not run here (need a cluster / cloud).
