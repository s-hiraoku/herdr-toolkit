#!/usr/bin/env bash
# 新マシンでのセットアップ:
#   1. home-manager switch (nix-config 側で config.toml のリンクが張られる)
#   2. このスクリプトで dispatch プラグインを herdr にリンク
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v herdr >/dev/null 2>&1; then
  echo "herdr が見つかりません。brew install herdr を先に実行してください" >&2
  exit 1
fi

herdr plugin link "$REPO_DIR/plugins/dispatch"
herdr plugin list | grep -i dispatch || true

echo "done. config.toml のリンクは nix-config (home-manager switch) 側で管理されます"
