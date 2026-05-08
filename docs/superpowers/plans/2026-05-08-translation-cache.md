# Translation Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a SQLite-based caching layer to the ai-translate skill that stores translation results, avoids redundant LLM calls, and provides visual indicators for cached vs AI results.

**Architecture:** A shell script (`scripts/cache.sh`) handles all SQLite operations. Modified skill files instruct the AI to call cache.sh via Bash tool before/after LLM calls. Cache entries use normalized (lowercase, trimmed) input as keys. Chinese→English multi-word responses create individual cache entries per English word.

**Tech Stack:** Bash, SQLite3 CLI, shell scripting

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `scripts/cache.sh` | Cache manager: check/get/set/clear/stats/refresh |
| Create | `tests/test_cache.sh` | Unit tests for all cache operations |
| Modify | `install.sh` | Updated prompts, install_skill, version bump |

---

### Task 1: Create cache.sh — Core Infrastructure

**Files:**
- Create: `scripts/cache.sh`

- [ ] **Step 1: Create cache.sh with shebang, constants, and init_db**

```bash
#!/bin/bash

# ai-translate cache manager
# Manages SQLite-based translation cache

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
DB_PATH="$DATA_DIR/cache.db"

normalize_input() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

init_db() {
    if ! command -v sqlite3 &>/dev/null; then
        echo "error: sqlite3 not found" >&2
        return 1
    fi
    mkdir -p "$DATA_DIR"
    if [ ! -f "$DB_PATH" ]; then
        sqlite3 "$DB_PATH" <<'SQL'
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
CREATE TABLE IF NOT EXISTS translations (
    input_key TEXT PRIMARY KEY,
    original_input TEXT NOT NULL,
    response TEXT NOT NULL,
    translated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source TEXT DEFAULT 'ai'
);
SQL
    fi
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/cache.sh`
Expected: No output (clean syntax)

- [ ] **Step 3: Commit**

```bash
git add scripts/cache.sh
git commit -m "feat(cache): add cache.sh core infrastructure — init_db and normalize"
```

---

### Task 2: Add check and get commands

**Files:**
- Modify: `scripts/cache.sh`

- [ ] **Step 1: Add cmd_check function**

Append to `scripts/cache.sh`:

```bash
cmd_check() {
    local key
    key="$(normalize_input "$1")"
    init_db || return 1
    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM translations WHERE input_key = '$(sqlite3_escape "$key")';")
    if [ "$count" -gt 0 ]; then
        echo "hit"
    else
        echo "miss"
    fi
}
```

- [ ] **Step 2: Add cmd_get function**

Append to `scripts/cache.sh`:

```bash
cmd_get() {
    local key
    key="$(normalize_input "$1")"
    init_db || return 1
    local result
    result=$(sqlite3 "$DB_PATH" "SELECT response FROM translations WHERE input_key = '$(sqlite3_escape "$key")';")
    if [ -n "$result" ]; then
        echo "$result"
    else
        echo ""
        return 1
    fi
}
```

- [ ] **Step 3: Add sqlite3_escape helper and command dispatcher**

Append to `scripts/cache.sh`:

```bash
sqlite3_escape() {
    echo "$1" | sed "s/'/''/g"
}

# --- command dispatcher ---
case "${1:-}" in
    check)
        cmd_check "$2"
        ;;
    get)
        cmd_get "$2"
        ;;
    *)
        echo "Usage: cache.sh <check|get|set|clear|clear-all|stats|refresh> [args]" >&2
        exit 1
        ;;
esac
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n scripts/cache.sh`
Expected: No output (clean syntax)

- [ ] **Step 5: Manual smoke test**

```bash
mkdir -p scripts
bash scripts/cache.sh check "hello"
```

