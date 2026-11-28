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
# Supabase secret key, JWT, password in URL. A password in a URL may hold "/" and "@" and the
# user may be empty (redis://:<password>@host). It is ignored when it is a placeholder (%s, <...>,
# ${VAR}, $VAR, ***, xxx, [redacted]), a well-known default (password, pass, secret,
# postgres, changeme, root, admin, guest, test, example, dev), or a port, as in
# http://localhost:3000?next=a@b.
# It does not catch a bare password with no recognisable shape; the briefs' never-print rule
# is what covers that case.
# Portable awk: no {n} intervals, which older mawk does not support.
set -uo pipefail

usage() { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; }

# Reads "<where>\t<line>\t<text>" records and prints the hits.
scan_records() {
  LC_ALL=C awk -F'\t' '
    # rep(c, n): the class c exactly n times; atleast(c, n): n times or more.
    function rep(c, n,   r) { r = ""; while (n-- > 0) r = r c; return r }
    function atleast(c, n) { return rep(c, n) c "*" }
    function hit(kind) { printf "%s:%s: %s\n", where, ln, kind; found = 1 }
    BEGIN {
      AN = "[A-Za-z0-9]"; W = "[A-Za-z0-9_-]"
      K[1] = "-----BEGIN [A-Z ]*PRIVATE KEY-----";                          N[1] = "private key"
      K[2] = "(^|[^A-Z0-9])(AKIA|ASIA)" rep("[0-9A-Z]", 16) "([^A-Z0-9]|$)"; N[2] = "AWS access key"
      K[3] = "(gh[pousr]_" atleast(AN, 36) "|github_pat_" atleast("[A-Za-z0-9_]", 40) ")"; N[3] = "GitHub token"
      K[4] = "xox[abprs]-" atleast("[A-Za-z0-9-]", 10);                      N[4] = "Slack token"
      # Not after a letter, digit, "_" or "-", so a name like task-sk-<long> is not a key.
      K[5] = "(^|[^A-Za-z0-9_-])sk-" atleast(W, 20);                         N[5] = "sk- API key"
      K[6] = "AIza" rep(W, 35);                                              N[6] = "Google API key"
      K[7] = "sb_secret_" atleast(W, 16);                                    N[7] = "Supabase secret key"
      K[8] = "eyJ" atleast(W, 10) "\\.eyJ" atleast(W, 10) "\\." atleast(W, 10); N[8] = "JWT"
      NK = 8
    }
    {
      where = $1; ln = $2; t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t)
      for (i = 1; i <= NK; i++) if (t ~ K[i]) hit(N[i])
      # scheme://[user]:password@host. The password runs to the last "@" of the token.
      s = t
      # A skipped match may have swallowed a later URL ("http://api:8080/v1","db":"pg://u:<password>@h"),
      # so scanning resumes right after the "://" of this match, not after the whole match.
      while (match(s, /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/ \t:@]*:[^ \t]+@/)) {
        u = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + index(u, "://") + 2)
        p = u; sub(/^[^:]*:\/\/[^:]*:/, "", p); sub(/@$/, "", p)
        lp = tolower(p)
        if (lp ~ /^(%[a-z]|<[^>]*>|\$\{?[a-z_][a-z0-9_]*\}?|\*+|x+|\[redacted\])$/) continue
        if (lp ~ /^(password|pass|passwd|pwd|secret|postgres|changeme|root|admin|guest|test|example|dev)$/) continue
        # host:port followed by a path or query that holds an "@": not a password.
        if (lp ~ /^[0-9]+([\/?#].*)?$/) continue
        hit("password in URL"); break
      }
    }
    END { exit found ? 1 : 0 }'
}

# Unified diff on stdin -> records of its added lines, numbered in the new file.
# Inside a hunk every line is content, even one that looks like a "+++ " header: the hunk's
# line counts say where it ends.
diff_records() {
  LC_ALL=C awk -v label="${1:-diff}" '
    function count(s,   a) { return (split(s, a, ",") > 1) ? a[2] + 0 : 1 }
    old > 0 || new > 0 {
      c = substr($0, 1, 1)
      if (c == "+") { printf "%s\t%d\t%s\n", (f == "" ? label : f), n, substr($0, 2); n++; new--; next }
      if (c == "-") { old--; next }
      if (c == "\\") next
      n++; old--; new--; next
    }
    /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); if (f == "/dev/null") f = label; next }
    /^@@ / { old = count(substr($2, 2)); split(substr($3, 2), a, ","); n = a[1] + 0; new = count(substr($3, 2)); next }'
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
