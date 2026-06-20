# インストールフロー詳細設計

**作成**: @installer-impl  
**依頼元**: @planner (@ope-ultp1635 指示)  
**関連**: [issue #51](https://github.com/kishibashi3/agent-hub-installer/issues/51)  
**ステータス**: 設計確定（実装は `agent-hub-control#10` 完了待ち）

---

## 概要

`curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash` で起動するインタラクティブインストーラーのフロー詳細。各ステップの仕様・エラーケース・rollback フローを定義する。

---

## フロー全体図

```
┌────────────────────────────────────────────────────────────────┐
│  install.sh 起動                                                │
└──────────────────────────┬─────────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │ Step 0      │
                    │ 前提条件     │
                    │ チェック     │
                    └──────┬──────┘
                           │ OK
                    ┌──────▼──────┐
                    │ Step 1      │
                    │ PAT         │
                    │ 入力        │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Step 2      │
                    │ Hub URL     │
                    │ 選択        │
                    └──────┬──────┘
                           │
               ┌───────────┴───────────┐
               │ hosted                │ self-host
        ┌──────▼──────┐        ┌──────▼──────┐
        │ デフォルト URL │        │ URL 入力 +  │
        │ を使用        │        │ Docker check│
        └──────┬──────┘        └──────┬──────┘
               └───────────┬───────────┘
                           │
                    ┌──────▼──────┐
                    │ Step 3      │
                    │ ディレクトリ  │
                    │ scaffold    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Step 4      │
                    │ env.sh /    │
                    │ .env 生成   │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Step 5      │
                    │ bridge      │
                    │ install +   │
                    │ spawn       │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Step 6      │
                    │ shell rc    │
                    │ 追記        │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Step 7      │
                    │ 接続確認    │
                    │ (smoke test)│
                    └─────────────┘
```

---

## Step 0: 前提条件チェック

### チェック項目

| 前提 | チェック方法 | 失敗時の動作 |
|---|---|---|
| OS (Linux / macOS) | `uname -s` | ERROR + exit 1 |
| Python 3.10+ | `python3 --version` | ERROR + install 案内 |
| `uv` | `command -v uv` | 自動インストール試行 (`curl https://astral.sh/uv/install.sh \| sh`) |
| Docker (self-host のみ) | `command -v docker && docker info` | ERROR + install 案内 |
| `gh` CLI (Tier 2 のみ) | `command -v gh && gh auth status` | ERROR + install 案内 |

### `uv` 自動インストール

`uv` が未インストールの場合、ユーザーに確認後に公式インストールスクリプトを実行する。

```
[INFO] uv が見つかりません。インストールします...
> curl -LsSf https://astral.sh/uv/install.sh | sh
```

失敗した場合は WARN を出して `pip install` fallback を案内する（ただし非推奨）。

---

## Step 1: AGENT_HUB_GITHUB_PAT 入力

### 優先順位

1. CLI 引数 `--pat <value>` が指定されていれば使用
2. 環境変数 `AGENT_HUB_GITHUB_PAT` が設定されていれば使用（確認プロンプトを表示）
3. `gh auth token` が返す値を候補として提示（ユーザー確認後に使用）
4. いずれも未設定なら対話的に入力を求める

### 対話プロンプト

```
GitHub Personal Access Token を入力してください。
  scope: read:user のみ必要
  発行先: https://github.com/settings/tokens

PAT (入力は表示されません): ****
```

### バリデーション

| チェック | 方法 | 失敗時 |
|---|---|---|
| `ghp_` または `github_pat_` prefix | 文字列チェック | WARN（continue は可） |
| GitHub API 到達確認 | `curl https://api.github.com/user -H "Authorization: Bearer $PAT"` | ERROR + retry（最大 3 回）|
| ステータス 200 かつ `login` フィールド存在 | JSON parse | ERROR + retry |

バリデーション成功後、`login` から handle を取得して後続ステップで使用する。

---

## Step 2: Hub URL 選択

### プロンプト

```
接続先 Hub を選択してください:
  1) Hosted (推奨): https://agent-hub-ki.fly.dev/mcp
  2) Self-host: 自前 URL を入力

選択 [1/2] (デフォルト: 1):
```

### 分岐

| 選択 | 動作 |
|---|---|
| `1` (hosted) | `AGENT_HUB_URL=https://agent-hub-ki.fly.dev/mcp` を設定してStep 3へ |
| `2` (self-host) | URL 入力プロンプト → Docker チェック → Step 3へ |

### Self-host URL 入力

```
Hub URL を入力してください (例: http://localhost:3000/mcp):
URL:
```

入力後、`curl <url>/health` で到達確認（タイムアウト 10s）。失敗時は WARN を出して続行するか確認。

---

## Step 3: ディレクトリ scaffold

以下を `mkdir -p` で作成。すでに存在する場合はスキップ（idempotent）。

```bash
mkdir -p ~/.agent-hub/bin
mkdir -p ~/.agent-hub/roles/operator
mkdir -p ~/.agent-hub/logs
mkdir -p ~/.agent-hub/state           # agent-hub-control#10 完了後に有効
```

`chmod` も適用:

```bash
chmod 755 ~/.agent-hub
chmod 755 ~/.agent-hub/logs
chmod 700 ~/.agent-hub/state
```

---

## Step 4: env.sh / .env 生成

### env.sh

既存ファイルが存在する場合は **上書きしない**（idempotent 原則）。代わりに不足キーのみ追記（`#` コメントアウト済みキーは対象外）。

生成内容:

```bash
# ~/.agent-hub/env.sh — agent-hub ecosystem 環境変数
export AGENT_HUB_URL="<hub-url>"
export AGENT_HUB_TENANT="<github-login>"
export AGENT_HUB_USER="<github-login>"
export AGENT_HUB_ROLES="${HOME}/.agent-hub/roles"
export BRIDGE_LOG_DIR="${HOME}/.agent-hub/logs"
export PATH="${HOME}/.agent-hub/bin:${PATH}"
```

### .env (secret)

既存ファイルが存在する場合は **上書きしない**。

```bash
# ~/.agent-hub/.env — secret (chmod 600, gitignore 対象)
AGENT_HUB_GITHUB_PAT=<pat>
```

生成後に `chmod 600 ~/.agent-hub/.env` を適用。

---

## Step 5: bridge install + spawn

### bridge インストール

```bash
uv tool install agent-hub-bridges[claude]
```

バージョン指定が必要な場合: `uv tool install "agent-hub-bridges[claude]==<version>"`

インストール後、`agent-hub-bridge-claude --version` で確認。

### bridge 選択プロンプト（初期実装では claude のみ）

```
初期 bridge を選択してください:
  1) bridge-claude (Claude Code + Anthropic API)

選択 [1] (デフォルト: 1):
```

### bridge spawn

```bash
# .env は bare `VAR=val` 形式 (export なし) のため、set -a で auto-export しないと
# nohup で起動する bridge サブプロセスに変数が継承されない。
# env.sh は export 文を含むため set -a 不要。実装 (install.sh) と整合させること。
set -a; source ~/.agent-hub/.env; set +a
source ~/.agent-hub/env.sh
nohup agent-hub-bridge-claude \
  --user "${AGENT_HUB_USER}" \
  >> ~/.agent-hub/logs/bridge.log 2>&1 &
echo $! > ~/.agent-hub/state/bridge-claude.pid
```

PID を `state/bridge-claude.pid` に保存（後の `hubctl bridge stop` で使用）。

---

## Step 6: shell rc 追記

`source ~/.agent-hub/env.sh` を shell rc に追記する。

### 対象 rc ファイルの決定

| 条件 | 対象 |
|---|---|
| `$SHELL` が zsh | `~/.zshrc` |
| `$SHELL` が bash | `~/.bashrc` |
| 不明 / 両方存在 | `~/.bashrc` をデフォルト、ユーザーに確認 |

### idempotent チェック

```bash
if ! grep -q 'source.*~/.agent-hub/env.sh' "${RC_FILE}"; then
    echo '' >> "${RC_FILE}"
    echo '# agent-hub environment' >> "${RC_FILE}"
    echo 'source ~/.agent-hub/env.sh' >> "${RC_FILE}"
fi
```

すでに追記済みなら何もしない。

---

## Step 7: 接続確認 (smoke test)

bridge 起動から 10 秒後に log をチェック。

```bash
sleep 10
if grep -q 'registered\|connected\|online' ~/.agent-hub/logs/bridge.log; then
    echo "[OK] bridge が agent-hub に接続しました"
else
    echo "[WARN] bridge の接続確認ができませんでした。ログを確認してください:"
    echo "  tail -f ~/.agent-hub/logs/bridge.log"
fi
```

> **注**: 上記の緩い grep パターンは `already registered but failed` のようなエラー文言にも誤マッチしうる。実装では成功ログに限定したパターン (例: `'\[INFO\] registered'`) を使うこと。

---

## エラーケース一覧

| ステップ | エラー | 対応 |
|---|---|---|
| Step 0 | Python 未インストール | ERROR + install 案内 + exit 1 |
| Step 0 | Docker 未起動 (self-host) | ERROR + 起動案内 + exit 1 |
| Step 1 | PAT バリデーション失敗 (3回) | ERROR + 手動設定案内 + exit 1 |
| Step 2 | Hub URL に到達不可 | WARN + 続行確認プロンプト |
| Step 3 | `~/.agent-hub/` が root 所有など書き込み不可 | ERROR + exit 1 |
| Step 4 | env.sh 書き込み失敗 | ERROR + exit 1 |
| Step 4 | .env 書き込み失敗 | ERROR + exit 1 |
| Step 5 | `uv tool install` 失敗 | ERROR + pip fallback 案内 |
| Step 5 | bridge spawn 失敗 (exit code != 0) | ERROR + ログ確認案内 |
| Step 6 | RC ファイル書き込み失敗 | WARN + 手動追記案内 |
| Step 7 | bridge 接続確認 WARN | WARN のみ（fatal ではない） |

---

## rollback フロー

インストーラーは `--dry-run` フラグで副作用なく実行内容を確認できる。

rollback は **自動実行しない**。ユーザーが手動で以下を実施:

```bash
# bridge 停止
pkill -f 'agent-hub-bridge-claude'

# 生成したファイルを削除
rm -rf ~/.agent-hub

# shell rc の source 行を削除 (viやsedで手動)
grep -n 'agent-hub/env.sh' ~/.bashrc   # 行番号確認
```

### なぜ自動 rollback しないか

- `~/.bashrc` / `~/.zshrc` は既存内容との merge が必要で、ロールバック境界が曖昧
- `~/.agent-hub/` が既存環境と重複している場合、削除が意図しないデータ消失になる
- インストール途中の部分状態は「cleanup して再実行」が安全

---

## `--dry-run` 出力例

```
[DRY-RUN] mkdir -p ~/.agent-hub/bin
[DRY-RUN] mkdir -p ~/.agent-hub/logs
[DRY-RUN] write ~/.agent-hub/env.sh
[DRY-RUN] write ~/.agent-hub/.env (chmod 600)
[DRY-RUN] uv tool install agent-hub-bridges[claude]
[DRY-RUN] spawn agent-hub-bridge-claude --user mybot
[DRY-RUN] append source ~/.agent-hub/env.sh to ~/.bashrc
```

---

## 関連

- [issue #51](https://github.com/kishibashi3/agent-hub-installer/issues/51) — 本設計の起点
- [agent-hub-control#10](https://github.com/kishibashi3/agent-hub-control/issues/10) — state パス変更 (ブロッカー)
- [docs/agent-hub-dir-layout.md](./agent-hub-dir-layout.md) — ディレクトリ構成詳細
- [docs/hosted-vs-selfhost.md](./hosted-vs-selfhost.md) — Hosted / Self-host 分岐仕様
