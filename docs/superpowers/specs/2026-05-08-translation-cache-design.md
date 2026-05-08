# Translation Cache System Design

**Date:** 2026-05-08
**Author:** AI Code Assistant
**Status:** Approved

## Overview

Add a caching layer to the ai-translate skill to store translation results in SQLite, reducing redundant LLM calls. The system provides manual cache refresh, visual indicators for cache vs AI results, and handles multi-word Chinese→English translations by creating individual entries for each returned English word.

## Requirements

### Functional Requirements

1. Store translation results in SQLite database per tool installation
2. Check cache before calling LLM; return cached result with 📦 icon if found
3. Save LLM results to cache with 🤖 icon on cache miss
4. Support manual cache refresh via dedicated `/t-refresh` command
5. For Chinese→English translations returning multiple words, create individual cache entries for each English word
6. Provide cache management commands: `stats`, `clear`, `clear-all`

### Non-Functional Requirements

1. Cache entries never expire automatically (user-controlled refresh only)
2. Cache keys are case-insensitive (normalized to lowercase, trimmed)
3. Graceful fallback to LLM if cache unavailable
4. Cache performance: < 50ms for cache hit, < 100ms for cache save
5. Support concurrent access from multiple sessions

### Design Decisions Made

- **Cache storage:** `skills/t/data/cache.db` (per-tool)
- **Script location:** `skills/t/scripts/cache.sh`
- **Cache key:** Normalized input (lowercase, trimmed)
- **Invalidation:** Manual refresh only
- **Icons:** 📦 for cached, 🤖 for AI-generated
- **Database:** SQLite (sqlite3 CLI)
- **Integration:** Bash tool calls in skill files

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                        User                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                    Skill File (t.md)                        │
│  - Normalizes input                                        │
│  - Checks cache via Bash tool                              │
│  - Calls LLM if cache miss                                │
│  - Saves result via Bash tool                              │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         ↓                       ↓
┌─────────────────────┐  ┌─────────────────────┐
│   Cache Manager     │  │      LLM             │
│  (scripts/cache.sh)│  │   (External API)     │
└────────┬────────────┘  └─────────────────────┘
         │
         ↓
┌─────────────────────┐
│   SQLite Database   │
│  (data/cache.db)    │
└─────────────────────┘
```

### Data Flow

**Cache Hit Flow:**
```
User input → Skill → Normalize → Bash: cache.sh check
                              ↓
                            Hit?
                              ↓ Yes
                    Bash: cache.sh get → Display 📦 → Exit
```

**Cache Miss Flow:**
```
User input → Skill → Normalize → Bash: cache.sh check
                              ↓
                            Hit?
                              ↓ No
                    Call LLM → Get response
                              ↓
                    Bash: cache.sh set → Display 🤖
```

**Multi-Word Chinese→English Flow:**
```
Input: "短暂" → LLM returns: "ephemeral, transient, fleeting"
                    ↓
            Cache: "短暂" → Full response
            Cache: "ephemeral" → Extracted entry
            Cache: "transient" → Extracted entry
            Cache: "fleeting" → Extracted entry
```

## Database Schema

### Table: translations

```sql
CREATE TABLE translations (
    input_key TEXT PRIMARY KEY,                  -- Normalized input (lowercase, trimmed)
    original_input TEXT NOT NULL,                -- Original input as typed
    response TEXT NOT NULL,                      -- Full AI response
    translated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source TEXT DEFAULT 'ai'                     -- 'ai' or 'refreshed'
);

CREATE INDEX idx_translations_input_key ON translations(input_key);
```

### Field Descriptions

- **input_key**: Normalized version for fast lookups (case-insensitive)
- **original_input**: Preserves user's exact input for display
- **response**: Complete AI response including formatting, examples, notes
- **translated_at**: Timestamp of translation
- **source**: Tracks if entry was from LLM or manual refresh

## Cache Manager Script

### Interface

```bash
# Check if input exists in cache
./scripts/cache.sh check "<normalized-input>"
# Output: "hit" or "miss" (exit code 0 or 1)

