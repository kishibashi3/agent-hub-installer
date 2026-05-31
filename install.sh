#!/usr/bin/env bash
# shellcheck shell=bash
#
# agent-hub installer (= issue #101 2-stage bootstrap)
#
# 1-command bootstrap for agent-hub ecosystem:
#   curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash
#
# Two tiers:
#   - Tier 1 (Try it):  fork なし、 `~/.agent-hub/` ローカルファイルで体験
#   - Tier 2 (Own it):  private fork で知的資産累積 (= roles repo を git managed)
#
# Idempotent: 既に install 済の場合は .env 上書きせずに hint 表示。
# 非破壊: 既存 `~/.agent-hub/.env` は **絶対に上書きしない** (= user 設定保護)。
#
# Refs: https://github.com/kishibashi3/agent-hub/issues/101

set -euo pipefail

# ============================================================
# Config / Defaults
# ============================================================

INSTALLER_VERSION="0.1.0"
AGENT_HUB_DIR="${AGENT_HUB_DIR:-${HOME}/.agent-hub}"
AGENT_HUB_URL_DEFAULT="https://agent-hub-ki.fly.dev/mcp"
AGENT_HUB_URL_SELFHOST_DEFAULT="http://localhost:3000/mcp"
DOCKER_IMAGE="ghcr.io/kishibashi3/agent-hub:latest"

# Args defaults
USER_HANDLE=""
TIER="1"
ROLES_REPO=""
HUB_MODE="public"   # public | self-host
HUB_URL=""          # --hub-url explicit override (= AGENT_HUB_URL に優先)
EDITION=""          # used for self-host (community | private)
DRY_RUN="no"
SKIP_DOCKER_PULL="no"
SUBCOMMAND=""

# ============================================================
# UI helpers
# ============================================================

