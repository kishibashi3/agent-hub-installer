# Hosted / Self-host 分岐仕様

**作成**: @installer-impl  
**依頼元**: @planner (@ope-ultp1635 指示)  
**関連**: [issue #51](https://github.com/kishibashi3/agent-hub-installer/issues/51)  
**ステータス**: 設計確定

---

## 概要

インストーラーは **Hosted** と **Self-host** の 2 つの Hub 接続モードをサポートする。両モードの差分を明確化し、インストーラーコードの分岐点を定義する。

---

## モード比較

| 観点 | Hosted | Self-host |
|---|---|---|
| **Hub サーバー** | `agent-hub-ki.fly.dev` (managed) | ユーザーが `docker compose up` で自前起動 |
| **URL** | `https://agent-hub-ki.fly.dev/mcp` | ユーザー指定 (例: `http://localhost:3000/mcp`) |
| **Docker** | 不要 | 必須 (Docker Engine 20.10+) |
| **メンテナンス責務** | managed 側 | ユーザー自身 |
| **tenant isolation** | TOFU + PAT auth で自動 | 同左 (auth mode は PAT 推奨) |
| **インストーラーが生成するファイル** | `env.sh`, `.env` | `env.sh`, `.env`, `docker-compose.yml` |
| **インストーラーが実行する追加ステップ** | なし | `docker compose pull` (オプション) |

---

## インストーラー上の分岐点

### 1. 前提条件チェック (Step 0)

```
if [ "$HUB_MODE" = "self-host" ]; then
    check_docker_installed()   # command -v docker
    check_docker_running()     # docker info
fi
```

Hosted モードでは Docker チェックをスキップ。

### 2. Hub URL 設定 (Step 2)

```
if [ "$HUB_MODE" = "hosted" ]; then
    AGENT_HUB_URL="https://agent-hub-ki.fly.dev/mcp"
else
    # ユーザーから URL を対話入力
    read -r AGENT_HUB_URL
    # 到達確認
    curl --max-time 10 "${AGENT_HUB_URL%/mcp}/health" || warn "Hub に到達できません"
fi
```

### 3. ファイル生成 (Step 4)

```
if [ "$HUB_MODE" = "self-host" ]; then
    generate_docker_compose()   # ~/.agent-hub/docker-compose.yml を生成
    generate_data_dir()         # ~/.agent-hub/data/ を作成
fi
```

Hosted モードでは `docker-compose.yml` / `data/` を生成しない。

### 4. コード上の分岐は URL のみ

Issue #51 の設計方針に従い、**インストーラーコード上の本質的な差分は `AGENT_HUB_URL` の値だけ**。Self-host 専用として追加されるのは以下のみ:

- Docker 前提条件チェック
- `docker-compose.yml` テンプレート生成
- `~/.agent-hub/data/` ディレクトリ作成

bridge spawn・env.sh 生成・shell rc 追記は両モードで共通。

---

## 認証モード (Auth Mode)

Hub サーバー側の認証設定（`AGENT_HUB_AUTH_MODE`）がクライアント要件を決定する。

| Server `AGENT_HUB_AUTH_MODE` | 推奨用途 | Bridge 必須設定 | Claude Code 必須設定 |
|---|---|---|---|
| `pat` (デフォルト) | Hosted / インターネット公開 Self-host | `AGENT_HUB_GITHUB_PAT` | `AGENT_HUB_GITHUB_PAT` |
| `trust` | localhost / LAN 内のみ (非推奨) | 不要 | `AGENT_HUB_USER` のみ |

> ⚠️ **`trust` モードはインターネット公開厳禁**: 廃止予定 ([agent-hub#271](https://github.com/kishibashi3/agent-hub/issues/271))。新規 self-host は `pat` を使用すること。

インストーラーは常に `pat` モードを前提とし、`AGENT_HUB_GITHUB_PAT` を必須入力として扱う。

---

## `docker-compose.yml` テンプレート (Self-host 専用)

Self-host モード選択時に `~/.agent-hub/docker-compose.yml` として生成される。

```yaml
services:
  agent-hub:
    image: ghcr.io/kishibashi3/agent-hub:latest
    ports:
      - "3000:3000"
    environment:
      AGENT_HUB_AUTH_MODE: pat
      AGENT_HUB_DB_PATH: /data/app.db
    volumes:
      - ./data:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

生成後のユーザー操作:

```bash
cd ~/.agent-hub
docker compose up -d
docker compose ps   # STATUS: healthy を確認
```

---

## フラグ / 環境変数対応

| CLI フラグ | 環境変数 | 値 | 意味 |
|---|---|---|---|
| `--hub-mode public` | `AGENT_HUB_HUB_MODE=public` | `public` | Hosted (デフォルト) |
| `--hub-mode self-host` | `AGENT_HUB_HUB_MODE=self-host` | `self-host` | Self-host |
| `--edition community` | — | — | PAT auth (Hosted / 公開 Self-host) |
| `--edition private` | — | — | 将来: LAN-only 向け (現状 `pat` と同義) |

> `--edition` フラグは将来の拡張のために予約。現時点では `community` と `private` のいずれを指定しても動作は同じ（常に PAT auth）。

---

## ユーザーへの表示メッセージ

### Hosted 選択時

```
[INFO] Hosted Hub (agent-hub-ki.fly.dev) に接続します。
[INFO] AGENT_HUB_URL=https://agent-hub-ki.fly.dev/mcp
[INFO] Docker は不要です。
```

### Self-host 選択時

```
[INFO] Self-host モードを選択しました。
[INFO] Docker が起動していることを確認してください。
[INPUT] Hub URL を入力してください (例: http://localhost:3000/mcp):
...
[INFO] 生成: ~/.agent-hub/docker-compose.yml
[INFO] Hub を起動するには:
  cd ~/.agent-hub && docker compose up -d
```

---

## 将来の拡張

| 項目 | 現状 | 将来 |
|---|---|---|
| Multi-hub | 未対応 | 複数 URL を `env.sh` に追記して `setup-hubs.sh` で `.mcp.json` 生成 |
| HTTPS 自動設定 | 未対応 | Let's Encrypt + reverse proxy template を `docker-compose.yml` に同梱 |
| HA/クラスター | 未対応 | 別 issue で設計 |

---

## 関連

- [issue #51](https://github.com/kishibashi3/agent-hub-installer/issues/51) — 本設計の起点
- [agent-hub#271](https://github.com/kishibashi3/agent-hub/issues/271) — trust モード廃止
- [docs/agent-hub-dir-layout.md](./agent-hub-dir-layout.md) — ディレクトリ構成詳細
- [docs/install-flow-design.md](./install-flow-design.md) — インストールフロー詳細設計
