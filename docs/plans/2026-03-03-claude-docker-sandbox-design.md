# Claude Docker Sandbox 설계

## 목적

Docker 컨테이너 안에서 Claude Code를 `--dangerously-skip-permissions`로 실행하여 풀스택 개발을 수행하되, 호스트 파일시스템 손상을 방지하는 샌드박스 환경 구축.

## 결정 사항

- **접근법**: DinD (Docker-in-Docker) + `--privileged` + 볼륨 마운트 제한
- **호스트**: macOS (Docker Desktop) — `--privileged`가 LinuxKit VM 내부로 한정되어 실질적 위험 낮음
- **파일 동기화**: Git 기반 (호스트 파일시스템 직접 마운트 없음)
- **인증**: OAuth 로그인 (`claude login`)
- **인터페이스**: CLI 스크립트 (`claude-sandbox`)

## 아키텍처

```
┌─ Host (macOS) ──────────────────────────────────────┐
│                                                       │
│  ~/projects/my-app/  (Git repo)                       │
│       │                                               │
│       │ git push/pull                                 │
│       ▼                                               │
│  ┌─ Claude Container (--privileged) ───────────────┐  │
│  │                                                  │  │
│  │  /workspace/my-app/  (git clone)                 │  │
│  │                                                  │  │
│  │  claude --dangerously-skip-permissions            │  │
│  │                                                  │  │
│  │  ┌─ 내부 Docker 데몬 (dockerd) ──────────────┐   │  │
│  │  │  Claude가 만드는 컨테이너들                  │   │  │
│  │  │  (DB, 웹서버, 빌드 등)                      │   │  │
│  │  │  호스트 파일시스템 접근 불가                  │   │  │
│  │  └────────────────────────────────────────────┘   │  │
│  │                                                  │  │
│  │  호스트와의 유일한 연결: Git (네트워크)            │  │
│  └──────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
```

## 구성 요소

### Dockerfile

Ubuntu 24.04 기반. Docker CE (CLI + 데몬), Node.js 22 LTS, Docker Compose plugin, Claude Code, Git 설치.

### entrypoint.sh

내부 Docker 데몬(`dockerd`)을 백그라운드로 시작하고 준비 완료를 대기한 뒤 bash 셸 진입.

### CLI 스크립트 (`claude-sandbox`)

| 명령 | 동작 |
|------|------|
| `start` | 이미지 빌드(필요시) + 컨테이너 시작. `--privileged`, named volume 사용 |
| `shell` | 실행 중인 컨테이너에 bash 셸 접속 |
| `stop` | 컨테이너 정지 (데이터 보존) |
| `destroy` | 컨테이너 + 볼륨 삭제 (완전 초기화) |
| `status` | 컨테이너 상태 확인 |

### 데이터 영속성 (Named Volumes)

- `workspace`: `/workspace` — Git clone한 코드, 작업 파일
- `docker-data`: `/var/lib/docker` — 내부 Docker 이미지/컨테이너 캐시

### 워크플로우

1. `claude-sandbox start` + `claude-sandbox shell`
2. 컨테이너 내부에서 `git clone <repo>` → `claude --dangerously-skip-permissions`
3. Claude가 자유롭게 작업 (docker build, compose up, DB 설정 등)
4. 작업 완료 후 `git push`
5. 호스트에서 `git pull`

## 보안 특성

### 보호 가능

- 호스트 파일시스템 손상 (볼륨 마운트 없음)
- 호스트 Docker 환경 간섭 (내부 데몬 사용)
- 무분별한 패키지 설치 (컨테이너 내부로 격리)

### 보호 불가

- `--privileged`를 통한 LinuxKit VM 커널 접근 (macOS에서 실질적 위험 낮음)
- 네트워크를 통한 데이터 유출 (컨테이너는 인터넷 접근 가능)
- workspace 볼륨 내 파일 삭제 (Git으로 복구 가능)

## 알려진 트레이드오프

- **Git 동기화 마찰**: 호스트-컨테이너 코드 교환에 commit/push/pull 필요
- **스토리지 오버헤드**: DinD 내부 Docker 이미지가 overlay-on-overlay로 저장
- **초기 구동 시간**: 내부 Docker 데몬 기동 대기 필요
