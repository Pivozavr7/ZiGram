#!/usr/bin/env bash
# Fetch the pinned SDL3 and Dear ImGui sources for ZiGram.
#
# Reads the package version and SHA-256 from sdl.lock / imgui.lock,
# downloads the release tarballs, verifies the hashes and extracts them
# into vendor/. The extracted sources are never committed.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dest_dir="${repo_root}/vendor"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

read_lock_value() {
    local key="$1" file="$2" line

    if [[ ! -f "${file}" ]]; then
        die "lock file not found: ${file}"
    fi

    line="$(grep -m1 "^${key}=" "${file}" || true)"
    if [[ -z "${line}" ]]; then
        die "missing '${key}' in ${file}"
    fi
    printf '%s' "${line#*=}"
}

fetch_one() {
    local name="$1" url="$2" dest_dir="$3"
    local lock_file="${repo_root}/${name}.lock"

    local version expected_sha256 tarball actual_sha256
    version="$(read_lock_value version "${lock_file}")"
    expected_sha256="$(read_lock_value sha256 "${lock_file}")"
    tarball="${dest_dir}/downloads/${name}-${version}.tar.gz"

    if [[ -d "${dest_dir}/${name}-${version}" ]]; then
        printf 'Already extracted %s\n' "${name}-${version}"
        return
    fi

    mkdir -p "$(dirname -- "${tarball}")"
    if [[ ! -f "${tarball}" ]]; then
        printf 'Fetching %s@%s\n' "${name}" "${version}"
        curl -fL --max-time 300 -o "${tarball}" "${url}"
    fi

    actual_sha256="$(sha256sum "${tarball}" | cut -d' ' -f1)"
    if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
        die "sha256 mismatch for ${name}: expected ${expected_sha256}, got ${actual_sha256}"
    fi

    tar -xzf "${tarball}" -C "${dest_dir}"
    printf 'Extracted %s@%s (sha256 %s)\n' "${name}" "${version}" "${actual_sha256}"
}

for tool in curl tar sha256sum; do
    command -v "${tool}" >/dev/null 2>&1 || die "required tool not found: ${tool}"
done

fetch_one \
    "sdl" \
    "https://github.com/libsdl-org/SDL/releases/download/release-$(read_lock_value version "${repo_root}/sdl.lock")/SDL3-$(read_lock_value version "${repo_root}/sdl.lock").tar.gz" \
    "${dest_dir}"

fetch_one \
    "imgui" \
    "https://github.com/ocornut/imgui/archive/refs/tags/v$(read_lock_value version "${repo_root}/imgui.lock").tar.gz" \
    "${dest_dir}"
