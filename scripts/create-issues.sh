#!/usr/bin/env bash
# Cria (ou atualiza) labels, milestones e issues do dsh-optmem a partir dos
# arquivos em .github/issues/. Idempotente: rodar duas vezes não duplica nada.
#
#   scripts/create-issues.sh                 # usa o repo do diretório atual
#   scripts/create-issues.sh --dry-run       # mostra o que faria
#   REPO=owner/name scripts/create-issues.sh
#
# Requer: gh autenticado com escopo `repo`.

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

ISSUES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.github/issues" && pwd)"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

say() { printf '%s\n' "$*"; }
run() {
  if (( DRY_RUN )); then
    say "  [dry-run] $*"
  else
    "$@"
  fi
}

say "repo: $REPO"
say "issues: $ISSUES_DIR"
say

# ---------------------------------------------------------------- labels
LABELS=(
  "area:store" "area:cover" "area:injection" "area:tools" "area:compression"
  "area:compaction" "area:scope" "area:security" "area:privacy" "area:web"
  "area:audit" "area:tests" "area:release" "area:docs"
  "type:feature" "type:test" "type:infra" "type:docs" "type:spike"
  "spec" "blocked" "good-first-issue"
)

say "== labels =="
for label in "${LABELS[@]}"; do
  color="ededed"
  case "$label" in
    area:*) color="1d76db" ;;
    type:*) color="0e8a16" ;;
    spec)   color="5319e7" ;;
    blocked) color="b60205" ;;
    good-first-issue) color="7057ff" ;;
  esac
  run gh label create "$label" --repo "$REPO" --color "$color" --force >/dev/null
done
say "  ${#LABELS[@]} labels"

# ------------------------------------------------------------ milestones
MILESTONES=(
  "M1 — Fundação"
  "M2 — Contexto"
  "M3 — Inteligência"
  "M4 — Superfície"
  "M5 — Endurecimento"
  "M6 — Release"
)

say
say "== milestones =="
existing_milestones="$(gh api "repos/$REPO/milestones?state=all&per_page=100" -q '.[].title' 2>/dev/null || true)"
for m in "${MILESTONES[@]}"; do
  if grep -Fxq "$m" <<<"$existing_milestones"; then
    say "  = $m"
  else
    say "  + $m"
    run gh api "repos/$REPO/milestones" -f title="$m" >/dev/null
  fi
done

# ---------------------------------------------------------------- issues
say
say "== issues =="
existing_titles="$(gh issue list --repo "$REPO" --state all --limit 500 --json title -q '.[].title' 2>/dev/null || true)"

created=0
skipped=0

for file in "$ISSUES_DIR"/*.md; do
  base="$(basename "$file")"
  [[ "$base" == "README.md" ]] && continue

  # Front-matter: linhas entre o primeiro e o segundo '---'.
  fm="$(awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$file")"
  title="$(sed -n 's/^title:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' <<<"$fm")"
  milestone="$(sed -n 's/^milestone:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' <<<"$fm")"
  labels="$(sed -n 's/^labels:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' <<<"$fm" | tr -d ' ' | tr ',' '\n' | sed '/^$/d')"

  if [[ -z "$title" ]]; then
    say "  ! $base: sem 'title' no cabeçalho — ignorado"
    continue
  fi

  if grep -Fxq "$title" <<<"$existing_titles"; then
    say "  = $title"
    skipped=$((skipped + 1))
    continue
  fi

  # Corpo: tudo depois do segundo '---'.
  body_file="$(mktemp)"
  awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; if(n==2){found=1; next}} found{print}' "$file" >"$body_file"

  args=(gh issue create --repo "$REPO" --title "$title" --body-file "$body_file")
  [[ -n "$milestone" ]] && args+=(--milestone "$milestone")
  while IFS= read -r l; do
    [[ -n "$l" ]] && args+=(--label "$l")
  done <<<"$labels"

  say "  + $title"
  run "${args[@]}" >/dev/null
  rm -f "$body_file"
  created=$((created + 1))
done

say
say "criadas: $created   já existiam: $skipped"