Expected: Either `miss` (if DB doesn't exist yet, it will be created) or `error` message.

- [ ] **Step 6: Commit**

```bash
git add scripts/cache.sh
git commit -m "feat(cache): add check and get commands"
```

---

### Task 3: Add set command with multi-word expansion

**Files:**
- Modify: `scripts/cache.sh`

- [ ] **Step 1: Add cmd_set function**

Insert before the command dispatcher in `scripts/cache.sh`:

```bash
extract_english_words() {
    local response="$1"
    # Match pattern: **【中文词】** english_word1, english_word2 /音标/
    # or: **【中文词】** english_word /音标/
    echo "$response" | grep -oE '\*\*【[^】]+】\*\*[^`/]*' | head -1 | \
        sed 's/\*\*【[^】]*】\*\*[[:space:]]*//' | \
        sed 's/[[:space:]]*$//' | \
        tr ',' '\n' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -E '^[a-zA-Z]'
}

cmd_set() {
    local key original response
    key="$(normalize_input "$1")"
    original="$2"
    response="$3"

    init_db || return 1

    local escaped_key escaped_orig escaped_resp
    escaped_key="$(sqlite3_escape "$key")"
    escaped_orig="$(sqlite3_escape "$original")"
    escaped_resp="$(sqlite3_escape "$response")"

    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO translations (input_key, original_input, response, translated_at, source) VALUES ('$escaped_key', '$escaped_orig', '$escaped_resp', CURRENT_TIMESTAMP, 'ai');"

    # Multi-word expansion: if Chinese input, extract English words and create individual entries
    if echo "$original" | grep -qE '[\x{4e00}-\x{9fff}]'; then
        local english_words
        english_words="$(extract_english_words "$response")"
        if [ -n "$english_words" ]; then
            while IFS= read -r word; do
                [ -z "$word" ] && continue
                local norm_word
                norm_word="$(normalize_input "$word")"
                local escaped_word escaped_word_resp
                escaped_word="$(sqlite3_escape "$norm_word")"
                escaped_word_resp="$(sqlite3_escape "$response")"
                sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO translations (input_key, original_input, response, translated_at, source) VALUES ('$escaped_word', '$word', '$escaped_word_resp', CURRENT_TIMESTAMP, 'expanded');"
            done <<< "$english_words"
        fi
    fi

    echo "saved"
}
```

- [ ] **Step 2: Add set to command dispatcher**

Update the dispatcher case block — add before `*)`:

```bash
    set)
        cmd_set "$2" "$3" "$4"
        ;;
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n scripts/cache.sh`
Expected: No output (clean syntax)

- [ ] **Step 4: Manual smoke test**

```bash
bash scripts/cache.sh set "hello" "hello" "**【hello】** /həˈloʊ/ interj. 你好"
bash scripts/cache.sh check "hello"
```

Expected: `saved` then `hit`

- [ ] **Step 5: Commit**

```bash
git add scripts/cache.sh
git commit -m "feat(cache): add set command with multi-word expansion"
```

---

### Task 4: Add clear, clear-all, stats, refresh commands

**Files:**
- Modify: `scripts/cache.sh`

- [ ] **Step 1: Add remaining command functions**

Insert before the command dispatcher in `scripts/cache.sh`:

```bash
cmd_clear() {
    local key
    key="$(normalize_input "$1")"
    init_db || return 1
    local escaped_key
    escaped_key="$(sqlite3_escape "$key")"
    sqlite3 "$DB_PATH" "DELETE FROM translations WHERE input_key = '$escaped_key';"
    echo "cleared"
}

cmd_clear_all() {
    init_db || return 1
    sqlite3 "$DB_PATH" "DELETE FROM translations;"
    echo "cleared all"
}

cmd_stats() {
    init_db || return 1
    local count last_updated
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM translations;")
    last_updated=$(sqlite3 "$DB_PATH" "SELECT MAX(translated_at) FROM translations;" 2>/dev/null || echo "N/A")
    [ -z "$last_updated" ] && last_updated="N/A"
    echo "Cache entries: $count | Last updated: $last_updated"
}

