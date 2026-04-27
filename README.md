# rules_certmanager

Hermetic [cert-manager](https://cert-manager.io/) install + readiness for
Bazel tests. Drops into [`rules_itest`](https://github.com/dzbarsky/rules_itest)
and composes with [`rules_kind`](https://github.com/collider-bazel-extensions/rules_kind)
(or any cluster the consumer provides via `KUBECONFIG`).

This rule set is the canonical home for cert-manager wiring across the
collider-bazel-extensions ecosystem; the inline cert-manager pinning in
[`rules_capsule`](https://github.com/collider-bazel-extensions/rules_capsule)
v0.1.x will be removed in a follow-up release in favor of depending on
`rules_certmanager` here.

**Supported platforms (v0.1):** Linux (x86\_64). macOS untested but the
rule is platform-independent (just kubectl + a static YAML). See
[Contributing](#contributing).

**Pinned versions:** cert-manager 1.18.3. The published `cert-manager.yaml`
release asset is downloaded directly and sha256-verified — **no `helm` is
required at maintainer or consumer side**.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Rules](#rules)
  - [cert\_manager\_install](#cert_manager_install)
  - [cert\_manager\_health\_check](#cert_manager_health_check)
- [`rules_itest` integration](#rules_itest-integration)
- [Providers](#providers)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_certmanager", version = "0.1.0")

cert_manager = use_extension("@rules_certmanager//:extensions.bzl", "cert_manager")
cert_manager.version(version = "1.18.3")
use_repo(cert_manager, "cert_manager")

register_toolchains("@cert_manager//:all")
```

`rules_certmanager` is **Bzlmod-only** in v0.1. Until it lands in BCR,
consume via `archive_override` or a git pin pointing at a tag.

---

## Quickstart

```python
load("@rules_certmanager//:defs.bzl", "cert_manager_install", "cert_manager_health_check")

# Long-running: applies the pinned cert-manager.yaml against whatever cluster
# `$KUBECONFIG` (or the env var named by `kubeconfig_env`) points at.
cert_manager_install(
    name = "cert_manager",
    kubeconfig_env = "KUBECONFIG",
)

# Readiness: tenants CRD registered + the three cert-manager Deployments
# (controller / cainjector / webhook) Available.
cert_manager_health_check(name = "cert_manager_health")
```

The rule itself doesn't bring up a cluster — it just installs cert-manager
into one you already have. For a kind-based composition, see
[`rules_itest` integration](#rules_itest-integration).

---

## Rules

### `cert_manager_install`

```python
cert_manager_install(
    name = "cert_manager",
    kubeconfig_env = "KUBECONFIG",
)
```

`kubectl apply -f` of the toolchain's pinned cert-manager manifest, then
sleeps until SIGTERM (so `rules_itest` treats it as a long-running
`itest_service`). Two-pass apply with retry to handle transient
webhook-startup races.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `kubeconfig_env` | `string` | `"KUBECONFIG"` | Env var holding the kubeconfig path. Under `rules_kind` + `rules_itest` you typically point this at whatever `kind_cluster`'s env file exports (often just `KUBECONFIG` after sourcing). |

### `cert_manager_health_check`

```python
cert_manager_health_check(
    name = "cert_manager_health",
    namespace = "cert-manager",
)
```

Two-step probe: (1) the `certificates.cert-manager.io` CRD is registered
(proves the manifest finished applying); (2) all Deployments in the
configured namespace are `Available=True` (controller, cainjector,
webhook). `rules_itest` retries until success or timeout.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `namespace` | `string` | `"cert-manager"` | Namespace cert-manager installs into; matches the manifest. |
| `kubeconfig_env` | `string` | `"KUBECONFIG"` | Env var holding the kubeconfig path. |

---

## `rules_itest` integration

`rules_certmanager` integrates by emitting `itest_service.exe` /
`health_check`-shaped targets. Composition is the consumer's job — there's
no pass-through `services=` attr, matching the
`rules_pg`/`rules_temporal`/`rules_kind`/`rules_playwright`/`rules_capsule`
convention.

The in-tree smoke test is the canonical reference. Composition shape:

```python
load("@rules_certmanager//:defs.bzl", "cert_manager_install", "cert_manager_health_check")
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# 1. The cluster.
kind_cluster(name = "cluster", k8s_version = "1.29")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. cert-manager.
cert_manager_install(name = "cert_manager_bin")
cert_manager_health_check(name = "cert_manager_health_bin")

# 3. Wrappers that bind the cluster-source-agnostic rule binaries to the
#    specific rules_kind cluster (source the env file with `set -a` so
#    KUBECONFIG/KUBECTL cross the `exec` boundary).
sh_binary(
    name = "cert_manager_install_wrapper",
    srcs = ["cert_manager_install_wrapper.sh"],
    data = [":cert_manager_bin"],
)
sh_binary(
    name = "cert_manager_health_wrapper",
    srcs = ["cert_manager_health_wrapper.sh"],
    data = [":cert_manager_health_bin"],
)
itest_service(
    name = "cert_manager_svc",
    exe = ":cert_manager_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":cert_manager_health_wrapper",
)
```

The `tests/` directory has the wrapper shell scripts and a worked
end-to-end test that mints a SelfSigned Certificate.

---

## Providers

### `CertManagerInfo`

| Field | Type | Description |
|---|---|---|
| `version` | `string` | cert-manager version, e.g. `"1.18.3"` |
| `manifest` | `File` | The downloaded, sha256-verified `cert-manager.yaml` |
| `namespace` | `string` | Always `"cert-manager"` (the manifest hard-codes it) |

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| `cert-manager.yaml` | Fully hermetic. URL + sha256 pinned in `private/versions.bzl`; downloaded by the bzlmod extension. | Update via `tools/update_versions.sh <version>` when bumping. |
| `kubectl` | **Not vendored.** v0.1 honors `$KUBECTL` env (set by `rules_kind`'s per-cluster env file) and falls back to `$PATH`. | Future: bundle a hermetic kubectl via toolchain. |
| Target cluster | Out of scope — bring your own (`rules_kind`, real cluster, etc.). | The rule reads `KUBECONFIG` from env. |
| cert-manager container images | **Pulled at runtime** by the cluster's nodes. Not pre-loaded. | Future: optional `images = [...]` attr for pre-loading via `kind_cluster.images`. |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned version: `bash tools/update_versions.sh <new-version> --update`.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted: macOS validation

The rule is platform-independent (kubectl + static YAML), but no one has
run the smoke test on Darwin. A green smoke run on macOS — even a pasted
log — flips this from "should work" to "verified" in v0.1.x.
