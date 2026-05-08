#!/bin/bash

VERSION="1.3.0"
INSTALLED=0

# --- prompt content ---

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

read -r -d '' TS_MD << 'PROMPT_EOF'
AI 翻译 + 语音朗读（支持中英双向及多语言）@author: stormzhang

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

翻译完成后，用 Bash 工具朗读英文原文：
- macOS: `say -v Samantha '$ARGUMENTS'`（必须指定 -v Samantha，默认语音有 bug）
- Windows: `powershell -Command "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('$ARGUMENTS')"`
- Linux: `espeak '$ARGUMENTS'`

根据当前系统自动选择对应命令。如果语音命令执行失败，不要输出错误信息，只需提示「当前系统暂不支持语音朗读」。

要翻译的内容：$ARGUMENTS
PROMPT_EOF

# --- cache prompt logic ---

CACHE_CHECK_PROMPT='先用 Bash 工具检查缓存：运行 `bash ./scripts/cache.sh check "输入内容的小写形式"`，如果返回 "hit"，则运行 `bash ./scripts/cache.sh get "输入内容的小写形式"` 获取缓存结果并直接显示，在结果开头加上 📦 图标，不再调用大模型。如果返回 "miss" 或任何错误，继续正常翻译流程。'

CACHE_SAVE_PROMPT='翻译完成后，用 Bash 工具保存结果：运行 `bash ./scripts/cache.sh set "输入内容的小写形式" "原始输入" "翻译结果"`。在翻译结果开头加上 🤖 图标。'

CACHE_REFRESH_PROMPT='先运行 `bash ./scripts/cache.sh clear "输入内容的小写形式"` 清除旧缓存。然后正常翻译，翻译完成后运行 `bash ./scripts/cache.sh set "输入内容的小写形式" "原始输入" "翻译结果"` 保存新结果。在翻译结果开头加上 🔄 图标。'

CACHE_STATS_PROMPT='运行 `bash ./scripts/cache.sh stats` 并显示结果。不要做其他事情。'

CACHE_CLEAR_PROMPT='运行 `bash ./scripts/cache.sh clear-all` 清除所有翻译缓存。显示清除结果。'

# --- tool-specific formats ---

BASIC_T_SKILL="---
name: t
description: AI 翻译（支持中英双向及多语言）
---

$T_MD"

BASIC_TS_SKILL="---
name: ts
description: AI 翻译 + 语音朗读（支持中英双向及多语言）
---

$TS_MD"

CLAUDE_T_SKILL="---
name: t
description: AI 翻译（支持中英双向及多语言）@author: stormzhang
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_CHECK_PROMPT

$T_MD

$CACHE_SAVE_PROMPT"

CLAUDE_TS_SKILL="---
name: ts
description: AI 翻译 + 语音朗读（支持中英双向及多语言）@author: stormzhang
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_CHECK_PROMPT

$TS_MD

$CACHE_SAVE_PROMPT"

CLAUDE_T_REFRESH_SKILL="---
name: t-refresh
description: 刷新翻译缓存并重新查询 AI 翻译
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_REFRESH_PROMPT

$T_MD"

CLAUDE_CACHE_STATS_SKILL="---
name: t-cache-stats
description: 显示翻译缓存统计信息
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_STATS_PROMPT"

CLAUDE_CACHE_CLEAR_SKILL="---
name: t-cache-clear
description: 清除所有翻译缓存
context: fork
allowed-tools: [\"Bash\"]
---

$CACHE_CLEAR_PROMPT"

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

# --- install functions ---

install_flat() {
    local name=$1 dir=$2 t_content=$3 ts_content=$4
    mkdir -p "$dir"
    if [ -f "$dir/t.md" ]; then
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
    echo "$t_content" > "$dir/t.md"
    echo "$ts_content" > "$dir/ts.md"
    echo "[OK] $name - $action"
    INSTALLED=1
}

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
    local SCRIPT_SRC
    SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/cache.sh"
    if [ -f "$SCRIPT_SRC" ]; then
        cp "$SCRIPT_SRC" "$t_dir/scripts/cache.sh"
        cp "$SCRIPT_SRC" "$ts_dir/scripts/cache.sh"
        chmod +x "$t_dir/scripts/cache.sh" "$ts_dir/scripts/cache.sh"
    fi
    echo "[OK] $name - $action"
    INSTALLED=1
}

