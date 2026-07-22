#!/usr/bin/env bash
# 新マシン/更新時のセットアップ:
#   1. home-manager switch (nix-config 側で config.toml のリンクが張られる)
#   2. このスクリプトで plugins/* を herdr に link し、CLI を PATH に通す
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${HWT_BIN_DIR:-$HOME/.local/bin}"

if ! command -v herdr >/dev/null 2>&1; then
  echo "herdr が見つかりません。brew install herdr を先に実行してください" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"

for manifest in "$REPO_DIR"/plugins/*/herdr-plugin.toml; do
  [ -e "$manifest" ] || continue
  plugin_dir="$(dirname "$manifest")"
  name="$(basename "$plugin_dir")"
  echo "→ link plugin: $name"
  if ! herdr plugin link "$plugin_dir" >/dev/null 2>&1; then
    echo "  retry link: $plugin_dir" >&2
    herdr plugin link "$plugin_dir" || { echo "エラー: plugin link に失敗しました: $plugin_dir" >&2; exit 1; }
  fi
  # CLI を公開するプラグイン(<name>.sh を持つ)は PATH に symlink
  if [ -f "$plugin_dir/$name.sh" ]; then
    ln -sf "$plugin_dir/$name.sh" "$BIN_DIR/$name"
    echo "  CLI: $BIN_DIR/$name → $plugin_dir/$name.sh"
  fi
done

herdr plugin list | grep -i "$(basename "$REPO_DIR")" || herdr plugin list | grep -iE 'hwt' || true
echo "done. PATH に $BIN_DIR を通してください(未設定なら shell rc に追加)。"
echo "      config.toml のリンクは nix-config (home-manager switch) 側で管理されます。"
