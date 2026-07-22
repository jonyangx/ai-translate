#!/bin/bash

# Can be sourced to extract variables: source install.sh
# Set SKIP_EXEC=1 before sourcing to skip the install logic.
[ "${SKIP_EXEC:-0}" = "1" ] && return 0 2>/dev/null

DRY_RUN="${DRY_RUN:-0}"

VERSION="1.5.0"
INSTALLED=0

# --- translation rules (the shared core, inlined into every skill body) ---

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

当输入涉及编程或技术概念时，优先选择该领域最常用的含义：
- concurrency → 并发（而非竞争/同时发生）
- callback → 回调（而非回拨）
- race condition → 竞态条件（而非种族条件）
- lazy loading → 延迟加载（而非懒惰加载）
- greedy algorithm → 贪心算法（而非贪婪算法）
- closure → 闭包（而非结束/关闭）
- middleware → 中间件（而非中间件/中间软件）
- stub/mock → 桩/模拟对象（而非残桩/嘲笑）
- thunk → 形参（而非思考）
- pragma → 杂注（而非pragma本身的含义）
PROMPT_EOF

# --- cache.sh content (embedded so `curl | bash` installs are self-contained).
# Keep in sync with scripts/cache.sh (the dev/test source of truth). ---

read -r -d '' CACHE_SH_SRC << 'CACHE_SH_EOF'
#!/bin/bash

# ai-translate cache manager
# Manages a globally-shared SQLite translation cache.
# DB location defaults to ~/.ai-translate/cache.db; override with AI_TRANSLATE_DATA_DIR.
# Every command writes a single, machine-parseable line to stdout (hit/miss/saved/...).

set -euo pipefail

DATA_DIR="${AI_TRANSLATE_DATA_DIR:-$HOME/.ai-translate}"
DB_PATH="$DATA_DIR/cache.db"

ensure_sqlite3() {
    if command -v sqlite3 &>/dev/null; then return 0; fi
    echo "Installing sqlite3..." >&2
    case "$(uname -s)" in
        Darwin)
            if command -v brew &>/dev/null; then
                brew install sqlite3
            else
                echo "error: Homebrew not found, install from https://brew.sh" >&2
                return 1
            fi
            ;;
        Linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y sqlite3
            elif command -v yum &>/dev/null; then
                sudo yum install -y sqlite
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y sqlite
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm sqlite3
            else
                echo "error: no supported package manager found" >&2
                return 1
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            if command -v pacman &>/dev/null; then
                pacman -S --noconfirm sqlite
            else
                echo "error: no supported package manager found" >&2
                return 1
            fi
            ;;
        *)
            echo "error: unsupported OS $(uname -s)" >&2
            return 1
            ;;
    esac
    if ! command -v sqlite3 &>/dev/null; then
        echo "error: sqlite3 installation failed" >&2
        return 1
    fi
}

normalize_input() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

sqlite3_escape() {
    echo "$1" | sed "s/'/''/g"
}

init_db() {
    ensure_sqlite3 || return 1
    mkdir -p "$DATA_DIR"
    if [ ! -f "$DB_PATH" ]; then
        # journal_mode is persistent (stored in the DB header) — set once on creation.
        # Output is redirected so it never pollutes stdout, which callers parse.
        sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL;" >/dev/null 2>&1 || true
        sqlite3 "$DB_PATH" "PRAGMA synchronous=NORMAL;" >/dev/null 2>&1 || true
        sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS translations (
    input_key TEXT PRIMARY KEY,
    original_input TEXT NOT NULL,
    response TEXT NOT NULL,
    translated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source TEXT DEFAULT 'ai'
);"
    fi
}

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

extract_english_words() {
    local response="$1"
    echo "$response" | grep -oE '\*\*【[^】]+】\*\*[^`/]*' | head -1 | \
        sed 's/\*\*【[^】]*】\*\*[[:space:]]*//' | \
        sed 's/[[:space:]]*$//' | \
        tr ',' '\n' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -E '^[a-zA-Z]'
}

