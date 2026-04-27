"""Bzlmod extension. Same shape as rules_capsule: one `version` tag class."""

load("//private:repositories.bzl", "cert_manager_version_repository")

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "cert_manager"),
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        for tag in mod.tags.version:
            cert_manager_version_repository(
                name = tag.name,
                version = tag.version,
            )

cert_manager = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
