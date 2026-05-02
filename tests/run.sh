#!/usr/bin/env bash
# End-to-end simulation of the cc-provider-add skill in an isolated $HOME.
#
# Mirrors what an agent following SKILL.md would do for two fake providers
# (one ANTHROPIC_API_KEY mode, one ANTHROPIC_AUTH_TOKEN mode), then verifies
# all artifacts and the launcher's Step-5 dispatch path.
#
# Does not call any real network. Mocks the `claude` binary on PATH.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME="$(mktemp -d -t cc-provider-add-test.XXXXXX)"

ok=0; fail=0
pass() { printf "  ✓ %s\n" "$1"; ok=$((ok+1)); }
miss() { printf "  ✗ %s\n" "$1"; fail=$((fail+1)); }
section() { printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

cleanup() { rm -rf "$TEST_HOME"; }
trap cleanup EXIT

export HOME="$TEST_HOME"
mkdir -p "$HOME/.local/bin" "$HOME/.config/ai-secrets"

# Mock claude: prints which auth header and base URL it sees.
cat > "$HOME/.local/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "MOCK_CLAUDE_RAN"
echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-unset}"
echo "API_KEY_LEN=${#ANTHROPIC_API_KEY}"
echo "AUTH_TOKEN_LEN=${#ANTHROPIC_AUTH_TOKEN}"
echo "BASE_URL=${ANTHROPIC_BASE_URL:-unset}"
EOF
chmod +x "$HOME/.local/bin/claude"
export PATH="$HOME/.local/bin:$PATH"

# Bootstrap launcher from skill template
cp "$SKILL_DIR/templates/launcher.sh" "$HOME/.local/bin/claude-provider-launch"
chmod +x "$HOME/.local/bin/claude-provider-launch"

zsh -n "$HOME/.local/bin/claude-provider-launch" && pass "launcher template zsh syntax valid" || miss "launcher template syntax invalid"

# Helper: insert a provider case branch (mirrors agent's Edit op)
insert_case() {
    local prov="$1"
    python3 - "$HOME/.local/bin/claude-provider-launch" "$prov" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
prov = sys.argv[2]
text = path.read_text()
branch = (
    f"    {prov})\n"
    f"        config_dir=\"$HOME/.claude-{prov}\"\n"
    f"        secrets_file=\"$HOME/.config/ai-secrets/{prov}.env\"\n"
    f"        ;;\n"
)
needle = "    *)\n        echo \"Unsupported provider:"
assert needle in text, "fallback marker not found"
path.write_text(text.replace(needle, branch + needle))
PYEOF
}

# Helper: write per-provider config
configure_provider() {
    local prov="$1" auth="$2" key="$3" url="$4" model="$5"
    mkdir -p "$HOME/.claude-$prov"
    printf 'export %s="%s"\n' "$auth" "$key" > "$HOME/.config/ai-secrets/$prov.env"
    chmod 600 "$HOME/.config/ai-secrets/$prov.env"

    cat > "$HOME/.claude-$prov/settings.json" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$url",
    "ANTHROPIC_MODEL": "$model",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$model",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "$model",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$model",
    "DISABLE_AUTOUPDATER": "1"
  },
  "model": "$model",
  "hasCompletedOnboarding": true
}
EOF

    if [[ "$auth" == "ANTHROPIC_API_KEY" ]]; then
        local last20
        last20=$(printf '%s' "$key" | tail -c 20)
        cat > "$HOME/.claude-$prov/.claude.json" <<EOF
{
  "hasCompletedOnboarding": true,
  "customApiKeyResponses": {
    "approved": ["$last20"],
    "rejected": []
  }
}
EOF
    else
        cat > "$HOME/.claude-$prov/.claude.json" <<EOF
{
  "hasCompletedOnboarding": true
}
EOF
    fi
}

# === Provider A: ANTHROPIC_API_KEY mode ===
section "Provider A — API_KEY mode (e.g. GLM-style)"
PROV_A=fakeglm
KEY_A="fake-glm-key-zzzzzzzzzzzzzzzzzzzz1234567890abcdefghij"
URL_A="https://example.invalid/anthropic"
MODEL_A="fake-model-1"

configure_provider "$PROV_A" ANTHROPIC_API_KEY "$KEY_A" "$URL_A" "$MODEL_A"
insert_case "$PROV_A"

