#!/usr/bin/env bash
# tools/merge-lanes.sh: Code Bot's lane report (LANES.md section 7). Read-only for remotes: it never pushes.
# Fetches every claude/* branch from shaunbirrell/war-empire (origin) and shaunbirrell/Padel-AI (the mirror Claude
# sessions clone), lists the ones with commits not in phase-7-polish, and dry-run merges each into phase-7-polish in
# a throwaway worktree to report conflicts. Your checkout and branches are left as they were.
# Usage: tools/merge-lanes.sh [base-branch]   (default: phase-7-polish)
set -euo pipefail
BASE="${1:-phase-7-polish}"
PADEL_URL="${PADEL_URL:-https://github.com/shaunbirrell/Padel-AI.git}"
cd "$(git rev-parse --show-toplevel)"

git fetch --quiet origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" "+refs/heads/claude/*:refs/remotes/origin/claude/*" --prune
git fetch --quiet "$PADEL_URL" "+refs/heads/claude/*:refs/remotes/padel/claude/*" 2>/dev/null || echo "note: could not fetch $PADEL_URL (skipped)"

BASE_REF="origin/$BASE"
WT="$(mktemp -d /tmp/merge-lanes.XXXXXX)"
git worktree add --quiet --detach "$WT" "$BASE_REF"
cleanup() { git worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$WT"; }
trap cleanup EXIT

printf 'base %s = %s\n\n' "$BASE_REF" "$(git rev-parse --short "$BASE_REF")"
printf '%-58s %-9s %-6s %s\n' "BRANCH" "HEAD" "NEW" "DRY-RUN MERGE"
declare -A SEEN=()
for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin/claude refs/remotes/padel/claude); do
  sha="$(git rev-parse "$ref")"
  new="$(git rev-list --count "$BASE_REF..$ref")"
  [ "$new" -eq 0 ] && continue
  if [ -n "${SEEN[$sha]:-}" ]; then printf '%-58s %-9s %-6s %s\n' "$ref" "${sha:0:8}" "$new" "same commit as ${SEEN[$sha]}"; continue; fi
  SEEN[$sha]="$ref"
  git -C "$WT" reset --quiet --hard "$BASE_REF"
  if git -C "$WT" -c user.name=merge-lanes -c user.email=merge-lanes@local merge --no-commit --no-ff --quiet "$sha" >/dev/null 2>&1; then
    result="clean ($(git -C "$WT" diff --cached --name-only | wc -l) files)"
  else
    files="$(git -C "$WT" diff --name-only --diff-filter=U | tr '\n' ' ')"
    result="CONFLICT: $files"
  fi
  git -C "$WT" merge --abort >/dev/null 2>&1 || git -C "$WT" reset --quiet --hard "$BASE_REF"
  printf '%-58s %-9s %-6s %s\n' "$ref" "${sha:0:8}" "$new" "$result"
done

# pairwise overlap: files touched by more than one pending branch (likely conflicts after the first merge)
echo
echo "files changed by more than one pending branch:"
for sha_ref in "${SEEN[@]}"; do git diff --name-only "$BASE_REF...$sha_ref"; done | sort | uniq -d | sed 's/^/  /' || true
echo
echo "nothing was pushed or merged; run the real merges in LANES.md order."
