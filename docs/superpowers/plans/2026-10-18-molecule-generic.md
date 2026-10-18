# molecule_generic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Ansible role `molecule_generic` whose `create.yml` / `destroy.yml` delegate to `molecule_docker`, `molecule_kubevirt` or `molecule_openstack` based on one variable.

**Architecture:** Thin dispatcher role. `tasks/validate.yml` checks the driver against a driver→role map in `vars/main.yml`; `tasks/create.yml` / `tasks/destroy.yml` then `include_role` the mapped role with the same `tasks_from`. Backend roles arrive via `requirements.yml` (git, `main`), installed by Molecule's galaxy dependency step.

**Tech Stack:** ansible-core 2.21, molecule 26.6, ansible-lint 26.6, community.docker, kubernetes.core, Docker 29 (local).

**Spec:** `docs/superpowers/specs/2026-10-18-molecule-generic-design.md`

## Global Constraints

- Driver variable: `molecule_generic_driver`, default `"{{ lookup('env', 'MOLECULE_DRIVER') | default('openstack', true) }}"`.
- Driver map variable: `molecule_generic_driver_roles: {docker: molecule_docker, kubevirt: molecule_kubevirt, openstack: molecule_openstack}`.
- Backend roles are NOT in `meta/main.yml` `dependencies` (must stay `[]`).
- Backend roles pinned `version: main` from `https://github.com/eclipse-slm/<role>.git`.
- Molecule config uses the top-level `ansible:` key style of the upstream roles (no `provisioner:`).
- Scenarios reference the role as `../../../molecule_generic` (repo dir name), matching upstream.
- No OpenStack stub; selecting it surfaces Ansible's missing-tasks error.
- License MIT, author Benjamin Goetz, company Fraunhofer IPA, namespace eclipse_slm.

## Review Focus

- `MOLECULE_DRIVER` set but empty (`MOLECULE_DRIVER=`) → must fall back to `openstack`, not `""` (the `true` arg of `default`). Pinned in Task 1 test.
- Driver given in different case (`Docker`) → fails validation with the valid-driver list; no silent lowercase. Pinned in Task 1 test.
- `-e molecule_generic_driver=kubevirt` while `MOLECULE_DRIVER=docker` → extra var wins. Pinned in Task 1 test.
- `molecule destroy` on a never-created docker scenario → must succeed (upstream destroy loops tolerate it). Pinned in Task 2 by running `molecule destroy -s docker` first.
- Docker destroy uses `json_query` → needs `community.general` + `jmespath`; missing collection would break destroy. `community.general` added to `requirements.yml` in Task 1; exercised by Task 2's full test.

---

### Task 1: Dispatcher role

**Files:**
- Create: `requirements.yml`, `defaults/main.yml`, `vars/main.yml`, `tasks/validate.yml`, `tasks/create.yml`, `tasks/destroy.yml`, `meta/main.yml`, `.ansible-lint`
- Test: `tests/driver_selection.yml`, `tests/run.sh`

**Interfaces:**
- Produces: `include_role: name=molecule_generic tasks_from=create.yml|destroy.yml|validate.yml`; vars above. `validate.yml` sets nothing; it only asserts.

- [ ] **Step 1: Write the failing test**

`tests/driver_selection.yml`: play on localhost, `roles: []`, tasks: `include_role name=../molecule_generic tasks_from=validate.yml` (relative from `tests/`; use `{{ playbook_dir }}/..`), then `debug: msg="DRIVER={{ molecule_generic_driver }} ROLE={{ molecule_generic_driver_roles[molecule_generic_driver] }}"`.

`tests/run.sh` (bash, `set -u`, exits non-zero on any failed expectation), cases:

| Env / args                                   | Expect                                             |
|----------------------------------------------|----------------------------------------------------|
| (none)                                       | rc 0, output has `DRIVER=openstack ROLE=molecule_openstack` |
| `MOLECULE_DRIVER=`                           | rc 0, `DRIVER=openstack`                           |
| `MOLECULE_DRIVER=docker`                     | rc 0, `DRIVER=docker ROLE=molecule_docker`         |
| `MOLECULE_DRIVER=docker -e molecule_generic_driver=kubevirt` | rc 0, `DRIVER=kubevirt ROLE=molecule_kubevirt` |
| `MOLECULE_DRIVER=bogus`                      | rc ≠ 0, output has `docker, kubevirt, openstack`   |
| `MOLECULE_DRIVER=Docker`                     | rc ≠ 0                                             |

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL (role files missing).

- [ ] **Step 3: Implement the role**