c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_blue()   { printf '\033[34m%s\033[0m\n' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
c_dim()    { printf '\033[2m%s\033[0m\n' "$*"; }

info()  { c_blue   "[info]  $*"; }
ok()    { c_green  "[ok]    $*"; }
warn()  { c_yellow "[warn]  $*" >&2; }
err()   { c_red    "[err]   $*" >&2; }

die() {
  err "$*"
  exit 1
}

# ============================================================
# Usage
# ============================================================

usage() {
  cat <<'EOF'
agent-hub installer — 2-stage bootstrap

USAGE:
  curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash
  curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- [OPTIONS]

SUBCOMMANDS:
  doctor                     health-check: PAT / hub / port / sed / grep / bash / env / plugin / zombie

OPTIONS:
  --user <handle>            Bridge bot handle name (= agent-hub の @handle)
                             default: $USER (= shell user name)
                             validation: alphanumeric + dash + underscore のみ
  --tier <1|2>               Tier 1 (try) | Tier 2 (own、 private fork 必須)
                             default: 1
  --roles-repo <owner/name>  Tier 2 で使う private fork repo (= --tier 2 必須)
  --hub-mode <public|self-host>  Hub server location
                             default: public (= agent-hub-ki.fly.dev)
  --hub-url <url>            Hub MCP endpoint URL を直接指定 (= --hub-mode default を上書き)
                             default: hub-mode から自動決定
                             (public: https://agent-hub-ki.fly.dev/mcp / self-host: http://localhost:3000/mcp)
  --edition <community|private>  Self-host edition (= --hub-mode self-host のみ)
  --dry-run                  実行内容のみ print、 副作用なし (= debug 用)
  --skip-docker-pull         Docker image pull を skip (= 開発 / 既 pull 済 path)
  -h, --help                 このメッセージ
  -v, --version              installer version

EXAMPLES:
  # Tier 1 default (= 最も簡単な体験)
  curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash

  # Tier 1 with custom handle
  curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- --user mybot

  # Tier 2 (既 fork 済 user)
  curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
    --tier 2 --roles-repo myuser/agent-hub-roles --user mybot

  # Self-host PE (= LAN 専用)
  curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \
    --hub-mode self-host --edition private --user admin

Tier 1 → Tier 2 への移行は fresh start で実行 (= 自動 migration tool なし、
Tier 1 throwaway 設計)。 Tier 1 で蓄積した customization は手動で fork に copy 必要。

Refs: https://github.com/kishibashi3/agent-hub/issues/101
EOF
}

# ============================================================
# Arg parsing
# ============================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      doctor)
        SUBCOMMAND="doctor"
        shift
        ;;
      --user)
        [[ $# -ge 2 ]] || die "--user requires an argument"
        USER_HANDLE="$2"
        shift 2
        ;;
      --tier)
        [[ $# -ge 2 ]] || die "--tier requires an argument (1|2)"
        TIER="$2"
        shift 2
        ;;
      --roles-repo)
        [[ $# -ge 2 ]] || die "--roles-repo requires <owner/name>"
        ROLES_REPO="$2"
        TIER="2"   # --roles-repo implies Tier 2
        shift 2
        ;;
      --hub-mode)
        [[ $# -ge 2 ]] || die "--hub-mode requires an argument (public|self-host)"
        HUB_MODE="$2"
        shift 2
        ;;
      --hub-url)
        [[ $# -ge 2 ]] || die "--hub-url requires an argument"
        HUB_URL="$2"
        shift 2
        ;;
      --edition)
        [[ $# -ge 2 ]] || die "--edition requires an argument (community|private)"
        EDITION="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="yes"
        shift
        ;;
      --skip-docker-pull)
        SKIP_DOCKER_PULL="yes"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -v|--version)
        echo "agent-hub installer v${INSTALLER_VERSION}"
        exit 0
        ;;
      *)
        die "unknown option: $1 (use --help for usage)"
        ;;
    esac
  done

  # Fallback defaults
  if [[ -z "${USER_HANDLE}" ]]; then
    USER_HANDLE="${USER:-bot}"
  fi
}

# ============================================================
# Hub URL resolution (issue #20)
# ============================================================

resolve_hub_url() {
  # AGENT_HUB_URL の決定優先順位 (= --hub-mode semantics を尊重):
  #   1. --hub-url フラグ     — 最優先、明示指定
  #   2. caller env の AGENT_HUB_URL — installer 起動前に export 済みなら honor
  #   3. --hub-mode self-host — localhost:3000/mcp を default
  #   4. --hub-mode public    — fly.dev (= AGENT_HUB_URL_DEFAULT)
  #
  # これにより `--hub-mode self-host` 時に fly.dev が書かれる silent failure (issue #20) を修正。
  if [[ -n "${HUB_URL}" ]]; then
    AGENT_HUB_URL="${HUB_URL}"
    info "Hub URL: ${AGENT_HUB_URL} (from --hub-url)"
  elif [[ -n "${AGENT_HUB_URL:-}" ]]; then
    info "Hub URL: ${AGENT_HUB_URL} (from caller env)"
  elif [[ "${HUB_MODE}" == "self-host" ]]; then
    AGENT_HUB_URL="${AGENT_HUB_URL_SELFHOST_DEFAULT}"
    info "Hub URL: ${AGENT_HUB_URL} (self-host default)"
  else
    AGENT_HUB_URL="${AGENT_HUB_URL_DEFAULT}"
    info "Hub URL: ${AGENT_HUB_URL} (public default)"
  fi
  export AGENT_HUB_URL
}

# ============================================================
# Pre-requisite checks
# ============================================================

check_os() {
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "${os}" in
    linux|darwin)
      info "OS: ${os} ✅"
      ;;
    *)
      die "unsupported OS: ${os}. agent-hub installer supports Linux + macOS only. (Windows: use WSL or wait for install.ps1)"
      ;;
  esac
}

check_command() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    die "required command not found: ${cmd}. ${install_hint}"
  fi
  info "${cmd} found ✅"
}

install_uv_python() {
  # uv python install で Python 3.12 を固定インストール。
  # pip / python3 直接呼び出しを廃止し、 uv が Python version を管理する。
  info "Installing Python 3.12 via uv..."
  run_or_dry uv python install 3.12
}

# Suggestion (d) 反映: --user handle の validation (= alphanumeric + `-_` のみ)
# 不正文字 (e.g. shell metacharacter / space / unicode) を early reject、
# その後 SQL / shell context への carry を防ぐ防御的 hardening。
check_user_handle() {
  local handle="$1"
  if [[ -z "${handle}" ]]; then
    die "--user handle is empty"
  fi
  if [[ ! "${handle}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    die "--user handle '${handle}' contains invalid characters. Use only alphanumeric + dash + underscore."
  fi
}

check_prereqs() {
  info "Checking prerequisites..."
  check_user_handle "${USER_HANDLE}"   # Suggestion (d) 反映、 early reject
  check_os
  # uv が Python 管理を担うため python3 直接 check は廃止。
  # uv がなければ installer を進められないため early reject。
  check_command uv "Install uv from https://docs.astral.sh/uv/getting-started/installation/"

  # Docker は **`--hub-mode self-host` の時のみ必須** (= PR #2 review Suggestion 1 反映、
  # Minor 3 の natural 延長)。 public mode (= agent-hub-ki.fly.dev に接続) では
  # local hub server を起動しないため Docker 不要、 check も skip。 これにより
  # Tier 1 「最も簡単な体験」 path で Docker 未 install の layperson も blocker なく実行可。
  if [[ "${HUB_MODE}" == "self-host" ]]; then
    check_command docker "Install Docker from https://docs.docker.com/get-docker/ (= --hub-mode self-host で必須)"
  else
    info "Docker check skipped (--hub-mode public → no local hub server)"
  fi

  if [[ "${TIER}" == "2" ]]; then
    check_command gh "Install gh CLI from https://cli.github.com/ (Tier 2 で private fork access に必要)"
    # gh auth token は gh 2.6.0 以降で追加されたサブコマンド。
    # Ubuntu 22.04 標準 apt の gh は 2.4.0 で未対応のため version check + WARN を表示する。
    local gh_version
    gh_version=$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
    local gh_major gh_minor
    gh_major=$(echo "${gh_version}" | cut -d. -f1)
    gh_minor=$(echo "${gh_version}" | cut -d. -f2)
    if [[ "${gh_major}" -lt 2 ]] || { [[ "${gh_major}" -eq 2 ]] && [[ "${gh_minor}" -lt 6 ]]; }; then
      warn "gh CLI version ${gh_version} is outdated (need 2.6.0+)."
      warn "  Ubuntu 22.04 標準 apt では古い版が入ります。公式インストール手順で更新してください:"
      warn "  https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
      warn "  → GITHUB_PAT を手動で export して続行することもできます:"
      warn "  →   export GITHUB_PAT=ghp_..."
    fi
    if ! gh auth status >/dev/null 2>&1; then
      die "gh CLI not authenticated. Run: gh auth login"
    fi
    info "gh CLI authenticated ✅"

    # ROLES_REPO が未指定でも auto_fork_roles_repo() が自動 fork するため ここでは die しない。
  fi

  if [[ "${HUB_MODE}" == "self-host" ]] && [[ -z "${EDITION}" ]]; then
    die "--hub-mode self-host requires --edition (community|private)"
  fi
}

# ============================================================
# Idempotency check
# ============================================================

check_existing_install() {
  if [[ -f "${AGENT_HUB_DIR}/.env" ]]; then
    warn "existing env file detected at ${AGENT_HUB_DIR}/.env"
    warn "  → installer will preserve it (= 上書きせず)"
    warn "  → to switch Tier 1 → Tier 2: rm -rf ${AGENT_HUB_DIR} and rerun with --tier 2 --roles-repo <yours> (= fresh start)"
    warn "  → to reinstall from scratch: rm -rf ${AGENT_HUB_DIR} and rerun"
    return 0
  fi
}

# ============================================================
# Install steps
# ============================================================

run_or_dry() {
  # Minor 1 反映: eval を廃止し array `"$@"` 渡しで shell injection 余地を eliminate。
  # caller は run_or_dry の引数を **個別 token として渡す** こと (= 文字列連結禁止)。
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] $*"
  else
    info "$*"
    "$@"
  fi
}

pull_docker_image() {
  # Minor 3 反映: `--hub-mode public` 時は agent-hub-ki.fly.dev に接続するため
  # **Docker image pull 不要** (= 数百 MB の無駄な転送を回避)。
  # `--hub-mode self-host` 時のみ local で hub server を起動するため pull が必要。
  if [[ "${SKIP_DOCKER_PULL}" == "yes" ]]; then
    info "Skipping Docker image pull (--skip-docker-pull)"
    return
  fi
  if [[ "${HUB_MODE}" == "public" ]]; then
    info "Skipping Docker image pull (--hub-mode public → no local hub server)"
    return
  fi
  info "Pulling ${DOCKER_IMAGE}..."
  run_or_dry docker pull "${DOCKER_IMAGE}"
}

install_python_packages() {
  info "Installing Python packages (agent-hub-bridges) via uv tool install..."
  # uv tool install で agent-hub-bridges[claude] を Python 3.12 環境にインストール。
  # pip install --user を廃止: uv が PATH / Python version を自動管理するため
  # PATH warn は不要になった (= uv が ~/.local/bin を適切に管理する)。
  # Note: agent-hub-roles は doc-only repo であり pip パッケージではない (= インストール不要)
  run_or_dry uv tool install --python 3.12 \
    'agent-hub-bridges[claude] @ git+https://github.com/kishibashi3/agent-hub-bridges.git'
}

init_agent_hub_dir() {
  info "Initializing ${AGENT_HUB_DIR}..."
  run_or_dry mkdir -p "${AGENT_HUB_DIR}/roles" "${AGENT_HUB_DIR}/logs"
}

auto_fork_roles_repo() {
  # Tier 2 で --roles-repo が未指定の場合、kishibashi3/agent-hub-roles を自動 fork する。
  # fork 先は "<gh-login>/agent-hub-roles" (private) とし ROLES_REPO にセットする。
  # --roles-repo が既に指定済みの場合は何もしない。
  [[ "${TIER}" == "2" ]] || return 0
  [[ -z "${ROLES_REPO}" ]] || return 0

  local template_repo="kishibashi3/agent-hub-roles"
  local gh_user
  gh_user=$(gh api user --jq '.login')
  local target_repo="${gh_user}/agent-hub-roles"

  info "--roles-repo not specified. Auto-forking ${template_repo}..."
  run_or_dry gh repo create --template "${template_repo}" --private "${target_repo}" \
    || die "Auto-fork failed (repo name conflict?). Retry with: --roles-repo ${target_repo}"

  ROLES_REPO="${target_repo}"
  # dry-run 時は fork を実行していないため成功メッセージを出さない (PR #16 Minor 1)
  [[ "${DRY_RUN}" != "yes" ]] && ok "Forked to ${target_repo} ✅"
}

clone_roles_repo() {
  # Tier 2 のみ: private fork を ${AGENT_HUB_DIR}/roles-repo に clone
  [[ "${TIER}" == "2" ]] || return 0
  local roles_dir="${AGENT_HUB_DIR}/roles-repo"
  if [[ -d "${roles_dir}" ]]; then
    info "Roles repo already cloned at ${roles_dir}, skipping"
    return
  fi
  info "Cloning ${ROLES_REPO} to ${roles_dir}..."
  run_or_dry gh repo clone "${ROLES_REPO}" "${roles_dir}"
}

write_env_file() {
  # config.yaml を廃止し env inject 方式に統一。
  # AGENT_HUB_URL / AGENT_HUB_TENANT を ${AGENT_HUB_DIR}/.env に書く。
  # GITHUB_PAT は caller env から継承 (秘密情報をファイルに書かない)。
  local env_file="${AGENT_HUB_DIR}/.env"
  if [[ -f "${env_file}" ]]; then
    info "Env file exists at ${env_file}, preserving"
    return
  fi
  info "Writing env file to ${env_file}..."
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would write ${env_file} (AGENT_HUB_URL=${AGENT_HUB_URL}, AGENT_HUB_TENANT=${USER_HANDLE})"
    return
  fi
  # AGENT_HUB_URL は resolve_hub_url() で --hub-url / caller env / --hub-mode から確定済み (issue #20)。
  # AGENT_HUB_TENANT は --user 指定 handle を正本とする (USER_HANDLE は parse_args() で $USER fallback 済)。
  cat > "${env_file}" <<EOF
AGENT_HUB_URL=${AGENT_HUB_URL}
AGENT_HUB_TENANT=${USER_HANDLE}
EOF
  chmod 600 "${env_file}"
  ok "Env file written (${env_file}) ✅"
}

write_env_sh() {
  # installer 完了時に Claude Code (MCP client) 側の shell env を source できる
  # env.sh を生成する (issue #22)。
  # bridge worker 側は ~/.agent-hub/.env で管理するが、 Claude Code (= MCP client) 起動時
  # の shell env は user が手動 export しない限り引き継がれず、 silent failure を招く。
  # env.sh を source してから claude を起動することで env propagation を installer が担う。
  # GITHUB_PAT は secret hygiene のため書かない (caller env / gh auth token で取得)。
  # 既存の env.sh は上書きしない (= .env と同じ idempotent 方針)。
  # 書き込む変数: AGENT_HUB_URL, AGENT_HUB_TENANT, AGENT_HUB_USER, AGENT_HUB_ROLES (issue #33)
  local env_sh="${AGENT_HUB_DIR}/env.sh"
  if [[ -f "${env_sh}" ]]; then
    info "env.sh exists at ${env_sh}, preserving"
    return
  fi
  info "Writing env.sh to ${env_sh}..."
  local roles_path
  if [[ "${TIER}" == "2" ]]; then
    roles_path="${AGENT_HUB_DIR}/roles-repo"
  else
    roles_path="${AGENT_HUB_DIR}/roles"
  fi
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would write ${env_sh} (AGENT_HUB_URL=${AGENT_HUB_URL}, AGENT_HUB_TENANT=${USER_HANDLE}, AGENT_HUB_USER=${USER_HANDLE}, AGENT_HUB_ROLES=${roles_path})"
    return
  fi
  # Critical (issue #22 review): コメント行に $(gh auth token) があるため、
  # <<EOF (unquoted) では heredoc 展開時に command substitution が実行されてしまう。
  # → <<'EOF' (quoted heredoc) でコメント部分を書くことで展開を完全に防ぐ。
  # Minor: 変数行は printf '%s' で書き、引用符を付ける (= source 時の特殊文字対策)。
  cat > "${env_sh}" <<'EOF'
# agent-hub shell env (issue #22)
# source this file before launching Claude Code:
#   source ~/.agent-hub/env.sh
#   export GITHUB_PAT=$(gh auth token)
#   claude
# GITHUB_PAT はここには書かない (secret hygiene)。
EOF
  printf 'export AGENT_HUB_URL="%s"\nexport AGENT_HUB_TENANT="%s"\nexport AGENT_HUB_USER="%s"\nexport AGENT_HUB_ROLES="%s"\n' \
    "${AGENT_HUB_URL}" "${USER_HANDLE}" "${USER_HANDLE}" "${roles_path}" >> "${env_sh}"
  chmod 600 "${env_sh}"
  ok "env.sh written (${env_sh}) ✅"
}

write_shell_rc() {
  # issue #35: shell rc に `source ~/.agent-hub/env.sh` を自動追記する。
  # これにより env.sh が環境変数の single source of truth となり、
  # shell rc と env.sh の二重管理・競合を防ぐ。
  # 既に source 行が存在する場合は追記しない (= idempotent)。
  local rc_file
  # SHELL 未設定時は "" -> *) ブランチ (warn + skip) — functional fallback ではなく null-guard
  case "${SHELL:-}" in
    */zsh)  rc_file="${HOME}/.zshrc" ;;
    */bash) rc_file="${HOME}/.bashrc" ;;
    *)
      warn "Unknown shell: ${SHELL:-unset}. Skipping shell rc update."
      warn "  → Manually add to your rc file: source ~/.agent-hub/env.sh"
      return 0
      ;;
  esac

  # double-quoted so ${AGENT_HUB_DIR} expands to actual path (supports custom AGENT_HUB_DIR)
  local source_line="source ${AGENT_HUB_DIR}/env.sh"

  # 既に source 行が存在するか確認 (idempotent)
  if [[ -f "${rc_file}" ]] && grep -qF "${source_line}" "${rc_file}"; then
    info "${rc_file} already contains source line, skipping"
    return 0
  fi

  info "Appending source line to ${rc_file}..."
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would append to ${rc_file}:"
    c_dim "  # agent-hub env (added by agent-hub installer)"
    c_dim "  ${source_line}"
    return 0
  fi

  local _rc_existed="yes"
  [[ -f "${rc_file}" ]] || _rc_existed="no"

  # Unquoted heredoc: ${AGENT_HUB_DIR} expands to actual path at write time.
  cat >> "${rc_file}" <<EOF

