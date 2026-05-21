#!/usr/bin/env bash
# SPDX-FileCopyrightText: NONE
# SPDX-License-Identifier: CC0-1.0
# Updates zip-content/module.prop version from the latest microG GmsCore on F-Droid
# and an incremental sub-version from the repository commit count.
#
# Usage: generate-module-version.sh <repo_root> [channel]
#   channel: alpha | stable | keep  (default: keep — preserve -alpha if already set)

set -euo pipefail

REPO_ROOT="${1-}"
CHANNEL="${2:-keep}"
if [[ -z "${REPO_ROOT}" ]]; then
  echo "Usage: $0 <repo_root> [alpha|stable|keep]" >&2
  exit 1
fi

REPO_ROOT="$(cd "${REPO_ROOT}" && pwd)"

MODULE_PROP="${REPO_ROOT}/zip-content/module.prop"
if [[ ! -f "${MODULE_PROP}" ]]; then
  echo "Missing ${MODULE_PROP}" >&2
  exit 1
fi

case "${CHANNEL}" in
  alpha | stable | keep) ;;
  *)
    echo "Invalid channel '${CHANNEL}' (use: alpha, stable, keep)" >&2
    exit 1
    ;;
esac

command -v wget >/dev/null 2>&1 || {
  echo 'wget is required to fetch the microG F-Droid index' >&2
  exit 1
}
command -v unzip >/dev/null 2>&1 || {
  echo 'unzip is required to read the microG F-Droid index' >&2
  exit 1
}
command -v xmlstarlet >/dev/null 2>&1 || {
  echo 'xmlstarlet is required to parse the microG F-Droid index' >&2
  exit 1
}

MICROG_REPO='https://microg.org/fdroid/repo'
CACHE_DIR="${REPO_ROOT}/cache/build/module-version"
mkdir -p "${CACHE_DIR}"
cd "${CACHE_DIR}"

if ! wget -q --connect-timeout=15 --tries=2 "${MICROG_REPO}/index.jar" -O microg_index.jar; then
  echo 'Failed to download microG F-Droid index' >&2
  exit 1
fi
unzip -p microg_index.jar index.xml > microg_index.xml

GMSCORE_VERSION="$(xmlstarlet sel -t -m '//application[id="com.google.android.gms"]/package[1]' -v 'version' -n microg_index.xml)"
if [[ -z "${GMSCORE_VERSION}" ]]; then
  echo 'Could not read GmsCore version from microG F-Droid index' >&2
  exit 1
fi

if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: ${REPO_ROOT}" >&2
  exit 1
fi

COMMIT_COUNT="$(git -C "${REPO_ROOT}" rev-list --count HEAD)"
if [[ -z "${COMMIT_COUNT}" ]] || [[ "${COMMIT_COUNT}" -lt 1 ]]; then
  echo 'Could not determine repository commit count (is the checkout shallow?)' >&2
  exit 1
fi

VERSION_BASE="v${GMSCORE_VERSION}.${COMMIT_COUNT}"
case "${CHANNEL}" in
  alpha) VERSION="${VERSION_BASE}-alpha" ;;
  stable) VERSION="${VERSION_BASE}" ;;
  keep)
    CURRENT="$(grep -m 1 -e '^version=' -- "${MODULE_PROP}" | cut -d '=' -f '2-' -s || true)"
    case "${CURRENT}" in
      *'-alpha') VERSION="${VERSION_BASE}-alpha" ;;
      *) VERSION="${VERSION_BASE}" ;;
    esac
    ;;
  *)
    echo "Invalid channel '${CHANNEL}' (use: alpha, stable, keep)" >&2
    exit 1
    ;;
esac

# versionCode must monotonically increase for Magisk/module managers
VERSION_CODE="${COMMIT_COUNT}"

tmp_prop="$(mktemp)"
trap 'rm -f "${tmp_prop}"' EXIT
while IFS= read -r line || [[ -n "${line}" ]]; do
  case "${line}" in
    version=*) printf 'version=%s\n' "${VERSION}" ;;
    versionCode=*) printf 'versionCode=%s\n' "${VERSION_CODE}" ;;
    *) printf '%s\n' "${line}" ;;
  esac
done < "${MODULE_PROP}" > "${tmp_prop}"
mv "${tmp_prop}" "${MODULE_PROP}"
trap - EXIT

printf 'Generated module version: %s (GmsCore %s, commit count %s, versionCode %s)\n' \
  "${VERSION}" "${GMSCORE_VERSION}" "${COMMIT_COUNT}" "${VERSION_CODE}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'GENERATED_MODULE_VERSION=%s\n' "${VERSION}"
    printf 'GENERATED_GMSCORE_VERSION=%s\n' "${GMSCORE_VERSION}"
    printf 'GENERATED_MODULE_VERSION_CODE=%s\n' "${VERSION_CODE}"
  } >> "${GITHUB_OUTPUT}"
fi