cmd_refresh() {
    local key original response
    key="$(normalize_input "$1")"
    original="$2"
    response="$3"
    init_db || return 1
    local escaped_key
    escaped_key="$(sqlite3_escape "$key")"
    sqlite3 "$DB_PATH" "DELETE FROM translations WHERE input_key = '$escaped_key';"
    # Re-use set logic, suppress "saved" output
    cmd_set "$1" "$2" "$3" >/dev/null
    echo "refreshed"
}
```

- [ ] **Step 2: Update command dispatcher**

The full dispatcher should now be:

```bash
case "${1:-}" in
    check)
        cmd_check "$2"
        ;;
    get)
        cmd_get "$2"
        ;;
    set)
        cmd_set "$2" "$3" "$4"
        ;;
    clear)
        cmd_clear "$2"
        ;;
    clear-all)
        cmd_clear_all
        ;;
    stats)
        cmd_stats
        ;;
    refresh)
        cmd_refresh "$2" "$3" "$4"
        ;;
    *)
        echo "Usage: cache.sh <check|get|set|clear|clear-all|stats|refresh> [args]" >&2
        exit 1
        ;;
esac
```

- [ ] **Step 3: Verify syntax and test**

```bash
bash -n scripts/cache.sh
bash scripts/cache.sh stats
bash scripts/cache.sh clear-all
bash scripts/cache.sh stats
```

Expected: syntax clean, then stats showing entries, `cleared all`, then `Cache entries: 0`

- [ ] **Step 4: Commit**

```bash
git add scripts/cache.sh
git commit -m "feat(cache): add clear, clear-all, stats, refresh commands"
```

---

### Task 5: Create test script

**Files:**
- Create: `tests/test_cache.sh`

- [ ] **Step 1: Write the test script**

```bash
#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_SH="$SCRIPT_DIR/../scripts/cache.sh"
TEST_DB_DIR=""

PASS=0
FAIL=0

cleanup() {
    if [ -n "$TEST_DB_DIR" ]; then
        rm -rf "$TEST_DB_DIR"
    fi
}
trap cleanup EXIT

setup() {
    TEST_DB_DIR=$(mktemp -d)
    # Override DATA_DIR for testing
    export CACHE_TEST_DATA_DIR="$TEST_DB_DIR"
    # We need to override DB_PATH in cache.sh — use a wrapper approach
    # Create a test-specific cache.sh that overrides DATA_DIR
    mkdir -p "$TEST_DB_DIR"
}

assert_equals() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected '$expected', got '$actual'"
        ((FAIL++))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — '$needle' not found in output"
        ((FAIL++))
    fi
}

# Override DB_PATH by using a sed wrapper
run_cache() {
    # Create temp copy of cache.sh with overridden DATA_DIR
    local tmp_script
    tmp_script=$(mktemp)
    sed "s|DATA_DIR=.*|DATA_DIR=\"$TEST_DB_DIR\"|" "$CACHE_SH" > "$tmp_script"
    chmod +x "$tmp_script"
    bash "$tmp_script" "$@"
    rm -f "$tmp_script"
}

# --- Tests ---

test_normalize_and_check_miss() {
    echo "test_normalize_and_check_miss:"
    setup
    local result
    result=$(run_cache check "nonexistent")
    assert_equals "check returns miss for nonexistent key" "miss" "$result"
}

test_set_and_get() {
    echo "test_set_and_get:"
    setup
    run_cache set "hello" "hello" "**【hello】** /həˈloʊ/ interj. 你好"
    local check_result
    check_result=$(run_cache check "hello")
    assert_equals "check returns hit after set" "hit" "$check_result"
    local get_result
    get_result=$(run_cache get "hello")
    assert_contains "get returns saved response" "你好" "$get_result"
}

test_case_insensitive() {
    echo "test_case_insensitive:"
    setup
    run_cache set "Hello" "Hello" "**【Hello】** /həˈloʊ/ interj. 你好"
    local result
    result=$(run_cache check "hello")
    assert_equals "lowercase lookup finds uppercase entry" "hit" "$result"
    result=$(run_cache check "HELLO")
    assert_equals "uppercase lookup finds entry" "hit" "$result"
}

test_set_overwrite() {
    echo "test_set_overwrite:"
    setup
    run_cache set "word" "word" "old response"
    run_cache set "word" "word" "new response"
    local result
    result=$(run_cache get "word")
    assert_equals "set overwrites existing entry" "new response" "$result"
}

