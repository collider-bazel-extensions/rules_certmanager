#!/usr/bin/env python3
"""Runtime launcher for cert_manager_install / cert_manager_health_check.

Same role as launcher.py in rules_pg / rules_temporal / rules_kind /
rules_playwright / rules_capsule. Owns:
- env setup (KUBECONFIG resolution, kubectl resolution honoring $KUBECTL)
- exec of `kubectl` against the resolved kubeconfig
- SIGTERM/SIGINT forwarding so itest can stop the long-running install
  service cleanly
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time


def _resolve_runfiles(rel: str) -> str:
    rfd = os.environ.get("RUNFILES_DIR") or os.environ.get("TEST_SRCDIR")
    if not rfd:
        return rel
    candidate = os.path.join(rfd, "_main", rel)
    if os.path.exists(candidate):
        return candidate
    candidate = os.path.join(rfd, rel)
    if os.path.exists(candidate):
        return candidate
    return rel


def _kubeconfig_from_env(name: str) -> str | None:
    """Resolve KUBECONFIG: prefer `<kubeconfig_env>` (set by rules_kind /
    consumer wiring), fall back to `KUBECONFIG`, finally None."""
    if name and os.environ.get(name):
        return os.environ[name]
    if os.environ.get("KUBECONFIG"):
        return os.environ["KUBECONFIG"]
    return None


def _resolve_kubectl() -> str | None:
    """Locate `kubectl`. Prefer `$KUBECTL` (set by rules_kind's per-cluster
    env file, which points at the bundled kubectl that shipped with the
    `kind_cluster` toolchain — same version as the cluster's API server,
    no PATH munging needed). Fall back to whatever's on PATH."""
    cand = os.environ.get("KUBECTL")
    if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
        return cand
    return shutil.which("kubectl")


def _run(cmd: list[str], env: dict[str, str]) -> int:
    print("rules_certmanager: " + " ".join(cmd), file=sys.stderr, flush=True)
    return subprocess.run(cmd, env=env).returncode


def _install(args, env: dict[str, str]) -> int:
    manifest = _resolve_runfiles(args.manifest)
    if not os.path.isfile(manifest):
        print(f"rules_certmanager: manifest not in runfiles: {manifest}", file=sys.stderr)
        return 2

    kubectl = _resolve_kubectl()
    if not kubectl:
        print(
            "rules_certmanager: kubectl not found. Set $KUBECTL (e.g. via "
            "rules_kind's env file) or put kubectl on $PATH.",
            file=sys.stderr,
        )
        return 127

    kubeconfig = _kubeconfig_from_env(args.kubeconfig_env)
    if not kubeconfig:
        print(
            f"rules_certmanager: no kubeconfig — set ${args.kubeconfig_env} or $KUBECONFIG.",
            file=sys.stderr,
        )
        return 2
    env["KUBECONFIG"] = kubeconfig

    # cert-manager.yaml is self-contained (it includes its own Namespace),
    # so we don't need namespace pre-creation like rules_capsule. The CRDs
    # appear at the top of the file; CRs of those CRDs (Issuer, Certificate
    # etc.) are not embedded — those are consumer-authored. So a single-pass
    # apply normally succeeds. Retry once defensively for transient failures
    # (slow API server warm-up, etc.).
    apply_cmd = [kubectl, "--kubeconfig", kubeconfig, "apply", "-f", manifest,
                 "--server-side=true", "--validate=false"]
    rc = 1
    for attempt in (1, 2):
        rc = _run(apply_cmd, env)
        if rc == 0:
            break
        if attempt == 1:
            print(
                f"rules_certmanager: apply attempt {attempt} failed; "
                f"retrying once after 5s.",
                file=sys.stderr,
            )
            time.sleep(5)
    if rc != 0:
        return rc

    # Stay alive so itest treats us as a long-running service. The actual
    # readiness gate is `cert_manager_health_check`, which itest polls.
    print("rules_certmanager: install applied; sleeping until SIGTERM",
          file=sys.stderr, flush=True)
    while True:
        time.sleep(3600)


def _health_check(args, env: dict[str, str]) -> int:
    kubectl = _resolve_kubectl()
    if not kubectl:
        print(
            "rules_certmanager: kubectl not found. Set $KUBECTL or put "
            "kubectl on $PATH.",
            file=sys.stderr,
        )
        return 127

    kubeconfig = _kubeconfig_from_env(args.kubeconfig_env)
    if not kubeconfig:
        print(
            f"rules_certmanager: no kubeconfig — set ${args.kubeconfig_env} or $KUBECONFIG.",
            file=sys.stderr,
        )
        return 2
    env["KUBECONFIG"] = kubeconfig

    ns = args.namespace
    # cert-manager has three Deployments — the CRD registration check is
    # also a meaningful signal that the manifest finished applying.
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "get", "crd",
         "certificates.cert-manager.io", "-o", "name"],
        env,
    )
    if rc != 0:
        return rc
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "-n", ns, "wait", "deploy",
         "--all", "--for=condition=Available", "--timeout=0s"],
        env,
    )
    return rc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["install", "health_check"], required=True)
    ap.add_argument("--manifest", default="", help="Pinned cert-manager.yaml (install mode).")
    ap.add_argument("--namespace", default="cert-manager")
    ap.add_argument("--kubeconfig-env", default="KUBECONFIG",
                    help="Env var holding the path to the kubeconfig file. " +
                         "Defaults to KUBECONFIG; rules_kind compositions " +
                         "typically set KUBECONFIG_<cluster> via itest.")
    args = ap.parse_args(argv[1:])

    env = os.environ.copy()

    if args.mode == "install":
        proc_func = lambda: _install(args, env)
    else:
        proc_func = lambda: _health_check(args, env)

    def handle(_signum, _frame):
        sys.exit(143)

    signal.signal(signal.SIGTERM, handle)
    signal.signal(signal.SIGINT, handle)

    return proc_func() or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
