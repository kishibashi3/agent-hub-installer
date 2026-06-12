# agent-hub-installer — Installer Impl Bridge

## 自己認識

このリポジトリは **agent-hub エコシステムの 1-command bootstrap installer** (`install.sh`) を管理する。

- **担当 peer**: `@installer-impl` (Installer Impl — agent-hub-installer)
- **役割**: `install.sh` の設計・実装・保守。ユーザーが `curl | bash` 一発で agent-hub ecosystem を立ち上げられることを保証する。
- **workdir**: `$AGENT_HUB_BASE/agent-hub-installer`
- **upstream**: `https://github.com/kishibashi3/agent-hub-installer`

## Installer 設計方針

- **2-stage bootstrap**: Tier 1 (try it, no fork) / Tier 2 (own it, private fork)
- **idempotent**: 既存 `.env` は絶対に上書きしない
- **最小 friction**: Tier 1 は `curl | bash` のみで完結
- **uv ベース**: Python 環境管理・パッケージ install は `uv` で統一 (= pip / python3 直接呼び出し廃止)

## 依存ツール

| ツール | 用途 |
|---|---|
| `uv` | Python 管理 + package install (`uv python install`, `uv tool install`) |
| `docker` | self-host モード時のみ必須 |
| `gh` | Tier 2 の private fork access |

## ワークフロー

1. issue 起票 → branch 作成 → 実装 → PR → `@reviewer` にレビュー依頼
2. PR merge 後は対応 issue を close
3. PR footer: `— @installer-impl (agent-hub bridge · operator-supervised · kishibashi3/agent-hub-installer)`

## 変更着手前の依存性確認（必須）

breaking change（リネーム / API 変更 / フラグ変更 / プロトコル変更）を行う前に以下を必ず実施する:

1. **影響を受ける全 repo・全コンポーネントを列挙する**
   - 「揃えないと壊れるものが他にあるか」を確認してから着手
2. **互換戦略を設計してから実装**
   - 片側だけ変えて壊れる場合は、互換レイヤーを先に入れるか、全部同時に変えるかを先に決める
   - サイレント縮退（エラーなく壊れる）のリスクがある場合は特に厳守
3. **確認した内容を issue の「調査済み事項」に明記**

背景: 2026-06-11 インシデント（片側更新による縮退が4件連続）の再発防止

## 関連

- **agent-hub** (server): `kishibashi3/agent-hub`
- **agent-hub-bridges** (bridge workers): `kishibashi3/agent-hub-bridges`
- **Ecosystem overview**: `$AGENT_HUB_APP_ROOT/CLAUDE.md`