test_clear_single() {
    echo "test_clear_single:"
    setup
    run_cache set "keep" "keep" "keep response"
    run_cache set "remove" "remove" "remove response"
    run_cache clear "remove"
    local result
    result=$(run_cache check "keep")
    assert_equals "keep entry still exists" "hit" "$result"
    result=$(run_cache check "remove")
    assert_equals "removed entry is gone" "miss" "$result"
}

test_clear_all() {
    echo "test_clear_all:"
    setup
    run_cache set "word1" "word1" "resp1"
    run_cache set "word2" "word2" "resp2"
    local result
    result=$(run_cache clear-all)
    assert_equals "clear-all returns message" "cleared all" "$result"
    result=$(run_cache check "word1")
    assert_equals "word1 cleared" "miss" "$result"
}

test_stats() {
    echo "test_stats:"
    setup
    run_cache set "word1" "word1" "resp1"
    run_cache set "word2" "word2" "resp2"
    local result
    result=$(run_cache stats)
    assert_contains "stats shows count" "Cache entries: 2" "$result"
    assert_contains "stats shows last updated" "Last updated:" "$result"
}

test_multi_word_expansion() {
    echo "test_multi_word_expansion:"
    setup
    run_cache set "短暂" "短暂" "**【短暂的】** ephemeral /ɪˈfemərəl/
adj. 短暂的，转瞬即逝的
*示例：The beauty of cherry blossoms is ephemeral.*
翻译：樱花之美转瞬即逝。"
    # Main entry should exist
    local result
    result=$(run_cache check "短暂")
    assert_equals "main Chinese entry exists" "hit" "$result"
    # English word should also have an entry
    result=$(run_cache check "ephemeral")
    assert_equals "expanded English word entry exists" "hit" "$result"
}

test_refresh() {
    echo "test_refresh:"
    setup
    run_cache set "word" "word" "old response"
    local result
    result=$(run_cache refresh "word" "word" "refreshed response")
    assert_equals "refresh returns message" "refreshed" "$result"
}

# --- Run all tests ---

echo ""
echo "Running cache.sh tests..."
echo ""

test_normalize_and_check_miss
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
```

- [ ] **Step 2: Make test script executable and run**

```bash
chmod +x tests/test_cache.sh
bash tests/test_cache.sh
```

Expected: All tests PASS

- [ ] **Step 3: Fix any test failures**

If any tests fail, debug the cache.sh functions and re-run until all pass.

- [ ] **Step 4: Commit**

```bash
git add tests/test_cache.sh
git commit -m "test(cache): add test suite for cache operations"
```

---

### Task 6: Update install.sh — prompt content with cache logic

**Files:**
- Modify: `install.sh`

This task modifies the heredoc prompt content to include cache check/save instructions. The prompts are embedded in `install.sh` via `read -r -d ''`.

- [ ] **Step 1: Update T_MD heredoc**

Replace the existing `T_MD` heredoc (lines 8-32) with cache-aware version:

```bash
read -r -d '' T_MD << 'PROMPT_EOF'
AI 翻译（支持中英双向及多语言）@author: stormzhang

自动识别输入语言。中文翻译为英文，其他任何语言都翻译为中文。

如果输入是英文单个单词，按这个格式输出：
**【单词】** `音标`
词性. 中文释义（如果有多个常用词性或含义，分行列出，最多 5 个）
*示例：简短英文例句*（只需 1 个，挑最常用的含义）
翻译：例句的中文翻译

如果输入是中文单个词语，按这个格式输出：
**【词语】** 对应英文单词 `音标`
*示例：简短英文例句*
翻译：例句的中文翻译

如果是短语或句子，直接给出对应语言的翻译即可。

不要多余的解释和废话。

如果输入的词恰好是当前 AI 编程工具的命令或概念，翻译完成后额外补充：
{当前工具名}内部命令：说明这个词在当前工具中的含义和用法，简短即可。只说当前工具，不要列举其他工具。

