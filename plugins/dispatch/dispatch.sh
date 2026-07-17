#!/usr/bin/env bash
# dispatch.sh — AI エージェントをローカル(split)か新規worktree(workspace)に送り出す
#
# 使い方:
#   dispatch.sh                          # モードを対話選択し、プロンプトを聞いて起動
#   dispatch.sh --local  "プロンプト"     # 現在のリポジトリで split して起動
#   dispatch.sh --worktree "プロンプト"   # 新規 worktree + workspace で起動
#   dispatch.sh --worktree -n 3 "..."    # worktree 3本で並列起動
#   dispatch.sh --worktree --no-prompt   # プロンプトなしで claude だけ起動(指示は手で打つ)
#   dispatch.sh --discard                # 「今いる dispatch worktree」を確認つきで破棄
#                                        # (popup キーバインドから使う想定。変更ありでも y で削除)
#   dispatch.sh --clean                  # dispatch/* worktree の残骸を掃除
#                                        # (変更なし・独自コミットなしのみ削除、それ以外は保護)
#
# 環境:
#   herdr のプラグインアクション/カスタムコマンドから呼ばれる場合は
#   HERDR_ACTIVE_PANE_CWD が渡される。CLI から直接呼んだ場合は $PWD を使う。
#   非TTY実行(plugin action等)ではモード未指定はエラー、プロンプトは自動でスキップする。
#   エージェントコマンドは $DISPATCH_AGENT (デフォルト: claude) で差し替え可能。
#
# 動作検証メモ (herdr 0.7.4 実測):
#   - `herdr worktree create --json` は JSON の前に "ok" 等の行を出す → grep '^{' で抽出
#   - workspace_id は .result.workspace.workspace_id、パスは .result.worktree.path
#   - `herdr wait agent-status` は not_implemented → `herdr agent get` のポーリングで代替
#   - agent の状態遷移(working/idle/blocked)は統合エージェント(claude等)のみ。
#     プロセス終了で agent 自体が消える(agent_not_found)
set -eu

MODE=""
COUNT=1
NO_PROMPT=0
PROMPT=""
AGENT_CMD="${DISPATCH_AGENT:-claude}"

notify() { herdr notification show "$1" ${2:+--sound "$2"} >/dev/null 2>&1 || true; }

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--local)    MODE="local" ;;
    -w|--worktree) MODE="worktree" ;;
    -n)            shift; COUNT="${1:-1}" ;;
    --no-prompt)   NO_PROMPT=1 ;;
    --clean)       MODE="clean" ;;
    --discard)     MODE="discard" ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             PROMPT="${PROMPT:+$PROMPT }$1" ;;
  esac
  shift
done

