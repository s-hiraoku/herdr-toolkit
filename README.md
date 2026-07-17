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

## dispatch プラグイン

AI コーディングエージェント(デフォルト: claude)を、**ローカル split** か
**新規 git worktree の workspace** に送り出すランチャー。

```bash
# インストール(ローカル開発)
herdr plugin link ~/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/dispatch

# または GitHub から
herdr plugin install s-hiraoku/herdr-toolkit/plugins/dispatch
```

使い方(プラグインアクション経由、またはスクリプト直接実行):

```bash
dispatch.sh                        # local / worktree を対話選択
dispatch.sh -l "軽い調査して"       # local: 今のリポジトリで split
dispatch.sh -w "Issue 123 実装"    # worktree: 新規ブランチ+workspace
dispatch.sh -w -n 3 "案を3通り"    # worktree 3本で並列
dispatch.sh -w --no-prompt         # 起動だけして指示は手で打つ
dispatch.sh --clean                # dispatch/* worktree の残骸を掃除
```

- worktree は herdr 本体の規約 (`~/.herdr/worktrees/<repo>/<branch-slug>`) に従い、
  親リポジトリの workspace にグループ化される
- ブランチ名: `dispatch/<MMDD-HHMMSS>-<slug>[-連番]`
- 各エージェントの完了(`done`)を監視し、`herdr notification` で通知
- エージェントは `DISPATCH_AGENT` 環境変数で差し替え可能(codex, pi 等)

### キーバインド(config.toml)

| キー | 動作 |
| --- | --- |
| `prefix+d` | dispatch(local / worktree を選択) |
| `prefix+D` | worktree に直行 |
| `prefix+C` | dispatch worktree の残骸を掃除 |

## 片付け

`prefix+C`(または `dispatch.sh --clean`)が、現在のリポジトリの `dispatch/*` worktree のうち
**未コミットの変更も独自コミットも無いもの**だけを worktree・ブランチごと削除する。
変更や独自コミットが残っているものは保護して一覧表示するので、マージ/破棄の判断をしてから
手で消す(`herdr worktree remove --workspace <ID>` または `git worktree remove` + `git branch -d`)。
