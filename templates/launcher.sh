#!/bin/zsh
# claude-provider-launch: dispatch Claude Code to a third-party Anthropic-compatible
# API endpoint, with each provider isolated in its own CLAUDE_CONFIG_DIR.
#
# Usage: claude-provider-launch <provider> [claude args...]
#
# Add a new provider: insert a new case branch above the *) fallback below.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: claude-provider-launch <provider> [claude args...]" >&2
    exit 1
fi

provider="$1"
shift

case "$provider" in
    # PROVIDER CASES BELOW — insert new branches here, format:
    #     <name>)
    #         config_dir="$HOME/.claude-<name>"
    #         secrets_file="$HOME/.config/ai-secrets/<name>.env"
    #         ;;
    *)
        echo "Unsupported provider: $provider" >&2
        exit 1
        ;;
esac

[[ -f "$secrets_file" ]] || { echo "Missing secrets file: $secrets_file" >&2; exit 1; }

# Clear any inherited Anthropic env to avoid conflicts; secrets file + settings.json repopulate.
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL \
      ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL

# shellcheck disable=SC1090
source "$secrets_file"

if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    echo "Neither ANTHROPIC_API_KEY nor ANTHROPIC_AUTH_TOKEN set in $secrets_file" >&2
    exit 1
fi

export CLAUDE_CONFIG_DIR="$config_dir"

exec claude "$@"
