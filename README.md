# herdr-toolkit

[herdr](https://herdr.dev/) の設定・プラグイン・セットアップ一式を管理する個人ツールキット。

## 構成

```
config/config.toml        # herdr 設定のソース・オブ・トゥルース
plugins/<name>/           # 1 プラグイン = 1 自己完結ディレクトリ
  └─ README.md            #   → 各プラグインの使い方はそれぞれの README
scripts/setup.sh          # plugins/* を herdr に link し CLI を PATH に通す
```

各プラグインの詳細は、それぞれのディレクトリの README を参照:

- **[hwt](plugins/hwt/README.md)** — git worktree を短いコマンドで扱う herdr ラッパー
  (`hwt new/ls/cd/clean/rm`。`new -a` で worktree 内に AI エージェントも起動)

新しいツールを足すときは `plugins/<name>/`（`herdr-plugin.toml` ＋ CLI を出すなら `<name>.sh`
＋ `README.md`）を作り、`scripts/setup.sh` を再実行するだけ。

## config.toml の管理方法

実体はこの repo の `config/config.toml`。`~/.config/herdr/config.toml` へのリンクは
home-manager ([nix-config](https://github.com/s-hiraoku/nix-config) の `modules/herdr.nix`) が
`mkOutOfStoreSymlink` で張る。

- その場で編集 → herdr 内で `prefix+r` で即リロード
- 履歴はこの repo に残る
- 新マシンは `git clone` + `home-manager switch` で再現

`config.toml` には prefix(`Ctrl+A`)や Vim 風ペイン移動などの基本キーバインドに加え、
各プラグインのキーバインド定義(`[[keys.command]]`)が含まれる。

## 新マシンのセットアップ

```bash
brew install herdr
ghq get s-hiraoku/nix-config && home-manager switch --flake <nix-config>#<profile>
ghq get s-hiraoku/herdr-toolkit
~/ghq/github.com/s-hiraoku/herdr-toolkit/scripts/setup.sh   # plugin link + CLI(PATH) まで
```
