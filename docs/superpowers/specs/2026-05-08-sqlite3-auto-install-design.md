# SQLite3 Auto-Install in cache.sh

**Date**: 2026-05-08
**Status**: Approved

## Context

`cache.sh` uses SQLite3 for translation caching. The `init_db()` function (line 21-24) currently checks for `sqlite3` and exits with an error if not found. Users on systems without SQLite3 pre-installed get a cryptic error with no guidance.

## Requirements

- Auto-detect missing `sqlite3` binary
- Install via system package manager based on OS
- Only modify `scripts/cache.sh`
- No interactive confirmation (AI tools call cache.sh non-interactively)

## Changes

### `scripts/cache.sh` — Add `ensure_sqlite3()` function

Insert before `normalize_input()`:

```bash
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
```

### `scripts/cache.sh` — Modify `init_db()`

Replace the existing check block:

```bash
# Before:
if ! command -v sqlite3 &>/dev/null; then
    echo "error: sqlite3 not found" >&2
    return 1
fi

# After:
ensure_sqlite3 || return 1
```

## Scope

- Only `scripts/cache.sh` modified (~30 lines added, 4 lines replaced)
- No changes to `install.sh`, prompts, or other files
