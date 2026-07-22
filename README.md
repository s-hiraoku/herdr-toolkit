# herdr-toolkit

[herdr](https://herdr.dev/) の設定・プラグイン・セットアップ一式を管理する個人ツールキット。

## 構成

```
config/config.toml     # herdr 設定のソース・オブ・トゥルース
plugins/dispatch/      # dispatch プラグイン(下記)
scripts/setup.sh       # 新マシンでのリンク・プラグイン登録
```

## config.toml の管理方法

実体はこの repo の `config/config.toml`。`~/.config/herdr/config.toml` へのリンクは
home-manager ([nix-config](https://github.com/s-hiraoku/nix-config) の `modules/herdr.nix`) が
`mkOutOfStoreSymlink` で張る。

- その場で編集 → herdr 内で `prefix+r` で即リロード
- 履歴はこの repo に残る
- 新マシンは `git clone` + `home-manager switch` で再現

---

# dispatch プラグイン

AI コーディングエージェント(デフォルト: claude)を、**ローカル split** か
**新規 git worktree の workspace** に送り出すランチャー。
「今の作業を汚さずに別案を試したい」「複数のタスクを並列で走らせたい」を
キー1つ・コマンド1発にする。

## インストール

```bash
# ローカル開発(この repo を clone している場合)
herdr plugin link ~/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/dispatch

# または GitHub から直接
herdr plugin install s-hiraoku/herdr-toolkit/plugins/dispatch
```

キーバインドは `config/config.toml` に定義済み(下表)。自分の config.toml を使う場合は
`[[keys.command]]` の `plugin_action` 定義をコピーする。

## キーバインド

| キー | 動作 |
| --- | --- |
| `prefix+d` | 今のリポジトリで local split 起動 |
| `prefix+shift+d` | worktree に直行(いちばんよく使う) |
| `prefix+shift+c` | dispatch worktree の残骸を掃除(変更ありは保護) |
| `prefix+shift+x` | **今いる** dispatch worktree を確認つきで破棄(popup) |

## 基本の使い方

### 1. 隔離環境でタスクを走らせる(`prefix+shift+d`)

対象リポジトリのペインにいる状態で `prefix+shift+d` を押すと:

1. そのリポジトリの **新規 worktree** が `~/.herdr/worktrees/<repo>/<branch-slug>` に作られる
   (ブランチ名: `dispatch/<MMDD-HHMMSS>-<slug>`、現在の HEAD から分岐)
2. worktree が **新しい workspace** として開き、親リポジトリの workspace にグループ化される
3. その中で claude が起動し、フォーカスが新 workspace に移る
4. あとは普通に指示を打てば、**元の作業コピーを一切汚さずに**作業が進む

元の作業に戻るには `prefix+s`(workspace 切替)か サイドバー。エージェントの状態
(working / idle / blocked)はサイドバーで一覧でき、**手が止まると通知**が届く
(idle=完了、blocked=入力待ち。20秒間隔のポーリング、最長2時間)。

### 2. ローカルで軽く走らせる(`prefix+d` → local)

worktree を作るほどでもない調査・質問は local モード。今のリポジトリ(同じ作業コピー)の
まま右 split でエージェントが起動する。**同じファイルを触る並列作業には使わない**こと
(衝突する。そういう時は worktree へ)。

### 3. CLI から使う(プロンプト付き起動・並列)

キーバインド経由は起動後に指示を打つスタイルだが、CLI からはプロンプトを渡して送り出せる:

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

エイリアスを張っておくと楽: `alias hd='bash ~/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/dispatch/dispatch.sh'`

### 4. 並列実行の典型フロー

```bash
hd -w -n 3 "PR #123 のレビュー指摘を直す方針を3案、それぞれ実装して"
```

1. worktree が3本でき(ブランチ末尾 `-1` `-2` `-3`)、それぞれで claude が走る
2. サイドバーで3つの進捗を眺める。手が止まったものから通知が来る
3. 各 workspace を見て回り、いちばん良い案のブランチだけ残す
4. `prefix+shift+c` で残りを掃除(変更が残っているものは保護されるので、
   不要なら中身を確認して手で消す)

## 個別に破棄(`prefix+shift+x` / `--discard`)

dispatch worktree の workspace に入った状態で `prefix+shift+x` を押すと、popup で
変更サマリ(未コミット変更・独自コミット数)を表示し、`y` で **workspace・worktree・
ブランチをまとめて破棄**する。変更が残っていても確認の上で消せるのが `--clean` との違い。
誤爆防止として `dispatch/*` ブランチの worktree でしか動かない。

## 片付け(`prefix+shift+c` / `--clean`)

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

## カスタマイズ

| 方法 | 内容 |
| --- | --- |
| `DISPATCH_AGENT=codex hd -w "..."` | エージェントを claude 以外に差し替え(codex, pi 等) |
| `-n <1..8>` | 並列本数(上限8) |
| worktree の置き場所 | herdr 本体の `[worktrees].directory` 設定に従う(デフォルト `~/.herdr/worktrees`) |

## 実装メモ(herdr 0.7.4 実測に基づく注意点)

`dispatch.sh` 冒頭のコメントにも記載。改修時に踏みやすい罠:

- `herdr worktree create --json` は JSON の前に `ok` 等の行を出す → `grep '^{'` で抽出する
- workspace_id / path は `.result.workspace.workspace_id` / `.result.worktree.path`
- `herdr wait agent-status` は 0.7.4 時点で not_implemented → `herdr agent get` のポーリングで代替
- agent の状態遷移(working/idle/blocked)は統合エージェント(claude 等)のみ。素の bash 等は
  unknown のまま。プロセス終了で agent 自体が消える(agent_not_found)
- plugin action の `$PWD` は**プラグイン root**。対象ディレクトリは
  `HERDR_PLUGIN_CONTEXT_JSON` の `focused_pane_cwd` から解決する
- `git rev-list --exclude` のパターンは `--branches` に対して `refs/heads/` を**除いた**
  短い名前でマッチする(付けると除外が効かず誤削除につながる)

## 新マシンのセットアップ

```bash
brew install herdr
ghq get s-hiraoku/nix-config && home-manager switch --flake <nix-config>#<profile>
ghq get s-hiraoku/herdr-toolkit
~/ghq/github.com/s-hiraoku/herdr-toolkit/scripts/setup.sh   # plugin link まで実行
```
