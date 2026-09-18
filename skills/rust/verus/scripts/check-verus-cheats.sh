#!/usr/bin/env bash
# Gate a Verus proof edit against the original file.
#
# Usage: check-verus-cheats.sh ORIGINAL CURRENT
#
# Reports the proof shortcuts a language model takes when a proof is hard:
# added assume/admit/axiom/external_body/assume_specification/uninterp,
# changed function signatures (which is where requires/ensures live), removed
# functions, and removed lines inside a function that already existed.
#
# Exit status:
#   0  no cheat found
#   1  at least one cheat found
#   2  usage or input error
#
# Limits: this is a line-based heuristic, not a Rust parser. It ignores string
# literals and `//` comments, does not understand `/* */`, and compares
# pre-existing function bodies by line content, so it will not see a change
# that keeps every substantive line intact (for example, editing only a string
# literal). Treat it as a filter for the common cheats, not as proof of
# innocence.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") ORIGINAL CURRENT" >&2
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

ORIGINAL="$1"
CURRENT="$2"
for file in "$ORIGINAL" "$CURRENT"; do
  if [ ! -f "$file" ]; then
    echo "check-verus-cheats: not a file: $file" >&2
    exit 2
  fi
done

if [ -d /private/tmp ]; then
  TEMP_ROOT=/private/tmp
else
  TEMP_ROOT=/tmp
fi
WORK=$(mktemp -d "$TEMP_ROOT/skills-sdlc-verus-cheats.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Emit one record per function signature and per substantive body line:
#   SIG<TAB>name<TAB>normalized signature
#   BODY<TAB>name<TAB>normalized body line
# Signatures span from `fn` to the opening `{` or the terminating `;`. Braces
# inside string literals and line comments are removed before counting, so the
# body-end scan survives them.
extract() {
  awk -v tag="$2" '
    function strip(s,   t) {
      t = s
      gsub(/"[^"]*"/, "", t)
      sub(/[ \t]*\/\/.*/, "", t)
      return t
    }
    function norm(s) {
      gsub(/[ \t]+/, " ", s)
      sub(/^ /, "", s)
      sub(/ $/, "", s)
      return s
    }
    function braces(s,   i, c, n) {
      n = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "{") n++
        else if (c == "}") n--
      }
      return n
    }
    function emit_signature() {
      printf "SIG\t%s\t%s\n", name, norm(sig)
      sig = ""
    }
    function open_body(rest) {
      inbody = 1
      insig = 0
      depth = 1 + braces(rest)
      line = norm(strip(rest))
      if (line != "") printf "BODY\t%s\t%s\n", name, line
      if (depth <= 0) {
        inbody = 0
        depth = 0
        name = ""
      }
    }
    BEGIN { insig = 0; inbody = 0; depth = 0; name = ""; sig = ""; printed = 0 }
    {
      if (!printed) {
        printf "FILE\t%s\n", tag
        printed = 1
      }
      code = strip($0)
      if (inbody) {
        depth += braces(code)
        line = norm(strip($0))
        if (line != "") printf "BODY\t%s\t%s\n", name, line
        if (depth <= 0) {
          inbody = 0
          depth = 0
          name = ""
        }
        next
      }
      if (!insig) {
        if (!match(code, /(^|[^A-Za-z0-9_])fn[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) next
        seg = substr(code, RSTART, RLENGTH)
        sub(/^[^A-Za-z_]*/, "", seg)
        sub(/^fn[ \t]+/, "", seg)
        name = seg
        insig = 1
        sig = ""
      }
      open = index(code, "{")
      semi = index(code, ";")
      if (open > 0 && (semi == 0 || open < semi)) {
        sig = sig " " substr(code, 1, open - 1)
        emit_signature()
        open_body(substr(code, open + 1))
      } else if (semi > 0) {
        sig = sig " " substr(code, 1, semi - 1)
        emit_signature()
        insig = 0
        name = ""
      } else {
        sig = sig " " code
      }
    }
    END {
      if (!printed) printf "FILE\t%s\n", tag
    }
  ' "$1"
}

extract "$ORIGINAL" original >"$WORK/original.records"
extract "$CURRENT" current >"$WORK/current.records"

violations=0

# Cheat keywords, restricted to added lines so pre-existing uses in the
# original do not fail the gate. Comments and string literals are removed
# first, so prose about `assume` is not a finding.
CHEAT_PATTERN='(^|[^A-Za-z0-9_])(assume|admit)[[:space:]]*\(|(^|[^A-Za-z0-9_])axiom[[:space:]]+fn|assume_specification|external_body|verifier::external($|[^_A-Za-z0-9])|(^|[^A-Za-z0-9_])uninterp[[:space:]]+spec'
cheat_lines=$(
  diff -u "$ORIGINAL" "$CURRENT" |
    awk '/^\+/ && !/^\+\+\+/ { print substr($0, 2) }' |
    awk '{
      gsub(/"[^"]*"/, "")
      sub(/[ \t]*\/\/.*/, "")
      gsub(/[ \t]+/, " ")
      if ($0 ~ /[^[:space:]]/) print
    }' |
    grep -E "$CHEAT_PATTERN" || true
)
if [ -n "$cheat_lines" ]; then
  violations=1
  echo "CHEAT: proof shortcut added"
  printf '%s\n' "$cheat_lines" | sed 's/^/  /'
