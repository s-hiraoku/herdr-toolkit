# on-attention

エージェントの状態変化に**向こうから反応する**イベント駆動プラグイン。別の作業をしていて
エージェントが**入力待ち（blocked）になった瞬間**に、「そのペインにジャンプする?」という
**popup を出して、あなたに決めさせる**（フォーカスを勝手に奪わない）。

「キーで呼ぶ」プラグインと違い、`[[actions]]` ではなく `[[events]]` でイベントを購読する例。

## しくみ

1. `[[events]]` で `pane.agent_status_changed` を購読 → `on-event.sh` が走る。
2. status が対象（既定 `blocked`）なら、対象ペインを state に記録し、
   `herdr plugin pane open` で popup（`[[panes]]` の `prompt`）を開く。
3. popup の `prompt.sh` が「ジャンプする? [Enter=移動 / n=閉じる]」を尋ね、
   Enter なら `herdr workspace focus` ＋ `herdr agent focus` で移動する。

イベント内容は `HERDR_PLUGIN_EVENT_JSON` で渡る（実測した実際の形）:

```json
{ "event": "pane_agent_status_changed",
  "data": { "pane_id": "w1:p1", "workspace_id": "w1", "agent_status": "blocked", "agent": "claude" } }
```

## インストール

```bash
herdr plugin install s-hiraoku/herdr-toolkit/plugins/on-attention
# ローカル: herdr plugin link /path/to/herdr-toolkit/plugins/on-attention
```

キーバインドは不要（イベント駆動で自動的に反応する）。

## 設定（env）

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `ON_ATTENTION_STATUS` | `blocked` | popup を出す対象 status（空白区切り）。例 `"blocked done"` で完了時も尋ねる |

status 値は `idle` / `working` / `blocked` / `done` / `unknown`。既定を `blocked` のみに
しているのは、`working` のたびに割り込むと邪魔だから（＝あなたの操作が要るときだけ）。

## 設計メモ

- 多重 popup を防ぐため atomic lock（`mkdir` ロック）を使い、prompt が開いている間は
  新しい popup を出さない（最新の対象で 1 つだけ）。
- popup とイベントハンドラは別プロセスなので、対象ペインは state ファイル
  （`HERDR_PLUGIN_STATE_DIR` 配下）で受け渡す。`workspace_id` が来なくても `pane_id` の
  `:` 前から導ける。
- `HERDR_PLUGIN_EVENT_JSON` のフィールドは `.data.*` 入れ子（実測で確定。公式ドキュメントの
  top-level 例とは異なるので注意）。
- 対話 I/O は `/dev/tty`。`HERDR_BIN_PATH` で PATH 補完。bash 3.2 互換。
