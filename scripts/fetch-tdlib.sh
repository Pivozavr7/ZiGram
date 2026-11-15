#!/usr/bin/env bash
# Fetch the pinned TDLib JSON library for ZiGram.
#
# Reads the npm package version and SHA-256 from tdlib.lock, downloads the
# package with `npm pack`, verifies the hash and installs the library into
# vendor/tdlib/. The binary itself is never committed.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="${repo_root}/tdlib.lock"
dest_dir="${repo_root}/vendor/tdlib"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

read_lock_value() {
    local key="$1"
    local line

    if [[ ! -f "${lock_file}" ]]; then
        die "lock file not found: ${lock_file}"
    fi

    line="$(grep -m1 "^${key}=" "${lock_file}" || true)"
    if [[ -z "${line}" ]]; then
        die "missing '${key}' in ${lock_file}"
    fi
    printf '%s' "${line#*=}"
}

for tool in npm tar sha256sum install find; do
    command -v "${tool}" >/dev/null 2>&1 || die "required tool not found: ${tool}"
done

package="$(read_lock_value package)"
version="$(read_lock_value version)"
expected_sha256="$(read_lock_value sha256)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

printf 'Fetching %s@%s\n' "${package}" "${version}"
npm pack "${package}@${version}" --pack-destination "${tmp_dir}" >/dev/null

tarball="$(find "${tmp_dir}" -maxdepth 1 -name '*.tgz' -type f -print -quit)"
if [[ -z "${tarball}" ]]; then
    die "npm pack did not produce a tarball"
fi

tar -xzf "${tarball}" -C "${tmp_dir}"

library="$(find "${tmp_dir}/package" -maxdepth 3 -name 'libtdjson.so' -type f -print -quit)"
if [[ -z "${library}" ]]; then
    die "libtdjson.so not found in ${package}@${version}"
fi

actual_sha256="$(sha256sum "${library}" | cut -d' ' -f1)"
if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    die "sha256 mismatch: expected ${expected_sha256}, got ${actual_sha256}"
fi

mkdir -p "${dest_dir}"
install -m 0644 "${library}" "${dest_dir}/libtdjson.so"

if [[ -f "${tmp_dir}/package/LICENSE" ]]; then
    install -m 0644 "${tmp_dir}/package/LICENSE" "${dest_dir}/LICENSE.tdlib"
else
    install -m 0644 "${repo_root}/licenses/Boost-1.0.txt" "${dest_dir}/LICENSE.tdlib"
fi

printf 'Installed %s\n' "${dest_dir}/libtdjson.so"
printf 'sha256 %s\n' "${actual_sha256}"
