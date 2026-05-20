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
# Idempotent: 既に install 済の場合は config 上書きせずに hint 表示。
# 非破壊: 既存 `~/.agent-hub/config.yaml` は **絶対に上書きしない** (= user 設定保護)。
#
# Refs: https://github.com/kishibashi3/agent-hub/issues/101

set -euo pipefail

# ============================================================
# Config / Defaults
# ============================================================

INSTALLER_VERSION="0.1.0"
AGENT_HUB_DIR="${AGENT_HUB_DIR:-${HOME}/.agent-hub}"
AGENT_HUB_HUB_URL_DEFAULT="https://agent-hub-ki.fly.dev/mcp"
DOCKER_IMAGE="ghcr.io/kishibashi3/agent-hub:latest"

# Args defaults
USER_HANDLE=""
TIER="1"
ROLES_REPO=""
HUB_MODE="public"   # public | self-host
EDITION=""          # used for self-host (community | private)
DRY_RUN="no"
SKIP_DOCKER_PULL="no"

# ============================================================
# UI helpers
# ============================================================

c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_blue()   { printf '\033[34m%s\033[0m\n' "$*"; }
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

OPTIONS:
  --user <handle>            Bridge bot handle name (= agent-hub の @handle)
                             default: $USER (= shell user name)
                             validation: alphanumeric + dash + underscore のみ
  --tier <1|2>               Tier 1 (try) | Tier 2 (own、 private fork 必須)
                             default: 1
  --roles-repo <owner/name>  Tier 2 で使う private fork repo (= --tier 2 必須)
  --hub-mode <public|self-host>  Hub server location
                             default: public (= agent-hub-ki.fly.dev)
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

check_python_version() {
  # Suggestion (b) 反映: arithmetic context (( ... )) を使って numeric comparison を idiomatic に
  local py_version major minor
  py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
  major="${py_version%.*}"
  minor="${py_version#*.}"
  if (( major < 3 )) || (( major == 3 && minor < 10 )); then
    die "Python 3.10+ required, found ${py_version}. Install Python 3.10 or newer."
  fi
  info "python3 ${py_version} ✅"
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
  check_command python3 "Install Python 3.10+ from https://www.python.org/"
  check_python_version
  check_command docker "Install Docker from https://docs.docker.com/get-docker/"

  if [[ "${TIER}" == "2" ]]; then
    check_command gh "Install gh CLI from https://cli.github.com/ (Tier 2 で private fork access に必要)"
    if ! gh auth status >/dev/null 2>&1; then
      die "gh CLI not authenticated. Run: gh auth login"
    fi
    info "gh CLI authenticated ✅"

    if [[ -z "${ROLES_REPO}" ]]; then
      die "Tier 2 requires --roles-repo <owner/name>. Create one via: gh repo create --template kishibashi3/agent-hub-roles --private"
    fi
  fi

  if [[ "${HUB_MODE}" == "self-host" ]] && [[ -z "${EDITION}" ]]; then
    die "--hub-mode self-host requires --edition (community|private)"
  fi
}

# ============================================================
# Idempotency check
# ============================================================

check_existing_install() {
  if [[ -f "${AGENT_HUB_DIR}/config.yaml" ]]; then
    warn "existing config detected at ${AGENT_HUB_DIR}/config.yaml"
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
  info "Installing Python packages (agent-hub-bridges + agent-hub-roles)..."
  # --user で user-site にインストール (= system Python を汚さない)
  # Minor 1 反映: array 渡し (= eval 廃止) で extras `[claude]` / `[all]` も
  # 各 token として正しく解釈される。
  run_or_dry python3 -m pip install --user 'agent-hub-bridges[claude]' 'agent-hub-roles[all]'

  # PATH hint (= user-site bin が PATH に通っていない場合の友好メッセージ)
  local user_bin
  user_bin=$(python3 -m site --user-base 2>/dev/null)/bin
  if [[ ":${PATH}:" != *":${user_bin}:"* ]]; then
    warn "${user_bin} is not in PATH. Add to your shell rc:"
    warn "  export PATH=\"${user_bin}:\$PATH\""
  fi
}

