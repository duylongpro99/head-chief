#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# run-state.sh — read and update a run's ledger, guard reviewer turns, quote result sections.
#
#   run-state.sh --run DIR get <key>              # jq path, e.g. status or envoy.pane
#   run-state.sh --run DIR set <key> <value>      # round status final_status max_rounds timeout_minutes
#   run-state.sh --run DIR guard begin|end <n>    # end prints clean|changed (+ HEAD/index lines, up to 20 changed paths)
#   run-state.sh --run DIR git-meta               # same|changed|unavailable vs the baseline .git config+hooks
#   run-state.sh --run DIR extract <section> <file> [--max-lines N]
#   run-state.sh --run DIR conflicts <review file>   # none|present|missing (never the content)
#
# extract prints one H2 section (default 8 lines, 600 chars), every line
# prefixed "> " and passed through redact, so the controller sees a quote,
# never instructions. conflicts exits 7 when the section is missing.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run=""
[ "${1:-}" != "-h" ] && [ "${1:-}" != "--help" ] || { print_usage; exit 0; }
[ "${1:-}" = "--run" ] && [ "$#" -ge 3 ] || usage_die "usage: run-state.sh --run DIR <get|set|guard|git-meta|extract|conflicts> ..."
run="$(resolve_run "$2")"; shift 2
sub="$1"; shift

STATUSES=" created dispatched reviewing fixing accepted concerns blocked timeout cleaned "

top_of_run() { git_top "$(run_get "$run" .cwd)" || true; }

# guard_snapshot <top> <manifest file>: HEAD (a commit leaves the status unchanged),
# the index entries, and the per-path manifest already written by worktree_manifest.
guard_snapshot() {
  local top="$1" manifest="$2"
  jq -n --arg h "$(git -C "$top" rev-parse -q --verify HEAD 2>/dev/null || true)" \
    --arg i "$(git -C "$top" ls-files -s | sha_stdin)" \
    --arg m "$(sha_stdin < "$manifest")" \
    '{head: $h, index_sha: $i, manifest_sha: $m, at: (now | todate)}'
}

# Lines of one "## <name>" section, without the heading, trimmed of blank edges.
# The closing Status or Verdict line of the templates also ends a section.
section() {
  awk -v want="## $1" '
    /^## / { if (inside) exit; if ($0 == want || $0 ~ ("^" want "[[:space:]]*$")) { inside = 1; next } }
    inside && /^(Status: (DONE|DONE_WITH_CONCERNS|BLOCKED)|Verdict: (ACCEPT|FINDINGS|BLOCKED))[[:space:]]*$/ { exit }
    inside { print }' "$2" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

case "$sub" in
  get)
    [ "$#" = 1 ] || usage_die "get needs one key"
    k="$1"; case "$k" in .*) ;; *) k=".$k" ;; esac
    run_get "$run" "$k"
    ;;
  set)
    [ "$#" = 2 ] || usage_die "set needs a key and a value"
    k="$1" v="$2"
    case "$k" in
      round|max_rounds|timeout_minutes)
        case "$v" in ''|*[!0-9]*) usage_die "$k must be a non-negative integer" ;; esac
        run_update "$run" '.[$k] = ($v | tonumber)' --arg k "$k" --arg v "$v" ;;
      status|final_status)
        case "$STATUSES" in *" $v "*) ;; *) usage_die "$k must be one of:$STATUSES" ;; esac
        run_update "$run" '.[$k] = $v' --arg k "$k" --arg v "$v" ;;
      *) usage_die "settable keys: round status final_status max_rounds timeout_minutes" ;;
    esac
    echo "$k=$v"
    ;;
  guard)
    [ "$#" = 2 ] || usage_die "guard needs begin|end and a turn number"
    op="$1" n="$2"
    case "$n" in ''|*[!0-9]*) usage_die "guard turn must be a number" ;; esac
    top="$(top_of_run)"
    if [ -z "$top" ]; then echo "unavailable: not a git repository"; exit 0; fi
    case "$op" in
      begin)
        worktree_manifest "$top" > "$run/guard-$n.manifest"
        run_update "$run" '.guard[$n] = {before: $b}' --arg n "$n" \
          --argjson b "$(guard_snapshot "$top" "$run/guard-$n.manifest")"
        echo "guard $n begun"
        ;;
      end)
        [ -f "$run/guard-$n.manifest" ] && [ -n "$(run_get "$run" ".guard[\"$n\"].before")" ] \
          || die "guard $n was never begun"
        worktree_manifest "$top" > "$run/guard-$n.after.manifest"
        after="$(guard_snapshot "$top" "$run/guard-$n.after.manifest")"
        before="$(run_get "$run" ".guard[\"$n\"].before")"
        clean="$(jq -n --argjson a "$after" --argjson b "$before" \
          '[$a.head, $a.index_sha, $a.manifest_sha] == [$b.head, $b.index_sha, $b.manifest_sha]')"
        run_update "$run" '.guard[$n].after = $a | .guard[$n].clean = $c' \
          --arg n "$n" --argjson a "$after" --argjson c "$clean"
        if [ "$clean" = true ]; then
          echo clean
        else
          echo changed
          [ "$(jq -r .head <<<"$before")" = "$(jq -r .head <<<"$after")" ] || echo "HEAD moved (commit, reset or checkout)"
          [ "$(jq -r .index_sha <<<"$before")" = "$(jq -r .index_sha <<<"$after")" ] || echo "index changed (staged content)"
          diff "$run/guard-$n.manifest" "$run/guard-$n.after.manifest" \
            | sed -n 's/^[<>] //p' | cut -f3- | sort -u | head -20 || true
        fi
        ;;
      *) usage_die "guard needs begin or end" ;;
    esac
    ;;
  git-meta)
    base="$(run_get "$run" .baseline.git_meta_sha)"
    top="$(top_of_run)"
    if [ -z "$base" ] || [ -z "$top" ]; then echo unavailable
    elif [ "$(git_meta_sha "$top")" = "$base" ]; then echo same
    else echo changed
    fi
    ;;
  extract)
    [ "$#" -ge 2 ] || usage_die "extract needs a section and a file"
    name="$1" file="$2" max=8; shift 2
    if [ "${1:-}" = "--max-lines" ]; then
      [ "$#" -ge 2 ] || usage_die "--max-lines needs a number"
      max="$2"
      case "$max" in ''|*[!0-9]*|0) usage_die "--max-lines must be a positive integer" ;; esac
    fi
    [ -f "$file" ] || die "no such file: $file"
    section "$name" "$file" | head -n "$max" | cut -c1-600 | redact \
      | awk 'BEGIN { left = 600 } { if (left <= 0) exit; line = substr($0, 1, left); left -= length(line); print "> " line }'
    ;;
  conflicts)
    [ "$#" = 1 ] || usage_die "conflicts needs a review file"
    [ -f "$1" ] || die "no such file: $1"
    if ! grep -Eq '^## Conflicts with brief or user decisions[[:space:]]*$' "$1"; then echo missing; exit 7; fi
    body="$(section "Conflicts with brief or user decisions" "$1" | sed '/^[[:space:]]*$/d' | tr '[:upper:]' '[:lower:]')"
    none_re='^[[:space:]]*(-[[:space:]]+)?none\.?[[:space:]]*$'
    if [ -z "$body" ] || [[ "$body" =~ $none_re ]]; then echo none; else echo present; fi
    ;;
  *) usage_die "unknown subcommand: $sub" ;;
esac
