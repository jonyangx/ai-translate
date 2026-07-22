#!/bin/bash

# Structural tests for install.sh (single /t skill model): heredoc content,
# variables, functions, and regression guards (legacy code removed, embedded
# cache.sh in sync).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
PASS=0
FAIL=0

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected '$needle'"; FAIL=$((FAIL + 1)); fi
}
assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -vq "$needle"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected NOT '$needle'"; FAIL=$((FAIL + 1)); fi
}
assert_non_empty() {
    local desc="$1" value="$2"
    if [ -n "$value" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected non-empty"; FAIL=$((FAIL + 1)); fi
}
assert_grep() {
    local desc="$1" needle="$2"
    if grep -q "$needle" "$INSTALL_SH"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected '$needle' in install.sh"; FAIL=$((FAIL + 1)); fi
}
assert_not_grep() {
    local desc="$1" needle="$2"
    if ! grep -q "$needle" "$INSTALL_SH"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — '$needle' should not be in install.sh"; FAIL=$((FAIL + 1)); fi
}

echo "=== Testing install.sh heredocs and structure ==="
echo ""

T_MD=$(sed -n '/^read -r -d .*.T_MD.*<< .PROMPT_EOF/,/^PROMPT_EOF$/p' "$INSTALL_SH" | sed '1d;$d')

test_t_md_exists() { assert_non_empty "T_MD heredoc is non-empty" "$T_MD"; }
test_format_sections() {
    assert_contains "T_MD contains 音标" "$T_MD" "音标"
    assert_contains "T_MD contains 词性" "$T_MD" "词性"
    assert_contains "T_MD contains 示例" "$T_MD" "示例"
    assert_contains "T_MD contains 翻译" "$T_MD" "翻译"
    assert_contains "T_MD contains tech term hint" "$T_MD" "编程或技术概念"
    assert_contains "T_MD contains 贪心算法" "$T_MD" "贪心算法"
    assert_contains "T_MD contains 闭包" "$T_MD" "闭包"
    assert_contains "T_MD contains 杂注" "$T_MD" "杂注"
}
test_t_md_is_pure_translate() {
    # T_MD is the shared translation-rules core; speech/cache live in the assembled bodies
    assert_not_contains "T_MD has no speech" "$T_MD" "say -v Samantha"
}
test_version() {
    local version
    version=$(grep -m1 '^VERSION=' "$INSTALL_SH" | sed 's/VERSION="\([^"]*\)"/\1/')
    if [ -n "$version" ]; then echo "  PASS: VERSION is '$version'"; PASS=$((PASS + 1)); else echo "  FAIL: VERSION not set"; FAIL=$((FAIL + 1)); fi
}
# Cache prompt snippets were folded into T_BODY inline; none should remain.
test_cache_prompts_removed() {
    local v
    for v in CACHE_CHECK_PROMPT CACHE_SAVE_PROMPT CACHE_REFRESH_PROMPT CACHE_STATS_PROMPT CACHE_CLEAR_PROMPT CACHE_REMOVE_PROMPT; do
        assert_not_grep "$v removed (merged into T_BODY)" "^$v="
    done
}
test_new_structure() {
    local v
    for v in T_DESC T_BODY T_FLAT_BODY CACHE_SH_PATH; do
        assert_grep "$v is defined" "^$v="
    done
    assert_grep "CACHE_SH_SRC heredoc defined" "read -r -d '' CACHE_SH_SRC"
}
test_build_skill_fn() { assert_grep "build_skill() is defined" "^build_skill()" ; }
test_install_functions() {
    local fn
    for fn in install_global_cache install_tool_skills install_tool_flat; do
        assert_grep "$fn() is defined" "^$fn()"
    done
}
# Everything from the multi-skill era must be gone.
test_legacy_removed() {
    assert_not_grep "no legacy *_SKILL variables" "^[A-Z_]*_SKILL="
    local fn
    for fn in install_flat install_skill install_skill_extra; do
        assert_not_grep "$fn() removed" "^$fn()"
    done
    local v
    for v in TS_DESC TC_DESC TS_BODY T_CACHE_BODY; do
        assert_not_grep "$v removed" "^$v="
    done
    # No standalone TS_MD heredoc — speech is inlined into the bodies
    if grep -q "read -r -d '' TS_MD" "$INSTALL_SH"; then
        echo "  FAIL: TS_MD heredoc should be removed"; FAIL=$((FAIL + 1))
    else
        echo "  PASS: no TS_MD heredoc"; PASS=$((PASS + 1))
    fi
}
test_embedded_cache_in_sync() {
    local embedded src
    embedded=$(sed -n "/<< 'CACHE_SH_EOF'/,/^CACHE_SH_EOF\$/p" "$INSTALL_SH" | sed '1d;$d')
    src=$(cat "$SCRIPT_DIR/scripts/cache.sh")
    if [ "$embedded" = "$src" ]; then
        echo "  PASS: embedded cache.sh is byte-identical to scripts/cache.sh"; PASS=$((PASS + 1))
    else
        echo "  FAIL: embedded cache.sh drifts from scripts/cache.sh"; FAIL=$((FAIL + 1))
    fi
}

test_t_md_exists
test_format_sections
test_t_md_is_pure_translate
test_version
test_cache_prompts_removed
test_new_structure
test_build_skill_fn
test_install_functions
test_legacy_removed
test_embedded_cache_in_sync

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
