#!/bin/bash

set -uo pipefail

INSTALL_SH="/Users/apple/opensource/ai-translate/install.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TEMP_DIRS=()

cleanup() {
    for d in "${TEMP_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

make_temp_dir() {
    local dir
    dir=$(mktemp -d)
    TEMP_DIRS+=("$dir")
    echo "$dir"
}

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

assert_file_contains() {
    local desc="$1" file="$2" needle="$3"
    if [ -f "$file" ] && grep -q "$needle" "$file"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected to find '$needle' in $file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_contains() {
    local desc="$1" file="$2" needle="$3"
    if [ -f "$file" ] && ! grep -q "$needle" "$file"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected NOT to find '$needle' in $file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — $file not found"
        FAIL=$((FAIL + 1))
    fi
}

# Run install.sh into a temp dir with mocked tool home.
# The install script checks $HOME/.claude, $HOME/.codex, etc.
run_install() {
    local mock_home
    mock_home=$(mktemp -d)
    TEMP_DIRS+=("$mock_home")

    mkdir -p "$mock_home/.claude"
    mkdir -p "$mock_home/.codex"
    mkdir -p "$mock_home/.config/opencode"
    mkdir -p "$mock_home/.cursor"
    mkdir -p "$mock_home/.codeium/windsurf"
    mkdir -p "$mock_home/.openclaw"
    mkdir -p "$mock_home/.hermes"

    HOME="$mock_home" DRY_RUN=0 bash "$INSTALL_SH" >/dev/null 2>&1

    echo "$mock_home"
}

# --- Extract T_MD / TS_MD from heredocs ---
T_MD=$(sed -n '/^read -r -d .*.T_MD.*<< .PROMPT_EOF/,/^PROMPT_EOF$/p' "$INSTALL_SH" | sed '1d;$d')
TS_MD=$(sed -n '/^read -r -d .*.TS_MD.*<< .PROMPT_EOF/,/^PROMPT_EOF$/p' "$INSTALL_SH" | sed '1d;$d')

echo "=== Testing skill file installation (via mocked install) ==="
echo ""

# Test 1: Claude Code skill files
test_claude_skills() {
    local home_dir
    home_dir=$(run_install)

    local t_sk="$home_dir/.claude/skills/t/SKILL.md"
    local ts_sk="$home_dir/.claude/skills/ts/SKILL.md"
    local refresh_sk="$home_dir/.claude/skills/t-refresh/SKILL.md"
    local stats_sk="$home_dir/.claude/skills/t-cache-stats/SKILL.md"
    local clear_sk="$home_dir/.claude/skills/t-cache-clear/SKILL.md"

    echo "--- Claude Code skills ---"
    assert_file_contains "t/SKILL.md has name: t" "$t_sk" "^name: t"
    assert_file_contains "t/SKILL.md has context: fork" "$t_sk" "context: fork"
    assert_file_contains "t/SKILL.md has allowed-tools" "$t_sk" 'allowed-tools'
    assert_file_contains "t/SKILL.md has translation prompt (音标)" "$t_sk" "音标"
    assert_file_contains "t/SKILL.md has cache check" "$t_sk" "cache.sh check"
    assert_file_contains "t/SKILL.md has cache save" "$t_sk" "cache.sh set"
    assert_file_contains "t/SKILL.md has tech term hint" "$t_sk" "贪心算法"
    assert_file_not_contains "t/SKILL.md has NO speech (say)" "$t_sk" "say -v Samantha"
    assert_file_exists "t/scripts/cache.sh exists" "$home_dir/.claude/skills/t/scripts/cache.sh"

    assert_file_contains "ts/SKILL.md has name: ts" "$ts_sk" "^name: ts"
    assert_file_contains "ts/SKILL.md has context: fork" "$ts_sk" "context: fork"
    assert_file_contains "ts/SKILL.md has speech (Samantha)" "$ts_sk" "say -v Samantha"
    assert_file_contains "ts/SKILL.md has tech term hint" "$ts_sk" "贪心算法"
    assert_file_contains "ts/SKILL.md has cache check" "$ts_sk" "cache.sh check"

    assert_file_contains "t-refresh has refresh prompt" "$refresh_sk" "cache.sh clear"
    assert_file_contains "t-cache-stats has stats prompt" "$stats_sk" "stats"
    assert_file_contains "t-cache-clear has clear prompt" "$clear_sk" "clear-all"
}

# Test 2: Codex skill files
test_codex_skills() {
    local home_dir
    home_dir=$(run_install)

    local t_sk="$home_dir/.codex/skills/t/SKILL.md"

    echo "--- Codex skills ---"
    assert_file_contains "Codex t/SKILL.md has name: t" "$t_sk" "^name: t"
    assert_file_not_contains "Codex t/SKILL.md has NO context: fork" "$t_sk" "context: fork"
    assert_file_contains "Codex t/SKILL.md has allowed-tools" "$t_sk" 'allowed-tools'
    assert_file_contains "Codex t/SKILL.md has cache check" "$t_sk" "cache.sh check"
    assert_file_contains "Codex t/SKILL.md has tech term hint" "$t_sk" "贪心算法"
    assert_file_not_contains "Codex t/SKILL.md has NO speech" "$t_sk" "say -v Samantha"
}

# Test 3: OpenCode flat files (mock ~/.config/opencode)
test_opencode_skills() {
    local home_dir
    home_dir=$(run_install)

    local opencode_t="$home_dir/.config/opencode/commands/t.md"
    local opencode_ts="$home_dir/.config/opencode/commands/ts.md"

    echo "--- OpenCode flat files ---"
    assert_file_contains "OpenCode t.md has translation prompt" "$opencode_t" "音标"
    assert_file_not_contains "OpenCode t.md has NO YAML frontmatter" "$opencode_t" "^---"
    assert_file_not_contains "OpenCode t.md has NO cache logic" "$opencode_t" "cache.sh"
    assert_file_contains "OpenCode t.md has tech term hint" "$opencode_t" "贪心算法"
    assert_file_not_contains "OpenCode t.md has NO speech" "$opencode_t" "say -v Samantha"

    assert_file_contains "OpenCode ts.md has speech (say)" "$opencode_ts" "say -v Samantha"
    assert_file_not_contains "OpenCode ts.md has NO YAML frontmatter" "$opencode_ts" "^---"
    assert_file_not_contains "OpenCode ts.md has NO cache logic" "$opencode_ts" "cache.sh"
    assert_file_contains "OpenCode ts.md has tech term hint" "$opencode_ts" "贪心算法"
}

# Test 4: Cursor flat files
test_cursor_skills() {
    local home_dir
    home_dir=$(run_install)

    local cursor_t="$home_dir/.cursor/commands/t.md"

    echo "--- Cursor flat files ---"
    assert_file_contains "Cursor t.md has name: t" "$cursor_t" "^name: t"
    assert_file_contains "Cursor t.md has translation prompt" "$cursor_t" "音标"
    assert_file_contains "Cursor t.md has YAML frontmatter" "$cursor_t" "^---"
    assert_file_not_contains "Cursor t.md has NO cache logic" "$cursor_t" "cache.sh"
}

# Test 5: Windsurf flat files
test_windsurf_skills() {
    local home_dir
    home_dir=$(run_install)

    local windsurf_ts="$home_dir/.codeium/windsurf/global_workflows/ts.md"

    echo "--- Windsurf flat files ---"
    assert_file_contains "Windsurf ts.md has name: ts" "$windsurf_ts" "^name: ts"
    assert_file_contains "Windsurf ts.md has speech (say)" "$windsurf_ts" "say -v Samantha"
    assert_file_contains "Windsurf ts.md has YAML frontmatter" "$windsurf_ts" "^---"
    assert_file_not_contains "Windsurf ts.md has NO cache logic" "$windsurf_ts" "cache.sh"
}

# Test 6: OpenClaw + Hermes (same format as Codex)
test_openclaw_hermes() {
    local home_dir
    home_dir=$(run_install)

    echo "--- OpenClaw + Hermes (Codex format) ---"
    assert_file_contains "OpenClaw t/SKILL.md has name: t" "$home_dir/.openclaw/skills/t/SKILL.md" "^name: t"
    assert_file_not_contains "OpenClaw t/SKILL.md has NO context: fork" "$home_dir/.openclaw/skills/t/SKILL.md" "context: fork"
    assert_file_contains "OpenClaw t/SKILL.md has cache check" "$home_dir/.openclaw/skills/t/SKILL.md" "cache.sh check"

    assert_file_contains "Hermes t/SKILL.md has name: t" "$home_dir/.hermes/skills/t/SKILL.md" "^name: t"
    assert_file_not_contains "Hermes t/SKILL.md has NO context: fork" "$home_dir/.hermes/skills/t/SKILL.md" "context: fork"
    assert_file_contains "Hermes t/SKILL.md has cache check" "$home_dir/.hermes/skills/t/SKILL.md" "cache.sh check"
}

# Test 7: Base prompt content correctness
test_prompt_content() {
    echo "--- Base prompt content ---"
    assert_contains "T_MD contains word format" "$T_MD" "音标"
    assert_contains "T_MD contains tech term hint" "$T_MD" "编程或技术概念"
    assert_contains "T_MD contains greedy algorithm" "$T_MD" "贪心算法"
    assert_contains "T_MD uses {current tool} placeholder" "$T_MD" "{当前工具名}"
    assert_contains "TS_MD contains speech command" "$TS_MD" "say -v Samantha"
    assert_contains "TS_MD contains tech term hint" "$TS_MD" "贪心算法"
    assert_contains "TS_MD contains espeak for Linux" "$TS_MD" "espeak"
    assert_contains "TS_MD contains PowerShell for Windows" "$TS_MD" "SpeechSynthesizer"
}

test_claude_skills
test_codex_skills
test_opencode_skills
test_cursor_skills
test_windsurf_skills
test_openclaw_hermes
test_prompt_content

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi