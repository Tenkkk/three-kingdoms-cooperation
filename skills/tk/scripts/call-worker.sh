#!/usr/bin/env bash
# call-worker.sh — 统一调用 Worker CLI，处理 prompt 输入、输出捕获和实时日志
# Usage: call-worker.sh <worker> <mode> <prompt_file> <output_file> [session_id]
#
# worker:     codex | gemini
# mode:       review (只读沙箱) | implement (可写)
# prompt_file: 包含完整 prompt 的文件路径
# output_file: Worker 回复写入的文件路径
# session_id:  可选，用于 resume 上一轮会话
#
# 输出文件：
#   ${OUTPUT_FILE}             — Worker 最终回复（codex 用 -o 写入；gemini 用 tee 写入）
#   ${OUTPUT_FILE}.stream.log  — stdout 完整输出（命令完成后可用）
#   ${OUTPUT_FILE}.stderr.log  — stderr 实时输出（IDE 中实时可见，推荐用户 watch）
#
# [!IMPORTANT] 调用方（Claude）必须使用 run_in_background: true 调用本脚本，
# 否则 Bash 工具 600s (10min) 超时会杀掉 Codex 等长时间运行的 Worker。

set -euo pipefail

WORKER="${1:?Usage: call-worker.sh <worker> <mode> <prompt_file> <output_file> [session_id]}"
MODE="${2:?Missing mode (review|implement)}"
PROMPT_FILE="${3:?Missing prompt_file}"
OUTPUT_FILE="${4:?Missing output_file}"
SESSION_ID="${5:-}"

# --- 路径绝对化（防止 CWD 漂移导致文件写错位置）---
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
export PROJECT_ROOT

case "$OUTPUT_FILE" in
  /*|[A-Za-z]:*) ;; # 已经是绝对路径（Unix / 或 Windows C:）
  *) OUTPUT_FILE="${PROJECT_ROOT}/${OUTPUT_FILE}" ;;
esac
case "$PROMPT_FILE" in
  /*|[A-Za-z]:*) ;;
  *) PROMPT_FILE="${PROJECT_ROOT}/${PROMPT_FILE}" ;;
esac

# 确保输出目录存在
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 日志文件
STREAM_LOG="${OUTPUT_FILE}.stream.log"
STDERR_FILE="${OUTPUT_FILE}.stderr.log"
> "$STREAM_LOG"   # 清空/创建
> "$STDERR_FILE"  # 清空/创建

# --- 错误处理 ---
cleanup_on_error() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    {
      echo ""
      echo "=== WORKER FAILED (exit code: $exit_code) ==="
      echo "Worker: $WORKER | Mode: $MODE | Time: $(date -Iseconds 2>/dev/null || date)"
      if [ -s "$STDERR_FILE" ]; then
        echo "--- stderr (last 20 lines) ---"
        tail -20 "$STDERR_FILE"
      fi
    } >> "$STREAM_LOG"
    # 仍以错误码退出，让调用方（Claude）看到失败
    exit $exit_code
  fi
}
trap cleanup_on_error EXIT

# 打印路径信息（出现在 stream.log 开头，供调试）
echo "[tk] Worker: $WORKER | Mode: $MODE"
echo "[tk] Real-time progress: $STDERR_FILE"
echo "[tk] Full output: $STREAM_LOG"
echo "[tk] Starting..."

# --- 检查文件是否被 gitignore（Gemini @file 对 gitignored 文件不可用）---
is_gitignored() {
  git check-ignore -q "$1" 2>/dev/null
}

# --- UUID 生成（Gemini --session-id 用；Git Bash 无 uuidgen，依次回退 python/powershell）---
gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  elif command -v python >/dev/null 2>&1; then
    python -c 'import uuid; print(uuid.uuid4())'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command '[guid]::NewGuid().ToString()' | tr -d '\r\n'
  else
    echo "ERROR: no uuid generator (need uuidgen, python, or powershell.exe)" >&2
    return 1
  fi
}

case "$WORKER" in
  codex)
    CODEX_ARGS=""
    if [ "$MODE" = "implement" ]; then
      CODEX_ARGS="--full-auto"
    fi
    if [ -n "$SESSION_ID" ]; then
      # Resume 指定会话
      codex exec resume "$SESSION_ID" $CODEX_ARGS -o "$OUTPUT_FILE" "$(cat "$PROMPT_FILE")" 2> "$STDERR_FILE" | tee "$STREAM_LOG"
    else
      # 新会话，stdin 管道传入
      codex exec $CODEX_ARGS -o "$OUTPUT_FILE" - < "$PROMPT_FILE" 2> "$STDERR_FILE" | tee "$STREAM_LOG"
    fi
    ;;
  gemini)
    GEMINI_ARGS=""
    if [ "$MODE" = "implement" ]; then
      GEMINI_ARGS="--approval-mode yolo"
    fi
    if [ -n "$SESSION_ID" ]; then
      # Resume 指定会话（接受任意之前用过的 UUID；必须用 -p 传 prompt，位置参数在 resume 模式下会超时）
      gemini --resume "$SESSION_ID" $GEMINI_ARGS -p "$(cat "$PROMPT_FILE")" 2>> "$STDERR_FILE" | tee "$OUTPUT_FILE" "$STREAM_LOG"
    else
      # 新会话：host 自带 UUID（--session-id <uuid>），并以 Codex 同款 banner 写入 stderr.log，
      # 让调用方用同一段 grep 模式从 stderr.log 抓取 session id。
      NEW_ID="$(gen_uuid)"
      echo "session id: $NEW_ID" >> "$STDERR_FILE"
      # @file 对 gitignored 文件不可用（Gemini 会跳过），需要 fallback 到内联 prompt
      if is_gitignored "$PROMPT_FILE"; then
        gemini --session-id "$NEW_ID" $GEMINI_ARGS "$(cat "$PROMPT_FILE")" 2>> "$STDERR_FILE" | tee "$OUTPUT_FILE" "$STREAM_LOG"
      else
        gemini --session-id "$NEW_ID" $GEMINI_ARGS "请处理以下任务：@${PROMPT_FILE}" 2>> "$STDERR_FILE" | tee "$OUTPUT_FILE" "$STREAM_LOG"
      fi
    fi
    ;;
  *)
    echo "Unknown worker: $WORKER (expected: codex | gemini)" >&2
    exit 1
    ;;
esac