[[ -f "$HOME/.config/ai-secrets/$PROV_A.env" ]] && pass "secrets file exists" || miss "secrets file missing"
# stat: GNU (Linux) syntax first, BSD (macOS) fallback. On Linux, `stat -f`
# means --file-system and writes to stdout *before* failing, so it must not be
# the first branch — its stdout would be captured into $perm even when the ||
# fallback triggers. See: actions run 25221912793.
perm=$(stat -c '%a' "$HOME/.config/ai-secrets/$PROV_A.env" 2>/dev/null \
       || stat -f '%Lp' "$HOME/.config/ai-secrets/$PROV_A.env")
[[ "$perm" == "600" ]] && pass "secrets mode 600" || miss "secrets mode is $perm"

KEY_A_LAST20=$(printf '%s' "$KEY_A" | tail -c 20)
python3 -c "
import json, pathlib
c = json.loads(pathlib.Path('$HOME/.claude-$PROV_A/.claude.json').read_text())
assert c['hasCompletedOnboarding'] is True
assert c['customApiKeyResponses']['approved'] == ['$KEY_A_LAST20']
" && pass ".claude.json has correct API_KEY-mode shape" || miss ".claude.json wrong"

python3 -c "
import json, pathlib
s = json.loads(pathlib.Path('$HOME/.claude-$PROV_A/settings.json').read_text())
assert s['env']['ANTHROPIC_BASE_URL'] == '$URL_A'
assert s['env']['ANTHROPIC_MODEL'] == '$MODEL_A'
assert s['env']['ANTHROPIC_DEFAULT_SONNET_MODEL'] == '$MODEL_A'
assert s['env']['ANTHROPIC_DEFAULT_OPUS_MODEL'] == '$MODEL_A'
assert s['env']['ANTHROPIC_DEFAULT_HAIKU_MODEL'] == '$MODEL_A'
" && pass "settings.json includes all 4 model env vars" || miss "settings.json model env vars wrong"

zsh -n "$HOME/.local/bin/claude-provider-launch" && pass "launcher syntax still valid after case insert" || miss "launcher syntax broken"

out=$("$HOME/.local/bin/claude-provider-launch" "$PROV_A" --version 2>&1 || true)
echo "$out" | grep -q "MOCK_CLAUDE_RAN" && pass "launcher exec'd claude" || miss "launcher dispatch failed"
echo "$out" | grep -q "API_KEY_LEN=${#KEY_A}" && pass "ANTHROPIC_API_KEY exported" || miss "API_KEY not exported"
echo "$out" | grep -q "AUTH_TOKEN_LEN=0" && pass "AUTH_TOKEN not leaked" || miss "AUTH_TOKEN leaked from outer env"

# === Provider B: ANTHROPIC_AUTH_TOKEN mode ===
section "Provider B — AUTH_TOKEN mode (e.g. MiMo-style)"
PROV_B=fakemimo
KEY_B="tp-fake-mimo-zzzzzzzzzzzzzzzzzzzz9876543210"
URL_B="https://other.invalid/anthropic"
MODEL_B="fake-model-2"

configure_provider "$PROV_B" ANTHROPIC_AUTH_TOKEN "$KEY_B" "$URL_B" "$MODEL_B"
insert_case "$PROV_B"

python3 -c "
import json, pathlib
c = json.loads(pathlib.Path('$HOME/.claude-$PROV_B/.claude.json').read_text())
assert c['hasCompletedOnboarding'] is True
assert 'customApiKeyResponses' not in c
" && pass ".claude.json has correct AUTH_TOKEN-mode shape (no customApiKeyResponses)" || miss ".claude.json wrong"

out=$("$HOME/.local/bin/claude-provider-launch" "$PROV_B" --version 2>&1 || true)
echo "$out" | grep -q "AUTH_TOKEN_LEN=${#KEY_B}" && pass "ANTHROPIC_AUTH_TOKEN exported" || miss "AUTH_TOKEN not exported"
echo "$out" | grep -q "API_KEY_LEN=0" && pass "API_KEY not leaked across providers" || miss "API_KEY leaked"

# === Cross-provider isolation ===
section "Cross-provider isolation"
out_a=$("$HOME/.local/bin/claude-provider-launch" "$PROV_A" 2>&1)
out_b=$("$HOME/.local/bin/claude-provider-launch" "$PROV_B" 2>&1)
echo "$out_a" | grep -q "CLAUDE_CONFIG_DIR=$HOME/.claude-$PROV_A" && pass "A points to its own config dir" || miss "A wrong config dir"
echo "$out_b" | grep -q "CLAUDE_CONFIG_DIR=$HOME/.claude-$PROV_B" && pass "B points to its own config dir" || miss "B wrong config dir"

