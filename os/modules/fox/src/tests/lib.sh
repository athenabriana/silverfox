#!/usr/bin/env bash
# tests/lib.sh — shared helpers for fox + factory-reset test suites.
# shellcheck disable=SC2034  # callers source these globals
set -euo pipefail

PASS=0
FAIL=0
FAIL_NAMES=()
SUITE="${SUITE:-unknown}"

mktmpdir() {
    mktemp -d "/tmp/fox-test-${SUITE}-XXXXXX"
}

# mk_fake_just <bindir> [exit_code]
# Drops a `just` stub that prints its argv to stderr (one per line, with
# a leading "FAKEJUST:" marker so tests can scan deterministically) and
# exits with $FAKE_JUST_EXIT (default 0).
mk_fake_just() {
    local bindir="$1"
    local rc="${2:-0}"
    mkdir -p "$bindir"
    cat >"$bindir/just" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    printf 'FAKEJUST:%s\n' "\$arg" >&2
done
exit ${rc}
EOF
    chmod +x "$bindir/just"
}

# run_with_pty <input> -- <cmd...>
# Wraps `script -qc` so the script's [[ -t 0 ]] sees a TTY. <input> is
# fed via a here-doc to the wrapped command's stdin.
run_with_pty() {
    local input="$1"
    shift
    [[ "$1" == "--" ]] || { echo "run_with_pty: expected -- after input"; return 2; }
    shift
    printf '%s' "$input" | script -qc "$*" /dev/null
}

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS+1))
        echo "  ok  $name"
    else
        FAIL=$((FAIL+1))
        FAIL_NAMES+=("$name")
        printf '  FAIL %s\n    expected: %q\n    actual:   %q\n' \
            "$name" "$expected" "$actual"
    fi
}

assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1))
        echo "  ok  $name"
    else
        FAIL=$((FAIL+1))
        FAIL_NAMES+=("$name")
        printf '  FAIL %s\n    needle: %q\n    haystack: %q\n' \
            "$name" "$needle" "$haystack"
    fi
}

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS+1))
        echo "  ok  $name (exit $actual)"
    else
        FAIL=$((FAIL+1))
        FAIL_NAMES+=("$name")
        printf '  FAIL %s: expected exit %s, got %s\n' \
            "$name" "$expected" "$actual"
    fi
}

summary() {
    echo
    echo "── $SUITE summary: $PASS passed, $FAIL failed ──"
    if (( FAIL > 0 )); then
        printf '   failing: %s\n' "${FAIL_NAMES[@]}"
        exit 1
    fi
    exit 0
}
