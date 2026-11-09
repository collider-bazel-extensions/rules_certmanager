#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no cert_manager.version() in the root resolves, and an cert_manager_install builds
#      against rules_certmanager's pinned version
#   2. the same version set twice in the root resolves
#   3. an unsupported version fails, naming cert_manager.version
#   4. tests/ and tools/ are not shipped, and @rules_certmanager//... loads
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_certmanager"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
version="$(sed -n '/^cert_manager.version(/,/)/s/.*version = "\(.*\)".*/\1/p' "$src/MODULE.bazel")"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_certmanager")
local_path_override(module_name = "rules_certmanager", path = "$src")
$2
MOD
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_certmanager//:defs.bzl", "cert_manager_install")

cert_manager_install(
    name = "cert_manager",
    kubeconfig_env = "KUBECONFIG",
)
BUILD
    echo "$c"
}

# 1. No cert_manager.version(): resolves, and the install builds with the pinned manifest.
c="$(consumer untagged "")"
(cd "$c" && bazel build //:cert_manager)
(cd "$c" && bazel mod show_extension @rules_certmanager//:extensions.bzl%cert_manager) | tee "$work/untagged.out"
grep -q "$version" "$work/untagged.out" || { echo "FAIL: untagged consumer did not get cert-manager $version" >&2; exit 1; }
echo "PASS: untagged root resolves, cert-manager $version"

# 2. The same version twice in the root.
c="$(consumer twice "cert_manager = use_extension(\"@rules_certmanager//:extensions.bzl\", \"cert_manager\")
cert_manager.version(version = \"$version\")
cert_manager.version(version = \"$version\")")"
(cd "$c" && bazel build //:cert_manager)
echo "PASS: repeated identical cert_manager.version resolves"

# 3. An unsupported version fails with a message naming cert_manager.version.
c="$(consumer unsupported 'cert_manager = use_extension("@rules_certmanager//:extensions.bzl", "cert_manager")
cert_manager.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'cert_manager.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_certmanager//... >/dev/null)
echo "PASS: @rules_certmanager//... loads"