# ---- 実行対象ディレクトリの解決 ----
# 優先順: HERDR_ACTIVE_PANE_CWD (custom command 経由)
#       → HERDR_PLUGIN_CONTEXT_JSON の focused_pane_cwd (plugin action 経由・実測)
#       → $PWD (CLI 直接実行)
# ※ plugin action の $PWD はプラグイン root になるため、そのまま使うと
#   プラグイン自身の repo に worktree が生えてしまう(実際に起きた事故)
CWD="${HERDR_ACTIVE_PANE_CWD:-}"
if [ -z "$CWD" ] && [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
  CWD="$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -z "$CWD" ] && CWD="$PWD"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 8 ]; then
  echo "エラー: -n は 1〜8 で指定してください" >&2
  exit 1
fi

# ---- discard モード: 「今いる dispatch worktree」を確認つきで破棄 ----
# popup キーバインド(type = "popup")から呼ぶ想定。変更が残っていても、
# 内容を見せた上で y と答えたら workspace・worktree・ブランチごと削除する。
if [ "$MODE" = "discard" ]; then
  # 今いる場所が dispatch/* ブランチの worktree かを確認
  BR="$(git -C "$CWD" branch --show-current 2>/dev/null || true)"
  WT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  case "$BR" in
    dispatch/*) ;;
    *)
      echo "ここは dispatch worktree ではありません (branch: ${BR:-なし})"
      echo "誤爆防止のため、dispatch/* ブランチの worktree でのみ使えます。"
      echo "Enter で閉じる..."; read -r _
      exit 1
      ;;
  esac

  # 中身のサマリを見せる
  MAIN_GIT_DIR="$(git -C "$WT_ROOT" rev-parse --git-common-dir)"
  MAIN_ROOT="$(dirname "$MAIN_GIT_DIR")"
  echo "破棄対象: $WT_ROOT"
  echo "ブランチ: $BR"
  dirty_count="$(git -C "$WT_ROOT" status --porcelain | wc -l | tr -d ' ')"
  unique="$(git -C "$MAIN_ROOT" rev-list --count "$BR" --not --exclude="$BR" --branches --remotes 2>/dev/null || echo '?')"
  echo "未コミットの変更: ${dirty_count} ファイル / 独自コミット: ${unique} 件"
  if [ "$dirty_count" != "0" ]; then
    echo "--- 変更ファイル ---"
    git -C "$WT_ROOT" status --porcelain | head -10
  fi
  echo ""
  printf "この worktree・ブランチ・workspace を完全に破棄しますか? [y/N] "
  read -r ans
  case "$ans" in
    y|Y|yes) ;;
    *) echo "中止しました"; exit 0 ;;
  esac

  # workspace を特定して herdr 経由で削除(タブごと)、残骸は git で始末
  WS_ID="$(herdr worktree list --cwd "$MAIN_ROOT" --json 2>/dev/null | grep -m1 '^{' \
    | jq -r --arg p "$WT_ROOT" '.result.worktrees[]? | select(.path == $p) | .open_workspace_id // empty')"
  if [ -n "$WS_ID" ]; then
    herdr worktree remove --workspace "$WS_ID" --force >/dev/null 2>&1 || true
  fi
  git -C "$MAIN_ROOT" worktree remove --force "$WT_ROOT" >/dev/null 2>&1 || true
  git -C "$MAIN_ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$MAIN_ROOT" branch -D "$BR" >/dev/null 2>&1 || true
  notify "dispatch: $BR を破棄しました" done
  exit 0
fi

# ---- clean モード: dispatch/* worktree の残骸を安全に掃除 ----
# 「変更なし かつ 独自コミットなし」のものだけ worktree + ブランチを削除する。
# 変更や独自コミットが残っているものは保護して一覧表示する。
if [ "$MODE" = "clean" ]; then
  if ! REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"; then
    notify "dispatch clean: $CWD は git リポジトリではありません" request
    echo "エラー: $CWD は git リポジトリではありません" >&2
    exit 1
  fi
  removed=0; kept=0; kept_list=""
  # herdr 側で workspace が開いているものを対応付ける
  OPEN_MAP="$(herdr worktree list --cwd "$REPO_ROOT" --json 2>/dev/null | grep -m1 '^{' \
    | jq -r '.result.worktrees[]? | select(.open_workspace_id != null) | "\(.path)\t\(.open_workspace_id)"' 2>/dev/null || true)"

  # このリポジトリの dispatch/* ブランチを持つ worktree を列挙
  while IFS=$'\t' read -r WT_PATH WT_BRANCH; do
    [ -z "$WT_PATH" ] && continue
    dirty="$(git -C "$WT_PATH" status --porcelain 2>/dev/null | head -1)"
    # --exclude のパターンは --branches に対しては refs/heads/ を除いた短い名前でマッチする
    # (refs/heads/ 付きだと除外が効かず、独自コミットが常に 0 になり誤削除する。実測済み)
    unique="$(git -C "$REPO_ROOT" rev-list --count "$WT_BRANCH" --not --exclude="$WT_BRANCH" --branches --remotes 2>/dev/null || echo 999)"
    if [ -z "$dirty" ] && [ "$unique" = "0" ]; then
      # 開いている workspace があれば herdr 経由で(タブごと)削除、なければ git で削除
      WS_ID="$(printf '%s\n' "$OPEN_MAP" | awk -F'\t' -v p="$WT_PATH" '$1==p {print $2}')"
      if [ -n "$WS_ID" ]; then
        herdr worktree remove --workspace "$WS_ID" --force >/dev/null 2>&1 || true
      fi
      git -C "$REPO_ROOT" worktree remove --force "$WT_PATH" >/dev/null 2>&1 || true
      git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
      git -C "$REPO_ROOT" branch -D "$WT_BRANCH" >/dev/null 2>&1 || true
      echo "削除: $WT_BRANCH ($WT_PATH)"
      removed=$((removed + 1))
    else
      reason=""
      [ -n "$dirty" ] && reason="未コミットの変更あり"
      [ "$unique" != "0" ] && reason="${reason:+$reason / }独自コミット ${unique} 件"
      echo "保護: $WT_BRANCH — $reason"
      kept=$((kept + 1)); kept_list="${kept_list:+$kept_list, }$WT_BRANCH"
    fi
  done < <(git -C "$REPO_ROOT" worktree list --porcelain \
    | awk '/^worktree /{p=$2} /^branch refs\/heads\/dispatch\//{sub("refs/heads/","",$2); print p "\t" $2}')

  echo ""
  echo "掃除完了: 削除 ${removed} 件 / 保護 ${kept} 件"
  notify "dispatch clean: 削除 ${removed} / 保護 ${kept}${kept_list:+ ($kept_list)}" done
  exit 0
fi

# ---- モード選択(未指定なら対話。非TTYなら明示エラー) ----
if [ -z "$MODE" ]; then
  if [ ! -t 0 ]; then
    notify "dispatch: モード未指定です。prefix+D (worktree直行) を使うか、CLI から -l/-w を指定してください" request
    echo "エラー: 非TTY実行ではモード(-l/-w)の指定が必須です" >&2
    exit 1
  fi
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

# ---- プロンプト入力(未指定なら対話。非TTYなら自動スキップ) ----
if [ -z "$PROMPT" ] && [ "$NO_PROMPT" -eq 0 ] && [ -t 0 ]; then
  printf "エージェントへの指示 (空Enterで指示なし起動): "
  read -r PROMPT
fi

# ---- worktree モードは git リポジトリ必須 ----
if [ "$MODE" = "worktree" ]; then
  if ! git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1; then
    notify "dispatch: $CWD は git リポジトリではありません" request
    echo "エラー: $CWD は git リポジトリではありません (worktree モードは git 必須)" >&2
    exit 1
  fi
fi

# ---- 名前・ブランチ生成 ----
# NAME には必ずタイムスタンプを含める(同名 agent の衝突防止)
slugify() {
  printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -c1-24
}
STAMP="$(date +%m%d-%H%M%S)"
SLUG="$(slugify "$PROMPT")"
[ -z "$SLUG" ] && SLUG="dispatch"

# ---- 完了ウォッチャ(バックグラウンド・ポーリング) ----
# herdr 0.7.4 は wait agent-status が未実装のため agent get をポーリングする。
# idle/blocked = エージェントが手を止めた(完了 or 入力待ち) → 通知
# agent_not_found = プロセス終了で pane が閉じた → 通知
watch_agent() {
  local target="$1"
  (
    local deadline=$(( $(date +%s) + 7200 ))  # 最長2時間
    sleep 30  # 起動直後の unknown/idle を拾わないよう助走を置く
    while [ "$(date +%s)" -lt "$deadline" ]; do
      local out status
      if ! out="$(herdr agent get "$target" 2>/dev/null)"; then
        notify "dispatch: $target が終了しました (pane クローズ)" done
        return
      fi
      status="$(printf '%s' "$out" | grep '^{' | jq -r '.result.agent.agent_status // .result.agent_status // "unknown"' 2>/dev/null || echo unknown)"
      case "$status" in
        idle)    notify "dispatch: $target が完了 (idle)" done; return ;;
        blocked) notify "dispatch: $target が入力待ち (blocked)" request; return ;;
      esac
      sleep 20
    done
    notify "dispatch: $target の監視が2時間でタイムアウトしました" request
  ) >/dev/null 2>&1 &
}

# ---- 起動 ----
launched=()
for i in $(seq 1 "$COUNT"); do
  if [ "$COUNT" -gt 1 ]; then
    NAME="${SLUG}-${STAMP}-${i}"
    BRANCH="dispatch/${STAMP}-${SLUG}-${i}"
  else
    NAME="${SLUG}-${STAMP}"
    BRANCH="dispatch/${STAMP}-${SLUG}"
  fi

  if [ "$MODE" = "worktree" ]; then
    # 単発 dispatch は新しい workspace にフォーカスを移す(押しても何も見えない問題の回避)。
    # 並列時は元の場所に留まる。
    FOCUS_OPT="--no-focus"
    [ "$COUNT" -eq 1 ] && FOCUS_OPT="--focus"
    # herdr が worktree checkout + workspace 作成 + 親workspaceへのグループ化まで行う。
    # --json でも JSON 以外の行が混ざるので '^{' の行だけを抽出する(実測)
    WT_JSON="$(herdr worktree create --cwd "$CWD" --branch "$BRANCH" --label "$NAME" "$FOCUS_OPT" --json | grep -m1 '^{')"
    WS_ID="$(printf '%s' "$WT_JSON" | jq -r '.result.workspace.workspace_id // empty')"
    WT_PATH="$(printf '%s' "$WT_JSON" | jq -r '.result.worktree.path // empty')"
    if [ -z "$WS_ID" ] || [ -z "$WT_PATH" ]; then
      notify "dispatch: worktree 作成に失敗しました" request
      echo "エラー: worktree 作成結果を解析できません: $WT_JSON" >&2
      exit 1
    fi
    if [ -n "$PROMPT" ]; then
      herdr agent start "$NAME" --workspace "$WS_ID" --cwd "$WT_PATH" --no-focus -- "$AGENT_CMD" "$PROMPT" >/dev/null
    else
      herdr agent start "$NAME" --workspace "$WS_ID" --cwd "$WT_PATH" --no-focus -- "$AGENT_CMD" >/dev/null
    fi
    echo "→ worktree: $WT_PATH (branch $BRANCH, workspace $WS_ID, agent $NAME)"
  else
    # local: 1本目は split、2本目以降は新タブ(同じ workspace 内)
    if [ "$i" -eq 1 ]; then
      SPLIT_OPTS=(--split right)
    else
      SPLIT_OPTS=()
    fi
    if [ -n "$PROMPT" ]; then
      herdr agent start "$NAME" --cwd "$CWD" "${SPLIT_OPTS[@]}" --no-focus -- "$AGENT_CMD" "$PROMPT" >/dev/null
    else
      herdr agent start "$NAME" --cwd "$CWD" "${SPLIT_OPTS[@]}" --no-focus -- "$AGENT_CMD" >/dev/null
    fi
    echo "→ local: $CWD (agent $NAME)"
  fi

  watch_agent "$NAME"
  launched+=("$NAME")
done

echo ""
echo "起動完了: ${launched[*]}"
echo "状態確認: herdr agent list / サイドバー。idle/blocked になったら通知します。"
