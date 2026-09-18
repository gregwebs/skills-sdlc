#!/usr/bin/env bash
# Functional test for skills/rust/verus/scripts/check-verus-cheats.sh.
# Fixture-driven: no Verus installation is required.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPOSITORY_ROOT/skills/rust/verus/scripts/check-verus-cheats.sh"

fail() {
  echo "check-verus-cheats test: $*" >&2
  exit 1
}

if [ -d /private/tmp ]; then
  TEMP_ROOT=/private/tmp
else
  TEMP_ROOT=/tmp
fi
WORK=$(mktemp -d "$TEMP_ROOT/skills-sdlc-verus-cheats-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

ORIGINAL="$WORK/original.rs"
MARKER='    // proof goes here
'
cat >"$ORIGINAL" <<'EOF'
use vstd::prelude::*;
verus!{

spec fn sum(s: Seq<u32>) -> u32 {
    if s.len() == 0 { 0 } else { s[0] + sum(s.drop_first()) }
}

fn add(a: u32, b: u32) -> (c: u32)
    requires a + b < 1000,
    ensures c == a + b,
{
    // proof goes here
    a + b
}

fn main() {}
}
EOF

# Copy the original and apply one exact replacement.
variant() {
  local name="$1" old="$2" new="$3"
  local out="$WORK/$name.rs"
  cp "$ORIGINAL" "$out"
  python3 - "$out" "$old" "$new" <<'PY'
import sys

path, old, new = sys.argv[1:4]
text = open(path).read()
if text.count(old) != 1:
    raise SystemExit(f"expected one occurrence of {old!r} in {path}, found {text.count(old)}")
open(path, "w").write(text.replace(old, new))
PY
  printf '%s\n' "$out"
}

# Runs the checker and captures status and output without tripping errexit.
run_checker() {
  status=0
  output=$("$CHECKER" "$@" 2>&1) || status=$?
}

expect_status() {
  local expected="$1"
  if [ "$status" -ne "$expected" ]; then
    fail "expected exit $expected, got $status
--- output ---
$output"
  fi
}

expect_output_contains() {
  local needle="$1"
  case "$output" in
    *"$needle"*) ;;
    *) fail "expected output to contain: $needle
--- output ---
$output" ;;
  esac
}

# An unchanged file is clean.
run_checker "$ORIGINAL" "$ORIGINAL"
expect_status 0
expect_output_contains "no cheats found"

