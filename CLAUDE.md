# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A translation plugin for AI coding tools (Claude Code, Codex, Cursor, Windsurf, OpenCode). The entire product is a set of prompt files + a SQLite cache layer, installed via a single shell script.

## Architecture

```
install.sh              ← THE core file: heredoc-embedded prompts + install logic + version
scripts/cache.sh        ← SQLite cache manager (check/get/set/clear/stats/refresh)
tests/test_cache.sh     ← Cache test suite
prompts/t.md, ts.md     ← Reference-only prompt source (not used at install time)
```

`install.sh` is the single source of truth. It embeds all prompts as heredoc variables, generates tool-specific skill formats (YAML frontmatter, `context: fork`, `allowed-tools`) by shell variable composition, and copies `cache.sh` into each skill's `scripts/` directory during install.

## Key Design: Multi-Tool Skill Format

The same translation prompt is delivered in different formats per tool:
- **Claude Code**: skills with `context: fork` (saves tokens) + `allowed-tools: ["Bash"]` (for cache + TTS)
- **Codex**: skills with YAML frontmatter but no `context: fork`
- **Cursor/Windsurf**: flat markdown files with YAML frontmatter
- **OpenCode**: raw prompt markdown, no frontmatter

The format variants are assembled in `install.sh` by combining `T_MD`/`TS_MD` base prompts with cache prompt snippets (`CACHE_CHECK_PROMPT`, `CACHE_SAVE_PROMPT`, etc.).

## Cache System

SQLite-based translation cache at `skills/t/data/cache.db`. Flow: check cache → hit returns cached result (📦), miss triggers AI translation then saves (🤖). Chinese→English results auto-expand into reverse-lookup entries. Extra skills: `t-refresh` (🔄), `t-cache-stats`, `t-cache-clear`.

## Development

```bash
bash -n install.sh          # Syntax check
bash install.sh             # Install locally (auto-detects installed tools)
bash tests/test_cache.sh    # Run cache tests
```

## Conventions

- Prompt edits must update `install.sh` heredocs, not just `prompts/` files
- Version lives in `VERSION` variable at top of `install.sh`
- `data/` directory is gitignored runtime state (SQLite DB)
- Design docs in `docs/superpowers/` (plans, specs) — not shipped with install
- Commit messages use Conventional Commits: `feat(cache):`, `fix:`, `docs:`, `test(cache):`