install_skill_extra() {
    local base_dir=$1 skill_name=$2 skill_content=$3
    local skill_dir="$base_dir/$skill_name"
    mkdir -p "$skill_dir/scripts" "$skill_dir/data"
    echo "$skill_content" > "$skill_dir/SKILL.md"
    local SCRIPT_SRC
    SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/cache.sh"
    if [ -f "$SCRIPT_SRC" ]; then
        cp "$SCRIPT_SRC" "$skill_dir/scripts/cache.sh"
        chmod +x "$skill_dir/scripts/cache.sh"
    fi
}

# --- detect and install ---

# Claude Code (skills with context: fork)
if [ -d "$HOME/.claude" ]; then
    install_skill "Claude Code" "$HOME/.claude/skills" "$CLAUDE_T_SKILL" "$CLAUDE_TS_SKILL"
    install_skill_extra "$HOME/.claude/skills" "t-refresh" "$CLAUDE_T_REFRESH_SKILL"
    install_skill_extra "$HOME/.claude/skills" "t-cache-stats" "$CLAUDE_CACHE_STATS_SKILL"
    install_skill_extra "$HOME/.claude/skills" "t-cache-clear" "$CLAUDE_CACHE_CLEAR_SKILL"
    rm -f "$HOME/.claude/commands/t.md" "$HOME/.claude/commands/ts.md" 2>/dev/null
fi

# Codex
if [ -d "$HOME/.codex" ]; then
    install_skill "Codex" "$HOME/.codex/skills" "$CODEX_T_SKILL" "$CODEX_TS_SKILL"
    install_skill_extra "$HOME/.codex/skills" "t-refresh" "$CODEX_T_REFRESH_SKILL"
    install_skill_extra "$HOME/.codex/skills" "t-cache-stats" "$CODEX_CACHE_STATS_SKILL"
    install_skill_extra "$HOME/.codex/skills" "t-cache-clear" "$CODEX_CACHE_CLEAR_SKILL"
    rm -f "$HOME/.codex/prompts/t.md" "$HOME/.codex/prompts/ts.md" 2>/dev/null
fi

# OpenCode
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/commands"
if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ] || [ -d "$HOME/.opencode" ]; then
    [ -d "$HOME/.opencode" ] && OPENCODE_DIR="$HOME/.opencode/commands"
    install_flat "OpenCode" "$OPENCODE_DIR" "$T_MD" "$TS_MD"
fi

# Cursor
if [ -d "$HOME/.cursor" ]; then
    install_flat "Cursor" "$HOME/.cursor/commands" "$BASIC_T_SKILL" "$BASIC_TS_SKILL"
fi

# Windsurf
if [ -d "$HOME/.codeium/windsurf" ]; then
    install_flat "Windsurf" "$HOME/.codeium/windsurf/global_workflows" "$BASIC_T_SKILL" "$BASIC_TS_SKILL"
fi

# OpenClaw
if [ -d "$HOME/.openclaw" ]; then
    install_skill "OpenClaw" "$HOME/.openclaw/skills" "$CODEX_T_SKILL" "$CODEX_TS_SKILL"
    install_skill_extra "$HOME/.openclaw/skills" "t-refresh" "$CODEX_T_REFRESH_SKILL"
    install_skill_extra "$HOME/.openclaw/skills" "t-cache-stats" "$CODEX_CACHE_STATS_SKILL"
    install_skill_extra "$HOME/.openclaw/skills" "t-cache-clear" "$CODEX_CACHE_CLEAR_SKILL"
fi

# Hermes
if [ -d "$HOME/.hermes" ]; then
    install_skill "Hermes" "$HOME/.hermes/skills" "$CODEX_T_SKILL" "$CODEX_TS_SKILL"
    install_skill_extra "$HOME/.hermes/skills" "t-refresh" "$CODEX_T_REFRESH_SKILL"
    install_skill_extra "$HOME/.hermes/skills" "t-cache-stats" "$CODEX_CACHE_STATS_SKILL"
    install_skill_extra "$HOME/.hermes/skills" "t-cache-clear" "$CODEX_CACHE_CLEAR_SKILL"
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
echo "Usage:"
echo "  /t word              translate (cached)"
echo "  /ts word             translate + speech (cached)"
echo "  /t-refresh word      force re-translate"
echo "  /t-cache-stats       show cache statistics"
echo "  /t-cache-clear       clear all cache"
echo "  (Codex: \$t word / \$ts word)"