# Proof annotations, including a new helper lemma, are the expected edit.
annotated=$(variant annotated "$MARKER" 'assert(a + b < 1000);
    lemma_sum();
')
python3 - "$annotated" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
open(path, "w").write(
    text.replace(
        "fn main() {}",
        "proof fn lemma_sum()\n    ensures true,\n{\n}\n\nfn main() {}",
    )
)
PY
run_checker "$ORIGINAL" "$annotated"
expect_status 0
expect_output_contains "no cheats found"

# Prose about a proof shortcut is not a shortcut.
commented=$(variant commented "$MARKER" '// never assume(a + b < 1000) or admit() here
    assert(a + b < 1000);
')
run_checker "$ORIGINAL" "$commented"
expect_status 0

# Each proof shortcut is a cheat.
assumed=$(variant assume "$MARKER" $'assume(a + b < 1000);\n')
run_checker "$ORIGINAL" "$assumed"
expect_status 1
expect_output_contains "CHEAT"

admitted=$(variant admit "$MARKER" $'assert(false) by { admit(); };\n')
run_checker "$ORIGINAL" "$admitted"
expect_status 1
expect_output_contains "CHEAT"

external=$(variant external "$MARKER" '#[verifier::external_body]
    let c = a + b;
')
run_checker "$ORIGINAL" "$external"
expect_status 1
expect_output_contains "CHEAT"

uninterp=$(variant uninterp "$MARKER" $'uninterp spec fn opaque(x: u32) -> u32;\n')
run_checker "$ORIGINAL" "$uninterp"
expect_status 1
expect_output_contains "CHEAT"

axiomatic=$(variant axiom "$MARKER" $'assert(false) by { magic(); };\n')
python3 - "$axiomatic" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
open(path, "w").write(
    text.replace("fn main() {}", "pub axiom fn magic()\n    ensures false;\n\nfn main() {}")
)
PY
run_checker "$ORIGINAL" "$axiomatic"
expect_status 1
expect_output_contains "CHEAT"

# A weakened or strengthened contract is a cheat.
weakened=$(variant weakened "ensures c == a + b," "ensures c >= a,")
run_checker "$ORIGINAL" "$weakened"
expect_status 1
expect_output_contains "SIGNATURE CHANGED"

# Changing executable code inside an existing function is a cheat.
changed_body=$(variant changed_body '    a + b
' '    a + b + 1
')
run_checker "$ORIGINAL" "$changed_body"
expect_status 1
expect_output_contains "BODY LINE CHANGED OR REMOVED"

# Changing a spec function body is a cheat.
changed_spec=$(variant changed_spec "else { s[0]" "else if s.len() == 1 { 0 } else { s[0]")
run_checker "$ORIGINAL" "$changed_spec"
expect_status 1
expect_output_contains "BODY LINE CHANGED OR REMOVED"

# Deleting a function is a cheat.
deleted=$(variant deleted '
fn main() {}
' '
')
run_checker "$ORIGINAL" "$deleted"
expect_status 1
expect_output_contains "REMOVED: function \`main\` is gone"

# Two functions may share a name in different impl blocks. Adding another one is
# not a signature change; changing one of them is.
DUP_ORIGINAL="$WORK/dup_original.rs"
cat >"$DUP_ORIGINAL" <<'EOF'
use vstd::prelude::*;
verus!{

struct A;
struct B;
struct C;

impl A {
    fn new() -> (a: A)
        ensures true,
    { A }
}

impl B {
    fn new() -> (b: B)
        ensures true,
    { B }
}

fn main() {}
}
EOF
DUP_ADDED="$WORK/dup_added.rs"
python3 - "$DUP_ORIGINAL" "$DUP_ADDED" <<'PY'
import sys

src, dst = sys.argv[1:3]
text = open(src).read()
open(dst, "w").write(
    text.replace(
        "fn main() {}",
        "impl C {\n    fn new() -> (c: C)\n        ensures true,\n    { C }\n}\n\nfn main() {}",
    )
)
PY
run_checker "$DUP_ORIGINAL" "$DUP_ADDED"
expect_status 0

DUP_CHANGED="$WORK/dup_changed.rs"
python3 - "$DUP_ORIGINAL" "$DUP_CHANGED" <<'PY'
import sys

src, dst = sys.argv[1:3]
text = open(src).read()
open(dst, "w").write(text.replace("    { A }", "    { A }\n    // same body, but the spec below moved", 1).replace(
    "impl A {\n    fn new() -> (a: A)\n        ensures true,",
    "impl A {\n    fn new() -> (a: A)\n        ensures a == A,",
))
PY
run_checker "$DUP_ORIGINAL" "$DUP_CHANGED"
expect_status 1
expect_output_contains "SIGNATURE CHANGED"

# Deleting one substantive body line is a cheat even though the rest remain.
DUP_BODY="$WORK/dup_body.rs"
python3 - "$DUP_BODY" <<'PY'
import sys

path = sys.argv[1]
text = """use vstd::prelude::*;
verus!{

fn f(x: u32) -> (y: u32)
    ensures y == x + x,
{
    let a = x + x;
    let b = a - x;
    let c = b - x;
    c
}

fn main() {}
}
"""
open(path, "w").write(text)
PY
DUP_BODY_CHANGED="$WORK/dup_body_changed.rs"
python3 - "$DUP_BODY" "$DUP_BODY_CHANGED" <<'PY'
import sys

src, dst = sys.argv[1:3]
text = open(src).read()
open(dst, "w").write(text.replace("    let b = a - x;\n", ""))
PY
run_checker "$DUP_BODY" "$DUP_BODY_CHANGED"
expect_status 1
expect_output_contains "BODY LINE CHANGED OR REMOVED"

# Bad invocations exit 2 instead of reporting a clean proof.
run_checker
expect_status 2
run_checker "$ORIGINAL"
expect_status 2
run_checker "$ORIGINAL" "$WORK/does-not-exist.rs"
expect_status 2
expect_output_contains "not a file"

echo "check-verus-cheats: all cases passed"
