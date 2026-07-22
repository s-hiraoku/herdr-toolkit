# dispatch プラグイン

AI コーディングエージェント(既定: `claude`)を、**ローカル split** か
**新規 git worktree の workspace** に送り出す [herdr](https://herdr.dev/) 用ランチャー。
「今の作業を汚さずに別案を試したい」「複数のタスクを並列で走らせたい」を
キー1つ・コマンド1発にする。

## インストール

```bash
# ローカル開発(この repo を clone している場合)
herdr plugin link ~/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/dispatch

# または GitHub から直接
herdr plugin install s-hiraoku/herdr-toolkit/plugins/dispatch
```

キーバインドは本 repo の `config/config.toml` に定義済み(下表)。自分の config.toml を
使う場合は `[[keys.command]]` の定義をコピーする。

## 操作リファレンス

1 つの操作は「キーバインド / CLI フラグ / plugin action」の 3 経路で呼べる。対応関係は次の通り。

| 操作 | キーバインド | CLI フラグ | plugin action | 説明 |
| --- | --- | --- | --- | --- |
| local split 起動 | `prefix+d` | `-l` / `--local` | `dispatch-local` | 今のリポジトリ(同じ作業コピー)で右 split して起動 |
| worktree 起動 | `prefix+shift+d` | `-w` / `--worktree` | `dispatch-worktree` | 新規 worktree + workspace を作って起動(いちばんよく使う) |
| モード対話選択 | (CLI のみ) | (引数なし) | `dispatch` | local / worktree を対話選択して起動 |
| 残骸を安全掃除 | `prefix+shift+c` | `--clean` | `dispatch-clean` | `dispatch/*` worktree を安全に一括削除(変更ありは保護) |
| 今の worktree を破棄 | `prefix+shift+x` | `--discard` | (popup) | 現在地の `dispatch/*` worktree を確認つきで破棄 |

> **なぜ対話選択モードはキーに割り当てないか**: 対話選択は選択プロンプトに TTY が必要だが、
> plugin action は非対話で実行されるため動かない。キーには mode 固定の local / worktree を
> 割り当て、対話選択は CLI(`dispatch.sh` 引数なし)専用にしている。

### 環境変数・フラグ

| 指定 | 既定 | 説明 |
| --- | --- | --- |
| `DISPATCH_AGENT` | `claude` | 起動するエージェント(codex, pi 等に差し替え) |
| `DISPATCH_MAX_WATCHERS` | `16` | 完了監視プロセスの同時上限(best-effort) |
| `-n <1..8>` | `1` | 並列本数(worktree を複数本作る。フラグ) |
| worktree の置き場所 | `~/.herdr/worktrees` | herdr 本体の `[worktrees].directory` 設定に従う |

## 基本の使い方

### 隔離環境でタスクを走らせる(`prefix+shift+d` / worktree)

対象リポジトリのペインにいる状態で `prefix+shift+d` を押すと:

1. そのリポジトリの **新規 worktree** が `~/.herdr/worktrees/<repo>/<branch-slug>` に作られる
   (ブランチ名: `dispatch/<MMDD-HHMMSS>-<slug>`、現在の HEAD から分岐)
2. worktree が **新しい workspace** として開き、親リポジトリの workspace にグループ化される
3. その中で `claude` が起動し、フォーカスが新 workspace に移る
4. あとは普通に指示を打てば、**元の作業コピーを一切汚さずに**作業が進む

元の作業に戻るには `prefix+s`(workspace 切替)か サイドバー。エージェントの状態
(working / idle / blocked)はサイドバーで一覧でき、**手が止まると通知**が届く
(idle=完了、blocked=入力待ち。20秒間隔のポーリング、最長2時間)。

### ローカルで軽く走らせる(`prefix+d` / local)

worktree を作るほどでもない調査・質問は local モード。今のリポジトリ(同じ作業コピー)の
まま右 split でエージェントが起動する。**同じファイルを触る並列作業には使わない**こと
(衝突する。そういう時は worktree へ)。

### CLI から使う(プロンプト付き起動・並列)

キーバインド経由は起動後に指示を打つスタイルだが、CLI からはプロンプトを渡して送り出せる。

```bash
DISPATCH="$HOME/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/dispatch/dispatch.sh"

bash $DISPATCH                        # local / worktree を対話選択
bash $DISPATCH -l "この関数の使用箇所を調べて"      # local split で起動
bash $DISPATCH -w "Issue 123 を実装して"           # worktree で起動
bash $DISPATCH -w -n 3 "この機能の実装案を作って"   # worktree 3本で並列(案の比較に)
bash $DISPATCH -w --no-prompt          # 起動だけして指示は手で打つ
bash $DISPATCH --discard               # 今いる dispatch worktree を確認つきで破棄
bash $DISPATCH --clean                 # 残骸掃除(下記)
```

エイリアスを張っておくと楽:

```bash
alias hd='bash ~/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/dispatch/dispatch.sh'
```

### 並列実行の典型フロー

```bash
hd -w -n 3 "PR #123 のレビュー指摘を直す方針を3案、それぞれ実装して"
```

1. worktree が3本でき(ブランチ末尾 `-1` `-2` `-3`)、それぞれで `claude` が走る
2. サイドバーで3つの進捗を眺める。手が止まったものから通知が来る
3. 各 workspace を見て回り、いちばん良い案のブランチだけ残す
4. `prefix+shift+c` で残りを掃除(変更が残っているものは保護されるので、
   不要なら中身を確認して手で消す)

## 後始末

### 今の worktree を破棄(`prefix+shift+x` / `--discard`)

dispatch worktree の workspace に入った状態で `prefix+shift+x` を押すと、popup で
変更サマリ(未コミット変更・独自コミット数)を表示し、`y` で **workspace・worktree・
ブランチをまとめて破棄**する。変更が残っていても確認の上で消せるのが `--clean` との違い。
誤爆防止として `dispatch/*` ブランチの worktree でしか動かない。

### 残骸を安全に掃除(`prefix+shift+c` / `--clean`)

現在のリポジトリの `dispatch/*` worktree を走査して:

- **未コミットの変更なし かつ 独自コミットなし** → worktree・ブランチごと自動削除
  (開いている workspace はタブごと閉じる)
- **変更 or 独自コミットが残っている** → 保護して理由つきで一覧表示

保護されたものは中身を確認し、採用するならマージ、捨てるなら手で削除:

```bash
git -C <worktreeパス> diff              # 何が残っているか確認
herdr worktree remove --workspace <ID> --force   # workspace ごと削除
# または
git worktree remove --force <パス> && git branch -D dispatch/...
```

## 開発メモ

改修時に踏みやすい herdr の挙動(実測ベース)。詳細は `dispatch.sh` 冒頭コメントも参照。

- `herdr worktree create --json` は JSON の前に `ok` 等の行を出す → `grep '^{'` で抽出する
- worktree パスは `.result.workspace.worktree.checkout_path`(0.7.5 で移動。旧: `.result.worktree.path`)
- `herdr agent start` は 0.7.5 で `<name> --kind <KIND> --pane <ID>` 形式に変更。作成直後の
  ペインは `agent_pane_busy` になるためリトライが要る。agent 名は `[a-z][a-z0-9_-]{0,31}` 制約
- `herdr wait agent-status` は未実装 → `herdr agent get` のポーリングで代替
- agent の状態遷移(working/idle/blocked)は統合エージェント(claude 等)のみ。素の bash 等は
  unknown のまま。プロセス終了で agent 自体が消える(agent_not_found)
- plugin action は最小 PATH で実行される。herdr 本体は `HERDR_BIN_PATH` から解決する
- plugin action の `$PWD` は**プラグイン root**。対象ディレクトリは
  `HERDR_PLUGIN_CONTEXT_JSON` の `focused_pane_cwd` から解決する
- 監視プロセスの pidfile は `HERDR_PLUGIN_STATE_DIR`(CLI 時は `TMPDIR`)配下に置く
- `git rev-list --exclude` のパターンは `--branches` に対して `refs/heads/` を**除いた**
  短い名前でマッチする(付けると除外が効かず誤削除につながる)
- macOS 同梱の bash は 3.2。`$BASHPID` など bash 4+ の機能は使わない(`set -u` で落ちる)
