#!/usr/bin/env bash
# Pins all allowed Marketplace actions in .github/workflows/ga-security-controls.yml
# to full-length commit SHAs, incl. CodeQL (v3 is a branch).
set -euo pipefail

# -------- prerequisites ----------
need() { command -v "$1" >/dev/null || { echo "❌ Install $1 first"; exit 1; }; }
need gh
need jq
need sed
need awk

WF_IN=".github/workflows/ga-security-controls.yml"
[ -f "$WF_IN" ] || { echo "❌ $WF_IN not found (run from repo root)"; exit 1; }

WF_BAK="${WF_IN}.bak"
cp "$WF_IN" "$WF_BAK"
echo "-> Backing up $WF_IN -> $WF_BAK"

CACHE=".pins.cache.$$"
trap 'rm -f "$CACHE"' EXIT

# Detect GNU sed vs BSD/macOS sed for -i flag
if sed --version >/dev/null 2>&1; then
  SED_GNU=1
else
  SED_GNU=0
fi

# ---------- resolve ref -> SHA (tag or branch) ----------
resolve_sha () {
  local repo="$1" tag="$2" key="${repo}@${tag}" sha obj_sha obj_type ref_json

  # cache
  if [ -f "$CACHE" ] && grep -Fq "^$key|" "$CACHE"; then
    awk -F'|' -v k="$key" '$1==k{print $2}' "$CACHE"
    return 0
  fi

  # 1) try as TAG
  if ref_json=$(gh api "repos/${repo}/git/ref/tags/${tag}" 2>/dev/null); then
    obj_sha=$(jq -r '.object.sha' <<<"$ref_json")
    obj_type=$(jq -r '.object.type'<<<"$ref_json")
    if [[ "$obj_type" == "tag" ]]; then
      sha=$(gh api "repos/${repo}/git/tags/${obj_sha}" -q '.object.sha')
    else
      sha="$obj_sha"
    fi
  else
    # 2) fallback: treat as BRANCH (used by github/codeql-action v3)
    sha=$(gh api "repos/${repo}/git/ref/heads/${tag}" -q '.object.sha') || {
      echo "❌ Cannot resolve ${repo}@${tag} (no tag or branch)"; return 1; }
  fi

  echo "${key}|${sha}" >> "$CACHE"
  echo "$sha"
}

# --------- list of repos@refs to pin ----------
LIST=$(cat <<'EOF'
actions/checkout v4
actions/upload-artifact v4
actions/download-artifact v4
actions/dependency-review-action v4
aws-actions/configure-aws-credentials v4
actions/attest-build-provenance v1
actions/attest-sbom v1
github/codeql-action v3
EOF
)

echo "-> Pinning actions to full SHAs…"

# ---------- do the pin ----------
while read -r repo tag; do
  [ -z "$repo" ] && continue
  sha="$(resolve_sha "$repo" "$tag")"
  # replace any uses: <repo>(/subdir)?@<anything> with @<sha>
  pattern="s#(uses:[[:space:]]*${repo}(/[a-zA-Z0-9._-]+)?@)[^[:space:]\"']+#\\1${sha}#g"
  if [ "$SED_GNU" -eq 1 ]; then
    sed -r -i "$pattern" "$WF_IN"
  else
    sed -E -i '' "$pattern" "$WF_IN"
  fi
  echo "   ${repo}@${tag} -> ${sha}"
done <<< "$LIST"

echo "OK. Updated: $WF_IN"
echo "Backup left at: $WF_BAK"

# sanity check: no leftover @vN tags
if grep -RInE 'uses:\s*[^@]+@v[0-9]+' "$WF_IN" >/dev/null; then
  echo "⚠️  Some actions still pinned by tag (vN). Inspect $WF_IN"
  exit 2
fi