init_agent_hub_dir() {
  info "Initializing ${AGENT_HUB_DIR}..."
  run_or_dry mkdir -p "${AGENT_HUB_DIR}/roles" "${AGENT_HUB_DIR}/logs"
}

write_config_tier1() {
  local cfg="${AGENT_HUB_DIR}/config.yaml"
  if [[ -f "${cfg}" ]]; then
    info "Config exists at ${cfg}, preserving"
    return
  fi
  info "Writing Tier 1 config to ${cfg}..."
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would write config.yaml (tier: 1, roles_source: pip-package)"
    return
  fi
  cat > "${cfg}" <<EOF_CFG
# agent-hub Tier 1 config (= Try it、 fork なし local 体験、 throwaway 前提)
#
# Tier 2 (= 私設 fork で knowledge 累積) への移行は fresh start:
#   1. Fork agent-hub-roles template (= gh repo create --template ... --private)
#   2. rm -rf ${AGENT_HUB_DIR} (= Tier 1 state を捨てる)
#   3. installer を rerun with --tier 2 --roles-repo <yours>
#   (= 自動 migration tool なし、 customization は手動 copy)
#
# Roles は agent-hub-roles[all] パッケージ標準のみ。
# Customization は ${AGENT_HUB_DIR}/roles/ で local override (= 履歴残らず)。

tier: 1
roles_source: pip-package

hub:
  url: ${AGENT_HUB_HUB_URL_DEFAULT}
  tenant: \${USER}     # 公開 hub では tenant 必須
  auth:
    github_pat: \${GITHUB_PAT}

bridges:
  - name: ${USER_HANDLE}
    type: claude
    role: default
EOF_CFG
  ok "Config written ✅"
}

write_config_tier2() {
  local cfg="${AGENT_HUB_DIR}/config.yaml"
  if [[ -f "${cfg}" ]]; then
    info "Config exists at ${cfg}, preserving"
    return
  fi
  info "Cloning ${ROLES_REPO} to ${AGENT_HUB_DIR}/roles-repo..."
  run_or_dry gh repo clone "${ROLES_REPO}" "${AGENT_HUB_DIR}/roles-repo"

  info "Writing Tier 2 config to ${cfg}..."
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would write config.yaml (tier: 2, roles_source: git-fork)"
    return
  fi
  cat > "${cfg}" <<EOF_CFG
# agent-hub Tier 2 config (= Own it、 private fork で知的資産累積)
#
# Roles は ${ROLES_REPO} (= private fork) を git managed。
# Customization は ${AGENT_HUB_DIR}/roles-repo/roles/ で編集 → git commit + push。

tier: 2
roles_source: git-fork
roles_repo: ${ROLES_REPO}

hub:
  url: ${AGENT_HUB_HUB_URL_DEFAULT}
  tenant: \${USER}     # 公開 hub では tenant 必須
  auth:
    github_pat: \${GITHUB_PAT}

bridges:
  - name: ${USER_HANDLE}
    type: claude
    role: default
EOF_CFG
  ok "Config written ✅"
}

