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
- `entrypoint.sh` — 내부 dockerd 시작 (stale PID 정리 포함) + 프로세스 실행
- `claude-sandbox` — CLI 스크립트 (start/shell/stop/destroy/status)

## Design Docs

- `docs/plans/2026-03-03-claude-docker-sandbox-design.md` — 아키텍처 설계 및 트레이드오프 분석
- `doc/brainstorming.md` — 초기 리서치 (Vagrant, Docker, VM 비교)
- `doc/brainstorming2.md` — 커뮤니티 샌드박싱 접근법 수집
