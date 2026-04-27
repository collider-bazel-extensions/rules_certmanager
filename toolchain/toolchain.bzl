"""cert_manager_toolchain — exposes the pinned, sha256-verified cert-manager
manifest as a `ToolchainInfo` so consumer rules can resolve it without
depending on the manifest's specific path.
"""

load("//private:providers.bzl", "CertManagerInfo")

CERTMANAGER_TOOLCHAIN_TYPE = Label("//toolchain:cert_manager")

def _toolchain_impl(ctx):
    info = CertManagerInfo(
        version = ctx.attr.version,
        manifest = ctx.file.manifest,
        namespace = ctx.attr.namespace,
    )
    return [
        platform_common.ToolchainInfo(cert_manager = info),
        DefaultInfo(files = depset([ctx.file.manifest])),
    ]

cert_manager_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "manifest": attr.label(allow_single_file = True, mandatory = True),
        "namespace": attr.string(
            default = "cert-manager",
            doc = "Namespace cert-manager's manifest installs into. " +
                  "Always 'cert-manager' — the manifest hard-codes it.",
        ),
    },
)
