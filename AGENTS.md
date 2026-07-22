# AGENTS.md

## Dev Commands

```bash
bash -n install.sh              # Syntax check
bash install.sh                  # Install locally (auto-detects tools)
bash tests/test_cache.sh          # Run cache tests
bash tests/test_install.sh         # Run install.sh heredoc/format tests
bash tests/test_skills.sh          # Run skill installation tests
```

## Architecture

`install.sh` is the **single source of truth** — it embeds all prompts (and `cache.sh`) as heredoc variables and generates the single `/t` skill via the `build_skill()` builder. Never edit prompt files directly; edit the heredocs in `install.sh`.

## Version

The version lives in the `VERSION` variable near the top of `install.sh`.

## Multi-Tool Skill Formats

| Tool | Format | Cache |
|------|--------|-------|
| Claude Code | Skill YAML + `context: fork` + `allowed-tools: ["Bash"]` | Yes |
| Codex / OpenClaw / Hermes | Skill YAML + `allowed-tools: ["Bash"]` | Yes |
| OpenCode | Flat markdown (no frontmatter), **no cache** | No |
| Cursor / Windsurf | Flat markdown + YAML frontmatter, **no cache** | No |

## Cache System

Translations are cached in a single global SQLite DB at `~/.ai-translate/cache.db`, shared across all skills and tools. Cache logic is inlined into the `/t` skill body in `install.sh`, which calls `~/.ai-translate/cache.sh` by absolute path. `scripts/cache.sh` is the dev/test source of truth and is also embedded in `install.sh` for self-contained `curl|bash` installs.

`cache.sh` commands: `check`, `get`, `set`, `clear`, `clear-all`, `stats`, `refresh`.

## Commit Conventions

Conventional Commits: `feat(cache):`, `fix:`, `docs:`, `test(cache):`
