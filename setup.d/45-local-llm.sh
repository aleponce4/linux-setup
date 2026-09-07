#!/usr/bin/env bash
# 45-local-llm.sh - llama.cpp with the Vulkan backend on the Arc B570, a small instruct model,
#                   and a llama-server user service on localhost.
#
# Why local at all: the dictation cleanup in productivity/bin/dictate-polish pays 2.5-4 s of
# network round trip before a remote model emits its first token. That is most of its latency
# and it is pure overhead for a task (punctuation, filler removal) a 4B model does well.
#
# Why Vulkan and not IPEX-LLM: Intel archived IPEX-LLM in January 2026. Vulkan is the
# supported route on Battlemage, and Speech Note already transcribes through the same stack.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

apt_install_list "$LISTS_DIR/apt-llm.txt"

# ---- model ----
# Kept on the root disk, not /data: the user service starts at login and /data is a separate
# device that may not be mounted yet. ~3 GB against ~850 GB free is not worth the dependency.
LLM_MODEL_DIR="${LLM_MODEL_DIR:-$HOME/.local/share/llama/models}"
LLM_MODEL_FILE="${LLM_MODEL_FILE:-Qwen3-4B-Instruct-2507-Q5_K_M.gguf}"
LLM_MODEL_URL="${LLM_MODEL_URL:-https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/$LLM_MODEL_FILE}"
# 11434, not 8080: CVAT's traefik binds 8080 and documents it as its default, and the two
# collided the first time this ran ("failed to bind host port 0.0.0.0:8080: address already
# in use"). 11434 is the conventional local-LLM port and is clear of web tooling.
LLM_PORT="${LLM_PORT:-11434}"

mkdir -p "$LLM_MODEL_DIR"
if [[ -s "$LLM_MODEL_DIR/$LLM_MODEL_FILE" ]]; then
  log "model already present: $LLM_MODEL_FILE"
else
  log "downloading $LLM_MODEL_FILE (~3 GB, resumable)"
  curl -fL --retry 3 --no-progress-meter -C - -o "$LLM_MODEL_DIR/$LLM_MODEL_FILE.part" "$LLM_MODEL_URL" \
    && mv "$LLM_MODEL_DIR/$LLM_MODEL_FILE.part" "$LLM_MODEL_DIR/$LLM_MODEL_FILE" \
    || warn "model download failed; dictate-polish will fall back to the remote model"
fi

# ---- llama-server user service ----
# Bound to 127.0.0.1: this is a local accelerator, not a network service. Do not expose it
# over the tailnet without thinking about who can then run inference on this GPU.
if have llama-server && [[ -s "$LLM_MODEL_DIR/$LLM_MODEL_FILE" ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  cat >"$HOME/.config/systemd/user/llama-server.service" <<EOF
[Unit]
Description=llama.cpp server (local model for dictation cleanup and agent use)
Documentation=file://$HOME/linux-setup/docs/dictation.md
After=graphical-session.target

[Service]
Type=simple
Environment=GGML_VK_VISIBLE_DEVICES=0
ExecStart=/usr/bin/llama-server \\
  --model $LLM_MODEL_DIR/$LLM_MODEL_FILE \\
  --host 127.0.0.1 --port $LLM_PORT \\
  --ctx-size 8192 \\
  --n-gpu-layers 999 \\
  --threads 6 \\
  --no-webui
Restart=on-failure
RestartSec=5
# The GPU is shared with Speech Note and the desktop; do not let inference starve them.
Nice=5

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now llama-server.service 2>/dev/null \
    || warn "llama-server user service not started (starts at next login)"
  log "llama-server on 127.0.0.1:$LLM_PORT"
else
  warn "llama-server binary or model missing; skipping the user service"
fi
