# plugins/

herdr プラグインの置き場。**1 プラグイン = 1 自己完結ディレクトリ** を規約とする。

## プラグインの追加方法

`plugins/<name>/` を作り、以下を置く:

```
plugins/<name>/
├── herdr-plugin.toml   # id = <namespace>.<name>、actions を宣言
├── <name>.sh           # (任意) CLI を公開する場合の実装本体
└── README.md           # そのプラグインの使い方・操作リファレンス
```

その後 `scripts/setup.sh` を再実行すると:

- `plugins/*/herdr-plugin.toml` を走査して各プラグインを `herdr plugin link`
- `<name>.sh` があれば `~/.local/bin/<name>` へ symlink（CLI として PATH に載る）

キーバインドは `config/config.toml` の `[[keys.command]]` に追記する（全プラグイン共通で集約）。

## メモ

- ラッパー系プラグインを作る前に、まず **herdr 本体が同じことをネイティブでできないか**を確認する
  （`herdr <subcommand> --help` / `keys.*` の named action / config ポリシー）。ネイティブで足りるなら
  プラグインを作らず、キーバインドやシェルエイリアスで済ませるのが保守コスト的に有利。
