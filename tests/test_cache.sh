#!/bin/bash

# Test suite for scripts/cache.sh
# Each test gets a fresh temp directory as the data dir.

set -uo pipefail

CACHE_SRC="/Users/apple/opensource/ai-translate/scripts/cache.sh"
PASS=0
FAIL=0
TEMP_DIRS=()

cleanup() {
    for d in "${TEMP_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

# Create a temp copy of cache.sh with DATA_DIR overridden to the given directory.
make_wrapper() {
    local target_data_dir="$1"
    local wrapper="$TEST_TMPDIR/cache_wrapper.sh"
    sed "s|DATA_DIR=.*|DATA_DIR=\"$target_data_dir\"|" "$CACHE_SRC" > "$wrapper"
    chmod +x "$wrapper"
    echo "$wrapper"
}

# Run a cache command, capturing stdout and exit code.
# Usage: run_cache <wrapper> <command> [args...]
# Sets: RUN_STDOUT, RUN_EXIT
run_cache() {
    local wrapper="$1"; shift
    # Filter out "wal" from PRAGMA journal_mode output in init_db
    RUN_STDOUT=$(bash "$wrapper" "$@" 2>/dev/null | grep -v "^wal$") && RUN_EXIT=0 || RUN_EXIT=$?
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

# --- setup: fresh temp dir for each test ---
setup() {
    TEST_TMPDIR=$(mktemp -d)
    TEMP_DIRS+=("$TEST_TMPDIR")
    WRAPPER=$(make_wrapper "$TEST_TMPDIR")
}

# --- Tests ---

test_check_miss() {
    setup
    run_cache "$WRAPPER" check "nonexistent"
    assert_eq "check nonexistent key returns miss" "miss" "$RUN_STDOUT"
}

test_set_and_get() {
    setup
    run_cache "$WRAPPER" set "hello" "hello" "world response"
    run_cache "$WRAPPER" get "hello"
    assert_eq "set then get returns saved response" "world response" "$RUN_STDOUT"
}

test_case_insensitive() {
    setup
    run_cache "$WRAPPER" set "Hello" "Hello" "greeting response"
    run_cache "$WRAPPER" check "hello"
    assert_eq "check 'hello' after set 'Hello' returns hit" "hit" "$RUN_STDOUT"
    run_cache "$WRAPPER" check "HELLO"
    assert_eq "check 'HELLO' after set 'Hello' returns hit" "hit" "$RUN_STDOUT"
}

test_set_overwrite() {
    setup
    run_cache "$WRAPPER" set "word" "word" "first"
    run_cache "$WRAPPER" set "word" "word" "second"
    run_cache "$WRAPPER" get "word"
    assert_eq "set twice, get returns latest value" "second" "$RUN_STDOUT"
}

test_clear_single() {
    setup
    run_cache "$WRAPPER" set "alpha" "alpha" "response_a"
    run_cache "$WRAPPER" set "beta" "beta" "response_b"
    run_cache "$WRAPPER" clear "alpha"
    assert_eq "clear single key returns cleared" "cleared" "$RUN_STDOUT"
    run_cache "$WRAPPER" check "alpha"
    assert_eq "cleared key is gone (miss)" "miss" "$RUN_STDOUT"
    run_cache "$WRAPPER" check "beta"
    assert_eq "other key still present (hit)" "hit" "$RUN_STDOUT"
}

test_clear_all() {
    setup
    run_cache "$WRAPPER" set "one" "one" "resp1"
    run_cache "$WRAPPER" set "two" "two" "resp2"
    run_cache "$WRAPPER" clear-all
    assert_eq "clear-all returns cleared all" "cleared all" "$RUN_STDOUT"
    run_cache "$WRAPPER" check "one"
    assert_eq "after clear-all, key 'one' is miss" "miss" "$RUN_STDOUT"
    run_cache "$WRAPPER" check "two"
    assert_eq "after clear-all, key 'two' is miss" "miss" "$RUN_STDOUT"
}

test_stats() {
    setup
    run_cache "$WRAPPER" set "foo" "foo" "bar"
    run_cache "$WRAPPER" set "baz" "baz" "qux"
    run_cache "$WRAPPER" stats
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
    # It extracts the English word after the **【...】** pattern.
    # Chinese input triggers expansion (original must contain Chinese characters)
    local response='**【短暂的】** ephemeral /ɪˈfemərəl/'
    run_cache "$WRAPPER" set "短暂的" "短暂的" "$response"
    assert_eq "set returns saved" "saved" "$RUN_STDOUT"

    # The English word "ephemeral" should also be cached
    run_cache "$WRAPPER" check "ephemeral"
    assert_eq "expanded English word 'ephemeral' is cached (hit)" "hit" "$RUN_STDOUT"

    run_cache "$WRAPPER" get "ephemeral"
    assert_eq "expanded entry has correct response" "$response" "$RUN_STDOUT"
}

test_refresh() {
    setup
    run_cache "$WRAPPER" set "word" "word" "old value"
    run_cache "$WRAPPER" refresh "word" "word" "new value"
    assert_eq "refresh returns refreshed" "refreshed" "$RUN_STDOUT"
    run_cache "$WRAPPER" get "word"
    assert_eq "after refresh, get returns new value" "new value" "$RUN_STDOUT"
}

# --- Run all tests ---
echo "Running cache.sh tests..."
echo ""
test_check_miss
test_set_and_get
test_case_insensitive
test_set_overwrite
test_clear_single
test_clear_all
test_stats
test_multi_word_expansion
test_refresh
echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
