# hwt（herdr worktree ラッパー）設計 — dispatch プラグイン改称・サブコマンド化

- 日付: 2026-07-22
- ステータス: 承認済み（実装計画へ）
- 対象リポジトリ: `s-hiraoku/herdr-toolkit`
- 関連: 既存 `plugins/dispatch/` の後継。PR #3(README 分割・A) の後段（B）。

## 背景・動機

`herdr worktree create --cwd … --branch … --label … --json` のような長いコマンドを
打つのが面倒で、それを短い操作で行うために作ったのが現 `dispatch` プラグイン。しかし
名前 `dispatch`（何を送る？）が実体を表しておらず、コマンド体系も「起動モード」と
「後始末」がフラットに混ざっていて拡張しにくい。

このツールの本質は **git worktree を楽に扱うこと**（＝ `herdr worktree` の薄い
エルゴノミクスラッパー）。AI エージェント起動は「あればいい」レベルの付加機能。
これを名前・コマンド体系・配置に正しく反映して作り直す。

また本リポジトリ `herdr-toolkit` は **複数ツールの器**であり、今後 hwt 以外も
足していく前提。リポジトリ構造を「プラグインを足しやすい」形に整える。

## ゴール / 非ゴール

**ゴール**
- `herdr worktree` を短い CLI（`hwt <verb>`）で扱えるようにする。CLI が主役。
- herdr キーバインドは主要操作の薄いショートカットとして併設。
- `herdr-toolkit` を「1 プラグイン = 1 自己完結ディレクトリ」で拡張しやすくする。
- 旧 `dispatch` からのハードカット（後方互換フラグ・旧 action id は残さない）。

**非ゴール（今回やらない・YAGNI）**
- `promote`(採用マージ) / `rerun`(再実行) verb。
- local split（worktree を作らず現ペインで agent 起動）モード → **廃止**。
- スクリプトの複数ファイル分割（`lib/` への切り出し）。将来 2 つ目のプラグインが
  共有コードを要したときに行う。今は seam（`scripts/lib/` の存在）だけ用意。
- 汎用の git-worktree ツール化。あくまで herdr 前提（`herdr` サーバが動いている前提）。

## リポジトリ構造（拡張性）

「プラグインを足すときは `plugins/<name>/` を作るだけ」を規約にする。

```
herdr-toolkit/
├── README.md                    # toolkit 概要 + 各プラグインへのリンク
├── config/config.toml           # 全プラグイン共通の設定・キーバインド（nix が symlink）
├── plugins/
│   └── hwt/
│       ├── herdr-plugin.toml
│       ├── hwt.sh               # 実装（CLI 兼 plugin action 本体）
│       └── README.md
├── scripts/
│   ├── setup.sh                 # plugins/* を走査して全プラグインを link + CLI を PATH へ
│   └── lib/                     # (将来) 複数プラグイン共有のシェル関数置き場。今回は未使用
```

**規約**
- 各プラグインは `plugins/<name>/herdr-plugin.toml` を持ち自己完結。
- CLI を公開するプラグインは実装を `<name>.sh` と命名する。
- `setup.sh` は `plugins/*/herdr-plugin.toml` をループで `herdr plugin link` し、
  `<name>.sh` があれば `~/.local/bin/<name>` へ symlink（PATH に通す）。
- → 新ツール追加は「3 ファイル置いて `setup.sh` 再実行」で完結。

## hwt コマンドモデル

CLI 主・キーバインド薄く（アプローチ A）。実体は 1 スクリプト `hwt.sh` を共有し、
CLI・plugin action の両方から呼ばれる。

| コマンド | plugin action id | type | keybinding | 説明 |
| --- | --- | --- | --- | --- |
| `hwt new [-a] [-n N] [テキスト]` | `new` | plugin_action | `prefix+d` | 現 repo から worktree+workspace 作成。`-a` で中に agent(既定 claude)起動。既定は起動しない |
| `hwt ls` | `ls` | popup | （既定なし） | 現 repo の `hwt/*` worktree を状態付きで一覧 |
| `hwt cd` | `cd` | popup | （既定なし） | worktree の workspace を選んでフォーカス移動 |
| `hwt clean` | `clean` | plugin_action | `prefix+shift+c` | `hwt/*` を安全一括掃除（変更ありは保護） |
| `hwt rm` | `rm` | popup | `prefix+shift+x` | 今いる worktree を確認つき破棄 |
| `hwt`（引数なし） | — | — | — | usage を表示（対話選択モードは廃止） |

**決定事項**
- 名前は **`hwt`**（= herdr worktree。中身を正確に表す。この環境で衝突なしを確認済み）。
- ブランチ接頭辞は `dispatch/*` → **`hwt/*`**。worktree パスは herdr の
  `[worktrees].directory`（既定 `~/.herdr/worktrees`）配下。
- keybinding は同じキーを流用。**空いた `prefix+d`（旧 local）を `hwt new` に再割当**。
  `prefix+shift+d`（旧 worktree 直行）は解放（将来用）。
- `cd` は「その worktree の workspace へ移動」の意味（shell の cd ではなく
  `herdr workspace focus`）。`switch` でも可だが `cd` を採用。
- `ls`/`cd`/`rm` は TTY/対話が要るため popup タイプ。`new`/`clean` は非対話で
  plugin_action。

### 各 verb の挙動

