# Claude Docker Sandbox Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Docker 컨테이너 안에서 Claude Code를 `--dangerously-skip-permissions`로 실행하는 DinD 기반 샌드박스 CLI 도구 구현

**Architecture:** `--privileged` DinD 컨테이너에 내부 Docker 데몬을 실행하고, Git 기반 파일 동기화로 호스트 파일시스템을 보호. CLI 스크립트(`claude-sandbox`)가 컨테이너 라이프사이클을 관리.

**Tech Stack:** Docker, Bash, Ubuntu 24.04, Node.js 22 LTS, Claude Code CLI

---

### Task 1: 프로젝트 초기화

**Files:**
- Create: `.gitignore`

**Step 1: Git 저장소 초기화**

```bash
cd <project-root>
git init
```

**Step 2: .gitignore 작성**

```gitignore
# OS
.DS_Store

# Docker build context
*.tar
```

**Step 3: 초기 커밋**

```bash
git add .gitignore CLAUDE.md doc/ docs/
git commit -m "chore: initial project setup with design docs"
```

---

### Task 2: entrypoint.sh 작성

**Files:**
- Create: `entrypoint.sh`

**Step 1: entrypoint.sh 작성**

```bash
#!/bin/bash
set -e

# 내부 Docker 데몬 시작
echo "Starting Docker daemon..."
dockerd \
  --storage-driver=overlay2 \
  --log-level=warn \
  &>/var/log/dockerd.log &

# 데몬 준비 대기 (최대 30초)
echo "Waiting for Docker daemon..."
timeout=30
while ! docker info &>/dev/null; do
  timeout=$((timeout - 1))
  if [ $timeout -le 0 ]; then
    echo "ERROR: Docker daemon failed to start. Logs:"
    cat /var/log/dockerd.log
    exit 1
  fi
  sleep 1
done
echo "Docker daemon ready."

# 인자가 있으면 해당 명령 실행, 없으면 bash 진입
if [ $# -gt 0 ]; then
  exec "$@"
else
  exec bash
fi
```

**Step 2: 실행 권한 확인**

파일 첫 줄에 `#!/bin/bash`가 있는지 확인. Dockerfile에서 `chmod +x`를 처리하므로 로컬 권한은 불필요.

**Step 3: 커밋**

```bash
git add entrypoint.sh
git commit -m "feat: add entrypoint script for internal Docker daemon"
```

---

### Task 3: Dockerfile 작성

**Files:**
- Create: `Dockerfile`

**Step 1: Dockerfile 작성**

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 기본 도구
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    sudo \
    ca-certificates \
    gnupg \
    lsb-release \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Docker CE (CLI + 데몬)
RUN curl -fsSL https://get.docker.com | sh

# Docker Compose plugin
RUN apt-get update && apt-get install -y docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# 작업 디렉토리
RUN mkdir -p /workspace
WORKDIR /workspace

# 엔트리포인트
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

**Step 2: 로컬 빌드 테스트**

```bash
docker build -t claude-sandbox .
```

Expected: 이미지 빌드 성공. 각 레이어가 정상적으로 설치됨.

**Step 3: 빌드된 이미지에서 기본 동작 확인**

```bash
docker run --rm --privileged claude-sandbox echo "hello from sandbox"
```

Expected: `hello from sandbox` 출력 후 종료.

**Step 4: 내부 Docker 데몬 동작 확인**

```bash
docker run --rm --privileged claude-sandbox docker info
```

Expected: Docker 데몬 정보 출력 (Server Version, Storage Driver 등).

**Step 5: 커밋**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile with DinD support"
```

---

### Task 4: CLI 스크립트 작성 — start, status

**Files:**
- Create: `claude-sandbox`

**Step 1: claude-sandbox 스크립트 기본 구조 작성**

```bash
#!/bin/bash
set -e

CONTAINER_NAME="claude-sandbox"
IMAGE_NAME="claude-sandbox"
VOLUME_WORKSPACE="claude-sandbox-workspace"
VOLUME_DOCKER="claude-sandbox-docker-data"

usage() {
  echo "Usage: claude-sandbox <command>"
  echo ""
  echo "Commands:"
  echo "  start     Build image (if needed) and start the sandbox container"
  echo "  shell     Open a bash shell in the running container"
  echo "  stop      Stop the container (preserves data)"
  echo "  destroy   Remove container and all volumes"
  echo "  status    Show container status"
}

