#!/usr/bin/env bash
# SPDX-FileCopyrightText: NONE
# SPDX-License-Identifier: CC0-1.0
# Creates the RELEASE_TOKEN fine-grained personal access token used by the release workflows,
# checks that it can write to the repository, then stores it as an Actions secret or hands it
# over for pasting into the organization (or repository) secret settings.
#
# GitHub does not allow creating personal access tokens through its API, so the token itself is
# generated on a pre-filled github.com page; everything around it is automated.

# shellcheck disable=SC2310 # Functions are deliberately used in conditions; failures are handled there

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
OWNER=''
REPO=''
REMOTE=''
SECRET_NAME='RELEASE_TOKEN'
EXPIRES_IN='366'
SCOPE='org'
SET_SECRET='false'
OPEN_BROWSER='true'
API='https://api.github.com'

usage()
{
  cat << EOF
Usage: ${SCRIPT_NAME} [options]

Creates the fine-grained personal access token used by the release workflows and stores it as
the ${SECRET_NAME} Actions secret.

Options:
  --owner NAME          Organization or user that owns the repository (e.g. Bliss-Bass)
  --repo NAME           Repository name (e.g. microg-unofficial-installer)
  --remote NAME         Read owner and repository from this git remote instead
  --secret-name NAME    Secret name (default: ${SECRET_NAME})
  --expires DAYS        Token lifetime: 1-366 or "none" (default: ${EXPIRES_IN}; org policy may cap it)
  --scope org|repo      Store as an organization secret or a repository secret (default: ${SCOPE})
  --set-secret          Store the secret with the GitHub CLI (gh) instead of pasting it manually
  --no-browser          Print URLs instead of opening them
  -h, --help            Show this help

Example:
  ${SCRIPT_NAME} --owner Bliss-Bass --repo microg-unofficial-installer
EOF
}

die()
{
  printf 'ERROR: %s\n' "${1}" >&2
  exit 1
}

info()
{
  printf '%s\n' "${1}"
}

urlencode()
{
  local _str="${1}" _out='' _char _hex _i
  for ((_i = 0; _i < ${#_str}; _i++)); do
    _char="${_str:_i:1}"
    case "${_char}" in
      [a-zA-Z0-9.~_-]) _out+="${_char}" ;;
      ' ') _out+='+' ;;
      *)
        printf -v _hex '%%%02X' "'${_char}"
        _out+="${_hex}"
        ;;
    esac
  done
  printf '%s' "${_out}"
}

open_url()
{
  if [[ "${OPEN_BROWSER}" == 'true' ]]; then
    local _opener
    for _opener in xdg-open open wslview; do
      if command -v "${_opener}" > /dev/null 2>&1; then
        "${_opener}" "${1}" > /dev/null 2>&1 &
        return 0
      fi
    done
  fi
  info "Open this URL in your browser:"
  info "  ${1}"
}

copy_to_clipboard()
{
  if command -v wl-copy > /dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY-}" ]]; then
    printf '%s' "${1}" | wl-copy
  elif command -v xclip > /dev/null 2>&1 && [[ -n "${DISPLAY-}" ]]; then
    printf '%s' "${1}" | xclip -selection clipboard
  elif command -v xsel > /dev/null 2>&1 && [[ -n "${DISPLAY-}" ]]; then
    printf '%s' "${1}" | xsel --clipboard --input
  elif command -v pbcopy > /dev/null 2>&1; then
    printf '%s' "${1}" | pbcopy
  elif command -v clip.exe > /dev/null 2>&1; then
    printf '%s' "${1}" | clip.exe
  else
    return 1
  fi
}

# Owner and repository from a GitHub remote URL (https or ssh)
parse_remote()
{
  local _url _path
  _url="$(git remote get-url "${1}")" || die "Git remote '${1}' not found"
  case "${_url}" in
    *github.com[:/]*) ;;
    *) die "Remote '${1}' is not a GitHub URL: ${_url}" ;;
  esac
  _path="${_url#*github.com}"
  _path="${_path#[:/]}"
  _path="${_path%.git}"
  OWNER="${_path%%/*}"
  REPO="${_path#*/}"
}

