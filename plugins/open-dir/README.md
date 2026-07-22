# open-dir

ディレクトリを選んで、その場所に **herdr workspace を作る**プラグイン。

herdr は任意フォルダ起点の workspace 作成を **CLI (`herdr workspace create --cwd`) でしか**できず、
キーバインドからは `new_cwd` ポリシー（follow / home / current / 固定パス）に縛られて**毎回違う
フォルダを選べません**。open-dir はその穴を埋め、**キー1発でディレクトリを選んで workspace 化**します。

## 特徴

- **依存ゼロで動く**: picker は純 bash（部分一致フィルタ＋番号選択）を内蔵。`fzf` があれば自動で使い、無ければ内蔵 picker にフォールバック。
- **候補ソースを自動検出**（優先順）: `zoxide`（頻度順）→ `ghq`（全リポジトリ）→ 設定ルートの浅い走査 → 手入力。ユーザが既に持っている仕組みをそのまま活かす。
- macOS / Linux 対応（bash 3.2 互換）。

## インストール

```bash
herdr plugin install s-hiraoku/herdr-toolkit/plugins/open-dir
# ローカル開発なら: herdr plugin link /path/to/herdr-toolkit/plugins/open-dir
```

キーバインドを `config.toml` に追加（対話 picker のため `type = "popup"`）:

```toml
[[keys.command]]
key = "prefix+shift+o"   # 好きな空きキーに
type = "popup"
command = '''bash "$HOME/ghq/github.com/s-hiraoku/herdr-toolkit/plugins/open-dir/open-dir.sh"'''
```

> 補足: `plugin_action` は非対話なので picker が動きません。TTY のある `popup` から
> スクリプトを直接呼びます。`command` のパスは自分のインストール場所に合わせてください。

## 設定（env）

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `OPEN_DIR_ROOTS` | `~/src ~/projects ~/ghq ~/dev ~/work`（存在するもの） | zoxide/ghq が無いときに浅く走査するルート（空白区切り） |

## 使い方

キーを押す → 候補一覧が出る → 選ぶ（fzf なら fuzzy、内蔵 picker なら文字でフィルタして番号）
→ そのディレクトリを起点に workspace が作られ、フォーカスが移動する。候補が無い環境では
パスを直接入力する。

## 開発メモ

- 対話 I/O は `/dev/tty` を使う（候補を stdin で渡すため `read` と混ざらないように）。
- herdr 本体は `HERDR_BIN_PATH` から PATH 補完。plugin action の最小 PATH 対策。
- `find -mindepth/-maxdepth` は BSD(macOS)/GNU 両対応。`$BASHPID` 等 bash 4+ 機能は使わない。