# Get cached response
./scripts/cache.sh get "<normalized-input>"
# Output: Full cached response (empty if not found)

# Save response to cache (handles multi-word expansion)
./scripts/cache.sh set "<normalized-input>" "<original-input>" "<response>"
# Output: "saved" (or error message)

# Clear cache for specific entry
./scripts/cache.sh clear "<normalized-input>"
# Output: "cleared"

# Clear all cache entries
./scripts/cache.sh clear-all
# Output: "cleared all"

# Show cache statistics
./scripts/cache.sh stats
# Output: "Cache entries: X | Last updated: YYYY-MM-DD HH:MM:SS"

# Refresh specific entry (delete + set)
./scripts/cache.sh refresh "<normalized-input>" "<original-input>" "<response>"
# Output: "refreshed"
```

### Normalization Logic

```bash
normalize_input() {
    echo "$1" | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    iconv -f UTF-8 -t UTF-8//TRANSLIT
}
```

### Multi-Word Expansion Logic

For Chinese→English responses with pattern: "【中文词】 word1, word2, word3 /ipa/"

```bash
extract_english_words() {
    local response="$1"
    # Extract text between 【】 and 音标
    # Split by comma to get individual words
    # Returns array of English words
    # Each word gets its own cache entry
}
```

## Error Handling

### Dependency Errors

- **sqlite3 not installed:**
  - Graceful fallback to LLM
  - Log: "⚠️  Cache unavailable: sqlite3 not found"
  - Continue with normal translation

- **Database corrupted:**
  - Delete and recreate database
  - Log: "⚠️  Cache corrupted, rebuilding database"

### Database Operation Errors

- **Insert collision:**
  - Use `INSERT OR REPLACE` to update existing entry

- **Lock contention:**
  - SQLite WAL mode handles automatically
  - Busy timeout: 5 seconds

### Parsing Errors

- **Unparseable AI response:**
  - Store response as-is without multi-word expansion
  - Log: "⚠️  Could not parse response, storing as single entry"

### Integration Errors

- **Bash tool failure:**
  - Treat as cache miss, call LLM directly
  - Log: "⚠️  Cache check failed, proceeding to LLM"

### User-Facing Indicators

- 📦 Cached result
- 🤖 AI translation
- ⚠️ Warning (non-critical issues)
- ❌ Error (critical failures, rare)

## Skill File Changes

### Modified t.md / ts.md Structure

```markdown
---
name: t
description: AI 翻译（支持中英双向及多语言）
context: fork
allowed-tools: ["Bash"]
---

AI 翻译（支持中英双向及多语言）@author: stormzhang

[Original translation instructions...]

---

**Cache Check:**
用 Bash 工具先检查缓存：
```bash
normalized_input=$(echo "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
result=$(./scripts/cache.sh check "$normalized_input")

if [ "$result" = "hit" ]; then
    cached=$(./scripts/cache.sh get "$normalized_input")
    echo "📦 Cached translation:"
    echo "$cached"
    exit
fi
```

**Translation Request:**
[Original translation prompt with $ARGUMENTS]

---

**Save to Cache:**
翻译完成后，用 Bash 工具保存结果：
```bash
./scripts/cache.sh set "$normalized_input" "$ARGUMENTS" "$TRANSLATION_RESULT"
```

🤖 AI translation completed.
```

### New /t-refresh Skill

```markdown
---
name: t-refresh
description: 刷新翻译缓存并重新查询
context: fork
allowed-tools: ["Bash"]
---

[Same prompt as t.md, but cache is cleared before translation]

./scripts/cache.sh clear "$normalized_input"
[Translation request...]
./scripts/cache.sh set "$normalized_input" "$ARGUMENTS" "$RESULT"

🔄 Cache refreshed.
```

## Installation Changes

### File Structure After Installation

```
~/.claude/skills/t/
├── SKILL.md              # Updated with cache logic
├── scripts/
│   └── cache.sh          # Cache manager script
└── data/
    └── cache.db          # Created on first use

~/.codex/skills/t/
├── SKILL.md
├── scripts/
│   └── cache.sh
└── data/
    └── cache.db