while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    --owner) OWNER="${2-}" && shift ;;
    --repo) REPO="${2-}" && shift ;;
    --remote) REMOTE="${2-}" && shift ;;
    --secret-name) SECRET_NAME="${2-}" && shift ;;
    --expires) EXPIRES_IN="${2-}" && shift ;;
    --scope) SCOPE="${2-}" && shift ;;
    --set-secret) SET_SECRET='true' ;;
    --no-browser) OPEN_BROWSER='false' ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: ${1} (see --help)" ;;
  esac
  shift
done

if [[ -n "${REMOTE}" ]]; then
  parse_remote "${REMOTE}"
fi
if [[ -z "${OWNER}" ]] || [[ -z "${REPO}" ]]; then
  usage >&2
  printf '\n' >&2
  die 'Pass --owner and --repo, or --remote with a GitHub remote'
fi
case "${SCOPE}" in
  org | repo) ;;
  *) die "Invalid --scope '${SCOPE}' (use: org, repo)" ;;
esac
case "${EXPIRES_IN}" in
  none) ;;
  *[!0-9]* | '') die "Invalid --expires '${EXPIRES_IN}' (use: 1-366 or none)" ;;
  *) if [[ "${EXPIRES_IN}" -lt 1 ]] || [[ "${EXPIRES_IN}" -gt 366 ]]; then die "Invalid --expires '${EXPIRES_IN}' (use: 1-366 or none)"; fi ;;
esac
command -v curl > /dev/null 2>&1 || die 'curl is required'
if [[ "${SET_SECRET}" == 'true' ]]; then
  command -v gh > /dev/null 2>&1 || die '--set-secret needs the GitHub CLI (gh); omit it to paste the secret manually'
  gh auth status > /dev/null 2>&1 || die 'The GitHub CLI is not logged in (run: gh auth login)'
fi

TMP_DIR="$(mktemp -d)"
cleanup()
{
  rm -rf -- "${TMP_DIR:?}"
}
trap cleanup EXIT

# Step 1: pre-filled token page
TOKEN_NAME="${REPO} release"
TOKEN_NAME="${TOKEN_NAME:0:40}"
TOKEN_DESCRIPTION="Lets GitHub Actions in ${OWNER}/${REPO} create releases and move the nightly tag (${SECRET_NAME} secret)."
enc_name="$(urlencode "${TOKEN_NAME}")"
enc_description="$(urlencode "${TOKEN_DESCRIPTION}")"
enc_owner="$(urlencode "${OWNER}")"
# Workflows write is needed because GitHub refuses to point a tag at commits that change .github/workflows without it
TOKEN_URL="https://github.com/settings/personal-access-tokens/new?name=${enc_name}&description=${enc_description}&target_name=${enc_owner}&expires_in=${EXPIRES_IN}&contents=write&workflows=write"

info "== Step 1/3: create the token for ${OWNER}/${REPO}"
info ''
open_url "${TOKEN_URL}"
info ''
info 'The page is pre-filled. Before clicking "Generate token":'
info "  1. Resource owner is ${OWNER}."
info "  2. Repository access: choose \"Only select repositories\" and pick ${REPO}."
info '     (GitHub does not allow pre-selecting repositories.)'
info '  3. Permissions show "Contents: Read and write" and "Workflows: Read and write"'
info '     (Metadata: Read-only is added automatically).'
info 'Then generate the token and copy it.'
info ''

# Step 2: read and check the token
info "== Step 2/3: check the token"
TOKEN=''
read -r -s -p 'Paste the token (input is hidden): ' TOKEN
printf '\n'
[[ -n "${TOKEN}" ]] || die 'No token entered'
case "${TOKEN}" in
  github_pat_*) ;;
  ghp_*) info 'Note: this is a classic token; a fine-grained token limited to this repository is safer.' ;;
  *) info 'Note: this does not look like a GitHub token; checking anyway.' ;;
esac

CURL_CONFIG="${TMP_DIR}/curl.conf"
(
  umask 077
  printf 'header = "Authorization: Bearer %s"\n' "${TOKEN}" > "${CURL_CONFIG}"
)