- `defaults/main.yml`, `vars/main.yml`: the two variables from Global Constraints.
- `tasks/validate.yml`: `ansible.builtin.assert` that `molecule_generic_driver in molecule_generic_driver_roles`; `fail_msg` lists `molecule_generic_driver_roles.keys() | sort | join(', ')`; `quiet: true`.
- `tasks/create.yml` / `destroy.yml`: `include_tasks: validate.yml`, then `include_role: name="{{ molecule_generic_driver_roles[molecule_generic_driver] }}" tasks_from=create.yml|destroy.yml`.
- `requirements.yml`: `roles:` three git entries (`name`, `src`, `scm: git`, `version: main`); `collections:` `community.docker`, `community.general`, `kubernetes.core`.
- `meta/main.yml`: real galaxy_info (description "Generic Molecule driver role dispatching to docker, kubevirt or openstack.", MIT, `min_ansible_version: "2.15"`, tags `molecule docker kubevirt openstack`), `dependencies: []`.
- `.ansible-lint`: `exclude_paths: [docs/]`.

- [ ] **Step 4: Run tests and lint**

Run: `bash tests/run.sh && ansible-lint`
Expected: all cases pass; ansible-lint reports no failures.

- [ ] **Step 5: Commit**

```bash
git add requirements.yml defaults vars tasks meta tests .ansible-lint
git commit -m "Add molecule_generic dispatcher role"
```

### Task 2: Shared playbooks + docker scenario

**Files:**
- Create: `molecule/default/{molecule.yml,converge.yml,destroy.yml,verify.yml}`, `molecule/docker/{molecule.yml,prepare.yml}`

**Interfaces:**
- Consumes: Task 1 entry points.
- Produces: shared playbooks at `../default/*.yml` for Task 3.

- [ ] **Step 1: Write scenario files**

- `default/converge.yml`: localhost play, `gather_facts: false`, `include_role name=../../../molecule_generic tasks_from=create.yml` (same pattern as upstream converge).
- `default/destroy.yml`: localhost play, `include_role … tasks_from=destroy.yml`, then the upstream "Dump instance config" `{}` block.
- `default/verify.yml`: copy upstream verify (touch + stat + assert `/tmp/molecule-empty-file`), `become: false`.
- `default/molecule.yml`: upstream default `molecule.yml` minus the bogus `--inventory=/path/to/inventory.yml` arg; no platforms; driver from caller's env.
- `docker/molecule.yml`: platforms = upstream `molecule_docker/molecule/ubuntu24` (two `ubuntu:24.04`, `sleep infinity`, shared network); `ansible.env.MOLECULE_DRIVER: docker`; playbooks converge/destroy/verify → `../default/…`, `prepare: prepare.yml`; `test_sequence` without `idempotence` (converge = create, not idempotent upstream).
- `docker/prepare.yml`: `hosts: all`, `gather_facts: false`, `raw: apt-get update && apt-get install -y python3`.

- [ ] **Step 2: Destroy on clean state**

Run: `molecule destroy -s docker`
Expected: exit 0.

- [ ] **Step 3: Full run**

Run: `molecule test -s docker`
Expected: exit 0; log shows tasks from `molecule_docker : Create a container`; verify asserts pass; afterwards `docker ps -a --filter name=ubuntu24` is empty.

- [ ] **Step 4: Lint and commit**

Run: `ansible-lint` → no failures.

```bash
git add molecule
git commit -m "Add shared playbooks and docker molecule scenario"
```

### Task 3: kubevirt scenario + README

**Files:**
- Create: `molecule/kubevirt/molecule.yml`
- Modify: `README.md`

- [ ] **Step 1: kubevirt scenario**

Platforms = upstream `molecule_kubevirt/molecule/ubuntu_24` (`quay.io/containerdisks/ubuntu:24.04`, `arch: amd64`); `ansible.env.MOLECULE_DRIVER: kubevirt`; playbooks → `../default/…`; `verify` with `become: true` is not required (shared verify writes to /tmp).

- [ ] **Step 2: Syntax check (no cluster available)**

Run: `molecule syntax -s kubevirt`
Expected: exit 0.

- [ ] **Step 3: README**

Sections: purpose, driver table (driver → role → requirements), selecting the driver (env var, `-e`, default `openstack`, current OpenStack status), using it from another project's scenario (requirements.yml snippet + converge/destroy snippet), scenarios in this repo, license.

- [ ] **Step 4: Lint and commit**

Run: `ansible-lint` → no failures.

```bash
git add molecule/kubevirt README.md
git commit -m "Add kubevirt scenario and README"
```
