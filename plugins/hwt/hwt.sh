#!/usr/bin/env bash
# hwt.sh — herdr worktree を楽に扱う CLI / herdr プラグイン本体
#
# 使い方:
#   hwt new [-n N] [テキスト]        # 新規 worktree+workspace を作成(agent なし)
#   hwt new -a [-n N] [テキスト]     # 新規 worktree+workspace + agent 起動
#   hwt ls                          # 現 repo の hwt/* worktree を一覧
#   hwt cd                          # worktree の workspace を選んでフォーカス移動
#   hwt clean                       # hwt/* の残骸を安全に掃除(変更ありは保護)
#   hwt rm                          # 今いる worktree を確認つきで破棄
#
# 環境:
#   plugin action/カスタムコマンドからは HERDR_ACTIVE_PANE_CWD / HERDR_PLUGIN_CONTEXT_JSON が
#   渡される。CLI 直接実行では $PWD を使う。エージェントは HWT_AGENT(既定 claude)で差し替え可能。
set -eu

# plugin action は最小 PATH で走るため herdr/jq を補完。herdr 本体は HERDR_BIN_PATH で解決。
if [ -n "${HERDR_BIN_PATH:-}" ]; then
  PATH="$(dirname "$HERDR_BIN_PATH"):$PATH"
fi
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

AGENT_CMD="${HWT_AGENT:-claude}"
WATCH_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-hwt}/watchers"
MAX_WATCHERS="${HWT_MAX_WATCHERS:-16}"
case "$MAX_WATCHERS" in ''|*[!0-9]*) MAX_WATCHERS=16 ;; esac

notify() { herdr notification show "$1" ${2:+--sound "$2"} >/dev/null 2>&1 || true; }

