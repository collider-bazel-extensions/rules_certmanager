# rules_certmanager — design decisions

Hermetic [cert-manager](https://cert-manager.io/) install + readiness for
Bazel tests. Drop-in for `rules_itest` services; composes with `rules_kind`
(or any cluster the consumer provides via `KUBECONFIG`).

This rule set is **the canonical home** for cert-manager wiring across the
collider-bazel-extensions ecosystem. `rules_capsule` v0.1.x carries an inline
copy of cert-manager pinning + apply scripts in its smoke test; that copy
will be removed in a follow-up release once consumers migrate to depend on
`rules_certmanager` instead.

All decisions inherited from sibling
`rules_pg`/`rules_temporal`/`rules_kind`/`rules_playwright`/`rules_capsule`.
Anything cert-manager-specific is flagged.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | rules_capsule precedent |
| 2 | Module extension shape | One tag class: `version` (download). No `system` mode. | rules_capsule |
| 3 | Toolchain type | `CERTMANAGER_TOOLCHAIN_TYPE = Label("//toolchain:cert_manager")`. `ToolchainInfo(cert_manager = …)` carries the pinned manifest. | rules_capsule |
| 4 | Manifest provisioning | `cert-manager.yaml` is fetched at extension/repo-rule time via `download` from GitHub releases at the sha256 pinned in `private/versions.bzl`. **No helm needed at maintainer or consumer side** — cert-manager publishes the manifest as a static release asset. | cert-manager-specific divergence from rules_capsule |
| 5 | Public surface | `cert_manager_install`, `cert_manager_health_check` + `CertManagerInfo` provider. CR resources (Issuer, Certificate, etc.) are consumer-authored YAML; no rule for them in v0.1. | All siblings |
| 6 | Namespace handling | The cert-manager manifest is self-contained — it includes the `Namespace` resource. No `--create-namespace` workaround needed (unlike rules_capsule). | cert-manager-specific |
| 7 | rules_itest integration | `cert_manager_install` produces an `itest_service.exe`-shaped target; `cert_manager_health_check` is the readiness probe. **No pass-through `services=` attr** — composition is the consumer's job. | All siblings |
| 8 | rules_kind dependency | **Examples-only.** The rule itself depends on neither `rules_kind` nor any cluster-provider rule; it just needs `KUBECONFIG` (or env-var-named-kubeconfig) on the host or via env. | rules_capsule precedent |
| 9 | Platform matrix v1 | Platform-independent (just `kubectl` + YAML). Validated on Linux x86_64; macOS pending. | rules_capsule |
| 10 | MODULE deps | `bazel_skylib`, `platforms`, `rules_python`. **No `rules_oci`**, no `rules_helm`, no `rules_certmanager`-style transitive deps. `rules_kind`/`rules_itest`/`rules_shell` are dev-only. | rules_capsule |
| 11 | Default test tags | `["cert_manager"]`; internal wrapper rules tagged `manual`. Smoke tests also `["requires-network", "no-sandbox"]`. | All siblings |
| 12 | Naming | snake_case rules, `MixedCaseInfo` providers, `UPPER_SNAKE` constants. | All siblings |
| 13 | Update workflow | `tools/update_versions.sh <version>` curls the manifest from GitHub, computes sha256, rewrites `private/versions.bzl`. Simpler than rules_capsule's helm-rendering tool. | rules_pg-style |
| 14 | Runtime lifecycle | One Python `private/launcher.py`: env setup, kubectl exec, SIGTERM forwarding. | All siblings |
| 15 | kubectl provisioning | **Host kubectl required** at v0.1, OR `$KUBECTL` env var (set by rules_kind's per-cluster env file). | rules_capsule precedent |

## cert-manager-specific notes

- The manifest at `https://github.com/cert-manager/cert-manager/releases/download/v<ver>/cert-manager.yaml` is pure Kubernetes YAML — no helm template / OCI / kustomize required.
- cert-manager has three Deployments (`cert-manager`, `cert-manager-cainjector`, `cert-manager-webhook`) all in the `cert-manager` namespace. The health check waits for all three to reach `Available=True`.
- The webhook needs CA injection from cainjector to be functional. `Available=True` on the webhook Deployment is a good proxy but not perfect — for tighter readiness, a smoke test should mint a real Certificate via a `SelfSigned` `Issuer` and assert `Ready`. The in-tree smoke test does exactly that.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| Module extension (`version` only) | planned |
| Pinned cert-manager 1.18.3 sha256 | planned |
| `cert_manager_install`, `cert_manager_health_check` rules | planned |
| `launcher.py` (env, exec, SIGTERM) | planned |
| Analysis tests | planned |
| In-tree smoke test (kind + cert-manager + self-signed Certificate) | planned |
| End-to-end `bazel test` runtime | planned (validated locally; macOS pending) |

## Deferred (not v0.1.0)

- **CR-shaped public rules** (`certmanager_certificate`, `certmanager_issuer`, etc.). Consumers author these as YAML for now. Add only if a real consumer asks.
- **trust-manager** companion. Separate operator, separate rule set candidate.
- **Hermetic kubectl.** v0.1 trusts host kubectl on PATH or `$KUBECTL` env var.
- **rules_capsule migration.** Once this rule set is cut as v0.1.0, follow up by removing the inline cert-manager pinning + scripts from `rules_capsule`'s smoke test and replacing them with a dev_dependency on `rules_certmanager`.
