FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 기본 도구 + 로케일
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    sudo \
    ca-certificates \
    gnupg \
    lsb-release \
    iptables \
    tmux \
    locales \
    python3 \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen ko_KR.UTF-8

# 한글 + 256 컬러 환경변수
ENV LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    TERM=xterm-256color

# Docker CE (CLI + 데몬) — GPG 서명 검증
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS — GPG 서명 검증
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] \
       https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code (네이티브 바이너리 직접 설치)
RUN CLAUDE_GCS="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases" \
    && CLAUDE_VERSION=$(curl -fsSL "$CLAUDE_GCS/latest") \
    && ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in amd64) ARCH="x64" ;; arm64) ARCH="arm64" ;; esac \
    && curl -fsSL -o /usr/local/bin/claude "$CLAUDE_GCS/$CLAUDE_VERSION/linux-$ARCH/claude" \
    && chmod +x /usr/local/bin/claude

# 비root 사용자 (Claude Code는 root에서 --dangerously-skip-permissions 거부)
RUN useradd -m -s /bin/bash -G docker claude \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude \
    && mkdir -p /workspace \
    && chown claude:claude /workspace \
    && mkdir -p /home/claude/.local/bin \
    && ln -s /usr/local/bin/claude /home/claude/.local/bin/claude \
    && chown -R claude:claude /home/claude/.local \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/claude/.bashrc

WORKDIR /workspace

# 엔트리포인트
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
