#!/usr/bin/env bash
# shellcheck disable=SC2016  # awk programs are single-quoted on purpose
# check-brief.sh — completeness check of a brief before dispatch.
#
#   check-brief.sh <brief.md> [--run DIR]
#
# Checks: the nine H2 sections of references/brief-template.md exist; no
# placeholder `{…}` is left outside code blocks; Acceptance criteria has at
# least one list item; Verification has a command (backticks or a code block)
# or a line "None: <reason>"; Output contract names result.md, and with --run
# exactly DIR/result.md. Prints one line per problem:
#   missing: <section> | placeholder: <section> | empty: <section> | invalid: Output contract …
# Exit 0: complete. 1: problems found. 2: usage.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

brief="" run=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run) [ "$#" -ge 2 ] || usage_die "--run needs a value"; run="${2%/}"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    -*) usage_die "unknown argument: $1" ;;
    *) [ -z "$brief" ] || usage_die "one brief at a time"; brief="$1"; shift ;;
  esac
done
[ -n "$brief" ] || usage_die "usage: check-brief.sh <brief.md> [--run DIR]"
[ -f "$brief" ] || die "no such file: $brief"

REQUIRED="Mission;Acceptance criteria;Context;Scope;Constraints;Verification;Hidden points;Output contract;Autonomy contract"

problems="$(awk -v req="$REQUIRED" -v dir="$run" '
  BEGIN { sec = "(title)" }
  /^[[:space:]]*(```|~~~)/ { fence = !fence; if (fence) code[sec] = 1; next }
  !fence && /^## / { sec = substr($0, 4); sub(/[[:space:]]+$/, "", sec); seen[sec] = 1; next }
  {
    if (index($0, "result.md")) rmd[sec] = 1
    if (dir != "" && index($0, dir "/result.md")) rpath[sec] = 1
    if (fence) next
    # A placeholder is {word…}; ${VAR} in shell snippets is not one.
    if ($0 ~ /(^|[^$])[{][A-Za-z][^{}]*[}]/) ph[sec] = 1
    if ($0 ~ /^[[:space:]]*(-|[0-9]+\.)[[:space:]]+[^[:space:]]/) item[sec] = 1
    if ($0 ~ /`[^`]+`/) code[sec] = 1
    if ($0 ~ /^[[:space:]]*None:[[:space:]]*[^[:space:]]/) none[sec] = 1
  }
  END {
    if (ph["(title)"]) print "placeholder: title"
    n = split(req, R, ";")
    for (i = 1; i <= n; i++) {
      s = R[i]
      if (!(s in seen)) { print "missing: " s; continue }
      if (ph[s]) print "placeholder: " s
    }
    a = "Acceptance criteria"; v = "Verification"; o = "Output contract"
    if ((a in seen) && !item[a]) print "empty: " a
    if ((v in seen) && !code[v] && !none[v]) print "empty: " v
    if (o in seen) {
      if (!rmd[o]) print "invalid: Output contract does not name result.md"
      else if (dir != "" && !rpath[o]) print "invalid: Output contract does not name " dir "/result.md"
    }
  }' "$brief")"

[ -z "$problems" ] && exit 0
printf '%s\n' "$problems"
exit 1