cmd_start() {
  # 이미 실행 중이면 알림
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Sandbox is already running. Use 'claude-sandbox shell' to connect."
    return 0
  fi

  # 정지된 컨테이너가 있으면 시작
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting existing sandbox container..."
    docker start "$CONTAINER_NAME"
    echo "Sandbox started. Use 'claude-sandbox shell' to connect."
    return 0
  fi

  # 이미지 빌드 (없거나 Dockerfile 변경 시)
  echo "Building sandbox image..."
  docker build -t "$IMAGE_NAME" "$(cd "$(dirname "$0")" && pwd)"

  # 새 컨테이너 생성 + 시작
  echo "Creating sandbox container..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    -v "${VOLUME_WORKSPACE}:/workspace" \
    -v "${VOLUME_DOCKER}:/var/lib/docker" \
    "$IMAGE_NAME" \
    sleep infinity

  # entrypoint가 Docker 데몬을 시작하도록 대기
  echo "Waiting for internal Docker daemon..."
  local timeout=30
  while ! docker exec "$CONTAINER_NAME" docker info &>/dev/null; do
    timeout=$((timeout - 1))
    if [ $timeout -le 0 ]; then
      echo "ERROR: Internal Docker daemon failed to start."
      echo "Logs:"
      docker exec "$CONTAINER_NAME" cat /var/log/dockerd.log 2>/dev/null || true
      return 1
    fi
    sleep 1
  done

  echo "Sandbox ready. Use 'claude-sandbox shell' to connect."
}

cmd_status() {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Status: RUNNING"
    docker exec "$CONTAINER_NAME" docker info --format '  Internal Docker: {{.ServerVersion}}' 2>/dev/null || true
    echo "  Workspace volume: ${VOLUME_WORKSPACE}"
  elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Status: STOPPED"
  else
    echo "Status: NOT CREATED"
  fi
}

case "${1:-}" in
  start)  cmd_start ;;
  status) cmd_status ;;
  *)      usage; exit 1 ;;
esac
```

**Step 2: 실행 권한 부여**

```bash
chmod +x claude-sandbox
```

**Step 3: start + status 테스트**

```bash
./claude-sandbox start
./claude-sandbox status
```

Expected: `Status: RUNNING`과 내부 Docker 버전 정보 출력.

**Step 4: 커밋**

```bash
git add claude-sandbox
git commit -m "feat: add CLI script with start and status commands"
```

---

### Task 5: CLI 스크립트 — shell, stop, destroy

**Files:**
- Modify: `claude-sandbox`

**Step 1: shell, stop, destroy 명령 추가**

`cmd_status()` 함수 아래에 다음 함수들을 추가:

```bash
cmd_shell() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Sandbox is not running. Run 'claude-sandbox start' first."
    return 1
  fi
  docker exec -it "$CONTAINER_NAME" bash
}

cmd_stop() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Sandbox is not running."
    return 0
  fi
  echo "Stopping sandbox..."
  docker stop "$CONTAINER_NAME"
  echo "Sandbox stopped. Data preserved in volumes."
}

cmd_destroy() {
  echo "This will delete the container and ALL data (workspace, Docker images)."
  read -p "Are you sure? [y/N] " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    return 0
  fi

  # 컨테이너 정지 + 삭제
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

  # 볼륨 삭제
  docker volume rm "$VOLUME_WORKSPACE" 2>/dev/null || true
  docker volume rm "$VOLUME_DOCKER" 2>/dev/null || true

  echo "Sandbox destroyed."
}
```

case문에 추가:

```bash
case "${1:-}" in
  start)   cmd_start ;;
  shell)   cmd_shell ;;
  stop)    cmd_stop ;;
  destroy) cmd_destroy ;;
  status)  cmd_status ;;
  *)       usage; exit 1 ;;