要翻译的内容：$ARGUMENTS
PROMPT_EOF
```

Note: T_MD stays unchanged — the cache logic is added in the tool-specific skill wrappers (CLAUDE_T_SKILL, etc.), not in the base prompt.

- [ ] **Step 2: Add cache-aware prompt wrapper function**

After the `TS_MD` heredoc and before `# --- tool-specific formats ---`, add cache prompt logic:

```bash
# --- cache prompt logic ---

CACHE_CHECK_PROMPT='先用 Bash 工具检查缓存：运行 `bash ./scripts/cache.sh check "输入内容的小写形式"`，如果返回 "hit"，则运行 `bash ./scripts/cache.sh get "输入内容的小写形式"` 获取缓存结果并直接显示，在结果开头加上 📦 图标，不再调用大模型。如果返回 "miss" 或任何错误，继续正常翻译流程。'

CACHE_SAVE_PROMPT='翻译完成后，用 Bash 工具保存结果：运行 `bash ./scripts/cache.sh set "输入内容的小写形式" "原始输入" "翻译结果"`。在翻译结果开头加上 🤖 图标。'
```

- [ ] **Step 3: Update CLAUDE_T_SKILL to include cache logic and allow Bash**

Replace the existing `CLAUDE_T_SKILL` (lines 83-90):

```bash
CLAUDE_T_SKILL="---
name: t
description: AI 翻译（支持中英双向及多语言）@author: stormzhang
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_CHECK_PROMPT

$T_MD

$CACHE_SAVE_PROMPT"
```

- [ ] **Step 4: Update CLAUDE_TS_SKILL to include cache logic**

Replace the existing `CLAUDE_TS_SKILL` (lines 92-99):

```bash
CLAUDE_TS_SKILL="---
name: ts
description: AI 翻译 + 语音朗读（支持中英双向及多语言）@author: stormzhang
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_CHECK_PROMPT

$TS_MD

$CACHE_SAVE_PROMPT"
```

- [ ] **Step 5: Add t-refresh skill heredocs**

After `CLAUDE_TS_SKILL`, add:

```bash
CACHE_REFRESH_PROMPT='先运行 `bash ./scripts/cache.sh clear "输入内容的小写形式"` 清除旧缓存。然后正常翻译，翻译完成后运行 `bash ./scripts/cache.sh set "输入内容的小写形式" "原始输入" "翻译结果"` 保存新结果。在翻译结果开头加上 🔄 图标。'

CLAUDE_T_REFRESH_SKILL="---
name: t-refresh
description: 刷新翻译缓存并重新查询 AI 翻译
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_REFRESH_PROMPT

$T_MD"

CACHE_STATS_PROMPT='运行 `bash ./scripts/cache.sh stats` 并显示结果。不要做其他事情。'

CLAUDE_CACHE_STATS_SKILL="---
name: t-cache-stats
description: 显示翻译缓存统计信息
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_STATS_PROMPT"

CACHE_CLEAR_PROMPT='运行 `bash ./scripts/cache.sh clear-all` 清除所有翻译缓存。显示清除结果。'

CLAUDE_CACHE_CLEAR_SKILL="---
name: t-cache-clear
description: 清除所有翻译缓存
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_CLEAR_PROMPT"

# --- Codex-specific skills (no context: fork) ---

CODEX_T_SKILL="---
name: t
description: AI 翻译（支持中英双向及多语言）@author: stormzhang
allowed-tools: [\"Bash\"]
---

$CACHE_CHECK_PROMPT

$T_MD

$CACHE_SAVE_PROMPT"

CODEX_TS_SKILL="---
name: ts
description: AI 翻译 + 语音朗读（支持中英双向及多语言）@author: stormzhang
allowed-tools: [\"Bash\"]
---

$CACHE_CHECK_PROMPT

$TS_MD

$CACHE_SAVE_PROMPT"

CODEX_T_REFRESH_SKILL="---
name: t-refresh
description: 刷新翻译缓存并重新查询 AI 翻译
allowed-tools: [\"Bash\"]
---

$CACHE_REFRESH_PROMPT

$T_MD"

CODEX_CACHE_STATS_SKILL="---
name: t-cache-stats
description: 显示翻译缓存统计信息
allowed-tools: [\"Bash\"]
---

$CACHE_STATS_PROMPT"

CODEX_CACHE_CLEAR_SKILL="---
name: t-cache-clear
description: 清除所有翻译缓存
allowed-tools: [\"Bash\"]
---

$CACHE_CLEAR_PROMPT"
```

