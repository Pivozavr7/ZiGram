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

# A failed step's log needs a login to read; when the script runs in CI
# the diagnostics are copied to the job summary as well, which is public.
write_failure_summary() {
    local name="$1" version="$2" url="$3" expected="$4"
    local status="$5" size="$6" sha="$7" curl_log="$8"

    if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
        return
    fi
    {
        printf '### fetch-deps: %s@%s failed\n\n' "${name}" "${version}"
        printf 'URL: `%s`\n\n' "${url}"
        printf 'curl exit status: %s, downloaded bytes: %s\n\n' "${status}" "${size}"
        printf 'expected sha256: `%s`\n\n' "${expected}"
        printf 'actual   sha256: `%s`\n\n' "${sha}"
        if [[ -s "${curl_log}" ]]; then
            printf 'curl stderr:\n\n```text\n'
            cat "${curl_log}"
            printf '\n```\n\n'
        fi
        printf 'probe: %s\n\n' "$(curl -sS -o /dev/null \
            -w 'http %{http_code}, %{size_download} bytes, %{time_total}s' \
            "${url}" 2>&1 || true)"
        printf 'curl: %s\n' "$(curl --version | head -1)"
    } >> "${GITHUB_STEP_SUMMARY}" 2>/dev/null || true
}

fetch_one() {
    local name="$1" url="$2" dest_dir="$3"
    local lock_file="${repo_root}/${name}.lock"

    local version expected_sha256 tarball actual_sha256 attempt
    version="$(read_lock_value version "${lock_file}")"
    expected_sha256="$(read_lock_value sha256 "${lock_file}")"
    tarball="${dest_dir}/downloads/${name}-${version}.tar.gz"

    if [[ -d "${dest_dir}/${name}-${version}" ]]; then
        printf 'Already extracted %s\n' "${name}-${version}"
        return
    fi

    # The release CDN resets connections and truncates downloads from
    # time to time, so both curl and the hash check retry; a mismatched
    # tarball is thrown away and fetched again.
    local curl_log="${dest_dir}/downloads/${name}-curl.log"
    local curl_status=0 downloaded_bytes=0 actual_sha256=unknown
    for attempt in 1 2 3; do
        mkdir -p "$(dirname -- "${tarball}")"
        rm -f "${tarball}"
        printf 'Fetching %s@%s (attempt %d)\n' "${name}" "${version}" "${attempt}"
        if curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
            --max-time 300 -o "${tarball}" "${url}" 2>"${curl_log}"; then
            curl_status=0
        else
            curl_status=$?
        fi
        if [[ -f "${tarball}" ]]; then
            downloaded_bytes="$(stat -c '%s' "${tarball}")"
            actual_sha256="$(sha256sum "${tarball}" | cut -d' ' -f1)"
        else
            downloaded_bytes=0
            actual_sha256=none
        fi

        if [[ "${curl_status}" -eq 0 && "${actual_sha256}" == "${expected_sha256}" ]]; then
            rm -f "${curl_log}"
            tar -xzf "${tarball}" -C "${dest_dir}"
            printf 'Extracted %s@%s (sha256 %s)\n' "${name}" "${version}" "${actual_sha256}"
            return
        fi
        printf 'attempt %d failed for %s: curl exit %d, %s bytes, sha %s\n' \
            "${attempt}" "${name}" "${curl_status}" "${downloaded_bytes}" "${actual_sha256}" >&2
        cat "${curl_log}" >&2 || true
    done

    write_failure_summary "${name}" "${version}" "${url}" "${expected_sha256}" \
        "${curl_status}" "${downloaded_bytes}" "${actual_sha256}" "${curl_log}"
    die "could not fetch a valid ${name}@${version} tarball from ${url}"
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