start_bridge() {
  info "Starting bridge worker in background (logs: ${AGENT_HUB_DIR}/logs/bridge.log)..."
  if [[ "${DRY_RUN}" == "yes" ]]; then
    c_dim "[dry-run] would spawn: agent-hub-bridges-claude --config ${AGENT_HUB_DIR}/config.yaml"
    return
  fi

  # Minor 2 反映: 既に bridge が動いていれば respawn しない (= idempotency 100% 担保)。
  # pgrep で `agent-hub-bridges-claude --config <this config path>` を grep、
  # 同 config の bridge が見つかれば skip + hint。 別 config で別 bridge を動かしている
  # case (= 同一 host で複数 handle 運用) は false positive 回避のため `-f` で full
  # command line match + config path で限定。
  if pgrep -f "agent-hub-bridges-claude.*${AGENT_HUB_DIR}/config.yaml" >/dev/null 2>&1; then
    local existing_pid
    existing_pid=$(pgrep -f "agent-hub-bridges-claude.*${AGENT_HUB_DIR}/config.yaml" | head -1)
    warn "Bridge worker already running (PID: ${existing_pid}). Skipping spawn."
    warn "  → to respawn: kill ${existing_pid} && rerun installer"
    return
  fi

  # nohup + & で daemonize + disown で shell 親子関係を切断 (= Suggestion (a) 反映、
  # agent-hub-roles start.sh と pattern を揃え、 SIGHUP propagation を防ぐ)。
  # stdout/stderr を log file に redirect。
  # shellcheck disable=SC2086  # config path には space 含まない前提
  nohup agent-hub-bridges-claude \
    --config "${AGENT_HUB_DIR}/config.yaml" \
    > "${AGENT_HUB_DIR}/logs/bridge.log" 2>&1 &
  local spawn_pid=$!
  disown "${spawn_pid}" 2>/dev/null || true   # Suggestion (a): job control 切断
  ok "Bridge worker spawned (PID: ${spawn_pid}) ✅"
}

# ============================================================
# Final summary
# ============================================================

print_summary() {
  echo
  c_green "═══════════════════════════════════════════════════════════════"
  c_green "  agent-hub bootstrapped (Tier ${TIER}) ✅"
  c_green "═══════════════════════════════════════════════════════════════"
  echo
  echo "  Config:  ${AGENT_HUB_DIR}/config.yaml"
  echo "  Logs:    ${AGENT_HUB_DIR}/logs/"
  echo "  Hub:     ${AGENT_HUB_HUB_URL_DEFAULT}"
  echo "  Handle:  @${USER_HANDLE}"
  echo
  if [[ "${TIER}" == "1" ]]; then
    c_yellow "  Tier 1 (Try it) — ローカル体験用 (= throwaway 前提)"
    echo
    echo "  To use Tier 2 (= 私設 fork で knowledge 累積、 team 共有):"
    echo "    1. Fork: gh repo create --template kishibashi3/agent-hub-roles --private <yourname>/agent-hub-roles"
    echo "    2. Rerun installer:"
    c_dim "       curl -fsSL https://kishibashi3.github.io/agent-hub-installer/install.sh | bash -s -- \\"
    c_dim "         --tier 2 --roles-repo <yourname>/agent-hub-roles --user ${USER_HANDLE}"
    echo "    (= fresh start、 Tier 1 customization は手動 copy が必要)"
  else
    c_yellow "  Tier 2 (Own it) — fork-based persistent customization"
    echo
    echo "  Roles repo: ${ROLES_REPO}"
    echo "  → \`git -C ${AGENT_HUB_DIR}/roles-repo push\` で team 共有"
  fi
  echo
  echo "  Next: open Claude Code, send '@${USER_HANDLE} hello'"
  echo
  c_dim "  Refs: https://github.com/kishibashi3/agent-hub/issues/101"
}

# ============================================================
# Main
# ============================================================

main() {
  echo "agent-hub installer v${INSTALLER_VERSION}"
  parse_args "$@"

  info "Args: tier=${TIER}, user=${USER_HANDLE}, hub-mode=${HUB_MODE}, roles-repo=${ROLES_REPO:-(none)}, dry-run=${DRY_RUN}"

  check_prereqs
  check_existing_install
  pull_docker_image
  install_python_packages
  init_agent_hub_dir

  if [[ "${TIER}" == "1" ]]; then
    write_config_tier1
  else
    write_config_tier2
  fi

  start_bridge
  print_summary
}

main "$@"
