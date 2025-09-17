#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "Install $1"; exit 1; }; }
need gh
need jq

INPUT=".github/workflows/ga-security-controls.yml"
BACKUP="${INPUT}.bak"

# Список actions, которые надо закрепить на full SHA
ACTIONS=$(cat <<'EOF'
actions/checkout@v4
actions/upload-artifact@v4
actions/download-artifact@v4
actions/dependency-review-action@v4
aws-actions/configure-aws-credentials@v4
actions/attest-build-provenance@v1
actions/attest-sbom@v1
github/codeql-action/init@v3
github/codeql-action/analyze@v3
EOF
)

# sed -i синтаксис отличается на macOS и Linux
if [[ "$(uname)" == "Darwin" ]]; then
  SEDI=(sed -E -i '')
else
  SEDI=(sed -E -i)
fi

# Кэш для уже разрешённых тегов -> SHA (без bash 4)
CACHE="$(mktemp)"
cleanup(){ rm -f "$CACHE"; }
trap cleanup EXIT

resolve_sha () {
  local repo="$1" tag="$2" key="${repo}@${tag}" sha type
  if grep -Fq "^$key|" "$CACHE"; then
    awk -F'|' -v k="$key" '$1==k{print $2}' "$CACHE"
    return 0
  fi
  # Получаем объект тега
  local ref_json
  if ! ref_json=$(gh api "repos/${repo}/git/ref/tags/${tag}" 2>/dev/null); then
    echo "Tag ${repo}@${tag} not found via GitHub API" >&2
    exit 1
  fi
  local obj_sha obj_type
  obj_sha=$(jq -r '.object.sha' <<<"$ref_json")
  obj_type=$(jq -r '.object.type'<<<"$ref_json")
  if [[ "$obj_type" == "tag" ]]; then
    sha=$(gh api "repos/${repo}/git/tags/${obj_sha}" -q '.object.sha')
  else
    sha="$obj_sha"
  fi
  echo "${key}|${sha}" >> "$CACHE"
  echo "$sha"
}

echo "-> Backing up ${INPUT} -> ${BACKUP}"
cp "$INPUT" "$BACKUP"

echo "-> Pinning actions to full SHAs…"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  repo="${line%@*}"
  tag="${line#*@}"
  sha="$(resolve_sha "$repo" "$tag")"
  echo "   ${repo}@${tag} -> ${sha}"
  # Заменяем uses: repo(/subpath)?@<что-угодно> на uses: …@<sha>
  "${SEDI[@]}" "s#(uses:\s*${repo}(/[A-Za-z0-9._-]+)?@)[^[:space:]]+#\1${sha}#g" "$INPUT"
done <<< "$ACTIONS"

echo "OK. Updated: ${INPUT}"
echo "Backup left at: ${BACKUP}"