fi

if ! awk '
  function substantive(s) {
    if (s == "") return 0
    if (s ~ /^[{}()\[\];,.]+$/) return 0
    return 1
  }
  function report(msg) {
    printf "%s\n", msg
    bad = 1
  }
  $1 == "FILE" {
    section = ($2 == "original") ? 1 : 2
    next
  }
  {
    rest = $0
    sub(/^[^\t]*\t/, "", rest)
    name = rest
    sub(/\t.*/, "", name)
    payload = rest
    sub(/^[^\t]*\t/, "", payload)
    if ($1 == "SIG") {
      sigs[section SUBSEP name SUBSEP payload]++
      signames[section SUBSEP name] = 1
    } else if ($1 == "BODY" && substantive(payload)) {
      bodies[section SUBSEP name SUBSEP payload]++
    }
  }
  END {
    for (key in signames) {
      split(key, parts, SUBSEP)
      if (parts[1] != 1) continue
      name = parts[2]
      if (!((2 SUBSEP name) in signames)) {
        report("REMOVED: function `" name "` is gone")
        continue
      }
      changed = 0
      for (sigkey in sigs) {
        split(sigkey, sigparts, SUBSEP)
        if (sigparts[1] != 1 || sigparts[2] != name) continue
        if (sigs[sigkey] > sigs[2 SUBSEP name SUBSEP sigparts[3]]) changed = 1
      }
      if (changed) {
        report("SIGNATURE CHANGED: `" name "`")
        for (sigkey in sigs) {
          split(sigkey, sigparts, SUBSEP)
          if (sigparts[1] == 1 && sigparts[2] == name) printf "  original: %s\n", sigparts[3]
        }
        for (sigkey in sigs) {
          split(sigkey, sigparts, SUBSEP)
          if (sigparts[1] == 2 && sigparts[2] == name) printf "  current:  %s\n", sigparts[3]
        }
      }
    }
    for (key in bodies) {
      split(key, parts, SUBSEP)
      if (parts[1] != 1) continue
      name = parts[2]
      line = parts[3]
      if (!((2 SUBSEP name) in signames)) continue
      if (bodies[2 SUBSEP name SUBSEP line] < bodies[key]) {
        report("BODY LINE CHANGED OR REMOVED: `" name "`: " line)
      }
    }
    exit (bad ? 1 : 0)
  }
' "$WORK/original.records" "$WORK/current.records"; then
  violations=1
fi

if [ "$violations" -ne 0 ]; then
  echo "result: cheats found; restore the original specification and executable code" >&2
  exit 1
fi

echo "result: no cheats found"
