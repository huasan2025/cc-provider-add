---
name: cc-provider-add
description: Add or update a third-party Anthropic-compatible API endpoint (MiMo, GLM, Kimi, AWS Bedrock, self-hosted relay, etc.) for Claude Code, with isolated CLAUDE_CONFIG_DIR per provider. Never touches ~/.claude/settings.json. Bypasses the official OAuth onboarding flow on a fresh provider config. Triggers on "add a CC provider", "configure third-party Claude API", "接入 xxx 到 Claude Code", "新增 cmimo/cglm 这种 alias", "configure cmimo/cmm/cglm", or any request to wire a non-Anthropic endpoint into Claude Code without using a binary like cc-switch.
---

# cc-provider-add

Wires Claude Code to a third-party Anthropic-compatible API endpoint, in full isolation from the user's main `~/.claude/` directory. Each provider gets its own `CLAUDE_CONFIG_DIR`, so sessions / plugins / settings never leak between providers, and two providers can run concurrently in two terminals.

## When to use

- User wants to add a new third-party Claude Code provider (MiMo, GLM, Kimi, etc.).
- User wants a `c<name>`-style shell alias to launch CC against that provider.
- User reports that a fresh provider config keeps forcing OAuth login.
- User explicitly does **not** want a tool like cc-switch modifying `~/.claude/`.

## Bundled assets

This skill ships with reusable files alongside `SKILL.md`:

- `templates/launcher.sh` — skeleton for `~/.local/bin/claude-provider-launch`. Empty case block; provider branches get inserted above the `*)` fallback.
- `scripts/recover-rejected.py` — fixes a key fingerprint stuck in `customApiKeyResponses.rejected`.

Always read these from the skill directory rather than typing the contents from memory.

## Required inputs

Ask the user for any missing values. Don't guess.

1. **provider name** — short lowercase identifier `[a-z0-9-]+`, used in file paths. Example: `mimo`, `glm`, `kimi`.
2. **base URL** — the provider's Anthropic-compatible endpoint. Example: `https://token-plan-sgp.xiaomimimo.com/anthropic`. **Verify this against the provider's actual account dashboard, not just their docs** — region URLs differ per user.
3. **API key** — the provider's auth token. Treat as secret. Refuse if it looks like a placeholder.
4. **auth header** — `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`. Different providers require different ones:
   - `ANTHROPIC_API_KEY` — Anthropic-native style. Triggers CC's "trust this key?" prompt on first launch (which the skill bypasses via `customApiKeyResponses.approved`). Used by GLM and most relay services.
   - `ANTHROPIC_AUTH_TOKEN` — used by MiMo and some other providers. Does not trigger the trust prompt.
   - **If unsure, check the provider's CC integration docs.** Default to `ANTHROPIC_API_KEY` only if the docs are silent.
5. **model name** — the model identifier the provider expects. **Case-sensitive — use exactly what the provider's docs specify** (e.g. MiMo wants lowercase `mimo-v2.5-pro`, GLM wants `glm-5.1`).
6. **alias** *(optional)* — shell function name `[a-z0-9-]+`. Defaults to `c<provider>`.

Refuse to operate if `name` contains `/`, `..`, or whitespace.

## Procedure

Use Read/Edit/Write tools, not shell heredocs, when modifying existing files. Bash is fine for `mkdir`, `chmod`, and computing the key fingerprint.

### Step 0 — compute key fingerprint (for API_KEY mode only)

```bash
KEY_LAST20=$(printf '%s' "$KEY" | tail -c 20)
```

Used only when `auth_header == ANTHROPIC_API_KEY`. The 20-char suffix is what Claude Code stores when the user clicks "trust this key" — pre-seeding it in `customApiKeyResponses.approved` skips the prompt. Skip this step entirely for `ANTHROPIC_AUTH_TOKEN` providers.

### Step 1 — directories and secrets

```bash
mkdir -p ~/.config/ai-secrets ~/.local/bin ~/.claude-<NAME>
```

Write `~/.config/ai-secrets/<NAME>.env` with the chosen auth header:

```bash
export <AUTH_HEADER>="<KEY>"
```

(literal: `export ANTHROPIC_API_KEY="..."` or `export ANTHROPIC_AUTH_TOKEN="..."`)

```bash
chmod 600 ~/.config/ai-secrets/<NAME>.env
```

### Step 2 — provider config dir

Write `~/.claude-<NAME>/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "<BASE_URL>",
    "ANTHROPIC_MODEL": "<MODEL>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "<MODEL>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "<MODEL>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "<MODEL>",
    "DISABLE_AUTOUPDATER": "1"
  },
  "model": "<MODEL>",
  "hasCompletedOnboarding": true
}
```

