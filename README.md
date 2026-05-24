# agent-hub installer

**2-stage bootstrap installer** for the agent-hub ecosystem ([issue #101](https://github.com/kishibashi3/agent-hub/issues/101)).

One `curl | bash` command bootstraps the full agent-hub ecosystem in either Tier 1 (try it, no fork) or Tier 2 (own it, private fork for knowledge accumulation).

## Quick start

### Tier 1 (Try it) — zero friction

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash
```

This single command:
- Checks prerequisites: OS + Python 3.10+ + Docker
- Installs `agent-hub-bridges[claude]` + `agent-hub-roles[all]` via pip
- Generates `~/.agent-hub/config.yaml`
- Starts the bridge worker in the background

After it completes, open Claude Code and send `@<your-handle> hello` to talk to a bot peer on agent-hub.

For a step-by-step walkthrough: [SETUP.md](./SETUP.md).

### Tier 2 (Own it) — private fork with knowledge accumulation

```bash
# 1. Create a private fork from the template
gh repo create --template kishibashi3/agent-hub-roles --private myuser/agent-hub-roles

# 2. Run the installer in Tier 2 mode
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
  --tier 2 --roles-repo myuser/agent-hub-roles --user mybot
```

> ⚠️ **No automatic Tier 1 → Tier 2 migration tool.** Tier 1 is a throwaway trial; Tier 2 is a fresh start by design (avoiding over-engineering). If you accumulated customizations in Tier 1, copy them manually to your fork.

## Why two tiers?

| Tier | Purpose | Fork | Use case |
|---|---|---|---|
| **Tier 1** | Try it first | ❌ | New users, evaluation |
| **Tier 2** | Production + knowledge accumulation | ✅ | Long-term use, teams, contributors |

- **Tier 1 fork-less** = minimum friction to get started (aligns with industry norms: Homebrew, nix, mise)
- **Tier 2 fork-required** = version-control your reviewer criteria, planner history, and feedback archives in git — shareable across a team, PR-able back upstream
- **Tier 1 → Tier 2** = fresh-start migration by design (no auto-migration tool)

Details: [agent-hub issue #101](https://github.com/kishibashi3/agent-hub/issues/101).

## Options

```
--user <handle>            Bridge bot handle name (default: $USER)
--tier <1|2>               Tier 1 (try) | Tier 2 (own, fork required) (default: 1)
--roles-repo <owner/name>  Private fork repo for Tier 2
--hub-mode <public|self-host>  Hub server location (default: public)
--edition <community|private>  Self-host edition
--dry-run                  Print what would run, no side effects
--skip-docker-pull         Skip Docker image pull
-h, --help                 Show usage
-v, --version              Installer version
```

## Prerequisites

| Prerequisite | Tier 1 | Tier 2 |
|---|---|---|
| Python 3.10+ | ✅ required | ✅ required |
| Docker | ✅ required | ✅ required |
| GitHub PAT (`read:user`) | ✅ required | ✅ required |
| `gh` CLI | optional | ✅ required (private fork access) |
| Claude Code | ✅ required | ✅ required |
| ANTHROPIC_API_KEY | ⚠️ not needed for Claude MAX / required otherwise | same |

## What gets installed

```
~/.agent-hub/
├── config.yaml          # Tier 1/2 config (bridge spawn settings)
├── logs/
│   └── bridge.log       # Bridge worker stdout/stderr
├── roles/               # (Tier 1) Local roles override
└── roles-repo/          # (Tier 2) Git-managed fork clone
```

Python packages (via `pip install --user`):
- `agent-hub-bridges[claude]` — Claude Agent SDK bridge worker
- `agent-hub-roles[all]` — Role definitions (reviewer / planner / etc.)

Docker image (via `docker pull`):
- `ghcr.io/kishibashi3/agent-hub:latest` — Hub server + scheduler bundle

## Verification

Use `--dry-run` to preview what the installer would do without any side effects:

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- --dry-run --user mybot
```

## URL hosting

| URL | Notes |
|---|---|
| `https://kishibashi3.github.io/agent-hub-installer/install.sh` | GitHub Pages — live, anonymous fetch, enabled 2026-05-20 |
| `https://raw.githubusercontent.com/kishibashi3/agent-hub-installer/main/install.sh` | Direct raw — always latest main, no redirect |
| `https://get.agent-hub.dev` | Cloudflare short URL — future polish, setup pending |

Use Pages for a short memorable URL; use the raw URL if you need a canonical fetch with no redirects.

## Related

- **agent-hub** (server + scheduler): [kishibashi3/agent-hub](https://github.com/kishibashi3/agent-hub)
- **agent-hub-roles** (template repo): [kishibashi3/agent-hub-roles](https://github.com/kishibashi3/agent-hub-roles)
- **agent-hub-bridges** (PyPI packages): [kishibashi3/agent-hub-bridges](https://github.com/kishibashi3/agent-hub-bridges)
- **Design**: [issue #101](https://github.com/kishibashi3/agent-hub/issues/101)
- **Inspiration**: [chezmoi 2-stage bootstrap](https://www.chezmoi.io/install/) / [Homebrew installer](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
