#!/usr/bin/env bash
# Pin all allowed Marketplace actions in .github/workflows to full SHAs.
set -euo pipefail

need(){ command -v "$1" >/dev/null || { echo "❌ install $1 first"; exit 1; }; }
need gh; need jq; need sed; need awk

WF_DIR=".github/workflows"
[ -d "$WF_DIR" ] || { echo "❌ $WF_DIR not found"; exit 1; }

# ---- allow-list по owner'ам ----
ALLOW_RE='^(actions|github|aws-actions|google-github-actions|dependabot|azure)(/|$)'

# ---- что пинить (repo + tag/branch) ----
TO_PIN=$(cat <<'EOF'
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

# ---- кэш резолвов ----
CACHE=".pins.cache.$$"; trap 'rm -f "$CACHE"' EXIT

resolve_sha () {
  local repo="$1" ref="$2" key="${repo}@${ref}" sha t
  if [ -f "$CACHE" ] && grep -Fq "^$key|" "$CACHE"; then
    awk -F'|' -v k="$key" '$1==k{print $2}' "$CACHE"; return 0
  fi
  # tag?
  if gh api "repos/${repo}/git/ref/tags/${ref}" >/dev/null 2>&1; then
    t=$(gh api "repos/${repo}/git/ref/tags/${ref}" -q '.object.type')
    sha=$(gh api "repos/${repo}/git/ref/tags/${ref}" -q '.object.sha')
    if [ "$t" = "tag" ]; then # annotated tag
      sha=$(gh api "repos/${repo}/git/tags/${sha}" -q '.object.sha')
    fi
  else
    # branch (например github/codeql-action@v3 — это ветка)
    sha=$(gh api "repos/${repo}/git/ref/heads/${ref}" -q '.object.sha') || {
      echo "❌ cannot resolve ${repo}@${ref}" >&2; return 1; }
  fi
  echo "${key}|${sha}" >> "$CACHE"
  echo "$sha"
}

# ---- список файлов workflow (совместимо с bash 3.2) ----
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(git ls-files "${WF_DIR}/*.yml" "${WF_DIR}/*.yaml" 2>/dev/null)

# ---- BSD/GNU sed -i флаг ----
if sed --version >/dev/null 2>&1; then
  SED_I=(-i)
else
  SED_I=(-i '')
fi

# ---- sanity: проверка owners в uses: ----
violations=0
for f in "${FILES[@]}"; do
  while IFS= read -r line; do
    # вытащить repo из "uses: <repo>@<ref>"
    repo=$(printf '%s\n' "$line" | sed -E 's/.*uses:[[:space:]]*([^@[:space:]]+).*/\1/')
    [ -z "$repo" ] && continue
    if [[ ! "$repo" =~ $ALLOW_RE ]]; then
      echo "❌ $f: $repo not allowed by policy"
      violations=1
    fi
  done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$f" || true)
done
[ $violations -eq 0 ] || { echo "🚫 fix disallowed owners first"; exit 1; }

# ---- пин заранее известных repo@ref ----
echo "→ Pinning well-known actions to full SHAs…"
while read -r repo ref; do
  [ -z "${repo:-}" ] && continue
  sha=$(resolve_sha "$repo" "$ref")
  # заменить uses: <repo>(/subpath)?@anything → @<sha>
  sed -E "${SED_I[@]}" "s#(uses:[[:space:]]*${repo}(/[a-zA-Z0-9._-]+)?@)[^[:space:]\"']+#\\1${sha}#g" "${FILES[@]}"
  echo "   ${repo}@${ref} → ${sha}"
done <<< "$TO_PIN"

# ---- CodeQL sub-actions (init/analyze) на один и тот же SHA ----
codeql_sha=$(resolve_sha "github/codeql-action" "v3")
sed -E "${SED_I[@]}" \
  "s#(uses:[[:space:]]*github/codeql-action/(init|analyze)@)[^[:space:]\"']+#\\1${codeql_sha}#g" \
  "${FILES[@]}"

# ---- контроль: не осталось @vN ----
if grep -RInE 'uses:\s*[^@]+@v[0-9]+' "${WF_DIR}" >/dev/null; then
  echo "⚠️  Остались uses:@vN — проверьте вручную:"
  grep -RInE 'uses:\s*[^@]+@v[0-9]+' "${WF_DIR}"
  exit 2
fi

echo "✅ Done. Commit the changes:"
echo "   git add ${WF_DIR} && git commit -m 'ci: pin GitHub Actions to full SHAs'"
