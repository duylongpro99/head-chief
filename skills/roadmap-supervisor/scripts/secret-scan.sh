#!/usr/bin/env bash
# secret-scan.sh — find likely secrets in text without ever printing them.
#
#   secret-scan.sh <file>...        # scan whole files
#   secret-scan.sh --diff [label]   # scan the added lines of a unified diff read from stdin
#
# Prints one line per hit: "<file>:<line>: <kind>". The matched value is never printed.
# Exit 0 when nothing matched, 1 when something did, 2 on a usage error.
#
# Kinds: private key, AWS access key, GitHub token, Slack token, sk- API key, Google API key,
# Supabase secret key, JWT, password in URL. A password in a URL is ignored when it is a
# placeholder: %s, <...>, ${VAR}, $VAR, ***, xxx, [redacted], password, pass, secret.
# It does not catch a bare password with no recognisable shape; the briefs' never-print rule
# is what covers that case.
set -uo pipefail

usage() { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; }

# Reads "<where>\t<line>\t<text>" records and prints the hits.
scan_records() {
  LC_ALL=C awk -F'\t' '
    function hit(kind) { printf "%s:%s: %s\n", where, ln, kind; found = 1 }
    {
      where = $1; ln = $2; t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t)
      if (t ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) hit("private key")
      if (t ~ /(^|[^A-Z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^A-Z0-9]|$)/) hit("AWS access key")
      if (t ~ /(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})/) hit("GitHub token")
      if (t ~ /xox[abprs]-[A-Za-z0-9-]{10,}/) hit("Slack token")
      if (t ~ /(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}/) hit("sk- API key")
      if (t ~ /AIza[0-9A-Za-z_-]{35}/) hit("Google API key")
      if (t ~ /sb_secret_[A-Za-z0-9_-]{16,}/) hit("Supabase secret key")
      if (t ~ /eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/) hit("JWT")
      # scheme://user:password@host, unless the password is a placeholder.
      s = t
      while (match(s, /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/ \t:@]+:[^\/ \t@]+@/)) {
        u = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        p = u; sub(/^[^:]*:\/\/[^:]*:/, "", p); sub(/@$/, "", p)
        lp = tolower(p)
        if (lp ~ /^(%[a-z]|<[^>]*>|\$\{?[a-z_][a-z0-9_]*\}?|\*+|x+|\[redacted\]|password|pass|passwd|secret|pwd)$/) continue
        hit("password in URL"); break
      }
    }
    END { exit found ? 1 : 0 }'
}

# Unified diff on stdin -> records of its added lines, numbered in the new file.
diff_records() {
  LC_ALL=C awk -v label="${1:-diff}" '
    /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); if (f == "/dev/null") f = label; next }
    /^@@ / { split($3, a, ","); n = substr(a[1], 2) + 0; next }
    /^\+/ { printf "%s\t%d\t%s\n", (f == "" ? label : f), n, substr($0, 2); n++; next }
    /^ / { n++ }'
}

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
case "$1" in
  -h|--help) usage; exit 0 ;;
  --diff) diff_records "${2:-diff}" | scan_records; exit $? ;;
esac
rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "secret-scan: no such file: $f" >&2; exit 2; }
  LC_ALL=C awk -v w="$f" '{ sub(/\r$/, ""); gsub(/\t/, " "); printf "%s\t%d\t%s\n", w, NR, $0 }' "$f" | scan_records || rc=1
done
exit "$rc"