# Usage: api_call METHOD PATH [JSON_BODY]; prints the HTTP status code, body goes to ${TMP_DIR}/body
api_call()
{
  local _args=(-sS -K "${CURL_CONFIG}" -o "${TMP_DIR}/body" -D "${TMP_DIR}/headers" -w '%{http_code}'
    -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' -X "${1}")
  if [[ -n "${3-}" ]]; then
    _args+=(-H 'Content-Type: application/json' --data "${3}")
  fi
  curl "${_args[@]}" "${API}${2}"
}

status="$(api_call GET "/repos/${OWNER}/${REPO}")" || die 'Could not reach the GitHub API'
case "${status}" in
  200) info "  Can read ${OWNER}/${REPO}." ;;
  401) die 'GitHub rejected the token (401). Copy it again and re-run.' ;;
  403 | 404) die "The token cannot see ${OWNER}/${REPO} (HTTP ${status}). Check that the repository is selected and, if the organization requires it, that an owner approved the token: https://github.com/organizations/${OWNER}/settings/personal-access-token-requests" ;;
  *) die "Unexpected HTTP ${status} while reading the repository" ;;
esac

expiration="$(grep -i -m 1 '^github-authentication-token-expiration:' "${TMP_DIR}/headers" | cut -d ':' -f '2-' | tr -d '\r' || true)"

# A tag ref pointing at a missing object is rejected with 422 only when the token may write contents (403 otherwise), so nothing is created
probe_ref='refs/tags/release-token-probe'
status="$(api_call POST "/repos/${OWNER}/${REPO}/git/refs" "{\"ref\":\"${probe_ref}\",\"sha\":\"0000000000000000000000000000000000000000\"}")" || die 'Could not reach the GitHub API'
case "${status}" in
  422) info '  Can write contents (create releases and tags).' ;;
  201)
    api_call DELETE "/repos/${OWNER}/${REPO}/git/${probe_ref}" > /dev/null || true
    info '  Can write contents (create releases and tags).'
    ;;
  403) die "The token cannot write to ${OWNER}/${REPO}. Set \"Contents\" to \"Read and write\", or wait for the organization owner to approve it: https://github.com/organizations/${OWNER}/settings/personal-access-token-requests" ;;
  *) die "Unexpected HTTP ${status} while checking write access" ;;
esac
if [[ -n "${expiration}" ]]; then
  info "  Expires:${expiration}. Re-run this script before then."
else
  info '  No expiration reported.'
fi
info ''

# Step 3: store the secret
info "== Step 3/3: store it as the ${SECRET_NAME} secret"
if [[ "${SCOPE}" == 'org' ]]; then
  SECRET_URL="https://github.com/organizations/${OWNER}/settings/secrets/actions/new"
else
  SECRET_URL="https://github.com/${OWNER}/${REPO}/settings/secrets/actions/new"
fi

if [[ "${SET_SECRET}" == 'true' ]]; then
  if [[ "${SCOPE}" == 'org' ]]; then
    printf '%s' "${TOKEN}" | gh secret set "${SECRET_NAME}" --org "${OWNER}" --repos "${REPO}" || die "gh could not set the organization secret (org admin rights needed); set it manually at ${SECRET_URL}"
  else
    printf '%s' "${TOKEN}" | gh secret set "${SECRET_NAME}" --repo "${OWNER}/${REPO}" || die "gh could not set the repository secret; set it manually at ${SECRET_URL}"
  fi
  TOKEN=''
  info "  Stored ${SECRET_NAME} (${SCOPE} secret). Done."
  exit 0
fi

if copy_to_clipboard "${TOKEN}"; then
  info '  The token is on your clipboard.'
else
  info '  No clipboard tool found; the token is still on your clipboard from GitHub.'
fi
TOKEN=''
open_url "${SECRET_URL}"
info ''
info 'On that page:'
info "  1. Name: ${SECRET_NAME}"
info '  2. Secret: paste the token.'
if [[ "${SCOPE}" == 'org' ]]; then
  info "  3. Repository access: \"Selected repositories\" and pick ${REPO}."
  info '  4. Click "Add secret".'
else
  info '  3. Click "Add secret".'
fi
info ''
info 'Clear your clipboard afterwards. The next nightly or tagged release will use the token automatically.'
