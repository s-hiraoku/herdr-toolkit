# herdr-toolkit

[herdr](https://herdr.dev/) の設定・プラグイン・セットアップ一式を管理する個人ツールキット。

## 構成

```
config/config.toml        # herdr 設定のソース・オブ・トゥルース
plugins/dispatch/         # dispatch プラグイン(エージェントランチャー)
  └─ README.md            #   → プラグインの使い方・操作リファレンスはこちら
scripts/setup.sh          # 新マシンでのリンク・プラグイン登録
```

各プラグインの詳細は、それぞれのディレクトリの README を参照:

- **[dispatch](plugins/dispatch/README.md)** — AI エージェントを local split / 新規 worktree に
  送り出すランチャー(並列実行・完了通知・安全な後片付けつき)

## config.toml の管理方法

実体はこの repo の `config/config.toml`。`~/.config/herdr/config.toml` へのリンクは
home-manager ([nix-config](https://github.com/s-hiraoku/nix-config) の `modules/herdr.nix`) が
`mkOutOfStoreSymlink` で張る。

- その場で編集 → herdr 内で `prefix+r` で即リロード
- 履歴はこの repo に残る
- 新マシンは `git clone` + `home-manager switch` で再現

`config.toml` には prefix(`Ctrl+A`)や Vim 風ペイン移動などの基本キーバインドに加え、
dispatch プラグインのキーバインド定義(`[[keys.command]]`)が含まれる。

## 新マシンのセットアップ

```bash
brew install herdr
ghq get s-hiraoku/nix-config && home-manager switch --flake <nix-config>#<profile>
ghq get s-hiraoku/herdr-toolkit
~/ghq/github.com/s-hiraoku/herdr-toolkit/scripts/setup.sh   # plugin link まで実行
```
