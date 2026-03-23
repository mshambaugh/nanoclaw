# NanoClaw

Personal Claude assistant. See [README.md](README.md) for philosophy and setup. See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for architecture decisions.

## Quick Context

Single Node.js process with skill-based channel system. Channels (WhatsApp, Telegram, Slack, Discord, Gmail) are skills that self-register at startup. Messages route to Claude Agent SDK running in containers (Linux VMs). Each group has isolated filesystem and memory.

## This Installation

- **Assistant name:** Sparky (configured in `.env` as `ASSISTANT_NAME`)
- **Container runtime:** Apple Container (not Docker)
- **Channel:** Telegram (@sparky_mjs_bot)
- **Main chat:** Michael (tg:8736115193) — no trigger required
- **Service:** macOS launchd (`com.nanoclaw.plist`)
- **Control script:** `./nanoclaw.sh {start|stop|restart|status|logs|sync-token|set-token}`
- **Auth:** Claude Max OAuth token (synced from macOS Keychain via `./nanoclaw.sh sync-token`)
- **Sender allowlist:** Locked to Michael only (`store/sender-allowlist.json`)
- **Mount allowlist:** `~/.config/nanoclaw/mount-allowlist.json` — entries must be `{ path, allowReadWrite }` objects, NOT plain strings

### MCP Servers (container-side)

Configured in `groups/telegram_main/.mcp.json`. Auto-approved via `enableAllProjectMcpServers` in the group's `.claude/settings.json`.

| Server | Purpose |
|--------|---------|
| `icloud-calendar` | iCloud CalDAV via `@jahfer/dav-mcp-server` |
| `email` | IMAP/SMTP via Python server at `/workspace/extra/email-mcp/` |
| `TDS Ventures ToDos` | Streamable HTTP MCP server |
| `public-com` | Public.com investment data (read-only) |

### Additional Mounts

Configured in SQLite `container_config` column for the registered group.

| Host Path | Container Path | Mode |
|-----------|---------------|------|
| `~/Documents/AI-Assisted/Sparky` | `/workspace/extra/sparky/` | read-write |
| `~/Documents/AI-Assisted/Projects/email-mcp` | `/workspace/extra/email-mcp/` | read-only |

### X (Twitter) Integration

Browser automation via Playwright on the host. Container writes IPC tasks, host runs Chrome scripts. Auth state in `data/x-auth.json`, browser profile in `data/x-browser-profile/`. Re-auth: `npx dotenv -e .env -- npx tsx .claude/skills/x-integration/scripts/setup.ts`

## Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Orchestrator: state, message loop, agent invocation |
| `src/channels/registry.ts` | Channel registry (self-registration at startup) |
| `src/ipc.ts` | IPC watcher and task processing (includes X IPC handler) |
| `src/router.ts` | Message formatting and outbound routing |
| `src/config.ts` | Trigger pattern, paths, intervals |
| `src/container-runner.ts` | Spawns agent containers with mounts |
| `src/container-runtime.ts` | Apple Container runtime abstraction |
| `src/mount-security.ts` | Mount allowlist validation |
| `src/task-scheduler.ts` | Runs scheduled tasks |
| `src/db.ts` | SQLite operations |
| `src/skills/x-integration/host.ts` | X (Twitter) host-side IPC handler |
| `groups/{name}/CLAUDE.md` | Per-group memory (isolated) |
| `groups/telegram_main/.mcp.json` | MCP servers for the main Telegram group |
| `container/skills/` | Skills loaded inside agent containers (browser, status, formatting) |

## Skills

Four types of skills exist in NanoClaw. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full taxonomy and guidelines.

- **Feature skills** — merge a `skill/*` branch to add capabilities (e.g. `/add-telegram`, `/add-slack`)
- **Utility skills** — ship code files alongside SKILL.md (e.g. `/claw`)
- **Operational skills** — instruction-only workflows, always on `main` (e.g. `/setup`, `/debug`)
- **Container skills** — loaded inside agent containers at runtime (`container/skills/`)

| Skill | When to Use |
|-------|-------------|
| `/setup` | First-time installation, authentication, service configuration |
| `/customize` | Adding channels, integrations, changing behavior |
| `/debug` | Container issues, logs, troubleshooting |
| `/update-nanoclaw` | Bring upstream NanoClaw updates into a customized install |
| `/qodo-pr-resolver` | Fetch and fix Qodo PR review issues interactively or in batch |
| `/get-qodo-rules` | Load org- and repo-level coding rules from Qodo before code tasks |

## Contributing

Before creating a PR, adding a skill, or preparing any contribution, you MUST read [CONTRIBUTING.md](CONTRIBUTING.md). It covers accepted change types, the four skill types and their guidelines, SKILL.md format rules, PR requirements, and the pre-submission checklist (searching for existing PRs/issues, testing, description format).

## Development

Run commands directly—don't tell the user to run them.

```bash
npm run dev          # Run with hot reload
npm run build        # Compile TypeScript
./container/build.sh # Rebuild agent container (build context is project root, not container/)
```

Service management (or use `./nanoclaw.sh`):
```bash
# macOS (launchd)
launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl kickstart -k gui/$(id -u)/com.nanoclaw  # restart

# Linux (systemd)
systemctl --user start nanoclaw
systemctl --user stop nanoclaw
systemctl --user restart nanoclaw
```

## Apple Container Gotchas

These were discovered during initial setup and are critical to remember:

- **No file mounts** — Apple Container only supports directory mounts (VirtioFS). You cannot mount `/dev/null` over a file. The `.env` shadowing is handled inside the container entrypoint via `mount --bind /dev/null .env` (requires starting as root, then dropping privileges via `setpriv`).
- **No `host.docker.internal`** — Containers reach the host via the VM gateway IP `192.168.64.1`, not `host.docker.internal`. The credential proxy must bind to `0.0.0.0` (not `127.0.0.1`).
- **Container build context** — `build.sh` uses project root as build context (not `container/`), so Dockerfile paths use `container/agent-runner/` prefix. The `.dockerignore` at project root controls what gets sent.
- **Stale agent-runner copies** — Per-group copies at `data/sessions/*/agent-runner-src/` are only created if missing. After changing container MCP tools, delete them: `rm -r data/sessions/*/agent-runner-src 2>/dev/null`
- **Builder cache** — To force clean rebuild: `container builder stop && container builder rm && container builder start`, then `./container/build.sh`

## Troubleshooting

**OAuth token expired (401 auth errors):** Run `./nanoclaw.sh sync-token && ./nanoclaw.sh restart` to pull the latest token from macOS Keychain. Or `./nanoclaw.sh set-token <token>` to set manually.

**Container agent not responding:** Check `tail -f logs/nanoclaw.log`. Common causes: expired OAuth token, container runtime not running (`container system start`), stale agent-runner copies.

**WhatsApp not connecting after upgrade:** WhatsApp is now a separate skill, not bundled in core. Run `/add-whatsapp` to install it.

**MCP server not detected by agent:** Ensure `.mcp.json` is in the group folder (mounted as working directory), `enableAllProjectMcpServers: true` is in the group's settings.json, and restart the service.

**Mount validation fails ("Cannot read properties of undefined"):** The mount allowlist at `~/.config/nanoclaw/mount-allowlist.json` requires `allowedRoots` entries as `{ "path": "...", "allowReadWrite": true/false }` objects, not plain strings.