# agent-hub env (added by agent-hub installer)
${source_line}
EOF
  [[ "${_rc_existed}" == "no" ]] && info "Created ${rc_file} (new file)"
  ok "Appended source line to ${rc_file} ✅"
  info "Run: source ${rc_file}"
}

start_bridge() {
  info "Starting bridge worker in background (logs: ${AGENT_HUB_DIR}/logs/bridge.log)..."
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would spawn: AGENT_HUB_URL=<url> agent-hub-bridge-claude --user ${USER_HANDLE}"
    return
  fi

  # Minor 2 反映: 既に bridge が動いていれば respawn しない (= idempotency 100% 担保)。
  # pgrep で `agent-hub-bridge-claude --user <handle>` を grep、
  # 同 handle の bridge が見つかれば skip + hint。
  if pgrep -f "agent-hub-bridge-claude.*--user.*${USER_HANDLE}" >/dev/null 2>&1; then
    local existing_pid
    existing_pid=$(pgrep -f "agent-hub-bridge-claude.*--user.*${USER_HANDLE}" | head -1)
    warn "Bridge worker already running (PID: ${existing_pid}). Skipping spawn."
    warn "  → to respawn: kill ${existing_pid} && rerun installer"
    return
  fi

  # bridge CLI は --user <handle> + env vars 方式 (--config フラグは未実装)。
  # AGENT_HUB_URL は resolve_hub_url() で既に export 済み。
  # .env が存在する場合は source して bridge に伝播させる (.env 内の値が優先)。
  # GITHUB_PAT は caller env から継承 (秘密情報をファイルに書かない)。
  if [[ -f "${AGENT_HUB_DIR}/.env" ]]; then
    # shellcheck source=/dev/null
    set -a; source "${AGENT_HUB_DIR}/.env"; set +a
  fi
  # AGENT_HUB_URL: resolve_hub_url() + .env source により必ず設定済み。
  # fly.dev 固定 default への silent fallback を廃止 (issue #20 修正と整合)。
  : "${AGENT_HUB_URL:=${AGENT_HUB_URL}}"       # no-op: resolve_hub_url() で export 済み
  # AGENT_HUB_TENANT: --user 指定 handle を正本とする (write_env_file() と統一)。
  : "${AGENT_HUB_TENANT:=${USER_HANDLE}}"
  export AGENT_HUB_URL AGENT_HUB_TENANT

  if [[ -z "${GITHUB_PAT:-}" ]]; then
    warn "GITHUB_PAT is not set. Bridge will fail to authenticate."
    warn "  Set it with: export GITHUB_PAT=<your-github-pat>"
  fi

  # nohup + & で daemonize + disown で shell 親子関係を切断 (= Suggestion (a) 反映、
  # SIGHUP propagation を防ぐ)。 stdout/stderr を log file に redirect。
  nohup agent-hub-bridge-claude \
    --user "${USER_HANDLE}" \
    > "${AGENT_HUB_DIR}/logs/bridge.log" 2>&1 &
  local spawn_pid=$!
  disown "${spawn_pid}" 2>/dev/null || true   # Suggestion (a): job control 切断
  ok "Bridge worker spawned (PID: ${spawn_pid}) ✅"
}

