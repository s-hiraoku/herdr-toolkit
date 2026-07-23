#!/usr/bin/env bash
# on-event.sh — pane.agent_status_changed イベントハンドラ。
# 対象 status(既定 blocked)になったら、その pane を state に記録し、
# 「ジャンプする?」を尋ねる popup を開く(フォーカスは奪わない)。
set -eu

if [ -n "${HERDR_BIN_PATH:-}" ]; then
  PATH="$(dirname "$HERDR_BIN_PATH"):$PATH"
fi
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

# 対象 status(空白区切り)。既定は blocked のみ(=あなたの入力が要るときだけ)。
TRIGGER="${ON_ATTENTION_STATUS:-blocked}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-on-attention}"
mkdir -p "$STATE_DIR" 2>/dev/null || true

json="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -z "$json" ] && exit 0

status="$(printf '%s' "$json" | jq -r '.data.agent_status // empty' 2>/dev/null || true)"
pane="$(printf '%s' "$json" | jq -r '.data.pane_id // empty' 2>/dev/null || true)"
ws="$(printf '%s' "$json" | jq -r '.data.workspace_id // empty' 2>/dev/null || true)"
if [ -z "$status" ] || [ -z "$pane" ]; then
  exit 0
fi

# 対象 status か判定
hit=0
for s in $TRIGGER; do
  [ "$s" = "$status" ] && hit=1
done
[ "$hit" -eq 1 ] || exit 0

# workspace_id が空なら pane_id の ':' 前から導出
[ -z "$ws" ] && ws="${pane%%:*}"

# 対象ペインが既に見えている(=フォーカス中 workspace の表示中タブ)なら popup 不要。
# 判定に失敗した場合は従来どおり popup を出す(安全側)。
tab="$(herdr agent list 2>/dev/null \
  | jq -r --arg p "$pane" '.result.agents[]? | select(.pane_id == $p) | .tab_id // empty' 2>/dev/null || true)"
if [ -n "$tab" ]; then
  visible="$(herdr workspace list 2>/dev/null \
    | jq -r --arg ws "$ws" --arg tab "$tab" \
      '.result.workspaces[]? | select(.workspace_id == $ws and .focused == true and .active_tab_id == $tab) | "1"' 2>/dev/null || true)"
  [ "$visible" = "1" ] && exit 0
fi

# 多重 popup 防止(atomic lock)。既に prompt が開いていれば何もしない。
if mkdir "$STATE_DIR/prompt.lock" 2>/dev/null; then
  printf '%s\t%s\t%s\n' "$status" "$ws" "$pane" > "$STATE_DIR/target"
  if ! herdr plugin pane open --plugin s-hiraoku.on-attention --entrypoint prompt >/dev/null 2>&1; then
    rmdir "$STATE_DIR/prompt.lock" 2>/dev/null || true
  fi
fi
