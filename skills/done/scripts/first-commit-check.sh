#!/usr/bin/env bash
# Safety check for /done Step 4a, run after `git add -A` in a brand-new repo and
# before its first commit. Prints one staged path per line that must NOT be
# committed, as "<reason>\t<path>". Never prints file contents.
#
# Exit codes - the caller must check BOTH output and exit code:
#   0 + no output  -> clean, safe to commit
#   0 + output     -> flagged files; unstage them and re-run
#   non-zero       -> the check itself failed; DO NOT commit
# It fails closed: an earlier version exited 0 with no output when git errored
# (e.g. pointed at a non-repo), which read exactly like "clean".
#
# One git + one awk pass over the whole index, on purpose: a per-file shell loop
# spawned ~5 processes per file and took minutes on a 100-file repo under Git Bash.
#   usage: first-commit-check.sh <repo folder>
set -uo pipefail
cd "$1" 2>/dev/null || { echo "check-failed: cannot enter $1" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "check-failed: not a git repository" >&2; exit 2; }

CONTENT_RE='(-----BEGIN [A-Z ]*PRIVATE KEY|"private_key"|"type"[[:space:]]*:[[:space:]]*"service_account"|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[abpr]-[A-Za-z0-9-]{10,}|_authToken|(api[_-]?key|secret|password|passwd|token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,})'
# The value must be a quoted literal: an unquoted form would flag ordinary code
# such as `token = req.headers.authorization` and keep source files out of git.

# NUL-separated end to end (-z / -Z), so a path with a newline or quote can't
# split into a harmless-looking name.
listing=$(git -c core.quotePath=false ls-files -z --format='%(objectname) %(path)' |
  git cat-file --batch-check='%(objectsize) %(rest)' -Z |
  awk 'BEGIN { RS = "\0" }
    NF == 0 { next }
    {
      size = $1; path = substr($0, index($0, " ") + 1); p = tolower(path)
      if (size !~ /^[0-9]+$/) { print "unreadable\t" path; next }
      if (path ~ /[\001-\037"\\]/) { print "unusual-name\t" path; next }
      if (p == ".gitignore" || p ~ /(^|\/)\.env\.(example|sample|template)$/) next
      if (p ~ /\.(xlsx|xlsm|xlsb|xls|ods|csv|tsv|db|db-journal|sqlite|sqlite3|sqlite-wal|sqlite-shm|duckdb|mdb|accdb|sql|dump|bak|parquet|feather|pkl|pickle|sav|dta|pem|p12|pfx|p8|key|jks|keystore|kdbx|ppk|ovpn|tfstate|tfvars)$/) { print "data-or-key-file\t" path; next }
      if (p ~ /(^|\/)(id_rsa|id_dsa|id_ecdsa|id_ed25519|\.npmrc|\.pypirc|\.netrc|\.git-credentials|\.htpasswd|\.pgpass)$/) { print "credential-file\t" path; next }
      # Source and docs are judged by content, not name: an HR app legitimately has
      # routes/employees.js, and keeping it out of git would break the repo.
      if (p !~ /\.(js|jsx|ts|tsx|mjs|cjs|py|md|html|css|ps1|sh|bat|vue|svelte)$/ &&
          p ~ /(^|[\/._-])(\.?env|keys?|secrets?|tokens?|credentials?|passwords?|snapshot|hris|employees?|salary|salaries|payroll|service-account|sa)([\/._-]|$)/) {
        print "sensitive-name\t" path; next
      }
      if (size > 5 * 1024 * 1024) print "over-5MB\t" path
    }') || { echo "check-failed: could not list the staged files" >&2; exit 3; }
[ -n "$listing" ] && printf '%s\n' "$listing"

# Binary files are scanned too (no -I): a key inside one must not slip through.
# git grep exits 1 for "no match" - that is clean; anything above 1 is a failure.
# (Names with newlines were already flagged as unusual-name above, so plain -l is safe.)
matches=$(git -c core.quotePath=false grep --cached -l -i -a -E "$CONTENT_RE" -- . ':!.gitignore' 2>/dev/null)
rc=$?
if [ "$rc" -gt 1 ]; then echo "check-failed: content scan error ($rc)" >&2; exit 4; fi
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$matches" | while IFS= read -r path; do
    [ -n "$path" ] && printf 'secret-like-content\t%s\n' "$path"
  done
fi
exit 0
