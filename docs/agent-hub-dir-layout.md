# `~/.agent-hub/` ディレクトリ構成

**作成**: @installer-impl  
**依頼元**: @planner (@ope-ultp1635 指示)  
**関連**: [issue #51](https://github.com/kishibashi3/agent-hub-installer/issues/51)  
**ステータス**: 設計確定（実装は `agent-hub-control#10` 完了待ち）

---

## 概要

インストーラーが作成する `~/.agent-hub/` は **agent-hub ecosystem のローカル root** として機能する。全設定・バイナリ・ログ・state がここに集約され、アンインストールは `rm -rf ~/.agent-hub` 一発で完結する。

---

## ディレクトリ構成

```
~/.agent-hub/
├── bin/
│   ├── hubctl               # agenthubctl バイナリ (symlink or コピー)
│   └── bridge-claude        # bridge-claude バイナリ (uv tool install で配置)
├── env.sh                   # 非 secret 設定 (shell rc から source)
├── .env                     # GITHUB_PAT 等 secret (chmod 600)
├── roles/                   # bridge workdir (ユーザーが CLAUDE.md 等を編集)
│   └── <role-name>/
│       └── CLAUDE.md
├── roles-repo/              # Tier 2 のみ: private fork clone 先
│   └── (git-managed roles)
├── logs/                    # bridge ログ (永続)
│   └── bridge.log
├── state/                   # ← agent-hub-control#10 完了後に有効
│   └── bridges.json         # bridge state (旧: ~/.local/share/agenthubctl/)
├── docker-compose.yml       # self-host 時のみ生成
└── data/                    # self-host 時のみ (app.db 等)
    └── app.db
```

---

## ファイル・ディレクトリ詳細

### `env.sh` — 環境変数の single source of truth

**種別**: 非 secret 設定  
**パーミッション**: `644`  
**役割**: shell rc (`~/.bashrc` / `~/.zshrc`) から `source` して環境変数を読み込む。

```bash
# ~/.agent-hub/env.sh (生成例)
export AGENT_HUB_URL="https://agent-hub-ki.fly.dev/mcp"
export AGENT_HUB_TENANT="<user-handle>"
export AGENT_HUB_USER="<user-handle>"
export AGENT_HUB_ROLES="${HOME}/.agent-hub/roles"
export BRIDGE_LOG_DIR="${HOME}/.agent-hub/logs"
export PATH="${HOME}/.agent-hub/bin:${PATH}"
```

- インストーラーが自動生成し、`source ~/.agent-hub/env.sh` を shell rc に追記する
- **secret は含まない**（`AGENT_HUB_GITHUB_PAT` は `.env` に分離）
- 既存ファイルは **絶対に上書きしない**（idempotent 設計原則）

### `.env` — secret ファイル

**種別**: secret  
**パーミッション**: `600`  
**役割**: `AGENT_HUB_GITHUB_PAT` など secret を格納。bridge 起動時に `source` またはプロセス環境に渡す。

```bash
# ~/.agent-hub/.env (生成例)
AGENT_HUB_GITHUB_PAT=ghp_xxx...
```

- インストーラーが生成し、git に入らないよう `.gitignore` で除外
- 既存ファイルは **絶対に上書きしない**

### `bin/` — バイナリ置き場

| ファイル | 由来 | 説明 |
|---|---|---|
| `hubctl` | installer が配置 | `agenthubctl` エイリアス / PE entry コマンド |
| `bridge-claude` | `uv tool install` で配置 (symlink) | bridge worker バイナリ |

`env.sh` が `PATH` に `~/.agent-hub/bin` を追加するため、shell 再起動後は `hubctl` コマンドが直接使える。

### `roles/` — bridge workdir

Tier 1 のデフォルト workdir。ユーザーが `CLAUDE.md` などを自由に編集してペルソナをカスタマイズする。

- Tier 2 では `roles-repo/` (= git managed fork) を使用し、`roles/` は使用しない
- インストーラーはデフォルト `roles/operator/CLAUDE.md` を scaffold する

### `roles-repo/` — Tier 2 専用 fork clone 先

`gh repo clone <owner>/agent-hub-roles ~/.agent-hub/roles-repo` で配置される。

- git managed なので変更を commit → push → team 共有が可能
- Tier 1 では作成されない

### `logs/` — bridge ログ (永続)

`BRIDGE_LOG_DIR` に対応。bridge worker が stdout/stderr をここに書き込む。

- インストーラーが `mkdir -p ~/.agent-hub/logs` で作成
- ログローテーションは現状未実装（手動 `truncate` またはディスク管理はユーザー責務）

### `state/bridges.json` — bridge state

**⚠️ 実装ブロック中**: `agent-hub-control#10` (state ファイルパス変更) の完了後に有効になる。  
旧パス: `~/.local/share/agenthubctl/bridges.json`  
新パス: `~/.agent-hub/state/bridges.json`

`hubctl bridge list` / `hubctl bridge start` / `hubctl bridge stop` が参照する state ファイル。

```json
{
  "bridges": [
    {
      "id": "bridge-claude-mybot",
      "user": "mybot",
      "pid": 12345,
      "status": "running",
      "started_at": "2026-06-09T13:00:00Z"
    }
  ]
}
```

### `docker-compose.yml` — self-host 専用

`--hub-mode self-host` 時のみインストーラーが生成。hosted mode では作成しない。

### `data/` — self-host 専用 DB

self-host 時の agent-hub server が使う SQLite DB (`app.db`) を格納。

- `docker-compose.yml` の volume mount 先
- hosted mode では作成しない

---

## パーミッション一覧

| パス | パーミッション | 理由 |
|---|---|---|
| `~/.agent-hub/` | `755` | 通常ディレクトリ |
| `~/.agent-hub/env.sh` | `644` | 非 secret、他プロセスが read 可 |
| `~/.agent-hub/.env` | `600` | secret、owner のみ read |
| `~/.agent-hub/bin/*` | `755` | 実行可能 |
| `~/.agent-hub/logs/` | `755` | bridge が write する |
| `~/.agent-hub/state/` | `700` | bridge state は owner のみ |

---

## アンインストール

```bash
# bridge を停止
pkill -f 'agent-hub-bridge-claude'

# ディレクトリ削除 (全 config / state / log が消える)
rm -rf ~/.agent-hub

# shell rc の source 行を手動削除
# ~/.bashrc または ~/.zshrc から以下の行を削除:
# source ~/.agent-hub/env.sh
```

ディレクトリ設計が single-root であるため、上記だけで痕跡なくアンインストールできる。

---

## 関連

- [issue #51](https://github.com/kishibashi3/agent-hub-installer/issues/51) — 本設計の起点
- [agent-hub-control#10](https://github.com/kishibashi3/agent-hub-control/issues/10) — state パス変更 (ブロッカー)
- [docs/install-flow-design.md](./install-flow-design.md) — インストールフロー詳細設計
- [docs/hosted-vs-selfhost.md](./hosted-vs-selfhost.md) — Hosted / Self-host 分岐仕様
