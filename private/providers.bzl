"""Providers exported by rules_certmanager."""

CertManagerInfo = provider(
    doc = "The resolved cert-manager install: pinned version + path to the " +
          "downloaded, sha256-verified manifest YAML the consumer applies " +
          "into a cluster.",
    fields = {
        "version": "cert-manager version string, e.g. '1.18.3'.",
        "manifest": "File: the downloaded cert-manager.yaml.",
        "namespace": "string: namespace cert-manager installs into " +
                     "(always 'cert-manager' — defined in the manifest).",
    },
)