# 対象 repo の cwd を解決（plugin action の $PWD はプラグイン root なので使わない）
resolve_cwd() {
  local c="${HERDR_ACTIVE_PANE_CWD:-}"
  if [ -z "$c" ] && [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
    c="$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
  fi
  [ -z "$c" ] && c="$PWD"
  printf '%s' "$c"
}

slugify() { printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -c1-24; }

# ---- 完了ウォッチャ(バックグラウンド・ポーリング) ----
prune_dead_watchers() {
  [ -d "$WATCH_DIR" ] || return 0
  local pf pid
  for pf in "$WATCH_DIR"/*.pid; do
    [ -e "$pf" ] || continue
    pid="$(cat "$pf" 2>/dev/null || true)"
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then rm -f "$pf"; fi
  done
}

live_watcher_count() {
  local n=0 pf
  for pf in "$WATCH_DIR"/*.pid; do [ -e "$pf" ] && n=$((n + 1)); done
  echo "$n"
}

watch_agent() {
  local target="$1"
  if ! mkdir -p "$WATCH_DIR" 2>/dev/null; then
    echo "⚠️ watcher 状態ディレクトリを作成できず $target の完了通知はスキップします ($WATCH_DIR)" >&2
    return 0
  fi
  prune_dead_watchers
  if [ "$(live_watcher_count)" -ge "$MAX_WATCHERS" ]; then
    echo "⚠️ 完了監視が上限(${MAX_WATCHERS}件)に達したため $target の通知はスキップします" >&2
    return 0
  fi
  (
    local deadline=$(( $(date +%s) + 7200 ))
    sleep 30
    while [ "$(date +%s)" -lt "$deadline" ]; do
      local out status
      if ! out="$(herdr agent get "$target" 2>/dev/null)"; then
        notify "hwt: $target が終了しました (pane クローズ)" done
        return
      fi
      status="$(printf '%s' "$out" | grep '^{' | jq -r '.result.agent.agent_status // .result.agent_status // "unknown"' 2>/dev/null || echo unknown)"
      case "$status" in
        idle)    notify "hwt: $target が完了 (idle)" done; return ;;
        blocked) notify "hwt: $target が入力待ち (blocked)" request; return ;;
      esac
      sleep 20
    done
    notify "hwt: $target の監視が2時間でタイムアウトしました" request
  ) >/dev/null 2>&1 &
  local wpid=$!
  if ! echo "$wpid" > "$WATCH_DIR/watch-${wpid}.pid" 2>/dev/null; then
    kill "$wpid" 2>/dev/null || true
  fi
}

# 既存ペインに agent を起動(0.7.5 方式)。作成直後は agent_pane_busy になるためリトライ。
start_agent_in_pane() {
  local name="$1" pane_id="$2" prompt="$3"
  local args=("$name" --kind "$AGENT_CMD" --pane "$pane_id")
  [ -n "$prompt" ] && args+=(-- "$prompt")
  local started=0 start_err="" _try
  for _try in $(seq 1 30); do
    if start_err="$(herdr agent start "${args[@]}" 2>&1 >/dev/null)"; then started=1; break; fi
    sleep 0.5
  done
  if [ "$started" -ne 1 ]; then
    notify "hwt: $name の起動に失敗しました (pane $pane_id)" request
    echo "エラー: agent start が失敗しました: $(printf '%s' "$start_err" | tail -1)" >&2
    return 1
  fi
}

usage() {
  cat <<'EOF'
hwt — herdr worktree を楽に扱う

  hwt new [-n N] [テキスト]      新規 worktree+workspace(agent なし)
  hwt new -a [-n N] [テキスト]   新規 worktree+workspace + agent 起動
  hwt ls                        現 repo の hwt/* worktree を一覧
  hwt cd                        worktree の workspace を選んで移動
  hwt clean                     hwt/* の残骸を安全に掃除(変更ありは保護)
  hwt rm                        今いる worktree を確認つき破棄
EOF
}

# ---- verb: new ----
cmd_new() {
  local with_agent=0 count=1 text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -a|--agent) with_agent=1 ;;
      -n) shift; count="${1:-1}" ;;
      -h|--help) echo "usage: hwt new [-a] [-n N] [テキスト]"; return 0 ;;
      -*) echo "hwt new: 不明なオプション $1" >&2; return 1 ;;
      *) text="${text:+$text }$1" ;;
    esac
    shift
  done
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 1 ] || [ "$count" -gt 8 ]; then
    echo "エラー: -n は 1〜8 で指定してください" >&2; return 1
  fi
  local cwd; cwd="$(resolve_cwd)"
  if ! git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1; then
    notify "hwt: $cwd は git リポジトリではありません" request
    echo "エラー: $cwd は git リポジトリではありません" >&2; return 1
  fi
  local stamp slug agent_slug
  stamp="$(date +%Y%m%d-%H%M%S)"
  slug="$(slugify "$text")"; [ -z "$slug" ] && slug="hwt"
  agent_slug="$(printf '%s' "$slug" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-18 | sed 's/-*$//')"
  case "$agent_slug" in [a-z]*) ;; *) agent_slug="h${agent_slug}" ;; esac
  [ -z "$agent_slug" ] && agent_slug="hwt"

  local launched=() i name branch focus_opt wt_json ws_id wt_path pane_id
  for i in $(seq 1 "$count"); do
    if [ "$count" -gt 1 ]; then name="${agent_slug}-${stamp}-${i}"; branch="hwt/${stamp}-${slug}-${i}"
    else name="${agent_slug}-${stamp}"; branch="hwt/${stamp}-${slug}"; fi
    focus_opt="--no-focus"; [ "$count" -eq 1 ] && focus_opt="--focus"
    wt_json="$(herdr worktree create --cwd "$cwd" --branch "$branch" --label "$name" "$focus_opt" --json | grep -m1 '^{')"
    ws_id="$(printf '%s' "$wt_json" | jq -r '.result.workspace.workspace_id // empty')"
    wt_path="$(printf '%s' "$wt_json" | jq -r '.result.workspace.worktree.checkout_path // .result.worktree.path // empty')"
    pane_id="$(printf '%s' "$wt_json" | jq -r '.result.root_pane.pane_id // empty')"
    if [ -z "$ws_id" ] || [ -z "$wt_path" ] || [ -z "$pane_id" ]; then
      notify "hwt: worktree 作成に失敗しました" request
      echo "エラー: worktree 作成結果を解析できません: $wt_json" >&2; return 1
    fi
    echo "→ worktree: $wt_path (branch $branch, workspace $ws_id)"
    if [ "$with_agent" -eq 1 ]; then
      start_agent_in_pane "$name" "$pane_id" "$text" || return 1
      watch_agent "$name"
      launched+=("$name")
    fi
  done
  if [ "$with_agent" -eq 1 ]; then
    echo ""; echo "起動完了: ${launched[*]}"
    echo "状態確認: hwt ls / herdr サイドバー。idle/blocked で通知します。"
  fi
}

# ---- verb: clean ----
cmd_clean() {
  local cwd repo_root; cwd="$(resolve_cwd)"
  if ! repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then
    notify "hwt clean: $cwd は git リポジトリではありません" request
    echo "エラー: $cwd は git リポジトリではありません" >&2; return 1
  fi
  local removed=0 kept=0 kept_list="" open_map
  open_map="$(herdr worktree list --cwd "$repo_root" --json 2>/dev/null | grep -m1 '^{' \
    | jq -r '.result.worktrees[]? | select(.open_workspace_id != null) | "\(.path)\t\(.open_workspace_id)"' 2>/dev/null || true)"
  local wt_path wt_branch dirty unique ws_id reason
  while IFS=$'\t' read -r wt_path wt_branch; do
    [ -z "$wt_path" ] && continue
    dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null | head -1)"
    unique="$(git -C "$repo_root" rev-list --count "$wt_branch" --not --exclude="$wt_branch" --branches --remotes 2>/dev/null || echo 999)"
    if [ -z "$dirty" ] && [ "$unique" = "0" ]; then
      ws_id="$(printf '%s\n' "$open_map" | awk -F'\t' -v p="$wt_path" '$1==p {print $2}')"
      [ -n "$ws_id" ] && herdr worktree remove --workspace "$ws_id" --force >/dev/null 2>&1 || true
      git -C "$repo_root" worktree remove --force "$wt_path" >/dev/null 2>&1 || true
      git -C "$repo_root" worktree prune >/dev/null 2>&1 || true
      git -C "$repo_root" branch -D "$wt_branch" >/dev/null 2>&1 || true
      echo "削除: $wt_branch ($wt_path)"; removed=$((removed + 1))
    else
      reason=""; [ -n "$dirty" ] && reason="未コミットの変更あり"
      [ "$unique" != "0" ] && reason="${reason:+$reason / }独自コミット ${unique} 件"
      echo "保護: $wt_branch — $reason"; kept=$((kept + 1)); kept_list="${kept_list:+$kept_list, }$wt_branch"
    fi
  done < <(git -C "$repo_root" worktree list --porcelain \
    | awk '/^worktree /{p=$2} /^branch refs\/heads\/hwt\//{sub("refs/heads/","",$2); print p "\t" $2}')
  echo ""; echo "掃除完了: 削除 ${removed} 件 / 保護 ${kept} 件"
  notify "hwt clean: 削除 ${removed} / 保護 ${kept}${kept_list:+ ($kept_list)}" done
}

# ---- verb: rm (今いる worktree を確認破棄) ----
cmd_rm() {
  local cwd br wt_root; cwd="$(resolve_cwd)"
  br="$(git -C "$cwd" branch --show-current 2>/dev/null || true)"
  wt_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  case "$br" in
    hwt/*) ;;
    *)
      echo "ここは hwt worktree ではありません (branch: ${br:-なし})"
      echo "誤爆防止のため、hwt/* ブランチの worktree でのみ使えます。"
      echo "Enter で閉じる..."; read -r _; return 1 ;;
  esac
  local main_git_dir main_root dirty_count unique ans ws_id
  main_git_dir="$(git -C "$wt_root" rev-parse --git-common-dir)"
  main_root="$(dirname "$main_git_dir")"
  echo "破棄対象: $wt_root"; echo "ブランチ: $br"
  dirty_count="$(git -C "$wt_root" status --porcelain | wc -l | tr -d ' ')"
  unique="$(git -C "$main_root" rev-list --count "$br" --not --exclude="$br" --branches --remotes 2>/dev/null || echo '?')"
  echo "未コミットの変更: ${dirty_count} ファイル / 独自コミット: ${unique} 件"
  if [ "$dirty_count" != "0" ]; then
    echo "--- 変更ファイル ---"; git -C "$wt_root" status --porcelain | head -10
  fi
  echo ""; printf "この worktree・ブランチ・workspace を完全に破棄しますか? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes) ;; *) echo "中止しました"; return 0 ;; esac
  ws_id="$(herdr worktree list --cwd "$main_root" --json 2>/dev/null | grep -m1 '^{' \
    | jq -r --arg p "$wt_root" '.result.worktrees[]? | select(.path == $p) | .open_workspace_id // empty')"
  [ -n "$ws_id" ] && herdr worktree remove --workspace "$ws_id" --force >/dev/null 2>&1 || true
  git -C "$main_root" worktree remove --force "$wt_root" >/dev/null 2>&1 || true
  git -C "$main_root" worktree prune >/dev/null 2>&1 || true
  git -C "$main_root" branch -D "$br" >/dev/null 2>&1 || true
  notify "hwt: $br を破棄しました" done
}

# ---- verb ディスパッチ ----
[ $# -eq 0 ] && { usage; exit 0; }
verb="$1"; shift
case "$verb" in
  new)       cmd_new "$@" ;;
  clean)     cmd_clean "$@" ;;
  rm)        cmd_rm "$@" ;;
  -h|--help) usage ;;
  *)         echo "hwt: 不明なコマンド '$verb'" >&2; usage >&2; exit 1 ;;
esac