- **new**: 現 repo の HEAD から `hwt/<YYYYMMDD-HHMMSS>[-<slug>]` ブランチを切り、
  `herdr worktree create` で worktree+workspace を作成しフォーカス移動。`-a` なしなら
  worktree を作るだけ。`-a` 指定時のみ `herdr agent start` で agent（`HWT_AGENT`、
  既定 `claude`）を起動し、完了監視（watcher）を張る。agent 名は herdr の命名規約
  `[a-z][a-z0-9_-]{0,31}` に正規化。
  - 位置引数 `[テキスト]` は常にブランチ slug 化に使う。**`-a` 併用時は同じテキストを
    agent への初期プロンプトとしても渡す**（旧 dispatch の「prompt 付き起動」を踏襲）。
    `-a` なしでテキストのみ指定した場合はブランチ名のヒントになるだけ。
  - `-n <2..8>` は worktree を複数本作る（ブランチ末尾 `-1/-2/…`）。`-a` と併用すると
    同一プロンプトで並列起動でき、案の比較に使える。
- **ls**: `herdr worktree list --json` から現 repo の `hwt/*` worktree を抽出し、
  ブランチ・workspace・（あれば）agent 状態（working/idle/blocked）を表形式で表示。
  読み取り専用。
- **cd**: `ls` 相当の候補から選択（`fzf` があれば fzf、なければ番号入力）し、
  `herdr workspace focus` で移動。
- **clean**: 現 repo の `hwt/*` worktree を走査。「未コミット変更なし かつ 独自
  コミットなし」のみ worktree+ブランチ削除（開いている workspace はタブごと閉じる）。
  変更/独自コミットが残るものは保護し理由つきで一覧。`git rev-list --exclude` の
  パターンは `refs/heads/` を除いた短い名前で渡す（付けると誤削除）。
- **rm**: 現在地が `hwt/*` worktree のときのみ動作（誤爆防止）。変更サマリを見せ、
  確認 `y` で workspace・worktree・ブランチをまとめて破棄。変更が残っていても消せる
  点が clean との違い。

### 環境変数・フラグ

| 指定 | 既定 | 説明 |
| --- | --- | --- |
| `-a` / `--agent` | off | `new` 時に worktree 内で agent を起動 |
| `HWT_AGENT` | `claude` | 起動する agent の種類（`-a` 時） |
| `-n <1..8>` | 1 | `new` の並列本数（`-a` と併用で案の比較に） |
| `HWT_MAX_WATCHERS` | 16 | 完了監視の同時上限（best-effort） |

## 旧 dispatch からの移行（ハードカット）

- `plugins/dispatch/` → **`plugins/hwt/`**（`git mv`）。`dispatch.sh` → `hwt.sh`。
- `herdr-plugin.toml`: `id = s-hiraoku.hwt`、action id を `new`/`ls`/`cd`/`clean`/`rm` に。
  version は 1.0.0 にリセット（改称＝新規扱い）。
- `config/config.toml`: dispatch のキーバインドブロックを hwt の action id へ向け直し
  （キーは流用、`prefix+d`→`new`）。旧 `dispatch.dispatch`/`--discard` 参照は削除。
- 旧 CLI フラグ（`-w/-l/--clean/--discard/--no-prompt` の旧セマンティクス）は廃止。
  `hwt` は verb 構文のみ受け付け、未知トークンは usage でエラー。
- README（トップ + `plugins/hwt/README.md`）を hwt の verb 表記に全面更新。
- `hd` エイリアスは `hwt` に置き換え（手作業・ハードカット合意済み）。
- 既存の `dispatch/*` worktree が残っていても、`hwt` は `hwt/*` のみ対象なので
  誤操作しない（旧 worktree は手または旧スクリプトで処理）。

## 内部構造・移植性

- **単一スクリプト `hwt.sh`**。先頭で `case "$1"` の verb ディスパッチ → 各 verb 関数。
  CWD 解決・命名・herdr JSON 抽出（`grep '^{'`）・watcher は共有関数。
- CLI 実行と plugin action 実行の両対応:
  - 対象 repo は `HERDR_ACTIVE_PANE_CWD` → `HERDR_PLUGIN_CONTEXT_JSON.focused_pane_cwd`
    → `$PWD` の順で解決（plugin action の `$PWD` はプラグイン root なので使わない）。
  - herdr 本体は `HERDR_BIN_PATH` から PATH を補完（Linux/macOS 両対応）。
- **bash 3.2 互換**（macOS 同梱）: `$BASHPID` 等 bash 4+ 機能を使わない。watcher の
  PID 記録は親側の `$!`。`set -u` で落ちる書き方を避ける。
- watcher の pidfile は `HERDR_PLUGIN_STATE_DIR`（CLI 時は `TMPDIR`）配下に登録し、
  起動のたびに死んだものを prune、`HWT_MAX_WATCHERS` で同時上限（best-effort）。

## テスト

一時 git リポジトリで各 verb を E2E 検証する。

- `new`（worktree+workspace 作成・フォーカス移動）
- `new -a`（agent 起動・命名正規化・watcher 登録）
- `ls`（`hwt/*` の抽出と状態表示）
- `cd`（候補選択→`workspace focus`）
- `clean`（変更なし=削除 / 変更あり=保護 の判定）
- `rm`（`hwt/*` 以外では拒否 / 確認 y で破棄）
- `setup.sh`（`plugins/*` を link し `~/.local/bin/hwt` を張る）
- `bash -n` 構文チェック、`herdr config check`、bash 3.2 互換の確認。

## 段取り

1. 本 spec 承認後、A（PR #3・README 分割）を先にマージ。
2. 更新済み main から B 実装ブランチを切り、`plugins/dispatch`→`plugins/hwt` 改称・
   verb 化・local 廃止・config/README 更新・setup.sh 汎用化を実装。
3. 実装計画は writing-plans で作成。
