#!/usr/bin/env bash
# SPDX-FileCopyrightText: NONE
# SPDX-License-Identifier: CC0-1.0
# Build flashable zips for every supported --arch value.

set -euo pipefail

BUILD_TYPE="${1:?Missing build type (full or oss)}"
REPO_ROOT="${2:-${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
ARCH_LIST="${ARCH_LIST:-universal,x86_64,x86,arm64-v8a,armeabi-v7a}"

cd "${REPO_ROOT:?}"

_resolve_version_channel() {
  if test -n "${MODULE_VERSION_CHANNEL:-}"; then
    printf '%s' "${MODULE_VERSION_CHANNEL:?}"
    return 0
  fi
  _tag="${GITHUB_REF_NAME:-}"
  case "${_tag:?}" in
    nightly) printf 'alpha' ;;
    v*-rc*) printf 'alpha' ;;
    v*) printf 'stable' ;;
    *) printf 'keep' ;;
  esac
}

if test -x "${REPO_ROOT:?}/tools/generate-module-version.sh"; then
  _version_channel="$(_resolve_version_channel)"
  "${REPO_ROOT:?}/tools/generate-module-version.sh" "${REPO_ROOT:?}" "${_version_channel:?}"
  export SKIP_MODULE_VERSION_GEN=1
  unset _version_channel
fi
unset -f _resolve_version_channel 2> /dev/null || :

if test -f "${REPO_ROOT:?}/zip-content/module.prop"; then
  MODULE_VER="$(grep -m 1 -e '^version=' -- "${REPO_ROOT:?}/zip-content/module.prop" | cut -d '=' -f '2-' -s)" || exit 1
else
  MODULE_VER='unknown'
fi

case "${MODULE_VER:?}" in
  *'-alpha') MODULE_IS_ALPHA='true' ;;
  *) MODULE_IS_ALPHA='false' ;;
esac

printf 'Building %s edition for arches: %s\n' "${BUILD_TYPE:?}" "${ARCH_LIST:?}"

_arch_array=''
IFS=',' read -r -a _arch_array <<< "${ARCH_LIST?}"
for TARGET_ARCH in "${_arch_array[@]}"; do
  test -n "${TARGET_ARCH:?}" || continue
  printf '\n=== Building --arch %s ===\n' "${TARGET_ARCH:?}"
  BUILD_TYPE="${BUILD_TYPE:?}" "${REPO_ROOT:?}/build.sh" --no-default-build-type --no-pause --arch "${TARGET_ARCH:?}"
done
unset _arch_array TARGET_ARCH

OUT_DIR="${REPO_ROOT:?}/output"
MANIFEST="${OUT_DIR:?}/arch-build-manifest.txt"
: > "${MANIFEST:?}"

zip_count=0
for zip_file in "${OUT_DIR:?}"/*-signed.zip; do
  test -e "${zip_file:?}" || continue
  zip_count=$((zip_count + 1))
  zip_base="$(basename -- "${zip_file:?}")"
  sha_file="${zip_file:?}.sha256"
  md5_file="${zip_file:?}.md5"
  zip_sha256=''
  zip_md5=''
  if test -f "${sha_file:?}"; then
    zip_sha256="$(cut -d ' ' -f '1' -s 0< "${sha_file:?}")" || zip_sha256=''
  fi
  if test -f "${md5_file:?}"; then
    zip_md5="$(cut -d ' ' -f '1' -s 0< "${md5_file:?}")" || zip_md5=''
  fi
  printf '%s|%s|%s\n' "${zip_base:?}" "${zip_sha256:?}" "${zip_md5:?}" >> "${MANIFEST:?}"
  printf 'Built: %s\n' "${zip_base:?}"
  test -n "${zip_sha256?}" && printf '  SHA-256: %s\n' "${zip_sha256:?}"
done

test "${zip_count:?}" -gt 0 || {
  printf '%s\n' '::error::No signed zip files were produced' >&2
  exit 1
}

SHORT_COMMIT_ID="$(git -C "${REPO_ROOT:?}" rev-parse --short=8 HEAD 2> /dev/null || printf '')"
BRANCH_NAME="$(git -C "${REPO_ROOT:?}" branch --show-current 2> /dev/null || printf '')"

if test -n "${GITHUB_OUTPUT:-}"; then
  {
    printf 'ZIP_FOLDER=%s\n' "${OUT_DIR:?}"
    printf 'ZIP_VERSION=%s\n' "${MODULE_VER:?}"
    printf 'ZIP_SHORT_COMMIT_ID=%s\n' "${SHORT_COMMIT_ID:?}"
    printf 'ZIP_BUILD_TYPE=%s\n' "${BUILD_TYPE:?}"
    printf 'ZIP_BUILD_TYPE_SUPPORTED=%s\n' 'true'
    printf 'ZIP_BRANCH_NAME=%s\n' "${BRANCH_NAME?}"
    printf 'ZIP_IS_ALPHA=%s\n' "${MODULE_IS_ALPHA?}"
    printf 'ZIP_ARCH_COUNT=%s\n' "${zip_count:?}"
    printf 'ZIP_MANIFEST=%s\n' "${MANIFEST:?}"
  } >> "${GITHUB_OUTPUT:?}"
fi

printf '\nDone. %s zip(s) in %s\n' "${zip_count:?}" "${OUT_DIR:?}"