```

### install.sh Updates

```bash
# Install function modifications
install_skill() {
    local name=$1 base_dir=$2 t_content=$3 ts_content=$4
    local t_dir="$base_dir/t"
    local ts_dir="$base_dir/ts"

    mkdir -p "$t_dir/scripts" "$t_dir/data"
    mkdir -p "$ts_dir/scripts" "$ts_dir/data"

    # Install cache.sh
    cp "$SCRIPTS_DIR/$CACHE_SCRIPT" "$t_dir/scripts/$CACHE_SCRIPT"
    cp "$SCRIPTS_DIR/$CACHE_SCRIPT" "$ts_dir/scripts/$CACHE_SCRIPT"

    chmod +x "$t_dir/scripts/$CACHE_SCRIPT"
    chmod +x "$ts_dir/scripts/$CACHE_SCRIPT"

    # Install skill files
    echo "$t_content" > "$t_dir/SKILL.md"
    echo "$ts_content" > "$ts_dir/SKILL.md"
}
```

## Performance Considerations

### Targets

- **Cache hit response time:** < 50ms
- **Cache miss + LLM time:** Depends on LLM (no additional overhead)
- **Cache save time:** < 100ms (including multi-word expansion)

### Optimizations

```sql
-- Enable WAL mode for concurrent access
PRAGMA journal_mode = WAL;

-- Faster writes (still safe)
PRAGMA synchronous = NORMAL;

-- Query optimization
CREATE INDEX IF NOT EXISTS idx_input_key ON translations(input_key);
```

- **Batch operations:** Multi-word expansion uses transaction
- **Memory management:** Streaming output for large responses
- **Cache size:** ~1KB per entry; 1000 entries ≈ 1MB

### Concurrent Access

- Multiple sessions can read/write simultaneously
- SQLite WAL mode handles conflicts
- No locking issues for single-user use

## Testing Strategy

### Unit Testing (tests/test_cache.sh)

```
├── test_normalize_input.sh      # Input normalization
├── test_check_cache.sh          # Cache hit/miss detection
├── test_set_cache.sh            # Saving entries
├── test_get_cache.sh            # Retrieving entries
├── test_multi_word_parse.sh     # Multi-word extraction
└── test_error_handling.sh       # Edge cases and errors
```

### Integration Testing Checklist

1. First use — Verify cache DB auto-creation
2. Cache hit — Translate same word twice, second shows 📦
3. Cache miss — Translate new word, shows 🤖
4. Case insensitivity — "apple", "Apple", "APPLE" all hit same cache
5. Chinese→English multi-word — Verify individual word entries created
6. Refresh command — `/t-refresh` updates existing entry
7. Clear commands — Test `clear` and `clear-all`
8. SQLite missing — Verify graceful fallback
9. Database corruption — Verify auto-recovery

### Test Coverage

- Normalization: lowercase, trimming, unicode
- CRUD operations: create, read, update, delete
- Multi-word parsing: Various AI response formats
- Error scenarios: Missing sqlite3, corrupted DB, malformed input

## Deliverables

1. **scripts/cache.sh** — Complete cache manager with all commands
2. **Updated install.sh** — Creates scripts/ and data/ directories
3. **Updated t.md and ts.md** — Cache check/save logic
4. **New t-refresh.md** — Manual cache refresh skill
5. **tests/** — Test suite for cache.sh

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| sqlite3 not installed | Graceful fallback to LLM with warning |
| Database corruption | Auto-recreate database on next access |
| Concurrent write conflicts | SQLite WAL mode handles automatically |
| Parsing failures | Store response as-is, log warning |
| Cache bloat | No hard limit, but SQLite handles large files efficiently |

## Success Criteria

1. ✓ Cache hit rate > 70% for repeated queries
2. ✓ Cache hit response time < 50ms
3. ✓ Zero degradation of existing functionality
4. ✓ Graceful fallback when cache unavailable
5. ✓ Manual refresh works correctly
6. ✓ Multi-word expansion creates correct entries
7. ✓ All error cases handled without crashes
