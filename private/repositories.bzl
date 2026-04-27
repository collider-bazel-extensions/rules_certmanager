"""Per-version hub repo: downloads cert-manager.yaml at the pinned URL +
sha256, exposes it as a `cert_manager_toolchain` per platform.
"""

load(":versions.bzl", "CERT_MANAGER_VERSIONS", "PLATFORMS")

_HUB_BUILD_TMPL = """\
load("@rules_certmanager//toolchain:toolchain.bzl", "cert_manager_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["cert-manager.yaml"])

{toolchains}
"""

_HUB_TC_TMPL = """\
cert_manager_toolchain(
    name = "{plat}_impl",
    version = "{version}",
    manifest = ":cert-manager.yaml",
)

toolchain(
    name = "{plat}",
    toolchain_type = "@rules_certmanager//toolchain:cert_manager",
    target_compatible_with = {compat},
    toolchain = ":{plat}_impl",
)
"""

def _hub_repo_impl(rctx):
    version = rctx.attr.version
    if version not in CERT_MANAGER_VERSIONS:
        fail("rules_certmanager: unknown version '{}'. Known: {}".format(
            version,
            sorted(CERT_MANAGER_VERSIONS.keys()),
        ))
    pinned = CERT_MANAGER_VERSIONS[version]
    rctx.download(
        url = pinned["url"],
        output = "cert-manager.yaml",
        sha256 = pinned["sha256"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))

    chunks = []
    for plat, compat in PLATFORMS.items():
        chunks.append(_HUB_TC_TMPL.format(
            plat = plat,
            version = version,
            compat = repr(compat),
        ))
    rctx.file("BUILD.bazel", _HUB_BUILD_TMPL.format(
        toolchains = "\n".join(chunks),
    ))

_cert_manager_hub_repository = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)

def cert_manager_version_repository(name, version):
    """Materialize the hub repo for one cert-manager version."""
    if version not in CERT_MANAGER_VERSIONS:
        fail("rules_certmanager: unknown version '{}'. Known: {}".format(
            version,
            sorted(CERT_MANAGER_VERSIONS.keys()),
        ))
    _cert_manager_hub_repository(name = name, version = version)
