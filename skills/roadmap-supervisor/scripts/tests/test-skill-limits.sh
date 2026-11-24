#!/usr/bin/env bash
# Guards that keep the skill short and every past mistake tied to a proof. No model.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$HERE/../.." && pwd -P)"
pass=0; total=0
check() { total=$((total + 1)); if [ "$2" -eq 0 ]; then pass=$((pass + 1)); echo "ok   - $1"; else echo "FAIL - $1"; [ -z "${3:-}" ] || printf '       %s\n' "$3"; fi; }

MAX_SKILL_BYTES=17000 MAX_RULES=8 MAX_RULE_CHARS=220

n="$(wc -c < "$SKILL/SKILL.md" | tr -d ' ')"
[ "$n" -le "$MAX_SKILL_BYTES" ]; check "SKILL.md is at most $MAX_SKILL_BYTES bytes" $? "it is $n bytes: move text to a reference or a script"

n="$(grep -c . "$SKILL/scripts/resume-rules.txt")"
[ "$n" -le "$MAX_RULES" ]; check "resume-rules.txt has at most $MAX_RULES rules" $? "it has $n: move one into a script check or a step before adding another"

long="$(awk -v m="$MAX_RULE_CHARS" 'length($0) > m { print NR }' "$SKILL/scripts/resume-rules.txt" | tr '\n' ' ')"
[ -z "$long" ]; check "each resume rule is at most $MAX_RULE_CHARS characters" $? "too long: line(s) $long"

! grep -q '^## Gotchas' "$SKILL/SKILL.md"; check "SKILL.md has no Gotchas section (rules live in a script or at their step)" $?

missing=""
for f in $(grep -oE '(references|scripts)/[A-Za-z0-9_./-]+\.(md|sh|txt)' "$SKILL/SKILL.md" | sort -u); do
  [ -e "$SKILL/$f" ] || missing="$missing $f"
done
[ -z "$missing" ]; check "every references/ and scripts/ path named in SKILL.md exists" $? "missing:$missing"

n="$(cat "$SKILL/SKILL.md" "$SKILL/references/brief-template.md" | grep -c 'herdr agent prompt <pane[^>]*> ".*" --wait --until working')"
[ "$n" -ge 2 ]; check "the dispatch line waits for the working state" $? "found in $n of 2 files"

# The lessons register lives in the repository, not in an installed copy of the skill.
LESSONS="$SKILL/../../docs/roadmap-supervisor-lessons.md"
if [ -f "$LESSONS" ]; then
  REPO="$(cd "$SKILL/../.." && pwd -P)"
  bad=""; rows=0
  while IFS= read -r row; do
    rows=$((rows + 1))
    proofs="$(printf '%s\n' "$row" | grep -oE '`(test|eval):[^`]+`' | tr -d '`' || true)"
    [ -n "$proofs" ] || { bad="$bad [row $rows: no test: or eval: proof]"; continue; }
    while IFS= read -r p; do
      case "$p" in
        test:*) t="${p#test:}"; grep -qF -- "$t" "$SKILL"/scripts/tests/*.sh || bad="$bad [$p: no such test name]" ;;
        eval:*) e="${p#eval:}"; [ -d "$REPO/tests/roadmap-supervisor-evals/scenarios/$e" ] || bad="$bad [$p: no such scenario]" ;;
      esac
    done <<< "$proofs"
  done < <(grep -E '^\| *L[0-9]+ ' "$LESSONS")
  [ "$rows" -gt 0 ] && [ -z "$bad" ]; check "every lesson in the register names a test or an eval scenario that exists" $? "rows: $rows;$bad"
fi

echo "$pass/$total passed"
[ "$pass" -eq "$total" ]
