"""cert_manager_health_check — one-shot readiness probe for cert-manager.

Verifies (in order):
  1. The `certificates.cert-manager.io` CRD is registered.
  2. All Deployments in the configured namespace are `Available=True`
     (which for cert-manager means controller / cainjector / webhook).

Exits 0 when both pass, non-zero otherwise. itest's service `health_check`
mechanism retries until success or timeout.
"""

def _impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{NAMESPACE}": ctx.attr.namespace,
            "{KUBECONFIG_ENV}": ctx.attr.kubeconfig_env,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [ctx.executable._launcher])
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

cert_manager_health_check = rule(
    implementation = _impl,
    attrs = {
        "namespace": attr.string(default = "cert-manager"),
        "kubeconfig_env": attr.string(default = "KUBECONFIG"),
        "_launcher": attr.label(
            default = "//private:launcher",
            executable = True,
            cfg = "exec",
        ),
        "_tmpl": attr.label(
            default = "//private:health_check.sh.tmpl",
            allow_single_file = True,
        ),
    },
    executable = True,
)
