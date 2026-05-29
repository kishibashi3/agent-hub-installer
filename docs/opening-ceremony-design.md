# Opening Ceremony 設計 — installer 完了から初回会話まで

**作成**: @installer-impl  
**依頼元**: @ope-ultp1635  
**ステータス**: 設計レビュー待ち

---

## 1. "Opening ceremony 完了" の定義

> **`@<handle> hello` に対する返信が Claude Code のチャットに届いた状態**

具体的な完了条件:
1. bridge worker が agent-hub hub に接続・登録済み
2. Claude Code に agent-hub MCP plugin が設定・接続済み
3. ユーザーが `@<handle> hello` を Claude Code から送信し、返信を受信した

この 3 条件が揃って初めて「agent-hub が使える状態」になる。

---

## 2. 現状分析

### 2-1. 現行 print_summary() の最終ステップ

```
Next:
  source ~/.agent-hub/env.sh
  export GITHUB_PAT=$(gh auth token)
  claude

Then in Claude Code: '@${USER_HANDLE} hello'
```

### 2-2. 問題点 (新規ユーザー視点)

| # | 問題 | 影響 |
|---|---|---|
| P1 | **MCP plugin インストール手順が欠落** | Claude Code が `@handle` を agent-hub に routing しない → 返信ゼロ、原因不明 |
| P2 | **ステップ番号がなく順序が不明確** | どこで詰まったかが分からない |
| P3 | **bridge 接続確認方法がない** | bridge が起動していても認証エラーで繋がっていないケースを検出できない |
| P4 | **GITHUB_PAT なしで bridge が起動した場合のリカバリ手順がない** | installer が PAT チェックを warn で skip して起動するため、bridge が認証エラーのまま動く可能性がある |
| P5 | **返信がない場合のデバッグ方法がない** | サイレントフェイルアウトでユーザーが詰む |

---

## 3. Opening ceremony ステップ設計

認知負荷を最小にするため **1 ステップ = 1 アクション** の原則で設計する。

### Tier 1 公開サーバー (public) — 標準 path

| ステップ | 場所 | アクション | 確認方法 |
|---|---|---|---|
| **Step 1** | ターミナル | `export GITHUB_PAT=$(gh auth token)` | エラーなし |
| **Step 2** | ターミナル | `source ~/.agent-hub/env.sh` | `echo $AGENT_HUB_URL` に値が入る |
| **Step 3** | ターミナル | `tail -20 ~/.agent-hub/logs/bridge.log` | `registered` / `connected` の文字列を確認 |
| **Step 4** | ターミナル | `claude` | Claude Code が起動する |
| **Step 5** | Claude Code 内 | `/mcp` で agent-hub が見えるか確認 | 一覧に `agent-hub` が表示される |
| **Step 6** | Claude Code 内 | `@<handle> hello` | `@<handle>` から返信が届く → 🎉 完了 |

**最短 path (plugin 既インストールの場合)**: Step 1 → 2 → 4 → 6 の 4 コマンド。

### 補足: plugin 未インストールの場合 (Step 5 で見えない場合)

```
/plugin marketplace add https://github.com/kishibashi3/agent-hub-plugins-claude
/plugin install agent-hub-plugin
```

その後 Claude Code を再起動し、Step 5 から再試行。

---

## 4. つまづきポイントと対処

### P1 (最重要): GITHUB_PAT なしで bridge が起動してしまった

**症状**: `@handle hello` を送っても返信なし。bridge.log に `authentication failed` 等のエラー。

**原因**: installer 実行時に `GITHUB_PAT` が未 export だった場合、bridge は起動するが認証に失敗する。

**対処**:
```bash
# bridge を停止
pkill -f agent-hub-bridge-claude

# PAT を設定して再起動
export GITHUB_PAT=$(gh auth token)   # gh なし? → GitHub Settings → tokens (scope: read:user)
source ~/.agent-hub/env.sh
nohup agent-hub-bridge-claude --user <handle> \
  >> ~/.agent-hub/logs/bridge.log 2>&1 &
```

### P2: gh auth token が使えない (gh CLI 古いバージョン)

**症状**: `gh auth token: unknown subcommand`

**対処**: GitHub → Settings → Developer settings → Personal access tokens → 新規発行 (scope: `read:user`)。`export GITHUB_PAT='ghp_xxx...'` で手動設定。

### P3: MCP plugin が Claude Code に入っていない

**症状**: Claude Code で `/mcp` を実行しても agent-hub が見えない。`@handle hello` が Claude AI に直接送信される。

**対処**:
```
/plugin marketplace add https://github.com/kishibashi3/agent-hub-plugins-claude
/plugin install agent-hub-plugin
```
その後 Claude Code を再起動。

### P4: bridge log に接続エラー

**症状**: `tail -20 ~/.agent-hub/logs/bridge.log` に timeout / connection refused 等。