esac
```

**Step 2: shell 테스트**

```bash
./claude-sandbox shell
# 컨테이너 내부에서:
docker info    # 내부 Docker 데몬 확인
exit
```

Expected: 컨테이너 bash 셸 진입, 내부 Docker 정보 출력.

**Step 3: stop + status 테스트**

```bash
./claude-sandbox stop
./claude-sandbox status
```

Expected: `Status: STOPPED`.

**Step 4: start (재시작) 테스트**

```bash
./claude-sandbox start
./claude-sandbox status
```

Expected: `Status: RUNNING`. 기존 데이터 보존됨.

**Step 5: 커밋**

```bash
git add claude-sandbox
git commit -m "feat: add shell, stop, destroy commands to CLI"
```

---

### Task 6: entrypoint.sh 수정 — sleep infinity 호환

**Files:**
- Modify: `entrypoint.sh`

현재 `cmd_start`에서 `sleep infinity`를 인자로 넘기므로, entrypoint의 `$@` 분기로 sleep infinity가 실행됩니다. 하지만 이 경우 Docker 데몬 시작 후 `sleep infinity`만 실행되고 bash 셸은 열리지 않습니다 — 이것이 의도된 동작입니다. 사용자는 `claude-sandbox shell`로 접속합니다.

**Step 1: entrypoint.sh가 현재 로직으로 정확히 동작하는지 확인**

```bash
docker exec claude-sandbox ps aux
```

Expected: `dockerd`, `sleep infinity` 프로세스가 보여야 함.

**Step 2: 변경 불필요 확인 후 스킵 또는 커밋**

변경이 필요 없으면 이 태스크는 스킵.

---

### Task 7: 통합 테스트 — 전체 워크플로우 검증

**Files:** (없음 — 수동 검증)

**Step 1: 클린 스타트**

```bash
./claude-sandbox destroy  # y 입력
./claude-sandbox start
```

**Step 2: 셸 접속 및 Git clone 테스트**

```bash
./claude-sandbox shell
# 컨테이너 내부:
git clone https://github.com/octocat/Hello-World.git /workspace/test-repo
ls /workspace/test-repo
```

Expected: 리포지토리가 정상 클론됨.

**Step 3: 내부 Docker 동작 테스트**

```bash
# 컨테이너 내부:
docker run --rm hello-world
```

Expected: Docker의 `Hello from Docker!` 메시지 출력.

**Step 4: Docker Compose 테스트**

```bash
# 컨테이너 내부:
mkdir -p /workspace/compose-test
cat > /workspace/compose-test/compose.yaml << 'EOF'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
EOF
cd /workspace/compose-test
docker compose up -d
curl -s http://localhost:8080 | head -5
docker compose down
```

Expected: nginx 응답 HTML 출력.

**Step 5: Claude Code 설치 확인**

```bash
# 컨테이너 내부:
claude --version
```

Expected: Claude Code 버전 출력.

**Step 6: 정리 및 커밋**

```bash
exit  # 컨테이너에서 나가기
./claude-sandbox stop
```

변경사항이 있으면 커밋:

```bash
git add -A
git commit -m "test: verify full sandbox workflow"
```

---

### Task 8: CLAUDE.md 업데이트

**Files:**
- Modify: `CLAUDE.md`

**Step 1: CLAUDE.md를 실제 구현에 맞게 업데이트**

빌드/실행 명령, 파일 구조, 아키텍처를 반영하여 업데이트:

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker 컨테이너 안에서 Claude Code를 `--dangerously-skip-permissions`로 안전하게 실행하기 위한 DinD(Docker-in-Docker) 기반 샌드박스 도구.

## Quick Start

```bash
./claude-sandbox start    # 이미지 빌드 + 컨테이너 시작
./claude-sandbox shell    # 컨테이너 bash 접속
# 컨테이너 내부에서:
claude --dangerously-skip-permissions
```

## Commands

- `./claude-sandbox start` — 이미지 빌드(필요시) + 컨테이너 시작
- `./claude-sandbox shell` — 실행 중인 컨테이너에 bash 접속
- `./claude-sandbox stop` — 컨테이너 정지 (데이터 보존)
- `./claude-sandbox destroy` — 컨테이너 + 볼륨 완전 삭제
- `./claude-sandbox status` — 상태 확인

## Architecture

`--privileged` DinD 컨테이너에 내부 Docker 데몬 실행. 호스트 볼륨 마운트 없음 — 파일 교환은 Git으로만 수행. macOS Docker Desktop에서 `--privileged`는 LinuxKit VM 내부로 한정됨.

## Key Files

- `Dockerfile` — Ubuntu 24.04 + Docker CE + Node.js 22 + Claude Code
- `entrypoint.sh` — 내부 dockerd 시작 + 프로세스 실행
- `claude-sandbox` — CLI 스크립트 (start/shell/stop/destroy/status)
```

**Step 2: 커밋**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with implementation details"
```
