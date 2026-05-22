#!/usr/bin/env bash
# SPDX-FileCopyrightText: NONE
# SPDX-License-Identifier: CC0-1.0
# Prints a Markdown section with recent commits and release-tag markers.
#
# Environment:
#   RELEASE_NOTES_REPO_ROOT  Git checkout (default: cwd)
#   RELEASE_NOTES_HEAD_SHA   Commit this build was made from (default: HEAD)
#   RELEASE_NOTES_CURRENT_TAG  Tag being published, if any (e.g. nightly, v1.3.2-rc1)
#   RELEASE_NOTES_COMMIT_LIMIT Number of commits (default: 30)
#
# Usage: render-release-commit-history.sh <repo_url>

set -euo pipefail

REPO_URL="${1-}"
if [[ -z "${REPO_URL}" ]]; then
  echo "Usage: $0 <repo_url>" >&2
  exit 1
fi

REPO_ROOT="${RELEASE_NOTES_REPO_ROOT:-.}"
HEAD_SHA="${RELEASE_NOTES_HEAD_SHA:-}"
CURRENT_TAG="${RELEASE_NOTES_CURRENT_TAG:-}"
COMMIT_LIMIT="${RELEASE_NOTES_COMMIT_LIMIT:-30}"

TMPDIR="${TMPDIR:-/tmp}"
_tag_list_file="$(mktemp "${TMPDIR}/release-notes-tags.XXXXXX")"
_recent_commits_file="$(mktemp "${TMPDIR}/release-notes-commits.XXXXXX")"
_commit_log_file="$(mktemp "${TMPDIR}/release-notes-log.XXXXXX")"
_release_hits_file="$(mktemp "${TMPDIR}/release-notes-hits.XXXXXX")"
cleanup() {
  rm -f "${_tag_list_file:?}" "${_recent_commits_file:?}" "${_commit_log_file:?}" "${_release_hits_file:?}"
}
trap cleanup EXIT

if [[ -z "${HEAD_SHA}" ]]; then
  HEAD_SHA="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
fi

HEAD_SHORT="$(git -C "${REPO_ROOT}" rev-parse --short=8 "${HEAD_SHA}")"

git -C "${REPO_ROOT}" fetch --tags --force origin 2>/dev/null || git -C "${REPO_ROOT}" fetch --tags --force 2>/dev/null || true

_format_release_tag_label() {
  local tag="${1:?}"
  local md_tick='`'
  case "${tag}" in
    nightly) printf '%s' "${md_tick}nightly${md_tick}" ;;
    *-rc* | *-RC*) printf '%s' "${md_tick}${tag}${md_tick} (RC)" ;;
    *) printf '%s' "${md_tick}${tag}${md_tick}" ;;
  esac
}

declare -A COMMIT_TAGS=()
declare -A COMMIT_TAG_SORT=()

git -C "${REPO_ROOT}" tag -l 'v*' 'nightly' > "${_tag_list_file}.raw" || true
sort -u "${_tag_list_file}.raw" > "${_tag_list_file}" || true
rm -f "${_tag_list_file}.raw"

while IFS= read -r tag; do
  [[ -n "${tag}" ]] || continue
  commit="$(git -C "${REPO_ROOT}" rev-parse "${tag}^{commit}" 2>/dev/null || true)"
  [[ -n "${commit}" ]] || continue
  tag_label="$(_format_release_tag_label "${tag}")"
  tag_date="$(git -C "${REPO_ROOT}" log -1 --format='%ct' "${tag}^{commit}" 2>/dev/null || printf '0')"
  COMMIT_TAG_SORT["${commit}:${tag}"]="${tag_date}"

  if [[ -n "${COMMIT_TAGS[${commit}]+x}" ]]; then
    COMMIT_TAGS["${commit}"]="${COMMIT_TAGS[${commit}]}, ${tag_label}"
  else
    COMMIT_TAGS["${commit}"]="${tag_label}"
  fi
done < "${_tag_list_file}"

printf '%s\n\n' '## Build info'
printf '%s\n' "- **Commit:** [\`${HEAD_SHORT}\`](${REPO_URL}/commit/${HEAD_SHA})"
if [[ -n "${CURRENT_TAG}" ]]; then
  printf '%s\n' "- **Publishing tag:** \`${CURRENT_TAG}\`"
fi
printf '\n'

# Summarize release tags that appear in the commit window
git -C "${REPO_ROOT}" log -n "${COMMIT_LIMIT}" --format='%H' "${HEAD_SHA}" > "${_recent_commits_file}"
mapfile -t _recent_commits < "${_recent_commits_file}"
declare -A _recent_set=()
for _c in "${_recent_commits[@]}"; do
  _recent_set["${_c}"]=1
done

_release_hits=()
for _key in "${!COMMIT_TAG_SORT[@]}"; do
  _commit="${_key%%:*}"
  if [[ -n "${_recent_set[${_commit}]+x}" ]]; then
    _tag="${_key#*:}"
    _release_hits+=("${COMMIT_TAG_SORT[${_key}]}|${_commit}|${_tag}")
  fi
done

if ((${#_release_hits[@]} > 0)); then
  printf '%s\n' "${_release_hits[@]}" | sort -t'|' -k1,1nr > "${_release_hits_file}"
  mapfile -t _release_hits_sorted < "${_release_hits_file}"
  printf '%s\n\n' '### Release tags in this commit window'
  _shown=0
  _last_commit=''
  for _entry in "${_release_hits_sorted[@]}"; do
    _rest="${_entry#*|}"
    _commit="${_rest%%|*}"
    if [[ "${_commit}" == "${_last_commit}" ]]; then
      continue
    fi
    _last_commit="${_commit}"
    _short="$(git -C "${REPO_ROOT}" rev-parse --short=8 "${_commit}")"
    _date="$(git -C "${REPO_ROOT}" log -1 --format='%cs' "${_commit}" 2>/dev/null || printf '?')"
    printf '%s\n' "- ${_date}: ${COMMIT_TAGS[${_commit}]} at [\`${_short}\`](${REPO_URL}/commit/${_commit})"
    _shown=$((_shown + 1))
    if ((_shown >= 10)); then
      break
    fi
  done
  printf '\n'
fi

printf '%s\n\n' "## Recent commits (last ${COMMIT_LIMIT})"
printf '%s\n\n' 'Newest first. Tags mark commits that were published as a nightly, RC, or version release.'

git -C "${REPO_ROOT}" log -n "${COMMIT_LIMIT}" --format='%H|%h|%s|%ci' "${HEAD_SHA}" > "${_commit_log_file}"
while IFS='|' read -r hash short subject date; do
  [[ -n "${hash}" ]] || continue
  subject="${subject//\`/}"
  subject="${subject//$'\r'/}"
  markers=''
  if [[ "${hash}" == "${HEAD_SHA}" ]]; then
    markers=' **(this build)**'
  fi
  if [[ -n "${COMMIT_TAGS[${hash}]+x}" ]]; then
    markers="${markers} — tagged: ${COMMIT_TAGS[${hash}]}"
  fi
  printf '%s\n' "- [\`${short}\`](${REPO_URL}/commit/${hash}) (${date%% *}) ${subject}${markers}"
done < "${_commit_log_file}"
