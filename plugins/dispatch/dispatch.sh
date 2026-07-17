#!/usr/bin/env bash
# dispatch.sh — AI エージェントをローカル(split)か新規worktree(workspace)に送り出す
#
# 使い方:
#   dispatch.sh                          # モードを対話選択し、プロンプトを聞いて起動
#   dispatch.sh --local  "プロンプト"     # 現在のリポジトリで split して起動
#   dispatch.sh --worktree "プロンプト"   # 新規 worktree + workspace で起動
#   dispatch.sh --worktree -n 3 "..."    # worktree 3本で並列起動
#   dispatch.sh --worktree --no-prompt   # プロンプトなしで claude だけ起動(指示は手で打つ)
#
# 環境:
#   herdr のプラグインアクション/カスタムコマンドから呼ばれる場合は
#   HERDR_ACTIVE_PANE_CWD が渡される。CLI から直接呼んだ場合は $PWD を使う。
#   エージェントコマンドは $DISPATCH_AGENT (デフォルト: claude) で差し替え可能。
set -eu

MODE=""
COUNT=1
NO_PROMPT=0
PROMPT=""
AGENT_CMD="${DISPATCH_AGENT:-claude}"

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--local)    MODE="local" ;;
    -w|--worktree) MODE="worktree" ;;
    -n)            shift; COUNT="${1:-1}" ;;
    --no-prompt)   NO_PROMPT=1 ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             PROMPT="${PROMPT:+$PROMPT }$1" ;;
  esac
  shift
done

CWD="${HERDR_ACTIVE_PANE_CWD:-$PWD}"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 8 ]; then
  echo "エラー: -n は 1〜8 で指定してください" >&2
  exit 1
fi

# ---- モード選択(未指定なら対話) ----
if [ -z "$MODE" ]; then
  echo "実行先を選択:"
  echo "  1) local    — 今のリポジトリで split して起動"
  echo "  2) worktree — 新規 worktree + workspace で起動"
  printf "> "
  read -r choice
  case "$choice" in
    1|l|local)    MODE="local" ;;
    2|w|worktree) MODE="worktree" ;;
    *) echo "中止しました" >&2; exit 1 ;;
  esac
fi

# ---- プロンプト入力(未指定なら対話) ----
if [ -z "$PROMPT" ] && [ "$NO_PROMPT" -eq 0 ]; then
  printf "エージェントへの指示 (空Enterで指示なし起動): "
  read -r PROMPT
fi

# ---- worktree モードは git リポジトリ必須 ----
if [ "$MODE" = "worktree" ]; then
  if ! git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "エラー: $CWD は git リポジトリではありません (worktree モードは git 必須)" >&2
    exit 1
  fi
fi

# ---- slug 生成(プロンプト先頭 or タイムスタンプ) ----
slugify() {
  # 英数字以外を - に置換して短く。日本語プロンプト等で空になったら時刻で代替
  printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -c1-24
}
STAMP="$(date +%m%d-%H%M%S)"
SLUG="$(slugify "$PROMPT")"
[ -z "$SLUG" ] && SLUG="dispatch"

# ---- 完了ウォッチャ(バックグラウンド) ----
watch_done() {
  local target="$1" label="$2"
  (
    if herdr wait agent-status "$target" --status done --timeout 7200000 >/dev/null 2>&1; then
      herdr notification show "dispatch: $label が完了" --sound done >/dev/null 2>&1 || true
    fi
  ) &
}

# ---- 起動 ----
launched=()
for i in $(seq 1 "$COUNT"); do
  if [ "$COUNT" -gt 1 ]; then
    NAME="${SLUG}-${i}"
    BRANCH="dispatch/${STAMP}-${SLUG}-${i}"
  else
    NAME="${SLUG}"
    BRANCH="dispatch/${STAMP}-${SLUG}"
  fi

  if [ "$MODE" = "worktree" ]; then
    # herdr が worktree checkout + workspace 作成 + 親workspaceへのグループ化まで行う
    WT_JSON="$(herdr worktree create --cwd "$CWD" --branch "$BRANCH" --label "$NAME" --no-focus --json)"
    WS_ID="$(printf '%s' "$WT_JSON" | jq -r '.result.workspace_id // .workspace_id // empty')"
    WT_PATH="$(printf '%s' "$WT_JSON" | jq -r '.result.path // .path // empty')"
    if [ -z "$WS_ID" ] || [ -z "$WT_PATH" ]; then
      echo "エラー: worktree 作成結果を解析できません: $WT_JSON" >&2
      exit 1
    fi
    if [ -n "$PROMPT" ]; then
      herdr agent start "$NAME" --workspace "$WS_ID" --cwd "$WT_PATH" --no-focus -- "$AGENT_CMD" "$PROMPT"
    else
      herdr agent start "$NAME" --workspace "$WS_ID" --cwd "$WT_PATH" --no-focus -- "$AGENT_CMD"
    fi
    echo "→ worktree: $WT_PATH (branch $BRANCH, workspace $WS_ID, agent $NAME)"
  else
    # local: 1本目は split、2本目以降は新タブ(同じ workspace 内)
    if [ "$i" -eq 1 ]; then
      if [ -n "$PROMPT" ]; then
        herdr agent start "$NAME" --cwd "$CWD" --split right --no-focus -- "$AGENT_CMD" "$PROMPT"
      else
        herdr agent start "$NAME" --cwd "$CWD" --split right --no-focus -- "$AGENT_CMD"
      fi
    else
      if [ -n "$PROMPT" ]; then
        herdr agent start "$NAME" --cwd "$CWD" --no-focus -- "$AGENT_CMD" "$PROMPT"
      else
        herdr agent start "$NAME" --cwd "$CWD" --no-focus -- "$AGENT_CMD"
      fi
    fi
    echo "→ local: $CWD (agent $NAME)"
  fi

  watch_done "$NAME" "$NAME"
  launched+=("$NAME")
done

echo ""
echo "起動完了: ${launched[*]}"
echo "状態確認: herdr agent list / サイドバー。完了時は通知が出ます。"
