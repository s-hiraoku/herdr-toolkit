#!/usr/bin/env bash
# open-dir.sh — ディレクトリを選んで、その場所に herdr workspace を作る。
#
# herdr は「任意フォルダを起点にした workspace 作成」を CLI(--cwd)でしか出来ず、
# キーからは new_cwd ポリシー固定で任意フォルダを選べない。その穴を埋める。
#
# 候補ソースは自動検出(優先順): zoxide → ghq → 設定ルートの浅い走査 → 手入力。
# picker は fzf があれば使用、無ければ純 bash(部分一致フィルタ + 番号選択)にフォールバック。
# 外部依存ゼロで動く(fzf/zoxide/ghq はあれば快適になる、任意)。
#
# 設定(env):
#   OPEN_DIR_ROOTS  走査ルート(空白区切り)。既定は存在するものだけ。
set -eu

# plugin action は最小 PATH で走るため補完。herdr 本体は HERDR_BIN_PATH で解決。
if [ -n "${HERDR_BIN_PATH:-}" ]; then
  PATH="$(dirname "$HERDR_BIN_PATH"):$PATH"
fi
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

# 候補ディレクトリを集める(あるソースを優先順に 1 つ採用)
gather_candidates() {
  local out
  if command -v zoxide >/dev/null 2>&1; then
    out="$(zoxide query -l 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return; }
  fi
  if command -v ghq >/dev/null 2>&1; then
    out="$(ghq list --full-path 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return; }
  fi
  local roots="${OPEN_DIR_ROOTS:-$HOME/src $HOME/projects $HOME/ghq $HOME/dev $HOME/work}"
  local r
  for r in $roots; do
    [ -d "$r" ] || continue
    find "$r" -mindepth 1 -maxdepth 2 -type d 2>/dev/null || true
  done
}

# 候補から 1 つ選ぶ($1 = 改行区切りの候補)。選択結果を stdout に出す。
# 対話 I/O は /dev/tty を使う(候補を stdin で渡すため read が混ざらないように)。
pick_dir() {
  local items="$1"
  if command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "$items" | fzf --prompt="workspace dir> " --height=40% --reverse --no-multi
    return
  fi
  local query="" filtered choice sel
  while :; do
    if [ -n "$query" ]; then
      filtered="$(printf '%s\n' "$items" | grep -iF -- "$query" || true)"
    else
      filtered="$(printf '%s\n' "$items")"
    fi
    {
      echo "--- 候補 (フィルタ: ${query:-なし}) ---"
      printf '%s\n' "$filtered" | nl -ba | sed -n '1,30p'
      printf '番号=選択 / 文字=フィルタ / 空Enter=クリア / q=中止 > '
    } >/dev/tty
    IFS= read -r choice </dev/tty || return 1
    case "$choice" in
      q|Q) return 1 ;;
      '') query="" ;;
      *[!0-9]*) query="$choice" ;;
      *) sel="$(printf '%s\n' "$filtered" | sed -n "${choice}p")"
         [ -n "$sel" ] && { printf '%s\n' "$sel"; return 0; } ;;
    esac
  done
}

main() {
  local candidates dir
  candidates="$(gather_candidates)"
  if [ -n "$candidates" ]; then
    dir="$(pick_dir "$candidates" || true)"
    [ -z "${dir:-}" ] && { echo "中止しました" >/dev/tty 2>/dev/null || true; exit 0; }
  else
    printf 'workspace にするディレクトリのパス (空で中止) > ' >/dev/tty
    IFS= read -r dir </dev/tty || exit 0
    [ -z "$dir" ] && { echo "中止しました"; exit 0; }
    case "$dir" in "~") dir="$HOME" ;; "~/"*) dir="$HOME/${dir#\~/}" ;; esac
  fi
  # 正規化・存在確認
  if ! dir="$(cd "$dir" 2>/dev/null && pwd -P)"; then
    echo "エラー: 開けないディレクトリです: $dir" >&2; exit 1
  fi
  if herdr workspace create --cwd "$dir" --label "$(basename "$dir")" --focus >/dev/null 2>&1; then
    echo "→ workspace: $dir"
  else
    echo "エラー: workspace の作成に失敗しました: $dir" >&2; exit 1
  fi
}

main "$@"
