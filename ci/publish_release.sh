#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Create (or reuse) a GitHub Release for RELEASE_TAG and upload every file
# under the given uploads directory (default: uploads/release). Same-named
# assets are replaced so the script is safe to re-run.
#
# Auth: the Actions-provided GITHUB_TOKEN only, passed through the
# environment. Nothing is written to disk.
set -euo pipefail

: "${RELEASE_TAG:?RELEASE_TAG must be set}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
SRC_DIR="${1:-uploads/release}"
[ -d "${SRC_DIR}" ] || { echo "ERROR: ${SRC_DIR} not found" >&2; exit 1; }

API="https://api.github.com/repos/${GITHUB_REPOSITORY}"
AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")
export TAG="${RELEASE_TAG}"

# --- locate or create the release --------------------------------------------
REL="$(curl -s "${AUTH[@]}" "${API}/releases/tags/${TAG}" || true)"
if echo "${REL}" | python3 -c 'import json,sys; sys.exit(0 if "id" in json.load(sys.stdin) else 1)'; then
  REL_ID="$(echo "${REL}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  echo "Reusing existing release id ${REL_ID}"
else
  export BODY="Automated reproducible build (GitHub Actions run ${GITHUB_RUN_ID:-manual}).
See BUILD-MANIFEST inside the kernel-images zip for refs, UTS release and vermagic.
Kernel-only flashing: keep stock vendor_dlkm/vendor_boot/dtbo untouched."
  REL="$(curl -s -X POST "${AUTH[@]}" "${API}/releases" \
    -d "$(python3 -c 'import json,os; print(json.dumps({
        "tag_name": os.environ["TAG"],
        "target_commitish": "p4/ci-build",
        "name": os.environ["TAG"],
        "body": os.environ["BODY"],
        "draft": False,
        "prerelease": False,
    }))')")"
  REL_ID="$(echo "${REL}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  echo "Created release id ${REL_ID}"
fi

# --- idempotent asset upload --------------------------------------------------
upload_asset() {
  local file="$1" ctype="$2" name old_id
  name="$(basename "${file}")"
  old_id="$(curl -s "${AUTH[@]}" "${API}/releases/${REL_ID}/assets" \
    | NAME="${name}" python3 -c 'import json,sys,os; print(" ".join(str(a["id"]) for a in json.load(sys.stdin) if a["name"] == os.environ["NAME"]))')"
  for id in ${old_id}; do
    echo "Replacing existing asset ${name} (id ${id})"
    curl -s -X DELETE "${AUTH[@]}" "${API}/releases/assets/${id}" >/dev/null
  done
  echo "Uploading ${name} ($(du -h "${file}" | cut -f1))"
  local resp http
  resp="$(mktemp)"
  http="$(curl -sS --retry 3 --retry-all-errors --connect-timeout 30 \
    -X POST "${AUTH[@]}" \
    -H "Content-Type: ${ctype}" \
    --data-binary "@${file}" \
    -o "${resp}" -w '%{http_code}' \
    "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${REL_ID}/assets?name=${name}")"
  if [ "${http}" = "201" ]; then
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ->", d.get("name"), d.get("state"))' "${resp}"
  else
    echo "ERROR uploading ${name}: HTTP ${http}" >&2
    head -c 500 "${resp}" >&2; echo >&2
    rm -f "${resp}"
    return 1
  fi
  rm -f "${resp}"
}

# Smallest first so a flaky large upload cannot block the small metadata.
shopt -s nullglob
mapfile -t FILES < <(find "${SRC_DIR}" -maxdepth 1 -type f -printf '%s\t%p\n' | sort -n | cut -f2-)
for f in "${FILES[@]}"; do
  case "${f}" in
    *.zip)          upload_asset "${f}" application/zip ;;
    *.tar.gz)       upload_asset "${f}" application/gzip ;;
    *.sha256|*.txt) upload_asset "${f}" text/plain ;;
    *)              upload_asset "${f}" application/octet-stream ;;
  esac
done
echo "Release ${TAG} assets:"
curl -s "${AUTH[@]}" "${API}/releases/${REL_ID}/assets" \
  | python3 -c 'import json,sys; [print(" -", a["name"], a["size"], a["state"]) for a in json.load(sys.stdin)]'
