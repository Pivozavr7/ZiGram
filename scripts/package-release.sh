#!/usr/bin/env bash
# Package a release tarball: the GUI and CLI binaries plus libtdjson.so.
#
# Usage: scripts/package-release.sh <version>   (e.g. 0.0.1-alpha)
#
# The tarball keeps the layout `zigram-cli` looks for: `vendor/tdlib/`
# next to the executables, so the library is found without configuration.
# A release still needs the user's own config.zon with `api_id`/`api_hash`
# in ~/.config/zigram/, see README.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

version="${1:-}"
if [[ -z "${version}" ]]; then
    die "usage: scripts/package-release.sh <version>"
fi

stage_dir="${repo_root}/.zig-cache/dist/zigram-${version}"
tarball_dir="${repo_root}/.zig-cache/dist"
tarball="${tarball_dir}/zigram-${version}-linux-x86_64.tar.gz"

for file in \
    "${repo_root}/zig-out/bin/zigram-gui" \
    "${repo_root}/zig-out/bin/zigram-cli" \
    "${repo_root}/vendor/tdlib/libtdjson.so" \
    "${repo_root}/vendor/tdlib/LICENSE.tdlib" \
    "${repo_root}/README.md" \
    "${repo_root}/LICENSE"
do
    [[ -f "${file}" ]] || die "missing file: ${file}; run the fetch and build scripts first"
done

rm -rf "${stage_dir}"
mkdir -p "${stage_dir}/vendor/tdlib"

install -m 0755 "${repo_root}/zig-out/bin/zigram-gui" "${stage_dir}/zigram-gui"
install -m 0755 "${repo_root}/zig-out/bin/zigram-cli" "${stage_dir}/zigram-cli"
install -m 0644 "${repo_root}/vendor/tdlib/libtdjson.so" "${stage_dir}/vendor/tdlib/libtdjson.so"
install -m 0644 "${repo_root}/vendor/tdlib/LICENSE.tdlib" "${stage_dir}/vendor/tdlib/LICENSE.tdlib"
install -m 0644 "${repo_root}/README.md" "${stage_dir}/README.md"
install -m 0644 "${repo_root}/LICENSE" "${stage_dir}/LICENSE"

mkdir -p "${tarball_dir}"
rm -f "${tarball}"
tar -czf "${tarball}" -C "${tarball_dir}" "zigram-${version}"

printf 'Packaged %s\n' "${tarball}"
sha256sum "${tarball}"
