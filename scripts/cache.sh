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

sqlite3_escape() {
    echo "$1" | sed "s/'/''/g"
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
    if [[ "$original" =~ [一-龥] ]]; then
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
    cmd_set "$1" "$2" "$3" >/dev/null
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
