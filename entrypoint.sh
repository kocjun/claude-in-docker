#!/bin/bash
set -e

# 이전 실행에서 남은 PID 파일 정리 (컨테이너 재시작 시)
rm -f /var/run/docker.pid /var/run/docker/containerd/containerd.pid

# 내부 Docker 데몬 시작
echo "Starting Docker daemon..."
dockerd \
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