The four `ANTHROPIC_*_MODEL` env vars are required by some providers (notably MiMo) — when CC asks for "sonnet" or "opus" or "haiku", these tell it which model to actually request. Setting all four to the same value is harmless when redundant and required when not.

Write `~/.claude-<NAME>/.claude.json`:

For **`ANTHROPIC_API_KEY`** mode:
```json
{
  "hasCompletedOnboarding": true,
  "customApiKeyResponses": {
    "approved": ["<KEY_LAST20>"],
    "rejected": []
  }
}
```

For **`ANTHROPIC_AUTH_TOKEN`** mode (no trust prompt fires, so no need to pre-approve):
```json
{
  "hasCompletedOnboarding": true
}
```

Without `.claude.json`, the empty config dir triggers OAuth onboarding regardless of auth header.

### Step 3 — launcher script

Path: `~/.local/bin/claude-provider-launch`.

**If the file does NOT exist**: copy `templates/launcher.sh` from this skill, then `chmod +x` it.

**Insert the provider's case branch** above the `*)` fallback line, preserving indentation:

```
    <NAME>)
        config_dir="$HOME/.claude-<NAME>"
        secrets_file="$HOME/.config/ai-secrets/<NAME>.env"
        ;;
```

Use Read + Edit, not append. The anchor for Edit is the `*)` line.

The launcher pre-clears all stale `ANTHROPIC_*` env vars before sourcing the secrets file, then accepts either `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` — no auth-method specifics in the launcher itself.

### Step 4 — shell alias

Detect the user's shell rc file:
- zsh → `~/.zshrc`
- bash → `~/.bashrc` (Linux) or `~/.bash_profile` (macOS)

Read the rc file. If it does not contain a `_claude_provider` function, add this block:

```bash
_claude_provider() {
    ~/.local/bin/claude-provider-launch "$@"
}
```

Then add the alias function:

```bash
<ALIAS>() {
    _claude_provider <NAME> "$@"
}
```

Use Edit, not blind appends.

### Step 5 — validate end-to-end against the real API

**Critical: do not declare success without this step.** A green CC startup proves only the local config is parseable, not that the API call goes through. The user lost an evening to this. Always run a real API ping before reporting done.

```bash
~/.local/bin/claude-provider-launch <NAME> -p "Reply with exactly: PONG"
```

Expected output: `PONG` on stdout.

Common failure modes and what they tell you:

| Symptom | Likely cause |
| --- | --- |
| `API Error: 401` | Wrong key, or wrong auth header (try the other) |
| `API Error: 400 ... Not supported model X` | Model name wrong (often case-sensitivity), or wrong base URL region |
| `API Error: 404` | Base URL wrong, or path missing `/anthropic` suffix |
| OAuth login appears | `.claude.json` missing or `hasCompletedOnboarding` not set |
| "Trust this API key?" prompt | API_KEY mode, fingerprint missing or wrong in `customApiKeyResponses.approved` |
| `connection refused` / DNS fail | Base URL hostname wrong |

Only after `PONG` (or equivalent) prints, tell the user `<ALIAS>` is ready and to `source ~/.zshrc`.

## Updating an existing provider

If `<NAME>` already exists, treat as update:

1. **Key changed** → overwrite `.env`, recompute fingerprint if API_KEY mode, rewrite `.claude.json`.
2. **Base URL or model changed** → overwrite `settings.json` (all four model env vars).
3. **Auth header changed** → rewrite `.env` and `.claude.json` (presence of `customApiKeyResponses` depends on mode).
4. **Alias name changed** → edit rc file (remove old function, add new).
5. Don't touch the launcher unless `<NAME>` itself changed.
6. **Always re-run Step 5** end-to-end validation after any change.

## Recovery: key stuck in rejected list

API_KEY mode only. If the user previously launched once and clicked "No" on the trust prompt, the fingerprint is in `customApiKeyResponses.rejected` and CC keeps refusing the key. Run the bundled script:

```bash
python3 ~/.claude/skills/cc-provider-add/scripts/recover-rejected.py <NAME> "<API_KEY>"
```

## What this skill never does

- Never writes to `~/.claude/`, `~/.claude/settings.json`, or any file under the user's main CC directory.
- Never modifies global env vars in `~/.profile` / `~/.zprofile` (only the rc file with the alias function).
- Never commits anything to git.
- Never sends the API key anywhere except writing it to the local secrets file (and Step 5's real API ping, which is by design).
- Never reports success without running Step 5.

## Security notes

- Secrets file always `chmod 600`.
- `~/.claude-<NAME>/.claude.json` accumulates a local `userID` after first launch; suggest the user add `~/.claude-*/` to their global gitignore.
