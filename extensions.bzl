"""Bzlmod extension. Same shape as rules_capsule: one `version` tag class."""

load("//private:repositories.bzl", "cert_manager_version_repository")

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "cert_manager"),
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    # Only honor `version` tags from the root module. Without this guard,
    # both rules_certmanager (when consumed as a dep) and the consumer
    # would each emit a `@cert_manager` repo with the same `name`, and
    # Bazel collides them: "A repo named cert_manager is already generated
    # by this module extension". The library's own MODULE.bazel still
    # needs `cert_manager.version()` so its in-tree smoke test can build,
    # but that only fires when rules_certmanager itself is the root.
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            cert_manager_version_repository(
                name = tag.name,
                version = tag.version,
            )

cert_manager = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
