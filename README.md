# cc-provider-add

> A Claude Code skill that wires third-party Anthropic-compatible API endpoints into Claude Code with full per-provider isolation. Zero binaries — just shell + JSON. Never touches `~/.claude/`.

[English](README.md) | [中文](README_ZH.md)

## What it does

Adds providers like MiMo, GLM, Kimi, AWS Bedrock, or any self-hosted Anthropic-compatible relay to Claude Code with one natural-language request. Each provider runs in its own `CLAUDE_CONFIG_DIR`, so:

- Sessions, plugins, and settings never leak between providers.
- Two providers can run **concurrently** in two terminal tabs.
- The user's main `~/.claude/` directory stays completely untouched.
- Switching providers means opening a new shell and typing a different alias — no GUI, no global state mutation.

## Why this exists

The native `~/.claude/settings.json` workaround works for one provider, but breaks down fast:

- A single config file means switching providers overwrites the previous provider's session state.
- A fresh `CLAUDE_CONFIG_DIR` triggers Claude Code's OAuth onboarding flow, which blocks the API-key path. The fix is non-obvious (a specific `.claude.json` shape with the key fingerprint pre-approved).
- GUI tools like cc-switch solve switching but introduce their own problems — most notably, they rewrite the user's live `~/.claude/settings.json` on every switch.

This skill encodes the minimal, transparent solution: per-provider isolation via `CLAUDE_CONFIG_DIR`, the OAuth-bypass trick, and a one-line shell alias to launch each.

## Quick start

After installing the skill, describe the provider in natural language. The skill will ask for anything missing:

> "Add a CC provider for MiMo. Base URL from my dashboard, API key `tp-…`, model `mimo-v2.5-pro`, uses `ANTHROPIC_AUTH_TOKEN`."

The skill will:

1. Write the API key to `~/.config/ai-secrets/<name>.env` (chmod 600), using the auth header your provider requires (`ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`).
2. Create `~/.claude-<name>/` with `settings.json` (base URL, model, and four required `ANTHROPIC_*_MODEL` env vars) and `.claude.json` (onboarding bypass; key fingerprint pre-approved if API_KEY mode).
3. Patch (or create) `~/.local/bin/claude-provider-launch` with a new case branch.
4. Add a shell function (`cmimo`, `cglm`, etc.) to your rc file.
5. **Validate end-to-end against the real API** — sends one ping and waits for a real response. Only declares success after the ping succeeds.

## How it works

### The four pieces

| File | Role |
| --- | --- |
| `~/.zshrc` shell function (e.g. `cmimo`) | One-letter command to launch CC against this provider. |
| `~/.local/bin/claude-provider-launch` | Dispatcher: takes a provider name, loads the right secrets and config dir, then `exec`s `claude`. |
| `~/.config/ai-secrets/<name>.env` | Just the API key. Mode 600. |
| `~/.claude-<name>/` | Per-provider isolated home: `settings.json` (base URL + model) and `.claude.json` (onboarding bypass). |

### The OAuth-bypass trick

A new `CLAUDE_CONFIG_DIR` is treated as a fresh account, which forces OAuth login. To bypass without touching `~/.claude/`, the skill writes a minimal `.claude.json`. The exact shape depends on the provider's auth header:

**`ANTHROPIC_AUTH_TOKEN` providers (e.g. MiMo)** — token mode does not trigger the trust prompt:

```json
{
  "hasCompletedOnboarding": true
}
```

**`ANTHROPIC_API_KEY` providers (e.g. GLM)** — pre-seed the key fingerprint to skip the trust prompt:

```json
{
  "hasCompletedOnboarding": true,
  "customApiKeyResponses": {
    "approved": ["<last 20 chars of API key>"],
    "rejected": []
  }
}
```

The 20-char fingerprint is exactly what Claude Code stores when you click "trust this key" in the prompt. If you've already launched once and clicked "No", the fingerprint is in `rejected` — the bundled `scripts/recover-rejected.py` moves it back to `approved`.

### Why four `ANTHROPIC_*_MODEL` env vars