**対処**: `cat ~/.agent-hub/.env` で `AGENT_HUB_URL` が正しいか確認。self-host の場合は Docker container が起動しているか `docker ps` で確認。

---

## 5. print_summary() 改善案

### 案A: ステップ番号付き (推奨、最小変更)

```
════════════════════════════════════════════════════════
  agent-hub bootstrapped (Tier 1) ✅ — 4 steps to first chat
════════════════════════════════════════════════════════

  Handle: @mybot    Hub: https://agent-hub-ki.fly.dev/mcp

  ─── Opening ceremony ────────────────────────────────

  [1/4] GITHUB_PAT を設定 (bridge 認証に必要):
    export GITHUB_PAT=$(gh auth token)
    # gh なし? → https://github.com/settings/tokens (scope: read:user)

  [2/4] env を load して bridge を確認:
    source ~/.agent-hub/env.sh
    tail -5 ~/.agent-hub/logs/bridge.log   # "registered" が見えれば OK

  [3/4] Claude Code を起動 + plugin を確認:
    claude
    # Claude Code 内: /mcp → agent-hub が見えれば OK
    # 見えない? → /plugin install agent-hub-plugin

  [4/4] 初回メッセージを送信:
    @mybot hello   # → 返信が来たら 🎉

  ─── トラブルシュート ─────────────────────────────────
  Bridge log : tail -f ~/.agent-hub/logs/bridge.log
  Bridge PID : pgrep -f agent-hub-bridge-claude
  Restart    : pkill -f agent-hub-bridge-claude && \
               source ~/.agent-hub/env.sh && \
               nohup agent-hub-bridge-claude --user mybot \
                 >> ~/.agent-hub/logs/bridge.log 2>&1 &
  Full guide : https://github.com/kishibashi3/agent-hub-installer/blob/main/README.md
```

**変更点**:
- `Env` / `Logs` 行を `Handle` / `Hub` だけに絞る (冗長な path 情報を排除)
- 4 ステップ番号付き opening ceremony section を追加
- MCP plugin 確認手順を Step 3 に組み込む
- bridge restart コマンドをトラブルシュート section に明記

### 案B: インタラクティブ wizard (将来拡張案)

`--interactive` フラグで installer 完了時に以下のフローを実行:

```
installer: GITHUB_PAT を入力してください (gh auth token の出力 or 手動):
> ghp_xxx...
installer: [ok] bridge を再起動します...
installer: [ok] registered を確認しました ✅
installer: Claude Code を起動します? [Y/n] → y
         → exec claude
```

**評価**: 認知負荷はさらに下がるが実装コストが高い。`curl | bash` 環境では stdin 受け取りが複雑になる。**現段階は案A を優先、wizard は将来 issue 化にとどめる。**

---

## 6. SETUP.md 更新案

> **実装済み (obsolete)**: この §6 の提案は PR #29 で実装完了。SETUP.md は削除され、内容は README.md に統合された。以下はアーカイブとして残す。

SETUP.md の「Step 4: 動作確認」を以下に更新:

```markdown
### Step 4: bridge 接続を確認

\`\`\`bash
tail -20 ~/.agent-hub/logs/bridge.log
\`\`\`

`registered` または `connected` が見えれば OK。見えない場合は GITHUB_PAT を確認してから bridge を再起動してください。

### Step 5: Claude Code を起動して plugin を確認

\`\`\`bash
source ~/.agent-hub/env.sh
claude
\`\`\`

Claude Code 内で:
\`\`\`
/mcp
\`\`\`

一覧に `agent-hub` が見えれば OK。見えない場合:
\`\`\`
/plugin install agent-hub-plugin
\`\`\`

### Step 6: 初回メッセージ

\`\`\`
@mybot hello
\`\`\`

bot から返信が来ればセットアップ完了 ✅
```

---

## 7. 実装優先度

| 優先度 | タスク | 規模 | 効果 |
|---|---|---|---|
| 🔴 High | `print_summary()` を案A に書き直す | S (installer.sh のみ) | installer 完了直後のガイダンス大幅改善 |
| 🟡 Mid | SETUP.md に bridge log 確認 + plugin 手順を追加 | S (SETUP.md のみ) | 詳細手順の補完 |
| 🟢 Low | wizard (`--interactive`) を issue 化 | - (実装なし) | 将来の認知負荷ゼロ化 |

---

## 8. 未解決の確認事項

設計時に判断しきれなかった点を @ope-ultp1635 に確認します:

1. **MCP plugin のインストールコマンド**: `/plugin install agent-hub-plugin` のコマンド名・URL は現在正しいか? (CLAUDE.md の CE admin setup ガイドにある記述から引用)
2. **bridge restart コマンド**: 上記の restart 手順は現行 bridge CLI の仕様と一致するか?
3. **wizard issue 化**: `--interactive` フラグは将来 scope に入れる予定があるか? issue 化の承認をいただきたい。

---

*— @installer-impl (agent-hub bridge · operator-supervised · kishibashi3/agent-hub-installer)*
