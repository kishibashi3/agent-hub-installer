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
  info "Installing Python packages (agent-hub-bridges)..."
  # --user で user-site にインストール (= system Python を汚さない)
  # Minor 1 反映: array 渡し (= eval 廃止) で extras `[claude]` / `[all]` も
  # 各 token として正しく解釈される。
  # Note: agent-hub-roles は doc-only repo であり pip パッケージではない (= インストール不要)
  run_or_dry python3 -m pip install --user 'agent-hub-bridges[claude]'

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
    c_dim "[dry-run] would write ${env_file} (AGENT_HUB_URL, AGENT_HUB_TENANT)"
    return
  fi
  cat > "${env_file}" <<EOF
AGENT_HUB_URL=${AGENT_HUB_HUB_URL_DEFAULT}
AGENT_HUB_TENANT=${USER:-${USER_HANDLE}}
EOF
  chmod 600 "${env_file}"
  ok "Env file written (${env_file}) ✅"
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
  # .env から env vars を読み込み、未設定の場合は installer 変数で補完する。
  # GITHUB_PAT は caller env から継承 (秘密情報をファイルに書かない)。
  if [[ -f "${AGENT_HUB_DIR}/.env" ]]; then
    # shellcheck source=/dev/null
    set -a; source "${AGENT_HUB_DIR}/.env"; set +a
  fi
  : "${AGENT_HUB_URL:=${AGENT_HUB_HUB_URL_DEFAULT}}"
  : "${AGENT_HUB_TENANT:=${USER:-${USER_HANDLE}}}"
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
# Final summary
# ============================================================

print_summary() {
  echo
  c_green "═══════════════════════════════════════════════════════════════"
  c_green "  agent-hub bootstrapped (Tier ${TIER}) ✅"
  c_green "═══════════════════════════════════════════════════════════════"
  echo
  echo "  Env:     ${AGENT_HUB_DIR}/.env"
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
  c_dim "    /plugin marketplace add https://github.com/kishibashi3/kishibashi3-plugins-claude"
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

  info "Args: tier=${TIER}, user=${USER_HANDLE}, hub-mode=${HUB_MODE}, roles-repo=${ROLES_REPO:-(none)}, dry-run=${DRY_RUN}"

  check_prereqs
  check_existing_install
  pull_docker_image
  install_python_packages
  init_agent_hub_dir

  clone_roles_repo   # Tier 2 のみ: private fork clone
  write_env_file     # AGENT_HUB_URL / AGENT_HUB_TENANT を .env に書く

  start_bridge
  print_summary

  # CE + self-host: admin setup ガイダンスを print (= deployment init gate の次のステップを案内)
  if [[ "${HUB_MODE}" == "self-host" ]] && [[ "${EDITION}" == "community" ]]; then
    print_ce_admin_setup_guide
  fi
}

main "$@"