# cmd_set <key> <original> <response> [source]
# source defaults to 'ai'; 'expanded' for reverse-lookup entries, 'refreshed' for /t cache refresh.
cmd_set() {
    local key original response source
    key="$(normalize_input "$1")"
    original="$2"
    response="$3"
    source="${4:-ai}"

    init_db || return 1

    local escaped_key escaped_orig escaped_resp
    escaped_key="$(sqlite3_escape "$key")"
    escaped_orig="$(sqlite3_escape "$original")"
    escaped_resp="$(sqlite3_escape "$response")"

    # INSERT OR REPLACE is an upsert, so refresh simply re-sets with source='refreshed'.
    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO translations (input_key, original_input, response, translated_at, source) VALUES ('$escaped_key', '$escaped_orig', '$escaped_resp', CURRENT_TIMESTAMP, '$source');"

    # Multi-word expansion: if Chinese input, extract English words and create individual entries
    if [[ "$original" =~ [一-龥] ]]; then
        local english_words
        english_words="$(extract_english_words "$response")"
        if [ -n "$english_words" ]; then
            while IFS= read -r word; do
                [ -z "$word" ] && continue
                local norm_word escaped_word
                norm_word="$(normalize_input "$word")"
                escaped_word="$(sqlite3_escape "$norm_word")"
                sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO translations (input_key, original_input, response, translated_at, source) VALUES ('$escaped_word', '$word', '$escaped_resp', CURRENT_TIMESTAMP, 'expanded');"
            done <<< "$english_words"
        fi
    fi

    echo "saved"
}

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
    local original response
    original="$2"
    response="$3"
    init_db || return 1
    cmd_set "$1" "$original" "$response" "refreshed" >/dev/null
    echo "refreshed"
}

# --- command dispatcher ---
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
CACHE_SH_EOF

# --- single skill body. __CACHE_SH__ is resolved below to an absolute path,
# so the skill never depends on the runtime CWD. $ARGUMENTS dispatches intent:
#   <text>            -> translate (with cache)
#   say <text>        -> translate + read aloud
#   cache <subcmd>    -> cache management (stats/clear/remove/refresh)

T_DESC="AI 翻译（支持语音朗读与缓存管理）"

T_BODY="你是 AI 翻译助手（支持中英双向及多语言）。根据参数 \$ARGUMENTS 判断用户意图并执行对应流程：

