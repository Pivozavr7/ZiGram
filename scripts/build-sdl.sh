#!/usr/bin/env bash
# Build the static libSDL3.a used by the ZiGram GUI.
#
# Expects the SDL3 sources to be present under vendor/ (see
# scripts/fetch-deps.sh). SDL's sources select platform backends with
# generated config headers, so cmake is used for this one third-party
# library; the rest of ZiGram builds with Zig alone.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for tool in cmake gcc make; do
    command -v "${tool}" >/dev/null 2>&1 || die "required tool not found: ${tool}"
done

version="$(grep -m1 '^version=' "${repo_root}/sdl.lock" | cut -d= -f2)"
source_dir="${repo_root}/vendor/SDL3-${version}"
build_dir="${repo_root}/.zig-cache/sdl-build"
out_dir="${repo_root}/vendor/sdl"

if [[ ! -d "${source_dir}" ]]; then
    die "SDL3 sources not found: ${source_dir}; run scripts/fetch-deps.sh"
fi

if [[ -f "${out_dir}/libSDL3.a" ]]; then
    printf 'Already built %s/libSDL3.a\n' "${out_dir}"
    exit 0
fi

cmake -S "${source_dir}" -B "${build_dir}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=OFF \
    -DSDL_STATIC=ON \
    -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF

cmake --build "${build_dir}" --parallel "$(nproc)"

mkdir -p "${out_dir}"
install -m 0644 "${build_dir}/libSDL3.a" "${out_dir}/libSDL3.a"
printf 'Built %s/libSDL3.a\n' "${out_dir}"
