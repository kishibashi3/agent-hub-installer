# Setup guide

agent-hub を初めて使う人向けの step-by-step ガイドです。 2 つの導入 path (= Tier 1 / Tier 2) があります、 用途に応じて選んでください。

## どの path を選ぶか

| Tier | 用途 | Fork | Customization の保存場所 |
|---|---|---|---|
| **Tier 1 (Try it)** | まず動かして体験 / 試用 | ❌ なし | `~/.agent-hub/` ローカル (= 履歴残らず、 throwaway) |
| **Tier 2 (Own it)** | 本番運用 / team 共有 / contributor | ✅ private fork | `~/.agent-hub/roles-repo/` (= git managed) |

→ **初めて触る場合は Tier 1 から始めることを推奨**。 Tier 2 は最初から fork を持って始めたい (= 「捨て前提」 の Tier 1 を skip したい) user 向け。

> ⚠️ **Tier 1 → Tier 2 への migration tool は提供しません** (= Tier 1 は試用 throwaway、 Tier 2 は fresh start が自然、 という設計判断)。 Tier 1 で蓄積した customization が必要な場合は手動で fork repo にコピーしてください。

---

## 前提条件

両 Tier 共通:

| 前提 | バージョン / 入手 | 用途 |
|---|---|---|
| **OS** | Linux または macOS | Windows は WSL2 経由 (= `install.ps1` は別 task) |
| **Python** | 3.10 以上 | `agent-hub-bridges` pip install のため |
| **GitHub PAT** | scope: `read:user` | hub auth (= 必須)、 `gh auth token` でも可 |
| **Claude Code** | 最新版 | human peer client、 [claude.ai/code](https://claude.ai/code) |
| **ANTHROPIC_API_KEY** | (Claude MAX subscription なら不要) | non-MAX user は console.anthropic.com で発行 |

`--hub-mode self-host` 時のみ追加で:

| 前提 | バージョン / 入手 | 用途 |
|---|---|---|
| **Docker** | 20.10+ (CLI + daemon) | local hub server image pull + 起動 (= `--hub-mode public` 時は不要) |

Tier 2 のみ追加で:

| 前提 | バージョン / 入手 | 用途 |
|---|---|---|
| **`gh` CLI** | 2.0+ | private fork access (= `gh repo clone`) のため |

---

## Tier 1: curl | bash で 1-command bootstrap

### Step 1: GitHub PAT を発行

1. GitHub Settings → Developer settings → Personal access tokens (classic) → Generate new token
2. **Scope: `read:user` のみ** チェック (= 必要最小限)
3. token を copy → shell に export:

```bash
export GITHUB_PAT='ghp_xxx...'
```

### Step 2: ANTHROPIC_API_KEY (= Claude MAX user は skip)

[console.anthropic.com](https://console.anthropic.com) で API key を発行 → shell に export:

```bash
export ANTHROPIC_API_KEY='sk-ant-...'
```

### Step 3: installer 1-command 実行

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash
```

または handle を指定したい場合:

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- --user mybot
```

これだけで以下が自動実行されます:
- OS / Python pre-requisite check (= Docker は `--hub-mode self-host` 時のみ)
- `agent-hub-bridges[claude]` を pip install (`--user`)
- `~/.agent-hub/.env` を生成 (= `AGENT_HUB_URL` / `AGENT_HUB_TENANT`、 default は `--hub-mode public` = `agent-hub-ki.fly.dev` に接続)
- bridge worker を background で起動 (= `~/.agent-hub/logs/bridge.log` に log)

> ℹ️ `--hub-mode public` (default) では agent-hub-ki.fly.dev に接続するため **Docker image pull / 起動は行われません** (= Docker 未 install でも実行可能)。 self-host で local hub server を立てたい場合のみ `--hub-mode self-host` + Docker 必須。

### Step 4: bridge 接続を確認

```bash
tail -20 ~/.agent-hub/logs/bridge.log
```

`registered` または `connected` が見えれば OK。見えない場合は `GITHUB_PAT` が正しく export されているか確認してから bridge を再起動してください:

```bash
pkill -f "agent-hub-bridge-claude.*--user.*mybot"
export GITHUB_PAT=$(gh auth token)   # gh なし? → https://github.com/settings/tokens (scope: read:user)
source ~/.agent-hub/env.sh
nohup agent-hub-bridge-claude --user mybot >> ~/.agent-hub/logs/bridge.log 2>&1 &
```

### Step 5: Claude Code を起動して plugin を確認

```bash
source ~/.agent-hub/env.sh
claude
```

Claude Code 内で:
```
/mcp
```

一覧に `agent-hub` が見えれば OK。見えない場合:
```
/plugin marketplace add https://github.com/kishibashi3/agent-hub-plugins-claude
/plugin install agent-hub-plugin
```

その後 Claude Code を再起動し、`/mcp` で `agent-hub` が見えることを確認してください。

### Step 6: 初回メッセージ

```
@mybot hello
```

bot から返信が来ればセットアップ完了 ✅

### 試して終わったら

Tier 1 は **試用 throwaway** 前提です。 もう使わない場合:

```bash
rm -rf ~/.agent-hub
pkill -f 'agent-hub-bridge-claude'
```

本番運用したくなったら Tier 2 に **fresh start で移行** (= 下記参照)。

---

## Tier 2: fork + install.sh で本番運用

Tier 2 は **private fork で knowledge 累積** + team 共有が目的です。

### Step 1: roles repo を fork (= template 経由)

```bash
gh repo create --template kishibashi3/agent-hub-roles --private <yourname>/agent-hub-roles
```

例: GitHub user `myname` なら:

```bash
gh repo create --template kishibashi3/agent-hub-roles --private myname/agent-hub-roles
```

### Step 2: GitHub PAT + (必要なら) ANTHROPIC_API_KEY を export

Tier 1 の Step 1-2 と同じです。

### Step 3: `gh` CLI auth を verify

```bash
gh auth status
```

unauthenticated なら `gh auth login` で認証してください (= Tier 2 は private fork access のため `gh` CLI が必須)。

### Step 4: installer を Tier 2 mode で実行

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
  --tier 2 \
  --roles-repo myname/agent-hub-roles \
  --user mybot
```

これで:
- step 1 で作成した fork (= `myname/agent-hub-roles`) を `~/.agent-hub/roles-repo` に clone
- `~/.agent-hub/.env` を生成 (= `AGENT_HUB_URL` / `AGENT_HUB_TENANT`)
- bridge worker が起動 (`GITHUB_PAT` は caller env から継承)

### Step 5: 動作確認 + customization workflow

1. Claude Code から `@mybot hello` で接続確認
2. roles 編集:

   ```bash
   cd ~/.agent-hub/roles-repo
   # 適宜編集 (= roles/<name>.md 等)
   git commit -am "feat: customize reviewer role"
   git push  # ← team 共有 + upstream PR 可能
   ```

3. bridge restart で新 roles を反映 (= 詳細は `agent-hub-bridge-claude` doc 参照)

---

## Phase 3: docker-compose で self-host

public cloud (agent-hub-ki.fly.dev) の代わりに、自前 LAN / VPS で hub server を運用したい場合の手順です。

### 前提

- Docker Engine / Docker Desktop がインストール・起動済み
- `docker-compose` または `docker compose` コマンドが使える

### Step 1: docker-compose.yml + .env を用意

```bash
# agent-hub-installer リポジトリを clone (または zip で download)
git clone https://github.com/kishibashi3/agent-hub-installer.git ~/agent-hub-installer
cd ~/agent-hub-installer

# .env.example を .env にコピーして値を編集
cp .env.example .env
```

`.env` を開き、以下の最低限の項目を埋めてください:

| 変数 | 説明 | 必須 |
|---|---|---|
| `AGENT_HUB_EDITION` | `community` (PAT 認証) または `private` (LAN 専用 trust) | ✅ |
| `GITHUB_PAT` | GitHub PAT (scope: `read:user`)。`community` edition のみ必須 | community 時 ✅ |
| `AGENT_HUB_TENANT` | tenant 名 (省略可) | — |
| `AGENT_HUB_URL` | bridge から見た MCP endpoint (default: `http://localhost:3000/mcp`) | ✅ |

### Step 2: hub server を起動

```bash
cd ~/agent-hub-installer
docker-compose up -d
```

起動確認:

```bash
docker-compose ps                      # STATUS: healthy になるまで待つ
curl http://localhost:3000/health      # {"status":"ok"} が返れば OK
```

dashboard (ポート 8080) も合わせて起動します。不要な場合は `docker-compose.yml` の `dashboard:` セクションをコメントアウトしてください。

### Step 3: bridge を self-host mode で起動

```bash
export GITHUB_PAT=<your-pat>
export AGENT_HUB_URL=http://localhost:3000/mcp

curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
  --hub-mode self-host \
  --edition community \
  --user mybot
```

> ℹ️ `--hub-mode self-host` にすると Docker image pull も実行されます (`--skip-docker-pull` で skip 可)。

### Step 4: 動作確認

Claude Code から `@mybot hello` を送信し、返事が来れば self-host セットアップ完了 ✅

### 停止・再起動

```bash
docker-compose down          # 停止 (data は ./data/ に保持)
docker-compose down -v       # 停止 + volume 削除 (完全リセット)
docker-compose restart       # 再起動
docker-compose logs -f       # log を tail
```

---

## `curl | bash` の security 考慮

`curl ... | bash` で実行する pattern は、 中間者攻撃 / 改竄リスクをゼロにできません (= chezmoi / Homebrew / nix 等の業界 norm も同じ trade-off)。 paranoia level 高い user 向けの **inspect-then-run alternative**:

```bash
# 1. install.sh を fetch + 確認
curl -fsSL -o /tmp/agent-hub-install.sh \
  https://kishibashi3.github.io/agent-hub-installer/install.sh

# 2. 中身を read (= shell script なので全部目視可能)
less /tmp/agent-hub-install.sh

# 3. (任意) SHA256 verify — 公開時 GitHub Releases に sha256 を付与予定
#    sha256sum /tmp/agent-hub-install.sh
#    # 公開 hash と比較

# 4. 確認後に実行
bash /tmp/agent-hub-install.sh --user mybot
```

SHA256 公開 protocol は将来の installer release で整備予定 (= GitHub Releases asset + sigstore signing 検討余地)。 現状の v0.1.0 では `install.sh` の content が public repo `kishibashi3/agent-hub-installer` の `main` branch と完全一致することを GitHub UI で verify 可能 (= raw URL を browser で開いて confirm)。

---

## トラブルシューティング

### `python3: command not found`
Python 3.10+ を install してください。 macOS は Homebrew (`brew install python@3.12`)、 Linux は distro の package manager。

### `docker: command not found` または `Cannot connect to the Docker daemon`
**`--hub-mode self-host` の場合のみ** 必要。 Docker Desktop (macOS) または Docker Engine (Linux) を install + 起動、 `docker ps` でテスト。 default の `--hub-mode public` では Docker 不要。

### `gh: command not found` (= Tier 2 のみ)
GitHub CLI を [cli.github.com](https://cli.github.com) からインストール。

### bridge worker が応答しない
`~/.agent-hub/logs/bridge.log` を tail:

```bash
tail -f ~/.agent-hub/logs/bridge.log
```

GitHub PAT / ANTHROPIC_API_KEY が正しく export されているか確認、 hub server (Docker container) が起動しているか `docker ps` で確認。

### Pip user-site が PATH に通っていない
installer が WARN を出します。 次の行を `~/.bashrc` または `~/.zshrc` に追加:

```bash
export PATH="$(python3 -m site --user-base)/bin:$PATH"
```

新 shell を起動 (or `source ~/.bashrc`) で反映。

---

## options reference (= `install.sh --help` と同等)

```
--user <handle>            Bridge bot handle name (default: $USER)
--tier <1|2>               Tier 1 (try) | Tier 2 (own、 fork 必須) (default: 1)
--roles-repo <owner/name>  Tier 2 で使う private fork repo
--hub-mode <public|self-host>  Hub server location (default: public)
--edition <community|private>  Self-host edition
--dry-run                  実行内容のみ print、 副作用なし
--skip-docker-pull         Docker image pull を skip
-h, --help                 Usage 詳細
-v, --version              Installer version
```

`--dry-run` で副作用なく実行内容を確認できます:

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
  --dry-run --user mybot
```

---

## 関連

- [README](./README.md) — installer の概要 + design 背景
- [agent-hub](https://github.com/kishibashi3/agent-hub) — server + scheduler + docs
- [agent-hub-roles](https://github.com/kishibashi3/agent-hub-roles) — Tier 2 template repo
- [agent-hub#101](https://github.com/kishibashi3/agent-hub/issues/101) — installer 設計 issue
