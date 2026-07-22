# hwt

git worktree を短いコマンドで扱う [herdr](https://herdr.dev/) ラッパー。内部で `herdr worktree`
を叩く。AI エージェント起動は `new -a` の付加機能（あれば便利、という位置づけ）。

汎用の git-worktree ツールではなく、**herdr（サーバが動いている前提）の worktree 機能を
短く叩くラッパー**です。

## インストール

```bash
herdr plugin link ~/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/hwt
# CLI を PATH に通す(setup.sh が ~/.local/bin/hwt を張る)
~/ghq/github.com/s-hiraoku/herdr-toolkit/scripts/setup.sh
```

## 操作リファレンス

| CLI | plugin action | keybinding | 説明 |
| --- | --- | --- | --- |
| `hwt new [-n N] [テキスト]` | `new` | `prefix+d` | 新規 worktree+workspace(agent なし) |
| `hwt new -a [-n N] [テキスト]` | `new-agent` | `prefix+shift+d` | 新規 worktree+workspace + agent 起動 |
| `hwt ls` | `ls` | （なし） | 現 repo の `hwt/*` worktree を状態付き一覧 |
| `hwt cd` | `cd` | （なし） | worktree の workspace を選んで移動 |
| `hwt clean` | `clean` | `prefix+shift+c` | `hwt/*` の残骸を安全掃除(変更ありは保護) |
| `hwt rm` | `rm` | `prefix+shift+x` | 今いる worktree を確認つき破棄 |

`hwt new` / `new -a` は worktree を**新しい workspace** として開き、親 repo の workspace に
グループ化し、フォーカスを移す（「押したら隔離された新しい場所に飛ぶ」操作感）。`-a` 時は
位置引数を agent の初期プロンプトにも使う。`-n <2..8>` で worktree を複数本作り、`-a` と
併用すると同一プロンプトで並列起動でき案の比較に使える。

`ls`/`cd`/`rm` は対話・TTY を伴うため CLI（またはキーの popup）から使う。

## 環境変数

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `HWT_AGENT` | `claude` | `-a` で起動する agent(codex, pi 等に差し替え) |
| `HWT_MAX_WATCHERS` | `16` | 完了監視の同時上限(best-effort) |

## 開発メモ

- herdr `--json` は先頭に `ok` 等が混ざる → `grep -m1 '^{'` で抽出
- worktree パスは `.result.workspace.worktree.checkout_path`(旧 `.result.worktree.path` もフォールバック)
- `herdr agent start` は 0.7.5 で `<name> --kind KIND --pane ID` 形式。作成直後は
  `agent_pane_busy` になるためリトライ。agent 名は `[a-z][a-z0-9_-]{0,31}` に正規化
- `git rev-list --exclude` は `--branches` に対し `refs/heads/` を除いた短い名前で渡す(誤削除回避)
- macOS 同梱 bash は 3.2。`$BASHPID` 等は使わない(watcher の PID は親側 `$!`)
- plugin action の `$PWD` はプラグイン root。対象 repo は `HERDR_PLUGIN_CONTEXT_JSON` の
  `focused_pane_cwd` から解決。herdr 本体は `HERDR_BIN_PATH` で PATH 補完
- watcher の pidfile は `HERDR_PLUGIN_STATE_DIR`(CLI 時は `TMPDIR`)配下に置き、起動のたびに
  死んだものを prune・同時数に上限を設ける