Note: `BASIC_T_SKILL` and `BASIC_TS_SKILL` remain unchanged — they are used by flat installs (Cursor, Windsurf, OpenCode) which don't support Bash tool calls or scripts directories. Cache only works with skill-based tools (Claude Code, Codex).

- [ ] **Step 6: Verify syntax**

Run: `bash -n install.sh`
Expected: No output (clean syntax)

- [ ] **Step 7: Commit**

```bash
git add install.sh
git commit -m "feat(cache): update skill prompts with cache logic"
```

---

### Task 7: Update install.sh — install functions and main flow

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Update version**

Change line 3 from `VERSION="1.1.0"` to `VERSION="1.2.0"`.

- [ ] **Step 2: Update install_skill function**

Replace the existing `install_skill()` function (lines 124-145) with:

```bash
install_skill() {
    local name=$1 base_dir=$2 t_content=$3 ts_content=$4
    local t_dir="$base_dir/t"
    local ts_dir="$base_dir/ts"
    mkdir -p "$t_dir/scripts" "$t_dir/data"
    mkdir -p "$ts_dir/scripts" "$ts_dir/data"
    if [ -f "$t_dir/SKILL.md" ]; then
        printf "$name 已安装翻译工具，是否覆盖更新？(y/N) "
        read -r answer < /dev/tty
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            echo "[SKIP] $name - skipped"
            INSTALLED=1
            return
        fi
        local action="updated"
    else
        local action="installed"
    fi
    echo "$t_content" > "$t_dir/SKILL.md"
    echo "$ts_content" > "$ts_dir/SKILL.md"
    # Install cache script
    SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/cache.sh"
    if [ -f "$SCRIPT_SRC" ]; then
        cp "$SCRIPT_SRC" "$t_dir/scripts/cache.sh"
        cp "$SCRIPT_SRC" "$ts_dir/scripts/cache.sh"
        chmod +x "$t_dir/scripts/cache.sh" "$ts_dir/scripts/cache.sh"
    fi
    echo "[OK] $name - $action"
    INSTALLED=1
}
```

- [ ] **Step 3: Add install_skill_extra function for additional skills**

Add after `install_skill()`:

```bash
install_skill_extra() {
    local base_dir=$1 skill_name=$2 skill_content=$3
    local skill_dir="$base_dir/$skill_name"
    mkdir -p "$skill_dir/scripts" "$skill_dir/data"
    echo "$skill_content" > "$skill_dir/SKILL.md"
    # Install cache script for refresh skill
    SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/cache.sh"
    if [ -f "$SCRIPT_SRC" ]; then
        cp "$SCRIPT_SRC" "$skill_dir/scripts/cache.sh"
        chmod +x "$skill_dir/scripts/cache.sh"
    fi
}
```

- [ ] **Step 4: Update Claude Code install section**

Replace lines 149-153:

```bash
# Claude Code (skills with context: fork)
if [ -d "$HOME/.claude" ]; then
    install_skill "Claude Code" "$HOME/.claude/skills" "$CLAUDE_T_SKILL" "$CLAUDE_TS_SKILL"
    install_skill_extra "$HOME/.claude/skills" "t-refresh" "$CLAUDE_T_REFRESH_SKILL"
    install_skill_extra "$HOME/.claude/skills" "t-cache-stats" "$CLAUDE_CACHE_STATS_SKILL"
    install_skill_extra "$HOME/.claude/skills" "t-cache-clear" "$CLAUDE_CACHE_CLEAR_SKILL"
    rm -f "$HOME/.claude/commands/t.md" "$HOME/.claude/commands/ts.md" 2>/dev/null
fi
```

- [ ] **Step 5: Update Codex install section**

