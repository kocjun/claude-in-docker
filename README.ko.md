# Claude-in-Docker

Docker 컨테이너 안에서 [Claude Code](https://docs.anthropic.com/en/docs/claude-code)를 `--dangerously-skip-permissions`로 안전하게 실행하기 위한 DinD(Docker-in-Docker) 기반 샌드박스.

호스트 파일시스템을 보호하면서 풀스택 개발(docker build, compose, DB 등)이 가능한 격리 환경을 제공합니다.

## Why?

Claude Code의 `--dangerously-skip-permissions` 플래그는 모든 작업을 사전 승인 없이 자동 수행하여 작업 흐름이 끊기지 않지만, 호스트 파일시스템 손상 위험이 있습니다.

이 프로젝트는 Docker 컨테이너 안에서 Claude Code를 실행하여:

- **호스트 파일시스템 손상 방지** — 볼륨 마운트 없이 Git으로만 파일 교환
- **호스트 Docker 환경 격리** — 내부 Docker 데몬을 사용하여 호스트 Docker와 분리
- **자유로운 풀스택 개발** — 컨테이너 안에서 docker build, compose up, DB 설정 등 모두 가능

## 아키텍처

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
│  │  ┌─ 내부 Docker 데몬 ──────────────────────┐   │  │
│  │  │  Claude가 만드는 컨테이너들               │   │  │
│  │  │  (DB, 웹서버, 빌드 등)                    │   │  │
│  │  │  호스트 파일시스템 접근 불가               │   │  │
│  │  └──────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

## 사전 요구사항

- macOS + [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Linux에서도 동작하지만, `--privileged`가 호스트 커널에 직접 접근하므로 macOS Docker Desktop(LinuxKit VM 경계) 사용을 권장합니다.

## 빠른 시작

```bash
git clone https://github.com/kocjun/claude-in-docker.git
cd claude-in-docker

# 이미지 빌드 + 컨테이너 시작
./claude-sandbox start

# 컨테이너 bash 접속
./claude-sandbox shell

# 컨테이너 내부에서:
claude --dangerously-skip-permissions
```

## 명령어

| 명령 | 설명 |
|------|------|
| `./claude-sandbox start` | 이미지 빌드(필요시) + 컨테이너 시작 |
| `./claude-sandbox shell` | 실행 중인 컨테이너에 bash 접속 |
| `./claude-sandbox stop` | 컨테이너 정지 (데이터 보존) |
| `./claude-sandbox destroy` | 컨테이너 + 볼륨 완전 삭제 |
| `./claude-sandbox commit` | 현재 컨테이너 상태를 이미지로 저장 |
| `./claude-sandbox rebuild` | Dockerfile로 이미지 강제 재빌드 |
| `./claude-sandbox status` | 상태 확인 |

### 옵션

```bash
# 포트 매핑 (-p, 반복 가능)
./claude-sandbox start -p 6173:6173 -p 8080:8080

# 바인드 마운트 (-m, 반복 가능)
./claude-sandbox start -m ~/projects/my-app:/workspace/my-app

# 조합
./claude-sandbox start -p 6173:6173 -m ~/projects/my-app:/workspace/my-app
```

## 워크플로우

1. `./claude-sandbox start` → `./claude-sandbox shell`
2. 컨테이너 내부에서 `git clone <repo>` → `cd <repo>`
3. `claude --dangerously-skip-permissions` 실행
4. Claude가 자유롭게 작업 (docker build, compose up, DB 설정 등)
5. 작업 완료 후 `git push`
6. 호스트에서 `git pull`

### 컨테이너 상태 저장

컨테이너 내부에서 패키지를 설치한 후 보존하려면:

```bash
# 현재 상태를 이미지로 커밋
./claude-sandbox commit

# 다음 start 시 커밋된 이미지를 사용
./claude-sandbox stop && ./claude-sandbox destroy
./claude-sandbox start
```

Dockerfile을 기준으로 처음부터 다시 빌드하려면:

```bash
./claude-sandbox rebuild
```

## 포함 구성요소

- **Ubuntu 24.04** base image
- **Docker CE** (CLI + daemon) — DinD 지원
- **Node.js 22 LTS**
- **Claude Code** (native binary)
- **GitHub CLI** (`gh`)
- **tmux**, **python3**, **git**
- 한글 로케일 (`ko_KR.UTF-8`) + 256-color 터미널

## 보안

### 보호 가능

- 호스트 파일시스템 손상 (볼륨 마운트 없음, Git으로만 파일 교환)
- 호스트 Docker 환경 간섭 (내부 Docker 데몬 사용)
- 무분별한 패키지 설치 (컨테이너 내부로 격리)

### 보호 불가

- `--privileged`를 통한 커널 접근 (macOS에서는 LinuxKit VM 내부로 한정되어 실질적 위험 낮음)
- 네트워크를 통한 데이터 유출 (컨테이너는 인터넷 접근 가능)
- workspace 볼륨 내 파일 삭제 (Git으로 복구 가능)

> **참고**: 이 샌드박스는 **실수 방지** 목적입니다. 악의적 공격 방어가 아닌, Claude Code가 의도치 않게 호스트 파일을 삭제하거나 시스템 설정을 변경하는 것을 방지합니다.

## 호스트 연동

`~/.claude` 디렉토리가 컨테이너에 마운트되어 Claude Code 설정, 스킬, 플러그인이 호스트와 공유됩니다.

## 알려진 제한사항

- **Git 동기화 마찰**: 호스트-컨테이너 코드 교환에 commit/push/pull 필요
- **스토리지 오버헤드**: DinD 내부 Docker 이미지가 overlay-on-overlay로 저장
- **초기 구동 시간**: 내부 Docker 데몬 기동 대기 (~10초)
- **Linux 호스트**: `--privileged`가 호스트 커널에 직접 접근하므로 주의 필요 (시작 시 경고 표시)

## 라이선스

MIT