Some providers (notably MiMo) reject requests when Claude Code asks for the literal Anthropic model names (`claude-sonnet-X`, `claude-opus-X`, `claude-haiku-X`). Setting `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, and `ANTHROPIC_DEFAULT_HAIKU_MODEL` (plus `ANTHROPIC_MODEL` as the global default) all to your provider's actual model ID makes CC route every request to the right model. Setting them is harmless when redundant and load-bearing when not, so the skill always sets all four.

### Validation

The skill always finishes with a real API ping (`-p "Reply with PONG"`) before declaring success — Claude Code starting cleanly does **not** prove the API call goes through, only that the local config parses. Skipping this step is how a working-looking config can sit broken behind a 400 error.

## vs cc-switch

[cc-switch](https://github.com/farion1231/cc-switch) is a polished Tauri desktop GUI managing providers across 5 CLI tools (Claude Code, Codex, Gemini CLI, OpenCode, OpenClaw) with 50+ presets, system tray, MCP/Skills sync, usage tracking, and cloud sync. **It is a different product, not a competitor.** The two can coexist.

|   | cc-provider-add (this skill) | cc-switch |
| --- | --- | --- |
| Footprint | Zero binary, just shell + JSON | Tauri desktop app (~30MB+) |
| Touches `~/.claude/settings.json` | **Never** | Yes — rewrites live config on every switch |
| Concurrent providers | ✅ Two shells, two providers, simultaneously | ❌ One active provider at a time |
| Per-provider session isolation | ✅ Separate `CLAUDE_CONFIG_DIR` | ❌ Shared |
| Switching speed | New shell + alias | Tray click (faster) |
| CLI tools supported | Claude Code only | CC + Codex + Gemini + OpenCode + OpenClaw |
| Provider presets | DIY | 50+ built-in |
| MCP / Skills central management | ❌ | ✅ |
| Usage dashboard | ❌ | ✅ |
| Cloud sync | ❌ | ✅ (Dropbox / OneDrive / iCloud / WebDAV) |
| Headless / SSH / CI usable | ✅ | ❌ |
| Auditable | Plain JSON, git-trackable | SQLite database |
| Learning curve | Need basic shell + JSON literacy | Drag-and-drop GUI |
| Cross-platform | macOS / Linux (Windows needs shell tweak) | Win / Mac / Linux native |

**Pick this skill if** you live in terminals, want zero binary deps, dislike GUI apps modifying your dotfiles, want true per-shell concurrent providers, or only use Claude Code (not the other CLIs).

**Pick cc-switch if** you want one tool to rule all 5 CLIs, prefer a GUI, want preset libraries, or value usage tracking and cloud sync out of the box.

## Adding a new provider manually (without the skill)

The full manual procedure is documented in [SKILL.md](SKILL.md). The skill itself is just the agent-facing version of that procedure.

## Security

- Secrets stored in `~/.config/ai-secrets/*.env` with mode 600.
- `~/.claude-<name>/.claude.json` contains a local `userID`; add `~/.claude-*/` to your global `.gitignore`.
- The skill **never** writes to `~/.claude/` or `~/.claude/settings.json`.
- Trusting a third-party endpoint means sending all your prompts to that provider — evaluate privacy and compliance accordingly.

## Install

Clone this repo somewhere and symlink it into Claude Code's skills directory:

```bash
git clone https://github.com/huasan2025/cc-provider-add.git ~/cc-provider-add
ln -s ~/cc-provider-add ~/.claude/skills/cc-provider-add
```

Or, if you keep skill sources in `~/.agents/skills/` (the convention this repo was developed against):

```bash
git clone https://github.com/huasan2025/cc-provider-add.git ~/.agents/skills/cc-provider-add
ln -s ~/.agents/skills/cc-provider-add ~/.claude/skills/cc-provider-add
```

Restart Claude Code, then invoke the skill by describing your provider in natural language (see Quick start above).

## Test

Run the bundled test suite (24 checks, simulates two providers in an isolated tmpdir, no network):

```bash
bash tests/run.sh
```
