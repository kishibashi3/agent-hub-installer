# agent-hub installer

agent-hub ecosystem の **2-stage bootstrap installer** (= [issue #101](https://github.com/kishibashi3/agent-hub/issues/101) origin)。

`curl | bash` の 1 コマンドで Tier 1 (= fork なし local 体験) または Tier 2 (= private fork で知的資産累積) のいずれかで agent-hub ecosystem を bootstrap します。

## Quick start

### Tier 1 (Try it) — 最も簡単な体験

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash
```

これだけで:
- OS + Python 3.10+ + Docker の pre-requisite check
- `agent-hub-bridges[claude]` + `agent-hub-roles[all]` を pip install
- `~/.agent-hub/config.yaml` を生成
- bridge worker を background で起動

完了後、 Claude Code を開いて `@<your-handle> hello` を送ると、 agent-hub 上の bot peer と会話できます。

step-by-step ガイドは [SETUP.md](./SETUP.md) を参照してください。

### Tier 2 (Own it) — private fork で knowledge 累積

```bash
# 1. template から private fork を作成
gh repo create --template kishibashi3/agent-hub-roles --private myuser/agent-hub-roles

# 2. installer を Tier 2 mode で実行
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
  --tier 2 --roles-repo myuser/agent-hub-roles --user mybot
```

> ⚠️ **Tier 1 → Tier 2 への自動 migration tool は提供しません**。 Tier 1 は試用 throwaway 前提、 Tier 2 は fresh start が自然、 という design 判断 (= over-engineering 回避)。 Tier 1 で customization を蓄積した場合は手動で fork repo にコピーしてください。

## なぜ 2-tier なのか

| Tier | 目的 | Fork | 用途 |
|---|---|---|---|
| **Tier 1** | まず動かして体験 | ❌ | 試用 / 新規 user |
| **Tier 2** | 本番運用 + knowledge accumulation | ✅ | 持続利用 / team / contributor |

- **Tier 1 fork-less** = 「まず動かす」 体験の friction 最小化 (= Homebrew / nix / mise 等の業界 norm に整合)
- **Tier 2 fork-required** = reviewer 判断基準 / planner 履歴 / feedback-archive 等の **知的資産を git で versioning** し、 team 共有 + upstream PR を可能にする
- **Tier 1 → Tier 2** = **fresh start** で移行 (= Tier 1 throwaway 設計、 自動 migration tool なし)

詳細は [agent-hub issue #101](https://github.com/kishibashi3/agent-hub/issues/101) 参照。

## Options

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

## 前提条件

| 前提 | Tier 1 | Tier 2 |
|---|---|---|
| Python 3.10+ | ✅ 必須 | ✅ 必須 |
| Docker | ✅ 必須 | ✅ 必須 |
| GitHub PAT (`read:user`) | ✅ 必須 | ✅ 必須 |
| `gh` CLI | optional | ✅ 必須 (= private fork access) |
| Claude Code | ✅ 必須 | ✅ 必須 |
| ANTHROPIC_API_KEY | ⚠️ Claude MAX 不要 / 他 必須 | 同左 |

## What gets installed

```
~/.agent-hub/
├── config.yaml          # Tier 1/2 config (= bridge spawn 設定)
├── logs/
│   └── bridge.log       # Bridge worker stdout/stderr
├── roles/               # (Tier 1) Local roles override
└── roles-repo/          # (Tier 2) Git-managed fork clone
```

Python packages (via `pip install --user`):
- `agent-hub-bridges[claude]` — Claude Agent SDK bridge worker
- `agent-hub-roles[all]` — Role definitions (= reviewer / planner / etc.)

Docker image (via `docker pull`):
- `ghcr.io/kishibashi3/agent-hub:latest` — Hub server + scheduler bundle

## Verification

`--dry-run` で実行内容を確認できます (副作用なし):

```bash
curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- --dry-run --user mybot
```

## URL hosting

主要 endpoint:
- `https://kishibashi3.github.io/agent-hub-installer/install.sh` — **GitHub Pages (= live、 anonymous fetch 可能、 operator が 2026-05-20 enable 済)**
- `https://raw.githubusercontent.com/kishibashi3/agent-hub-installer/main/install.sh` — Direct raw (= 常に最新 main、 redirect なし)
- `https://get.agent-hub.dev` — Cloudflare worker / DNS short URL (= future polish、 setup pending)

GitHub Pages は operator の personal domain (= 例 `kishibashi3.github.io` CNAME 設定) で配信される可能性があります。 短く覚えやすい URL を優先する場合は Pages、 redirect なしの canonical fetch を保証したい場合は raw URL を使ってください。

## Related

- **agent-hub** (server + scheduler): [kishibashi3/agent-hub](https://github.com/kishibashi3/agent-hub)
- **agent-hub-roles** (template repo): [kishibashi3/agent-hub-roles](https://github.com/kishibashi3/agent-hub-roles)
- **agent-hub-bridges** (PyPI packages): [kishibashi3/agent-hub-bridges](https://github.com/kishibashi3/agent-hub-bridges)
- **Design**: [issue #101](https://github.com/kishibashi3/agent-hub/issues/101)
- **Inspiration**: [chezmoi 2-stage bootstrap](https://www.chezmoi.io/install/) / [Homebrew installer](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