Replace lines 155-158:

```bash
# Codex
if [ -d "$HOME/.codex" ]; then
    install_skill "Codex" "$HOME/.codex/skills" "$CODEX_T_SKILL" "$CODEX_TS_SKILL"
    install_skill_extra "$HOME/.codex/skills" "t-refresh" "$CODEX_T_REFRESH_SKILL"
    install_skill_extra "$HOME/.codex/skills" "t-cache-stats" "$CODEX_CACHE_STATS_SKILL"
    install_skill_extra "$HOME/.codex/skills" "t-cache-clear" "$CODEX_CACHE_CLEAR_SKILL"
    rm -f "$HOME/.codex/prompts/t.md" "$HOME/.codex/prompts/ts.md" 2>/dev/null
fi
```

Note: Codex uses its own skill variables (`CODEX_*`) which include `allowed-tools: ["Bash"]` but NOT `context: fork` (a Claude Code-specific feature).

- [ ] **Step 6: Update usage message**

Replace the usage echo block (lines 192-197):

```bash
echo ""
echo "Done! v${VERSION} installed"
echo ""
echo "Usage:"
echo "  /t word              translate (cached)"
echo "  /ts word             translate + speech (cached)"
echo "  /t-refresh word      force re-translate"
echo "  /t-cache-stats       show cache statistics"
echo "  /t-cache-clear       clear all cache"
echo "  (Codex: \$t word / \$ts word)"
```

- [ ] **Step 7: Verify syntax**

Run: `bash -n install.sh`
Expected: No output (clean syntax)

- [ ] **Step 8: Run local install test**

```bash
bash install.sh
```

Verify:
- `~/.claude/skills/t/scripts/cache.sh` exists and is executable
- `~/.claude/skills/t/data/` directory exists
- `~/.claude/skills/t-refresh/SKILL.md` exists
- `~/.claude/skills/t-cache-stats/SKILL.md` exists
- `~/.claude/skills/t-cache-clear/SKILL.md` exists

- [ ] **Step 9: Commit**

```bash
git add install.sh
git commit -m "feat(cache): update install.sh with cache script deployment"
```

---

### Task 8: Run full test suite and integration check

**Files:**
- No new files

- [ ] **Step 1: Run unit tests**

```bash
bash tests/test_cache.sh
```

Expected: All tests PASS

- [ ] **Step 2: Clean up test artifacts from local install**

If install.sh was run in Step 8, verify the installed files work:

```bash
bash ~/.claude/skills/t/scripts/cache.sh stats
bash ~/.claude/skills/t/scripts/cache.sh set "test" "test" "test response"
bash ~/.claude/skills/t/scripts/cache.sh check "test"
bash ~/.claude/skills/t/scripts/cache.sh get "test"
bash ~/.claude/skills/t/scripts/cache.sh stats
bash ~/.claude/skills/t/scripts/cache.sh clear-all
```

Expected: `saved`, `hit`, test response displayed, stats shown, `cleared all`

- [ ] **Step 3: Verify skill files are correct**

```bash
head -10 ~/.claude/skills/t/SKILL.md
head -10 ~/.claude/skills/t-refresh/SKILL.md
cat ~/.claude/skills/t-cache-stats/SKILL.md
cat ~/.claude/skills/t-cache-clear/SKILL.md
```

Expected: All skill files contain correct YAML frontmatter and prompt content with cache instructions.

- [ ] **Step 4: Final commit with version bump**

Already committed in previous steps. Verify clean state:

```bash
git status
git log --oneline -5
```

Expected: Clean working tree, all commits present.

---

## Summary

| Task | Description | Commits |
|------|-------------|---------|
| 1 | cache.sh core infrastructure | 1 |
| 2 | check and get commands | 1 |
| 3 | set with multi-word expansion | 1 |
| 4 | clear, clear-all, stats, refresh | 1 |
| 5 | Test suite | 1 |
| 6 | Prompt content updates | 1 |
| 7 | Install function updates | 1 |
| 8 | Integration verification | 0 |

**Total: 8 tasks, 7 commits**
