#!/usr/bin/env python3
"""
Recover from a stuck "rejected" API key in ~/.claude-<name>/.claude.json.

If the user previously launched the provider once and clicked "No" on the
"trust this API key?" prompt, the key fingerprint (last 20 chars of the key)
ends up in customApiKeyResponses.rejected and Claude Code keeps refusing it.

This script moves the fingerprint to .approved and sets hasCompletedOnboarding=true.

Usage:
    recover-rejected.py <provider_name> <api_key>
    recover-rejected.py mimo "$(cat ~/.config/ai-secrets/mimo.env | sed -n 's/.*"\\(.*\\)"/\\1/p')"

The provider's config dir must already exist at ~/.claude-<provider_name>/.
"""

import json
import pathlib
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    name, key = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"[a-z0-9-]+", name):
        print(f"invalid provider name: {name!r}", file=sys.stderr)
        return 2
    if len(key) < 20:
        print("api key must be at least 20 characters", file=sys.stderr)
        return 2

    suffix = key[-20:]
    config = pathlib.Path.home() / f".claude-{name}/.claude.json"
    if not config.parent.is_dir():
        print(f"missing config dir: {config.parent}", file=sys.stderr)
        return 1

    data = json.loads(config.read_text()) if config.exists() else {}
    data["hasCompletedOnboarding"] = True
    responses = data.setdefault("customApiKeyResponses", {"approved": [], "rejected": []})
    responses["rejected"] = [s for s in responses.get("rejected", []) if s != suffix]
    approved = responses.setdefault("approved", [])
    if suffix not in approved:
        approved.append(suffix)

    config.write_text(json.dumps(data, indent=2) + "\n")
    print(f"recovered: {config}")
    print(f"  approved: {approved}")
    print(f"  rejected: {responses['rejected']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
