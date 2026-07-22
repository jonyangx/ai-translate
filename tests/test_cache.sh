#!/bin/bash

# Test suite for scripts/cache.sh
# Each test gets a fresh data dir via AI_TRANSLATE_DATA_DIR — the real script is
# exercised unchanged (no sed patching), so this validates actual behavior.

set -uo pipefail

CACHE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/cache.sh"
PASS=0
FAIL=0
TEMP_DIRS=()

cleanup() {
    for d in "${TEMP_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

# Run a cache command against the current test data dir, capturing stdout and exit code.
# Usage: run_cache <command> [args...]
# Sets: RUN_STDOUT, RUN_EXIT
run_cache() {
    RUN_STDOUT=$(AI_TRANSLATE_DATA_DIR="$TEST_DATA_DIR" bash "$CACHE_SRC" "$@" 2>/dev/null) && RUN_EXIT=0 || RUN_EXIT=$?
}

# Query the raw DB directly (bypass cache.sh) to verify internal state.
raw_query() {
    AI_TRANSLATE_DATA_DIR="$TEST_DATA_DIR" sqlite3 "$TEST_DATA_DIR/cache.db" "$1" 2>/dev/null
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc -- expected '$expected', got '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_empty() {
    local desc="$1" actual="$2"
    if [ -n "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc -- expected non-empty, got empty"
        FAIL=$((FAIL + 1))
    fi
}

# --- setup: fresh temp data dir for each test ---
setup() {
    TEST_DATA_DIR=$(mktemp -d)
    TEMP_DIRS+=("$TEST_DATA_DIR")
}

# --- Tests ---

test_check_miss() {
    setup
    run_cache check "nonexistent"
    assert_eq "check nonexistent key returns miss" "miss" "$RUN_STDOUT"
}

test_no_wal_leak() {
    setup
    # First-ever command creates the DB; stdout must be exactly "miss", not "wal\nmiss".
    run_cache check "anything"
    assert_eq "first-run check does not leak 'wal' to stdout" "miss" "$RUN_STDOUT"
}

test_set_and_get() {
    setup
    run_cache set "hello" "hello" "world response"
    run_cache get "hello"
    assert_eq "set then get returns saved response" "world response" "$RUN_STDOUT"
}

test_case_insensitive() {
    setup
    run_cache set "Hello" "Hello" "greeting response"
    run_cache check "hello"
    assert_eq "check 'hello' after set 'Hello' returns hit" "hit" "$RUN_STDOUT"
    run_cache check "HELLO"
    assert_eq "check 'HELLO' after set 'Hello' returns hit" "hit" "$RUN_STDOUT"
}

test_set_overwrite() {
    setup
    run_cache set "word" "word" "first"
    run_cache set "word" "word" "second"
    run_cache get "word"
    assert_eq "set twice, get returns latest value" "second" "$RUN_STDOUT"
}

test_clear_single() {
    setup
    run_cache set "alpha" "alpha" "response_a"
    run_cache set "beta" "beta" "response_b"
    run_cache clear "alpha"
    assert_eq "clear single key returns cleared" "cleared" "$RUN_STDOUT"
    run_cache check "alpha"
    assert_eq "cleared key is gone (miss)" "miss" "$RUN_STDOUT"
    run_cache check "beta"
    assert_eq "other key still present (hit)" "hit" "$RUN_STDOUT"
}

test_clear_all() {
    setup
    run_cache set "one" "one" "resp1"
    run_cache set "two" "two" "resp2"
    run_cache clear-all
    assert_eq "clear-all returns cleared all" "cleared all" "$RUN_STDOUT"
    run_cache check "one"
    assert_eq "after clear-all, key 'one' is miss" "miss" "$RUN_STDOUT"
    run_cache check "two"
    assert_eq "after clear-all, key 'two' is miss" "miss" "$RUN_STDOUT"
}

test_stats() {
    setup
    run_cache set "foo" "foo" "bar"
    run_cache set "baz" "baz" "qux"
    run_cache stats
    assert_not_empty "stats returns non-empty output" "$RUN_STDOUT"
    # Verify count = 2
    echo "$RUN_STDOUT" | grep -q "Cache entries: 2"
    if [ $? -eq 0 ]; then
        echo "  PASS: stats shows correct count (2)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: stats shows correct count (2) -- expected 'Cache entries: 2' in '$RUN_STDOUT'"
        FAIL=$((FAIL + 1))
    fi
}

test_multi_word_expansion() {
    setup
    # The extract_english_words function matches: **【短暂的】** ephemeral /ɪˈfemərəl/
    # Chinese input triggers expansion (original must contain Chinese characters)
    local response='**【短暂的】** ephemeral /ɪˈfemərəl/'
    run_cache set "短暂的" "短暂的" "$response"
    assert_eq "set returns saved" "saved" "$RUN_STDOUT"

    # The English word "ephemeral" should also be cached
    run_cache check "ephemeral"
    assert_eq "expanded English word 'ephemeral' is cached (hit)" "hit" "$RUN_STDOUT"

    run_cache get "ephemeral"
    assert_eq "expanded entry has correct response" "$response" "$RUN_STDOUT"
}

test_refresh() {
    setup
    run_cache set "word" "word" "old value"
    run_cache refresh "word" "word" "new value"
    assert_eq "refresh returns refreshed" "refreshed" "$RUN_STDOUT"
    run_cache get "word"
    assert_eq "after refresh, get returns new value" "new value" "$RUN_STDOUT"
}

test_refresh_marks_source() {
    setup
    run_cache refresh "word" "word" "fresh value"
    assert_eq "refresh marks source as refreshed" "refreshed" "$(raw_query "SELECT source FROM translations WHERE input_key='word';")"
}

test_default_db_location() {
    # DATA_DIR must NOT depend on SCRIPT_DIR/CWD — verify the script honors the env override.
    setup
    run_cache set "loc" "loc" "v"
    [ -f "$TEST_DATA_DIR/cache.db" ]
    if [ $? -eq 0 ]; then
        echo "  PASS: DB is created under AI_TRANSLATE_DATA_DIR, not relative to CWD"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: DB not found under AI_TRANSLATE_DATA_DIR"
        FAIL=$((FAIL + 1))
    fi
}

# --- Run all tests ---
echo "Running cache.sh tests..."
echo ""
test_check_miss
test_no_wal_leak
test_set_and_get
test_case_insensitive
test_set_overwrite
test_clear_single
test_clear_all
test_stats
test_multi_word_expansion
test_refresh
test_refresh_marks_source
test_default_db_location
echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
