# Claude-in-Docker

[한국어](README.ko.md)

A DinD (Docker-in-Docker) sandbox for safely running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with `--dangerously-skip-permissions` inside a Docker container.

Provides an isolated environment for full-stack development (docker build, compose, DB, etc.) while protecting your host filesystem.

## Why?

Claude Code's `--dangerously-skip-permissions` flag auto-approves all operations for an uninterrupted workflow, but risks damaging your host filesystem.

This project runs Claude Code inside a Docker container to:

- **Protect host filesystem** — no volume mounts; file exchange via Git only
- **Isolate Docker environments** — uses an internal Docker daemon, separate from host Docker
- **Enable full-stack development** — docker build, compose up, DB setup, etc. all work inside the container

## Architecture

```
┌─ Host (macOS) ──────────────────────────────────────┐
│                                                      │
│  ~/projects/my-app/  (Git repo)                      │
│       │                                              │
│       │ git push/pull                                │
│       ▼                                              │
│  ┌─ Claude Container (--privileged) ──────────────┐  │
│  │                                                 │  │
│  │  /workspace/my-app/  (git clone)                │  │
│  │  claude --dangerously-skip-permissions           │  │
│  │                                                 │  │
│  │  ┌─ Internal Docker Daemon ─────────────────┐   │  │
│  │  │  Containers created by Claude             │   │  │
│  │  │  (DB, web servers, builds, etc.)          │   │  │
│  │  │  No access to host filesystem             │   │  │
│  │  └──────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

## Prerequisites

- macOS with [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Also works on Linux, but `--privileged` grants direct host kernel access. macOS Docker Desktop (LinuxKit VM boundary) is recommended.

## Quick Start

```bash
git clone https://github.com/kocjun/claude-in-docker.git
cd claude-in-docker

# Build image + start container
./claude-sandbox start

# Open a bash shell inside the container
./claude-sandbox shell

# Inside the container:
claude --dangerously-skip-permissions
```

## Commands

| Command | Description |
|---------|-------------|
| `./claude-sandbox start` | Build image (if needed) + start container |
| `./claude-sandbox shell` | Open bash shell in the running container |
| `./claude-sandbox stop` | Stop container (data preserved) |
| `./claude-sandbox destroy` | Remove container + delete all volumes |
| `./claude-sandbox commit` | Save current container state to image |
| `./claude-sandbox rebuild` | Force rebuild image from Dockerfile |
| `./claude-sandbox status` | Show current status |

### Options

```bash
# Port mapping (-p, repeatable)
./claude-sandbox start -p 6173:6173 -p 8080:8080

# Bind mount (-m, repeatable)
./claude-sandbox start -m ~/projects/my-app:/workspace/my-app

# Combined
./claude-sandbox start -p 6173:6173 -m ~/projects/my-app:/workspace/my-app
```

## Workflow

1. `./claude-sandbox start` → `./claude-sandbox shell`
2. Inside the container: `git clone <repo>` → `cd <repo>`
3. Run `claude --dangerously-skip-permissions`
4. Claude works freely (docker build, compose up, DB setup, etc.)
5. When done: `git push`
6. On host: `git pull`

### Saving Container State

To preserve packages installed inside the container:

```bash
# Commit current state to image
./claude-sandbox commit

# Next start will use the committed image
./claude-sandbox stop && ./claude-sandbox destroy
./claude-sandbox start
```

To rebuild from scratch using the Dockerfile:

```bash
./claude-sandbox rebuild
```

## What's Inside

- **Ubuntu 24.04** base image
- **Docker CE** (CLI + daemon) — DinD support
- **Node.js 22 LTS**
- **Claude Code** (native binary)
- **GitHub CLI** (`gh`)
- **tmux**, **python3**, **git**
- Korean locale (`ko_KR.UTF-8`) + 256-color terminal

## Security

### Protected

- Host filesystem damage (no volume mounts; file exchange via Git only)
- Host Docker environment interference (uses internal Docker daemon)
- Uncontrolled package installations (isolated inside the container)

### Not Protected

- Kernel access via `--privileged` (on macOS, confined to LinuxKit VM — low practical risk)
- Data exfiltration via network (container has internet access)
- File deletion within workspace volume (recoverable via Git)

> **Note**: This sandbox is designed for **accident prevention**, not defense against malicious attacks. It prevents Claude Code from unintentionally deleting host files or modifying system configurations.

## Host Integration

The `~/.claude` directory is mounted into the container, sharing Claude Code settings, skills, and plugins with the host.

## Known Limitations

- **Git sync friction**: Code exchange between host and container requires commit/push/pull
- **Storage overhead**: DinD internal Docker images stored as overlay-on-overlay
- **Startup time**: Internal Docker daemon takes ~10 seconds to initialize
- **Linux hosts**: `--privileged` grants direct host kernel access — use with caution (warning displayed on start)

## License

MIT