# Outer env should not leak into either provider
section "Outer-env quarantine"
export ANTHROPIC_API_KEY="LEAKED-OUTER-KEY"
export ANTHROPIC_AUTH_TOKEN="LEAKED-OUTER-TOKEN"
export ANTHROPIC_BASE_URL="https://leaked.invalid"
out=$("$HOME/.local/bin/claude-provider-launch" "$PROV_B" 2>&1 || true)
echo "$out" | grep -q "API_KEY_LEN=0" && pass "outer ANTHROPIC_API_KEY cleared by launcher" || miss "outer API_KEY leaked through"
# AUTH_TOKEN should be the legitimate one, not the leaked outer value
echo "$out" | grep -q "AUTH_TOKEN_LEN=${#KEY_B}" && pass "outer AUTH_TOKEN replaced by secrets file" || miss "outer AUTH_TOKEN persisted"
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL

# === Negative tests ===
section "Negative tests"
out=$("$HOME/.local/bin/claude-provider-launch" bogus 2>&1 || true)
echo "$out" | grep -q "Unsupported provider" && pass "launcher rejects unknown provider" || miss "did not reject unknown"

# Missing secrets file
mv "$HOME/.config/ai-secrets/$PROV_A.env" "$HOME/.config/ai-secrets/$PROV_A.env.bak"
out=$("$HOME/.local/bin/claude-provider-launch" "$PROV_A" 2>&1 || true)
echo "$out" | grep -q "Missing secrets file" && pass "launcher catches missing secrets" || miss "did not catch missing secrets"
mv "$HOME/.config/ai-secrets/$PROV_A.env.bak" "$HOME/.config/ai-secrets/$PROV_A.env"

# Empty secrets file (neither var set)
echo "" > "$HOME/.config/ai-secrets/$PROV_A.env"
out=$("$HOME/.local/bin/claude-provider-launch" "$PROV_A" 2>&1 || true)
echo "$out" | grep -q "Neither ANTHROPIC_API_KEY nor ANTHROPIC_AUTH_TOKEN" && pass "launcher catches empty secrets" || miss "did not catch empty secrets"
configure_provider "$PROV_A" ANTHROPIC_API_KEY "$KEY_A" "$URL_A" "$MODEL_A"

# === Recovery script ===
section "Recovery script"
python3 -c "
import json, pathlib
p = pathlib.Path('$HOME/.claude-$PROV_A/.claude.json')
d = json.loads(p.read_text())
d['customApiKeyResponses']['approved'] = []
d['customApiKeyResponses']['rejected'] = ['$KEY_A_LAST20']
p.write_text(json.dumps(d, indent=2))
"
python3 "$SKILL_DIR/scripts/recover-rejected.py" "$PROV_A" "$KEY_A" >/dev/null
python3 -c "
import json, pathlib
d = json.loads(pathlib.Path('$HOME/.claude-$PROV_A/.claude.json').read_text())
assert d['customApiKeyResponses']['approved'] == ['$KEY_A_LAST20']
assert d['customApiKeyResponses']['rejected'] == []
" && pass "recovery moves rejected → approved" || miss "recovery script broken"

out=$(python3 "$SKILL_DIR/scripts/recover-rejected.py" "../bad" "$KEY_A" 2>&1 || true)
echo "$out" | grep -q "invalid provider name" && pass "recovery rejects ../" || miss "recovery accepted bad name"

out=$(python3 "$SKILL_DIR/scripts/recover-rejected.py" "$PROV_A" "tooshort" 2>&1 || true)
echo "$out" | grep -q "at least 20" && pass "recovery rejects short key" || miss "recovery accepted short key"

# === Shell alias ===
section "Shell alias dispatches via launcher"
touch "$HOME/.zshrc"
cat >> "$HOME/.zshrc" <<EOF
_claude_provider() { ~/.local/bin/claude-provider-launch "\$@"; }
c$PROV_A() { _claude_provider $PROV_A "\$@"; }
EOF

zsh -n "$HOME/.zshrc" && pass "zshrc syntax valid" || miss "zshrc syntax invalid"

out=$(zsh -c "source $HOME/.zshrc && c$PROV_A --version" 2>&1 || true)
echo "$out" | grep -q "MOCK_CLAUDE_RAN" && pass "alias dispatches" || miss "alias broken"

section "Result"
echo "passed: $ok"
echo "failed: $fail"
exit $fail
