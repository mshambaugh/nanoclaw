#!/bin/bash
# NanoClaw service control

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST=~/Library/LaunchAgents/com.nanoclaw.plist
ENV_FILE="$SCRIPT_DIR/.env"
CREDS_FILE=~/.claude/.credentials.json

case "${1:-}" in
  start)
    launchctl load "$PLIST" 2>/dev/null
    echo "NanoClaw started"
    ;;
  stop)
    launchctl unload "$PLIST" 2>/dev/null
    echo "NanoClaw stopped"
    ;;
  restart)
    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST"
    echo "NanoClaw restarted"
    ;;
  status)
    if launchctl list | grep -q com.nanoclaw; then
      echo "NanoClaw is running"
    else
      echo "NanoClaw is stopped"
    fi
    ;;
  logs)
    tail -f "$SCRIPT_DIR/logs/nanoclaw.log"
    ;;
  sync-token)
    # Sync OAuth token from macOS Keychain to .env
    CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -z "$CREDS" ]; then
      echo "No credentials found in Keychain"
      echo "Run 'claude setup-token' first, then try again"
      exit 1
    fi
    TOKEN=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
    if [ -z "$TOKEN" ]; then
      echo "Could not extract token from Keychain"
      exit 1
    fi
    sed -i '' "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=$TOKEN|" "$ENV_FILE"
    cp "$ENV_FILE" "$SCRIPT_DIR/data/env/env"
    echo "Token synced from Keychain"
    echo "Run '$0 restart' to apply"
    ;;
  set-token)
    # Manually set a new OAuth token
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 set-token <token>"
      exit 1
    fi
    sed -i '' "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=$2|" "$ENV_FILE"
    cp "$ENV_FILE" "$SCRIPT_DIR/data/env/env"
    echo "Token updated"
    echo "Run '$0 restart' to apply"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|sync-token|set-token <token>}"
    exit 1
    ;;
esac