【缓存管理】若 \$ARGUMENTS 以 \"cache \" 开头（注意空格；单独一个 \"cache\" 视为要翻译的词）：
- \`cache stats\` → 运行 \`bash __CACHE_SH__ stats\` 并显示结果，不做其他事。
- \`cache clear\` → 运行 \`bash __CACHE_SH__ clear-all\` 清空所有翻译缓存，显示结果。
- \`cache remove <词>\` → 运行 \`bash __CACHE_SH__ clear \"<词>\"\` 删除该词的缓存，显示结果。
- \`cache refresh <词>\` → 先运行 \`bash __CACHE_SH__ clear \"<词>\"\` 清除旧缓存，再按【翻译规则】重新翻译 <词>，完成后运行 \`bash __CACHE_SH__ set \"<词的小写形式>\" \"<词>\" \"<翻译结果>\"\` 保存，结果开头加 🔄 图标。

【朗读翻译】若 \$ARGUMENTS 以 \"say \" 开头：取 \"say\" 之后的内容作为待翻译文本，按【默认翻译】流程处理（含缓存检查与保存），翻译完成后再朗读英文原文：
- macOS: \`say -v Samantha '<英文原文>'\`（必须指定 -v Samantha，默认语音有 bug）
- Windows: \`powershell -Command \"Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('<英文原文>')\"\`
- Linux: \`espeak '<英文原文>'\`
根据当前系统自动选择命令。朗读失败不要输出错误，只需提示「当前系统暂不支持语音朗读」。

【默认翻译】其他情况，\$ARGUMENTS 即为待翻译内容：
1. 先运行 \`bash __CACHE_SH__ check \"<内容的小写形式>\"\`；若返回 \"hit\"，则运行 \`bash __CACHE_SH__ get \"<内容的小写形式>\"\` 取得结果并直接显示，开头加 📦 图标，不再调用大模型。
2. 若返回 \"miss\" 或任何错误，按【翻译规则】翻译，完成后运行 \`bash __CACHE_SH__ set \"<内容的小写形式>\" \"<原始输入>\" \"<翻译结果>\"\` 保存，开头加 🤖 图标。

【翻译规则】
$T_MD

要翻译的内容：\$ARGUMENTS（朗读模式去掉前缀 \"say\"；缓存模式按上文取参）"

# Flat-tool body: same dispatch (translate / say), but no cache (those tools
# don't run the Bash-based cache layer).
T_FLAT_BODY="你是 AI 翻译助手（支持中英双向及多语言）。根据参数 \$ARGUMENTS 判断用户意图：

【朗读翻译】若 \$ARGUMENTS 以 \"say \" 开头：取其后内容按【翻译规则】翻译，翻译完成后再朗读英文原文：
- macOS: \`say -v Samantha '<英文原文>'\`
- Windows: \`powershell -Command \"Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('<英文原文>')\"\`
- Linux: \`espeak '<英文原文>'\`
朗读失败只提示「当前系统暂不支持语音朗读」，不报错。

【默认翻译】其他情况直接按【翻译规则】翻译 \$ARGUMENTS。

【翻译规则】
$T_MD

要翻译的内容：\$ARGUMENTS（朗读模式去掉前缀 \"say\"）"

# --- resolve the global cache.sh path and bake it into the skill body ---
CACHE_SH_PATH="$HOME/.ai-translate/cache.sh"
T_BODY="${T_BODY//__CACHE_SH__/$CACHE_SH_PATH}"

# --- skill format builder ---
# build_skill <name> <desc> <body> [fork:0/1] [tools:0/1]
# fork=1  -> emit `context: fork` (Claude Code, saves tokens)
# tools=1 -> emit `allowed-tools: ["Bash"]` (skills that call the cache)
build_skill() {
    local name="$1" desc="$2" body="$3" fork="${4:-0}" tools="${5:-1}"
    printf -- "---\nname: %s\ndescription: %s\n" "$name" "$desc"
    if [ "$fork" = "1" ]; then printf 'context: fork\n'; fi
    if [ "$tools" = "1" ]; then printf 'allowed-tools: ["Bash"]\n'; fi
    printf -- "---\n\n%s\n" "$body"
}

# --- Only run install logic when executed, not when sourced ---
if [ "${SKIP_EXEC:-0}" = "0" ]; then

# --- install helpers ---

# Install the single shared cache.sh to ~/.ai-translate/. Prefer the real
# scripts/cache.sh (clone installs / dev) so there is one source of truth;
# fall back to the embedded heredoc (curl | bash installs).
install_global_cache() {
    mkdir -p "$HOME/.ai-translate"
    local SCRIPT_SRC dest="$HOME/.ai-translate/cache.sh"
    SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/cache.sh"
    if [ -f "$SCRIPT_SRC" ]; then
        cp "$SCRIPT_SRC" "$dest"
    else
        printf '%s\n' "$CACHE_SH_SRC" > "$dest"
    fi
    chmod +x "$dest"
}

# install_tool_skills <name> <base_dir> <fork:0/1>
# Installs the single /t skill and removes legacy skill dirs (ts, t-cache, and
# the older one-skill-per-command set) from prior versions.
install_tool_skills() {
    local name="$1" base="$2" fork="$3"
    local t_dir="$base/t"
    local action answer
    if [ -f "$t_dir/SKILL.md" ] && [ "${DRY_RUN:-0}" = "0" ]; then
        printf "%s 已安装翻译工具，是否覆盖更新？(y/N) " "$name"
        read -r answer < /dev/tty
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            echo "[SKIP] $name - skipped"
            INSTALLED=1
            return
        fi
        action="updated"
    else
        action="installed"
    fi
    mkdir -p "$t_dir"
    build_skill t "$T_DESC" "$T_BODY" "$fork" > "$t_dir/SKILL.md"
    # legacy cleanup: everything that used to be a separate skill
    rm -rf "$base/ts" "$base/t-cache" "$base/t-refresh" "$base/t-cache-stats" "$base/t-cache-clear" "$base/t-cache-remove" 2>/dev/null
    echo "[OK] $name - $action"
    INSTALLED=1
}

# install_tool_flat <name> <dir> <with_frontmatter:0/1>
# Installs a single t.md for flat-command tools (no cache).
install_tool_flat() {
    local name="$1" dir="$2" front="$3"
    local action answer
    if [ -f "$dir/t.md" ] && [ "${DRY_RUN:-0}" = "0" ]; then
        printf "%s 已安装翻译工具，是否覆盖更新？(y/N) " "$name"
        read -r answer < /dev/tty
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            echo "[SKIP] $name - skipped"
            INSTALLED=1
            return
        fi
        action="updated"
    else
        action="installed"
    fi
    mkdir -p "$dir"
    if [ "$front" = "1" ]; then
        build_skill t "$T_DESC" "$T_FLAT_BODY" 0 0 > "$dir/t.md"
    else
        printf '%s\n' "$T_FLAT_BODY" > "$dir/t.md"
    fi
    rm -f "$dir/ts.md" 2>/dev/null
    echo "[OK] $name - $action"
    INSTALLED=1
}

# --- detect and install ---

install_global_cache

# Claude Code (skills with context: fork)
if [ -d "$HOME/.claude" ]; then
    install_tool_skills "Claude Code" "$HOME/.claude/skills" 1
    rm -f "$HOME/.claude/commands/t.md" "$HOME/.claude/commands/ts.md" 2>/dev/null
fi

# Codex
if [ -d "$HOME/.codex" ]; then
    install_tool_skills "Codex" "$HOME/.codex/skills" 0
    rm -f "$HOME/.codex/prompts/t.md" "$HOME/.codex/prompts/ts.md" 2>/dev/null
fi

# OpenClaw (Codex format)
if [ -d "$HOME/.openclaw" ]; then
    install_tool_skills "OpenClaw" "$HOME/.openclaw/skills" 0
fi

# Hermes (Codex format)
if [ -d "$HOME/.hermes" ]; then
    install_tool_skills "Hermes" "$HOME/.hermes/skills" 0
fi

# OpenCode (raw prompt markdown, no frontmatter)
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/commands"
if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ] || [ -d "$HOME/.opencode" ]; then
    [ -d "$HOME/.opencode" ] && OPENCODE_DIR="$HOME/.opencode/commands"
    install_tool_flat "OpenCode" "$OPENCODE_DIR" 0
fi

# Cursor (flat markdown + YAML frontmatter)
if [ -d "$HOME/.cursor" ]; then
    install_tool_flat "Cursor" "$HOME/.cursor/commands" 1
fi

# Windsurf (flat markdown + YAML frontmatter)
if [ -d "$HOME/.codeium/windsurf" ]; then
    install_tool_flat "Windsurf" "$HOME/.codeium/windsurf/global_workflows" 1
fi

if [ $INSTALLED -eq 0 ]; then
    echo "未检测到支持的 AI 编程工具，请先安装以下任一工具："
    echo ""
    echo "  Claude Code  https://claude.ai/code"
    echo "  Codex        https://github.com/openai/codex"
    echo "  OpenClaw     https://github.com/nicepkg/openclaw"
    echo "  Hermes       https://github.com/nicepkg/hermes"
    echo "  OpenCode     https://github.com/opencode-ai/opencode"
    echo "  Cursor       https://cursor.com"
    echo "  Windsurf     https://windsurf.com"
    echo ""
    echo "安装完成后重新运行此脚本即可。"
    exit 1
fi

echo ""
echo "Done! v${VERSION} installed"
echo ""
echo "Usage (all via /t):"
echo "  /t word              translate (cached)"
echo "  /t say word          translate + speech"
echo "  /t cache stats       show cache statistics"
echo "  /t cache clear       clear all cache"
echo "  /t cache remove word remove single word cache"
echo "  /t cache refresh word force re-translate"
echo "  (Codex: \$t word / \$t say word / \$t cache <subcmd>)"

fi