# ============================================================
# doctor subcommand (issue #37) — health-check
# ============================================================

doctor_cmd() {
  echo
  c_bold "agent-hub doctor — health-check"
  echo

  local _pass=0 _warn=0 _fail=0

  # Source env files to pick up AGENT_HUB_URL / GITHUB_PAT etc.
  # shellcheck source=/dev/null
  [[ -f "${HOME}/.agent-hub/env.sh" ]] && source "${HOME}/.agent-hub/env.sh" || true
  if [[ -f "${HOME}/.agent-hub/.env" ]]; then
    # shellcheck source=/dev/null
    set -a; source "${HOME}/.agent-hub/.env"; set +a
  fi

  # ── Check 1: PAT validity ────────────────────────────────────
  local _pat="${GITHUB_PAT:-}"
  if [[ -z "${_pat}" ]] && command -v gh >/dev/null 2>&1; then
    _pat=$(gh auth token 2>/dev/null || true)
  fi
  if [[ -z "${_pat}" ]]; then
    err "[fail]  PAT validity — GITHUB_PAT not set and gh auth token unavailable"
    (( _fail++ )) || true
  elif curl -sf -H "Authorization: Bearer ${_pat}" https://api.github.com/user 2>/dev/null | grep -q '"login"'; then
    ok "PAT validity — GitHub API returned 200"
    (( _pass++ )) || true
  else
    err "[fail]  PAT validity — GitHub API did not return valid user (token expired?)"
    (( _fail++ )) || true
  fi

  # ── Check 2: Hub reachability ────────────────────────────────
  local _hub_url="${AGENT_HUB_URL:-}"
  local _hub_alive="yes"
  if [[ -z "${_hub_url}" ]]; then
    warn "[warn]  Hub reachability — AGENT_HUB_URL not set (source ~/.agent-hub/env.sh?), skipping"
    (( _warn++ )) || true
    _hub_alive="no"
  else
    # Strip /mcp suffix to get base URL, then append /health
    local _hub_base="${_hub_url%/mcp}"
    _hub_base="${_hub_base%/}"
    local _health_url="${_hub_base}/health"
    if curl -sf --max-time 10 "${_health_url}" >/dev/null 2>&1; then
      ok "Hub reachability — ${_health_url} responded"
      (( _pass++ )) || true
    else
      err "[fail]  Hub reachability — ${_health_url} did not respond (hub down?)"
      (( _fail++ )) || true
      _hub_alive="no"
    fi
  fi

  # ── Check 3: Port conflict ────────────────────────────────────
  # Extract port from hub URL (default 3000)
  local _port
  _port=$(printf '%s' "${_hub_url}" | grep -oE ':[0-9]+/' | grep -oE '[0-9]+' | head -1 || true)
  if [[ -z "${_port}" ]]; then
    _port=$(printf '%s' "${_hub_url}" | grep -oE ':[0-9]+$' | grep -oE '[0-9]+' | head -1 || true)
  fi
  [[ -z "${_port}" ]] && _port="3000"
  local _port_user=""
  local _port_tool=""
  if command -v lsof >/dev/null 2>&1; then
    _port_tool="lsof"
    _port_user=$(lsof -ti:"${_port}" 2>/dev/null | head -1 || true)
  elif command -v ss >/dev/null 2>&1; then
    _port_tool="ss"
    _port_user=$(ss -ltn 2>/dev/null | grep -E ":${_port}[^0-9]" | head -1 || true)
  fi
  if [[ -z "${_port_tool}" ]]; then
    warn "[warn]  Port conflict — neither lsof nor ss available, cannot check port ${_port}"
    (( _warn++ )) || true
  elif [[ -n "${_port_user}" ]]; then
    if [[ "${_port_tool}" == "lsof" ]]; then
      warn "[warn]  Port conflict — port ${_port} is in use by PID ${_port_user}. Hub may conflict."
    else
      warn "[warn]  Port conflict — port ${_port} is in use (ss: ${_port_user}). Hub may conflict."
    fi
    (( _warn++ )) || true
  else
    ok "Port conflict — port ${_port} is free"
    (( _pass++ )) || true
  fi

  # ── Check 4: sed compatibility ────────────────────────────────
  local _sed_test
  _sed_test=$(mktemp 2>/dev/null || echo "/tmp/agent-hub-doctor-sed-$$")
  printf 'test' > "${_sed_test}"
  if sed -i '' 's/test/ok/' "${_sed_test}" 2>/dev/null; then
    ok "sed compatibility — BSD sed (-i '' syntax) works"
    (( _pass++ )) || true
  else
    warn "[warn]  sed compatibility — BSD sed not available (GNU sed detected); -i '' will fail on this system"
    (( _warn++ )) || true
  fi
  rm -f "${_sed_test}"

  # ── Check 5: grep compatibility ───────────────────────────────
  if echo test | grep -P 'test' >/dev/null 2>&1; then
    ok "grep compatibility — grep -P (PCRE) is supported"
    (( _pass++ )) || true
  else
    warn "[warn]  grep compatibility — grep -P unavailable (BSD grep); use -E instead of -P"
    (( _warn++ )) || true
  fi

  # ── Check 6: bash version ─────────────────────────────────────
  local _bash_ver
  _bash_ver=$(bash --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0.0")
  local _bash_major
  _bash_major=$(printf '%s' "${_bash_ver}" | cut -d. -f1)
  if [[ "${_bash_major}" -lt 4 ]]; then
    warn "[warn]  bash version — bash ${_bash_ver} detected (macOS default is 3.2). \${var^^} case conversion and associative arrays unavailable."
    (( _warn++ )) || true
  else
    ok "bash version — bash ${_bash_ver} (>= 4.x)"
    (( _pass++ )) || true
  fi

  # ── Check 7: env completeness ─────────────────────────────────
  local _env_missing=()
  [[ -z "${AGENT_HUB_URL:-}" ]]    && _env_missing+=("AGENT_HUB_URL")
  [[ -z "${AGENT_HUB_USER:-}" ]]   && _env_missing+=("AGENT_HUB_USER")
  [[ -z "${AGENT_HUB_ROLES:-}" ]]  && _env_missing+=("AGENT_HUB_ROLES")
  [[ -z "${AGENT_HUB_TENANT:-}" ]] && _env_missing+=("AGENT_HUB_TENANT")
  if [[ ${#_env_missing[@]} -eq 0 ]]; then
    ok "env completeness — AGENT_HUB_URL / USER / ROLES / TENANT all set"
    (( _pass++ )) || true
  else
    warn "[warn]  env completeness — missing: ${_env_missing[*]} (source ~/.agent-hub/env.sh?)"
    (( _warn++ )) || true
  fi

  # ── Check 8: plugin patch status ──────────────────────────────
  local _watch_sh
  _watch_sh=$(find "${HOME}/.claude" -name watch.sh 2>/dev/null | head -1 || true)
  if [[ -z "${_watch_sh}" ]]; then
    ok "plugin patch status — watch.sh not found (agent-hub plugin not installed, skip)"
    (( _pass++ )) || true
  else
    if grep -q 'grep -oP' "${_watch_sh}" 2>/dev/null; then
      warn "[warn]  plugin patch status — ${_watch_sh} contains 'grep -oP' (BSD grep incompatible; patch needed)"
      (( _warn++ )) || true
    else
      ok "plugin patch status — watch.sh found, no grep -oP detected"
      (( _pass++ )) || true
    fi
  fi

  # ── Check 9: bridge zombie detection ──────────────────────────
  # If hub is unreachable, check whether bridge processes are still running
  if [[ "${_hub_alive}" == "no" ]]; then
    local _zombie_pids=""
    if command -v pgrep >/dev/null 2>&1; then
      _zombie_pids=$(pgrep -f agent-hub-bridge 2>/dev/null | tr '\n' ' ' || true)
    fi
    if [[ -n "${_zombie_pids}" ]]; then
      warn "[warn]  bridge zombie detection — hub unreachable but bridge PIDs running: ${_zombie_pids}(zombie; kill and respawn after hub recovers)"
      (( _warn++ )) || true
    else
      ok "bridge zombie detection — hub unreachable but no bridge processes found"
      (( _pass++ )) || true
    fi
  else
    ok "bridge zombie detection — hub is reachable, no zombie check needed"
    (( _pass++ )) || true
  fi

  # ── Summary ───────────────────────────────────────────────────
  echo
  c_bold "─── doctor summary ──────────────────────────────────────────"
  echo "  passed: ${_pass}   warned: ${_warn}   failed: ${_fail}"
  echo

  if [[ "${_fail}" -gt 0 ]]; then
    c_red  "  Some checks FAILED. Fix the issues above before running bridges."
    return 1
  elif [[ "${_warn}" -gt 0 ]]; then
    c_yellow "  All critical checks passed, but warnings need attention."
    return 0
  else
    c_green "  All checks passed."
    return 0
  fi
}

# ============================================================
# Final summary
# ============================================================

print_summary() {
  local hub_url="${AGENT_HUB_URL}"
  echo
  c_green "════════════════════════════════════════════════════════"
  c_green "  agent-hub bootstrapped (Tier ${TIER}) ✅  — 4 steps to first chat"
  c_green "════════════════════════════════════════════════════════"
  echo
  echo "  Handle: @${USER_HANDLE}    Hub: ${hub_url}"
  echo
  if [[ "${TIER}" == "2" ]]; then
    c_yellow "  Tier 2 (Own it) — fork-based persistent customization"
    echo "  Roles repo: ${ROLES_REPO}"
    echo "  → \`git -C ${AGENT_HUB_DIR}/roles-repo push\` で team 共有"
    echo
  fi
  c_bold "  ─── Opening ceremony ────────────────────────────────────"
  echo
  echo "  [1/4] GITHUB_PAT を設定 (bridge 認証に必要):"
  echo "    export GITHUB_PAT=\$(gh auth token)"
  c_dim "    # gh なし? → https://github.com/settings/tokens (scope: read:user)"
  echo
  echo "  [2/4] 新しい terminal を開く (または即時反映: source ~/.bashrc  /  source ~/.zshrc) + bridge を確認:"
  echo "    tail -5 ~/.agent-hub/logs/bridge.log"
  c_dim "    # \"registered\" が見えれば OK"
  c_dim "    # env.sh は自動で shell rc に追記済み — 手動 source 不要"
  echo
  echo "  [3/4] Claude Code を起動 + plugin を確認:"
  echo "    claude"
  c_dim "    # Claude Code 内: /mcp → agent-hub が見えれば OK"
  c_dim "    # 見えない? → /plugin marketplace add https://github.com/kishibashi3/agent-hub-plugins-claude"
  c_dim "    #              /plugin install agent-hub-plugin"
  echo
  echo "  [4/4] 初回メッセージを送信:"
  echo "    @${USER_HANDLE} hello"
  c_dim "    # → 返信が来たら 🎉"
  echo
  c_bold "  ─── トラブルシュート ────────────────────────────────────"
  echo "  Bridge log : tail -f ~/.agent-hub/logs/bridge.log"
  echo "  Bridge PID : pgrep -f agent-hub-bridge-claude"
  echo "  Restart    : export GITHUB_PAT=\$(gh auth token)  # gh なし? → 手動で export"
  echo "               pkill -f \"agent-hub-bridge-claude.*--user.*${USER_HANDLE}\" || true"
  echo "               source ${AGENT_HUB_DIR}/env.sh"
  echo "               nohup agent-hub-bridge-claude --user ${USER_HANDLE} \\"
  echo "                 >> ~/.agent-hub/logs/bridge.log 2>&1 &"
  c_dim "  Full guide : https://github.com/kishibashi3/agent-hub-installer/blob/main/README.md"
  echo
  if [[ "${TIER}" == "1" ]]; then
    c_dim "  ─── Tier 2 へのステップアップ (= 本番運用・team 共有) ──────"
    c_dim "  1. Fork: gh repo create --template kishibashi3/agent-hub-roles --private <yourname>/agent-hub-roles"
    c_dim "  2. Rerun: curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \\"
    c_dim "              --tier 2 --roles-repo <yourname>/agent-hub-roles --user ${USER_HANDLE}"
    c_dim "  (fresh start — Tier 1 customization は手動 copy が必要)"
    echo
  fi
}

# ============================================================
# CE admin setup guidance (= community edition + self-host only)
# ============================================================

print_ce_admin_setup_guide() {
  echo
  c_blue "═══════════════════════════════════════════════════════════════"
  c_blue "  CE Admin Setup — required before other peers can join"
  c_blue "═══════════════════════════════════════════════════════════════"
  echo
  echo "  Once your hub is running (docker-compose up -d), claim @admin to initialize the deployment."
  echo
  c_bold "  Step 1: Set environment variables"
  echo "    export GITHUB_PAT=ghp_..."
  c_dim "             # GitHub → Settings → Personal Access Tokens (scope: read:user)"
  echo "    export AGENT_HUB_URL=http://localhost:3000/mcp"
  c_dim "             # (or your server URL if different)"
  echo "    export AGENT_HUB_USER=admin"
  c_dim "             # fixes your Claude Code handle to @admin (TOFU operator claim)"
  echo
  c_bold "  Step 2: Install agent-hub-plugin in Claude Code (skip if already installed)"
  c_dim "    /plugin marketplace add https://github.com/kishibashi3/agent-hub-plugins-claude"
  c_dim "    /plugin install agent-hub-plugin"
  echo
  c_bold "  Step 3: Claim @admin via Claude Code"
  echo "    → Use the 'register' tool with name=\"admin\""
  c_dim "    → The deployment init gate opens once @admin is claimed"
  c_dim "      (until then, all other access is blocked with 503)"
  echo
  c_bold "  Step 4: Claim your tenant (recommended)"
  echo "    export AGENT_HUB_TENANT=<your-tenant-name>"
  echo "    → Re-run register — you become the TOFU owner of that tenant"
  echo
  c_bold "  Step 5: Start peer bridges"
  echo "    scripts/start.sh all   (from your roles repo)"
  c_dim "    → spawns @reviewer / @planner / @researcher / @writer bridges"
  echo
  c_dim "  Full walkthrough : https://github.com/kishibashi3/agent-hub/blob/main/docs/ce-onboarding.md"
  c_dim "  Admin ops guide  : roles/admin/CLAUDE.md  (in your roles repo)"
  echo
}

# ============================================================
# Main
# ============================================================

main() {
  echo "agent-hub installer v${INSTALLER_VERSION}"
  parse_args "$@"

  if [[ "${SUBCOMMAND}" == "doctor" ]]; then
    doctor_cmd || exit 1
    exit 0
  fi

  resolve_hub_url     # --hub-url / caller env / --hub-mode から AGENT_HUB_URL を確定 (issue #20)

  info "Args: tier=${TIER}, user=${USER_HANDLE}, hub-mode=${HUB_MODE}, hub-url=${AGENT_HUB_URL}, roles-repo=${ROLES_REPO:-(none)}, dry-run=${DRY_RUN}"

  check_prereqs
  install_uv_python     # uv で Python 3.12 を確保 (issue #18)
  auto_fork_roles_repo  # Tier 2 + --roles-repo 未指定時に自動 fork (issue #15)
  check_existing_install
  pull_docker_image
  install_python_packages
  init_agent_hub_dir

  clone_roles_repo   # Tier 2 のみ: private fork clone
  write_env_file     # AGENT_HUB_URL / AGENT_HUB_TENANT を .env に書く
  write_env_sh       # Claude Code 起動用 env.sh を生成 (issue #22)
  write_shell_rc     # shell rc に source ~/.agent-hub/env.sh を追記 (issue #35)

  start_bridge
  print_summary

  # CE + self-host: admin setup ガイダンスを print (= deployment init gate の次のステップを案内)
  if [[ "${HUB_MODE}" == "self-host" ]] && [[ "${EDITION}" == "community" ]]; then
    print_ce_admin_setup_guide
  fi
}

main "$@"
