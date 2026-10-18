# molecule_generic

An Ansible role that Molecule scenarios use to create and destroy test instances.
It contains no backend logic of its own: one variable selects which backend role
does the work.

| Driver      | Backend role                                                                       | Needs                                                   |
|-------------|------------------------------------------------------------------------------------|---------------------------------------------------------|
| `docker`    | [molecule_docker](https://github.com/eclipse-slm/molecule_docker)                   | Docker daemon, `community.docker`, Python `docker` SDK  |
| `kubevirt`  | [molecule_kubevirt](https://github.com/eclipse-slm/molecule_kubevirt)               | Kubernetes with KubeVirt, `kubernetes.core`, kubeconfig |
| `openstack` | [molecule_openstack](https://github.com/eclipse-slm/molecule_openstack)             | Not usable yet (see below)                              |

## Selecting the driver

`molecule_generic_driver` picks the backend. It defaults to the `MOLECULE_DRIVER`
environment variable, and to `openstack` when that is unset or empty.

```bash
MOLECULE_DRIVER=docker molecule test                        # per run
molecule converge -- -e molecule_generic_driver=kubevirt    # extra var wins over the env var
```

A scenario can also fix its driver in `molecule.yml`:

```yaml
ansible:
  env:
    MOLECULE_DRIVER: docker
```

An unknown value fails before anything is created and lists the valid drivers.

**OpenStack:** the upstream role has no tasks and no `meta/main.yml` yet, so
`ansible-galaxy` cannot install it and its entry in `requirements.yml` is
commented out. Selecting `openstack` (the default) fails until that role is
published; then uncomment the entry.

## Using it in your project

`requirements.yml` (installed by Molecule's `dependency: galaxy` step):

```yaml
roles:
  - name: molecule_generic
    src: https://github.com/eclipse-slm/molecule_generic.git
    scm: git
    version: main
  - name: molecule_docker
    src: https://github.com/eclipse-slm/molecule_docker.git
    scm: git
    version: main
  - name: molecule_kubevirt
    src: https://github.com/eclipse-slm/molecule_kubevirt.git
    scm: git
    version: main

collections:
  - name: community.docker
  - name: community.general
  - name: kubernetes.core
```

`converge.yml` and `destroy.yml` call the role like the backend roles, from localhost:

```yaml
- name: Converge
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Create instances
      ansible.builtin.include_role:
        name: molecule_generic
        tasks_from: create.yml   # destroy.yml in destroy.yml
```

`molecule_yml.platforms` and every backend variable (for example
`molecule_kubevirt_default_*`) are passed through unchanged, so platform entries
use the format of the selected backend.

## Scenarios in this repository

| Scenario   | Driver                       | Notes                                              |
|------------|------------------------------|----------------------------------------------------|
| `default`  | from `MOLECULE_DRIVER`       | Shared converge/destroy/verify playbooks; no platforms |
| `docker`   | `docker`                     | Two `ubuntu:24.04` containers; prepare installs Python |
| `kubevirt` | `kubevirt`                   | Two Ubuntu 24.04 VMs; needs a cluster              |

```bash
molecule test -s docker
bash tests/run.sh          # driver selection checks, no instances created
```

## License

MIT

## Author Information

- **Author**: Benjamin Goetz
- **Company**: Fraunhofer IPA
- **Namespace**: eclipse_slm
