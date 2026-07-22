#!/bin/bash

# Installs install.sh into a mock HOME and asserts the single /t skill (and
# flat t.md) for every supported tool, plus regression guards for the global
# cache and the removal of all legacy skills (ts, t-cache, t-refresh, ...).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
PASS=0
FAIL=0
TEMP_DIRS=()

cleanup() {
    for d in ${TEMP_DIRS[@]+"${TEMP_DIRS[@]}"}; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected '$needle'"; FAIL=$((FAIL + 1)); fi
}
assert_file_contains() {
    local desc="$1" file="$2" needle="$3"
    if [ -f "$file" ] && grep -q "$needle" "$file"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected '$needle' in $file"; FAIL=$((FAIL + 1)); fi
}
assert_file_not_contains() {
    local desc="$1" file="$2" needle="$3"
    if [ -f "$file" ] && ! grep -q "$needle" "$file"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected NOT '$needle' in $file"; FAIL=$((FAIL + 1)); fi
}
assert_file_exists() {
    local desc="$1" file="$2"
    if [ -f "$file" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — $file not found"; FAIL=$((FAIL + 1)); fi
}
assert_file_not_exists() {
    local desc="$1" file="$2"
    if [ ! -e "$file" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — $file should not exist"; FAIL=$((FAIL + 1)); fi
}
assert_file_not_contains_fixed() {
    local desc="$1" file="$2" needle="$3"
    if [ -f "$file" ] && ! grep -qF "$needle" "$file"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected NOT fixed '$needle' in $file"; FAIL=$((FAIL + 1)); fi
}
assert_file_contains_fixed() {
    local desc="$1" file="$2" needle="$3"
    if [ -f "$file" ] && grep -qF "$needle" "$file"; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc — expected fixed '$needle' in $file"; FAIL=$((FAIL + 1)); fi
}

# Sets global LAST_HOME. Must NOT be invoked via command substitution.
run_install() {
    LAST_HOME=$(mktemp -d)
    TEMP_DIRS+=("$LAST_HOME")
    mkdir -p "$LAST_HOME/.claude" "$LAST_HOME/.codex" "$LAST_HOME/.config/opencode" \
             "$LAST_HOME/.cursor" "$LAST_HOME/.codeium/windsurf" "$LAST_HOME/.openclaw" "$LAST_HOME/.hermes"
    HOME="$LAST_HOME" DRY_RUN=0 bash "$INSTALL_SH" >/dev/null 2>&1
}

T_MD=$(sed -n '/^read -r -d .*.T_MD.*<< .PROMPT_EOF/,/^PROMPT_EOF$/p' "$INSTALL_SH" | sed '1d;$d')

echo "=== Testing single /t skill installation (mocked) ==="
echo ""

# Test 1: Claude Code — single /t skill with translate + say + cache dispatch
test_claude_skill() {
    run_install; local h="$LAST_HOME"
    local t_sk="$h/.claude/skills/t/SKILL.md"
    echo "--- Claude Code ---"
    assert_file_contains "t/SKILL.md name: t" "$t_sk" "^name: t"
    assert_file_contains "t/SKILL.md context: fork" "$t_sk" "context: fork"
    assert_file_contains "t/SKILL.md allowed-tools" "$t_sk" 'allowed-tools'
    assert_file_contains "t/SKILL.md translation rule (音标)" "$t_sk" "音标"
    assert_file_contains "t/SKILL.md cache check" "$t_sk" "cache.sh check"
    assert_file_contains "t/SKILL.md cache set" "$t_sk" "cache.sh set"
    assert_file_contains "t/SKILL.md say branch" "$t_sk" "say -v Samantha"
    assert_file_contains "t/SKILL.md cache stats subcommand" "$t_sk" "cache stats"
    assert_file_contains "t/SKILL.md cache refresh subcommand" "$t_sk" "cache refresh"
    assert_file_contains "t/SKILL.md tech term (贪心算法)" "$t_sk" "贪心算法"
    # P0-2 guard: absolute path, never ./scripts/cache.sh
    assert_file_not_contains_fixed "t/SKILL.md no relative ./scripts" "$t_sk" "./scripts/cache.sh"
    assert_file_contains_fixed "t/SKILL.md uses global path" "$t_sk" ".ai-translate/cache.sh"
    # Merge guard: no separate skills
    assert_file_not_exists "no ts skill" "$h/.claude/skills/ts"
    assert_file_not_exists "no t-cache skill" "$h/.claude/skills/t-cache"
    assert_file_not_exists "no t-refresh skill" "$h/.claude/skills/t-refresh"
}

# Test 2: Global shared cache.sh, installed once, identical to source
test_global_cache() {
    run_install; local h="$LAST_HOME"
    echo "--- Global cache.sh ---"
    assert_file_exists "~/.ai-translate/cache.sh exists" "$h/.ai-translate/cache.sh"
    if diff -q "$h/.ai-translate/cache.sh" "$SCRIPT_DIR/scripts/cache.sh" >/dev/null; then
        echo "  PASS: global cache.sh identical to source"; PASS=$((PASS + 1))
    else
        echo "  FAIL: global cache.sh differs from source"; FAIL=$((FAIL + 1))
    fi
    assert_file_not_exists "t/ has no scripts/cache.sh copy" "$h/.claude/skills/t/scripts/cache.sh"
}

# Test 3: Codex — single /t, no context: fork
test_codex_skill() {
    run_install; local h="$LAST_HOME"
    local t_sk="$h/.codex/skills/t/SKILL.md"
    echo "--- Codex ---"
    assert_file_contains "Codex t name: t" "$t_sk" "^name: t"
    assert_file_not_contains "Codex t NO context: fork" "$t_sk" "context: fork"
    assert_file_contains "Codex t allowed-tools" "$t_sk" 'allowed-tools'
    assert_file_contains "Codex t say branch" "$t_sk" "say -v Samantha"
    assert_file_contains "Codex t cache subcommand" "$t_sk" "cache stats"
    assert_file_not_exists "Codex no ts skill" "$h/.codex/skills/ts"
    assert_file_not_exists "Codex no t-cache skill" "$h/.codex/skills/t-cache"
}

# Test 4: OpenCode flat — single t.md, raw (no frontmatter), say yes, cache no
test_opencode_skill() {
    run_install; local h="$LAST_HOME"
    local t="$h/.config/opencode/commands/t.md"
    echo "--- OpenCode ---"
    assert_file_contains "OpenCode t.md translation prompt" "$t" "音标"
    assert_file_not_contains "OpenCode t.md NO frontmatter" "$t" "^---"
    assert_file_contains "OpenCode t.md has say" "$t" "say -v Samantha"
    assert_file_not_contains "OpenCode t.md NO cache" "$t" "cache stats"
    assert_file_not_exists "OpenCode no ts.md" "$h/.config/opencode/commands/ts.md"
}

# Test 5: Cursor flat — single t.md with frontmatter
test_cursor_skill() {
    run_install; local h="$LAST_HOME"
    local t="$h/.cursor/commands/t.md"
    echo "--- Cursor ---"
    assert_file_contains "Cursor t.md name: t" "$t" "^name: t"
    assert_file_contains "Cursor t.md frontmatter" "$t" "^---"
    assert_file_contains "Cursor t.md has say" "$t" "say -v Samantha"
    assert_file_not_contains "Cursor t.md NO cache" "$t" "cache stats"
    assert_file_not_exists "Cursor no ts.md" "$h/.cursor/commands/ts.md"
}

# Test 6: Windsurf flat
test_windsurf_skill() {
    run_install; local h="$LAST_HOME"
    local t="$h/.codeium/windsurf/global_workflows/t.md"
    echo "--- Windsurf ---"
    assert_file_contains "Windsurf t.md name: t" "$t" "^name: t"
    assert_file_contains "Windsurf t.md has say" "$t" "say -v Samantha"
    assert_file_not_contains "Windsurf t.md NO cache" "$t" "cache stats"
    assert_file_not_exists "Windsurf no ts.md" "$h/.codeium/windsurf/global_workflows/ts.md"
}

# Test 7: OpenClaw + Hermes (Codex format)
test_openclaw_hermes() {
    run_install; local h="$LAST_HOME"
    echo "--- OpenClaw + Hermes ---"
    assert_file_contains "OpenClaw t name: t" "$h/.openclaw/skills/t/SKILL.md" "^name: t"
    assert_file_not_contains "OpenClaw t NO context: fork" "$h/.openclaw/skills/t/SKILL.md" "context: fork"
    assert_file_contains "OpenClaw t cache" "$h/.openclaw/skills/t/SKILL.md" "cache stats"
    assert_file_not_exists "OpenClaw no ts" "$h/.openclaw/skills/ts"
    assert_file_contains "Hermes t name: t" "$h/.hermes/skills/t/SKILL.md" "^name: t"
    assert_file_not_contains "Hermes t NO context: fork" "$h/.hermes/skills/t/SKILL.md" "context: fork"
    assert_file_contains "Hermes t cache" "$h/.hermes/skills/t/SKILL.md" "cache stats"
    assert_file_not_exists "Hermes no ts" "$h/.hermes/skills/ts"
}

# Test 8: Base prompt content
test_prompt_content() {
    echo "--- Base prompt content ---"
    assert_contains "T_MD word format" "$T_MD" "音标"
    assert_contains "T_MD tech term hint" "$T_MD" "编程或技术概念"
    assert_contains "T_MD greedy algorithm" "$T_MD" "贪心算法"
    assert_contains "T_MD {current tool} placeholder" "$T_MD" "{当前工具名}"
}

test_claude_skill
test_global_cache
test_codex_skill
test_opencode_skill
test_cursor_skill
test_windsurf_skill
test_openclaw_hermes
test_prompt_content

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
