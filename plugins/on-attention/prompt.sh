#!/usr/bin/env bash
# prompt.sh — popup の中身。state に記録された対象へジャンプするか尋ねる。
# Enter=移動 / n=閉じる。終了時に lock を解放する(次のイベントで再度開けるように)。
set -eu

if [ -n "${HERDR_BIN_PATH:-}" ]; then
  PATH="$(dirname "$HERDR_BIN_PATH"):$PATH"
fi
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-on-attention}"
trap 'rmdir "$STATE_DIR/prompt.lock" 2>/dev/null || true' EXIT

target="$(cat "$STATE_DIR/target" 2>/dev/null || true)"
[ -z "$target" ] && exit 0
status="$(printf '%s' "$target" | cut -f1)"
ws="$(printf '%s' "$target" | cut -f2)"
pane="$(printf '%s' "$target" | cut -f3)"

printf 'エージェントが "%s" になりました (%s / %s)\n' "$status" "$ws" "$pane"
printf 'そのペインにジャンプしますか? [Enter=移動 / n=閉じる] > '
IFS= read -r ans </dev/tty 2>/dev/null || ans="n"
case "$ans" in
  n|N|no) echo "閉じました" ;;
  *)
    herdr workspace focus "$ws" >/dev/null 2>&1 || true
    herdr agent focus "$pane" >/dev/null 2>&1 || true
    ;;
esac
