#!/usr/bin/env bash
# SPDX-FileCopyrightText: NONE
# SPDX-License-Identifier: CC0-1.0
# Write GitHub release notes listing every built zip and its SHA-256.

set -euo pipefail

RELEASE_TYPE="${1:?Missing release type (nightly or release)}"
OUT_FILE="${2:?Missing output path}"
ZIP_FOLDER="${3:?Missing zip folder}"
ZIP_VERSION="${4:-}"
ZIP_ATTESTATION_URL="${5:-}"
REPO_URL="${6:-}"

{
  if test "${RELEASE_TYPE:?}" = 'nightly'; then
    printf '%s' "**If you'd like to support my work, you can find donation details on "
    printf '%s\n' "[this page](${REPO_URL:?}/blob/main/docs/DONATE.rst)."
    printf '%s\n' 'Contributions are greatly appreciated but always optional.**'
    printf '\n'
    printf '%s\n\n' "Latest automatically built ZIPs ($(date -u -- '+%Y/%m/%d' || :))."
  elif test "${RELEASE_TYPE:?}" = 'rc'; then
    printf '%s' "**If you'd like to support my work, you can find donation details on "
    printf '%s\n' "[this page](${REPO_URL:?}/blob/main/docs/DONATE.rst)."
    printf '%s\n' 'Contributions are greatly appreciated but always optional.**'
    printf '\n'
    test -z "${ZIP_VERSION?}" || printf 'Module version in tree: **%s**\n\n' "${ZIP_VERSION:?}"
    printf '%s\n\n' '**Release candidate** — pre-release build; not a stable release.'
  else
    printf '%s' '**If you want to help me you can donate to me using the `Sponsor` button at the top of '
    printf '%s\n' "[this repository](${REPO_URL:?})."
    printf '%s\n' 'Donations are appreciated and will always remain optional.**'
    printf '\n'
    test -z "${ZIP_VERSION?}" || printf 'Version: **%s**\n\n' "${ZIP_VERSION:?}"
  fi

  printf '%s\n' '## Verification'
  printf '%s\n' 'Each flashable zip is built fresh for its target ABI (or universal fat APKs).'
  printf '\n'

  manifest_sorted=''
  if test -f "${ZIP_FOLDER:?}/arch-build-manifest.txt"; then
    manifest_sorted="$(mktemp)"
    sort -- "${ZIP_FOLDER:?}/arch-build-manifest.txt" > "${manifest_sorted:?}"
  fi

  if test -n "${manifest_sorted?}" && test -s "${manifest_sorted:?}"; then
    while IFS='|' read -r zip_name zip_sha256 _zip_md5; do
      test -n "${zip_name?}" || continue
      if test -n "${zip_sha256?}"; then
        printf '%s\n' "- \`${zip_name?}\`: \`${zip_sha256?}\`"
      else
        printf '%s\n' "- \`${zip_name?}\`"
      fi
    done < "${manifest_sorted:?}"
    rm -f "${manifest_sorted:?}"
  else
    for sha_file in "${ZIP_FOLDER:?}"/*.zip.sha256; do
      test -e "${sha_file:?}" || continue
      zip_name="$(basename -- "${sha_file:?}" .sha256)"
      zip_sha256="$(cut -d ' ' -f '1' -s 0< "${sha_file:?}")" || zip_sha256=''
      test -n "${zip_sha256?}" || continue
      printf '%s\n' "- \`${zip_name?}\`: \`${zip_sha256?}\`"
    done
  fi

  test -z "${ZIP_ATTESTATION_URL?}" || printf '\n%s\n' "Attestation: ${ZIP_ATTESTATION_URL:?}"

  if test "${RELEASE_TYPE:?}" = 'release'; then
    printf '\n'
    printf '%s\n\n' '## Changelog'
    printf '%s\n' '[**Changelog**](./CHANGELOG.rst).'
  fi
} > "${OUT_FILE:?}"
