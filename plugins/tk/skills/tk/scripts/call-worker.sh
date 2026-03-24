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
# 实时日志：输出同时 tee 到 ${OUTPUT_FILE}.stream.log，用户可在另一终端
# tail -f <stream_log> 实时观看 Worker 输出。

set -euo pipefail

WORKER="${1:?Usage: call-worker.sh <worker> <mode> <prompt_file> <output_file> [session_id]}"
MODE="${2:?Missing mode (review|implement)}"
PROMPT_FILE="${3:?Missing prompt_file}"
OUTPUT_FILE="${4:?Missing output_file}"
SESSION_ID="${5:-}"

# 确保输出目录存在
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 实时日志文件（用户可在另一终端 tail -f 观看）
STREAM_LOG="${OUTPUT_FILE}.stream.log"
> "$STREAM_LOG"  # 清空/创建

# 检查文件是否被 gitignore（Gemini @file 对 gitignored 文件不可用）
is_gitignored() {
  git check-ignore -q "$1" 2>/dev/null
}

case "$WORKER" in
  codex)
    CODEX_ARGS=""
    if [ "$MODE" = "implement" ]; then
      CODEX_ARGS="--full-auto"
    fi
    if [ -n "$SESSION_ID" ]; then
      # Resume 指定会话
      codex exec resume "$SESSION_ID" $CODEX_ARGS -o "$OUTPUT_FILE" "$(cat "$PROMPT_FILE")" 2>&1 | tee "$STREAM_LOG"
    else
      # 新会话，stdin 管道传入
      codex exec $CODEX_ARGS -o "$OUTPUT_FILE" - < "$PROMPT_FILE" 2>&1 | tee "$STREAM_LOG"
    fi
    ;;
  gemini)
    GEMINI_ARGS=""
    if [ "$MODE" = "implement" ]; then
      GEMINI_ARGS="--approval-mode yolo"
    fi
    if [ -n "$SESSION_ID" ]; then
      # Resume 指定会话（必须用 -p 传 prompt，位置参数在 resume 模式下会超时）
      gemini --resume "$SESSION_ID" $GEMINI_ARGS -p "$(cat "$PROMPT_FILE")" 2>&1 | tee "$OUTPUT_FILE" "$STREAM_LOG"
    else
      # 新会话：优先用 @file 注入（避免 bash 管道截断/转义问题）
      # 但 @file 对 gitignored 文件不可用（Gemini 会跳过），需要 fallback 到内联 prompt
      if is_gitignored "$PROMPT_FILE"; then
        gemini $GEMINI_ARGS "$(cat "$PROMPT_FILE")" 2>&1 | tee "$OUTPUT_FILE" "$STREAM_LOG"
      else
        gemini $GEMINI_ARGS "请处理以下任务：@${PROMPT_FILE}" 2>&1 | tee "$OUTPUT_FILE" "$STREAM_LOG"
      fi
    fi
    ;;
  *)
    echo "Unknown worker: $WORKER (expected: codex | gemini)" >&2
    exit 1
    ;;
esac
