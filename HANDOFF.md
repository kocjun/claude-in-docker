# HANDOFF.md

## Goal

Docker 컨테이너 안에서 Claude Code를 `--dangerously-skip-permissions`로 안전하게 실행하는 DinD(Docker-in-Docker) 기반 샌드박스 도구. 호스트 파일시스템 손상을 방지하면서 풀스택 개발(docker build, compose, DB 등)이 가능한 격리 환경 제공.

## Current Progress

### 완성된 것
- **Dockerfile**: Ubuntu 24.04 + Docker CE + Node.js 22 + Claude Code(네이티브 바이너리) + gh CLI + tmux + python3 + 한글 로케일 + 256-color
- **entrypoint.sh**: 내부 Docker 데몬 시작 + stale PID 정리
- **claude-sandbox CLI**: start / shell / stop / destroy / commit / rebuild / status
- **보안**: GPG 서명 검증된 APT 저장소, Linux 호스트 --privileged 경고, 비root 사용자(claude)
- **호스트 연동**: `~/.claude` 마운트로 설정/스킬/플러그인 공유
- **statusline-colorful.py**: macOS/Linux 크로스플랫폼 지원 (CPU, 메모리, 네트워크, OAuth)

### 아키텍처
```
Host (macOS) → --privileged DinD 컨테이너 → 내부 Docker 데몬
- 호스트 볼륨 마운트 없음 (Git으로만 파일 교환)
- ~/.claude만 마운트 (설정 공유)
- Named volumes: workspace + docker-data
```

### CLI 명령어
| 명령 | 동작 |
|------|------|
| `start` | 이미지 빌드(없으면) + 컨테이너 시작 |
| `shell` | claude 사용자로 bash 접속 |
| `stop` | 정지 (데이터 보존) |
| `destroy` | 컨테이너 + 볼륨 삭제 |
| `commit` | 현재 상태를 이미지로 저장 |
| `rebuild` | Dockerfile로 이미지 재빌드 |
| `status` | 상태 확인 |

## What Worked

- **DinD + --privileged + 볼륨 마운트 없음**: macOS Docker Desktop에서 --privileged가 LinuxKit VM 내부로 한정되어 실질적으로 안전
- **비root 사용자**: Claude Code가 root에서 `--dangerously-skip-permissions` 거부하므로 `claude` 사용자 필수
- **네이티브 바이너리 직접 설치**: GCS에서 바이너리를 `/usr/local/bin/claude`로 직접 다운로드 + `~/.local/bin/claude` 심볼릭 링크
- **GPG 서명 검증 APT 저장소**: Docker CE, Node.js를 curl|sh 대신 서명 검증으로 설치
- **commit/rebuild 패턴**: 컨테이너 내부 변경사항을 이미지로 보존 가능

## What Didn't Work

- **Docker Socket 마운트 방식 (접근법 B)**: `/var/run/docker.sock` 마운트는 호스트 Docker에 대한 root 접근과 동일하여 샌드박스 무의미. `docker run -v /:/host`로 호스트 전체 파일시스템 접근 가능
- **npm install -g @anthropic-ai/claude-code**: "Claude Code has switched from npm to native installer" 경고 발생. 네이티브 바이너리로 전환 필요
- **curl -fsSL https://claude.ai/install.sh | sh**: Docker 빌드 환경에서 `claude install` 단계 실패. 바이너리 직접 다운로드로 우회
- **--storage-driver=overlay2**: macOS Docker Desktop에서 overlay2 커널 모듈 미지원. 자동 감지로 변경
- **Sysbox 런타임**: macOS Docker Desktop 미지원 (Linux 전용)

## Next Steps

- [ ] `statusline-colorful.py` 변경사항 커밋 (macOS/Linux 크로스플랫폼 수정 완료, 아직 미커밋)
- [ ] 통합 테스트 재실행 (Dockerfile 변경 후 전체 워크플로우 검증)
- [ ] README.md 작성 (설치 방법, 사용법, 보안 특성 문서화)
- [ ] 네트워크 제한 옵션 검토 (`--network=none` 모드 또는 DNS 화이트리스트)
- [ ] CLAUDE.md 업데이트 (commit/rebuild 명령, 한글/256-color 지원 등 반영)
- [ ] `claude-sandbox` 스크립트에 `logs` 명령 추가 검토 (내부 Docker 데몬 로그 조회)

## Key Files

- `Dockerfile` — 이미지 정의
- `entrypoint.sh` — 컨테이너 엔트리포인트
- `claude-sandbox` — CLI 스크립트
- `~/.claude/statusline-colorful.py` — 크로스플랫폼 statusline (프로젝트 외부)
- `docs/plans/2026-03-03-claude-docker-sandbox-design.md` — 설계 문서
- `docs/plans/2026-03-03-claude-docker-sandbox-implementation.md` — 구현 계획
