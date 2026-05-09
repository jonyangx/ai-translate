# AGENTS.md

## Dev Commands

```bash
bash -n install.sh              # Syntax check
bash install.sh                  # Install locally (auto-detects tools)
bash tests/test_cache.sh          # Run cache tests
```

## Architecture

`install.sh` is the **single source of truth** — it embeds all prompts as heredoc variables and generates tool-specific skill formats via shell variable composition. `prompts/t.md` and `prompts/ts.md` are reference-only and not used during install. Never edit the prompt files directly; edit the heredocs in `install.sh`.

## Version

The version lives in the `VERSION` variable at the top of `install.sh` (line 3).

## Multi-Tool Skill Formats

| Tool | Format | Cache |
|------|--------|-------|
| Claude Code | Skill YAML + `context: fork` + `allowed-tools: ["Bash"]` | Yes |
| Codex / OpenClaw / Hermes | Skill YAML + `allowed-tools: ["Bash"]` | Yes |
| OpenCode | Flat markdown (no frontmatter), **no cache** | No |
| Cursor / Windsurf | Flat markdown + YAML frontmatter, **no cache** | No |

## Cache System

SQLite at `<skill>/data/cache.db`. Cache logic is injected into prompts via shell variables (`CACHE_CHECK_PROMPT`, `CACHE_SAVE_PROMPT`, etc.) assembled in `install.sh`. `scripts/cache.sh` is copied into each skill's `scripts/` directory during install. The `data/` directory is gitignored.

`cache.sh` commands: `check`, `get`, `set`, `clear`, `clear-all`, `stats`, `refresh`.

## Commit Conventions

Conventional Commits: `feat(cache):`, `fix:`, `docs:`, `test(cache):`
