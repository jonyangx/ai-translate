# OpenClaw & Hermes Skill Installation Support

**Date**: 2026-05-08
**Status**: Approved

## Context

ai-translate currently supports 5 AI coding tools: Claude Code, Codex, OpenCode, Cursor, and Windsurf. OpenClaw is an installed tool on the user's system with an AgentSkills-compatible skill format. Hermes is in design phase but will use a similar skill directory structure (`~/.hermes/skills`).

## Requirements

- Add OpenClaw skill installation to `install.sh`
- Add Hermes skill installation to `install.sh`
- Both use full skill format: `SKILL.md` + `scripts/cache.sh` + `data/`
- Detect installed tools via directory presence (`~/.openclaw`, `~/.hermes`)

## Design Decisions

### Reuse Codex format variables

OpenClaw and Hermes use the same skill format as Codex (YAML frontmatter with `allowed-tools: ["Bash"]`, no `context: fork`). Rather than creating new `OPENCLAW_*_SKILL` and `HERMES_*_SKILL` variables, we directly reuse the existing `CODEX_*_SKILL` variables. This avoids duplication and the formats are functionally identical.

If future differentiation is needed (e.g., OpenClaw-specific `metadata.openclaw` fields), the variables can be split at that time with minimal effort.

### Reuse existing install functions

The existing `install_skill()` and `install_skill_extra()` functions handle the exact directory structure needed (`SKILL.md` + `scripts/` + `data/`). No new functions required.

### Detection: directory presence

Follow the existing pattern: check if the tool's home directory exists (`~/.openclaw`, `~/.hermes`). This is consistent with how Claude Code (`~/.claude`), Codex (`~/.codex`), Cursor (`~/.cursor`), and Windsurf are detected.

## Changes

### 1. `install.sh` — Detection & installation blocks

Insert after the Windsurf block (line ~302), before the "not detected" check:

```bash
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
```

### 2. `install.sh` — Update "not detected" message

Add OpenClaw and Hermes to the supported tools list:

```
  OpenClaw     https://github.com/open-claw/openclaw
  Hermes       (TBD)
```

### 3. `install.sh` — Version bump

`VERSION` from `1.2.0` to `1.3.0`.

## Installed directory structure

```
~/.openclaw/skills/
├── t/
│   ├── SKILL.md
│   ├── scripts/cache.sh
│   └── data/           (runtime, cache.db created on use)
├── ts/
│   ├── SKILL.md
│   ├── scripts/cache.sh
│   └── data/
├── t-refresh/
│   ├── SKILL.md
│   └── scripts/cache.sh
├── t-cache-stats/
│   ├── SKILL.md
│   └── scripts/cache.sh
└── t-cache-clear/
    ├── SKILL.md
    └── scripts/cache.sh
```

Same structure under `~/.hermes/skills/`.

## Scope

- ~20 lines of new code in `install.sh`
- No changes to `scripts/cache.sh`, `tests/test_cache.sh`, or prompt content
- No new files created
