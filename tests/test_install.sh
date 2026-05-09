#!/bin/bash

set -uo pipefail

INSTALL_SH="/Users/apple/opensource/ai-translate/install.sh"
PASS=0
FAIL=0

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected to find '$needle'"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -vq "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected NOT to find '$needle'"
        FAIL=$((FAIL + 1))
    fi
}

assert_non_empty() {
    local desc="$1" value="$2"
    if [ -n "$value" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected non-empty"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Testing install.sh heredocs and format generation ==="
echo ""

# Extract T_MD heredoc content
T_MD=$(sed -n '/^read -r -d .*.T_MD.*<< .PROMPT_EOF/,/^PROMPT_EOF$/p' "$INSTALL_SH" | sed '1d;$d')
TS_MD=$(sed -n '/^read -r -d .*.TS_MD.*<< .PROMPT_EOF/,/^PROMPT_EOF$/p' "$INSTALL_SH" | sed '1d;$d')

# --- Heredoc tests ---
test_t_md_exists() {
    assert_non_empty "T_MD heredoc is non-empty" "$T_MD"
}
test_ts_md_exists() {
    assert_non_empty "TS_MD heredoc is non-empty" "$TS_MD"
}
test_format_sections() {
    assert_contains "T_MD contains word format (音标)" "$T_MD" "音标"
    assert_contains "T_MD contains pos (词性)" "$T_MD" "词性"
    assert_contains "T_MD contains example (示例)" "$T_MD" "示例"
    assert_contains "T_MD contains translation (翻译)" "$T_MD" "翻译"
    assert_contains "T_MD contains tech term hint" "$T_MD" "编程或技术概念"
    assert_contains "T_MD contains disambiguation entries" "$T_MD" "贪心算法"
    assert_contains "T_MD contains closure translation" "$T_MD" "闭包"
}
test_ts_md_speech() {
    assert_contains "TS_MD contains macOS say command" "$TS_MD" "say -v Samantha"
    assert_contains "TS_MD contains Linux espeak command" "$TS_MD" "espeak"
    assert_contains "TS_MD contains Windows PowerShell command" "$TS_MD" "SpeechSynthesizer"
    assert_contains "TS_MD contains tech term hint" "$TS_MD" "编程或技术概念"
    assert_contains "TS_MD contains greedy algorithm disambiguation" "$TS_MD" "贪心算法"
}
test_no_tool_names_in_base() {
    assert_not_contains "T_MD does not hardcode tool names" "$T_MD" "Claude Code 内部命令"
    assert_contains "T_MD uses placeholder for tool name" "$T_MD" "{当前工具名}"
}
test_no_speech_in_t() {
    assert_not_contains "T_MD does not contain speech commands" "$T_MD" "say -v Samantha"
    assert_not_contains "T_MD does not contain espeak" "$T_MD" "espeak"
}

# --- Version test ---
test_version() {
    local version
    version=$(grep -m1 '^VERSION=' "$INSTALL_SH" | sed 's/VERSION="\([^"]*\)"/\1/')
    if [ -n "$version" ]; then
        echo "  PASS: VERSION is set to '$version'"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: VERSION is not set"
        FAIL=$((FAIL + 1))
    fi
}

# --- Cache prompt variables ---
test_cache_prompts() {
    local vars="CACHE_CHECK_PROMPT CACHE_SAVE_PROMPT CACHE_REFRESH_PROMPT CACHE_STATS_PROMPT CACHE_CLEAR_PROMPT"
    for v in $vars; do
        if grep -q "^$v=" "$INSTALL_SH"; then
            echo "  PASS: $v is defined"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $v is missing"
            FAIL=$((FAIL + 1))
        fi
    done
}

# --- Skill format variables ---
test_skill_formats() {
    local formats="CLAUDE_T_SKILL CLAUDE_TS_SKILL CODEX_T_SKILL CODEX_TS_SKILL BASIC_T_SKILL BASIC_TS_SKILL"
    formats="$formats CLAUDE_T_REFRESH_SKILL CODEX_T_REFRESH_SKILL"
    formats="$formats CLAUDE_CACHE_STATS_SKILL CODEX_CACHE_STATS_SKILL"
    formats="$formats CLAUDE_CACHE_CLEAR_SKILL CODEX_CACHE_CLEAR_SKILL"
    for f in $formats; do
        if grep -q "^$f=" "$INSTALL_SH"; then
            echo "  PASS: $f is defined"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $f is missing"
            FAIL=$((FAIL + 1))
        fi
    done
}

# --- Install functions ---
test_install_functions() {
    local funcs="install_flat install_skill install_skill_extra"
    for fn in $funcs; do
        if grep -q "^$fn()" "$INSTALL_SH"; then
            echo "  PASS: $fn() is defined"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $fn() is missing"
            FAIL=$((FAIL + 1))
        fi
    done
}

# --- Run all tests ---
test_t_md_exists
test_ts_md_exists
test_format_sections
test_ts_md_speech
test_no_tool_names_in_base
test_no_speech_in_t
test_version
test_cache_prompts
test_skill_formats
test_install_functions

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi