#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Linux Agent Kit — Ubuntu 24.04 LTS / x86_64 시작 키트

사용법: bash install.sh [--plan | --dry-run | --apply] [--with tailscale,postgres]

기본은 --plan: 설치 계획만 출력하며 다운로드/파일/서비스를 변경하지 않습니다.
--apply       계획에 있는 설치를 실제로 실행합니다. 일반 사용자로 실행하세요.
--with 목록   tailscale, postgres 중 선택. 로그인과 DB 생성은 자동 실행하지 않습니다.
--help        도움말

기본 설치: Claude Code 공식 네이티브 stable 채널 + Herdr 공식 설치 프로그램.
계정 로그인, 구독/결제, 토큰 저장, SSH 설정, 워크스페이스 생성은 포함하지 않습니다.
EOF
}

fail() { printf '오류: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

on_error() {
  local status=$1 line=$2
  printf '오류: %s 단계, install.sh:%s (종료 코드 %s). 이후 단계는 중단했습니다.\n' \
    "${stage:-초기화}" "$line" "$status" >&2
  exit "$status"
}

read_platform() {
  [[ -r /etc/os-release ]] || fail '/etc/os-release를 읽을 수 없습니다.'
  # OS 관리자가 제공하는 로컬 배포판 정보입니다.
  # shellcheck disable=SC1091
  source /etc/os-release
  platform_id=${ID:-}
  platform_version=${VERSION_ID:-}
  platform_arch=$(uname -m)
}

resolve_paths() {
  kit_user_dir=${HOME:?HOME이 설정되어 있어야 합니다.}
  [[ $kit_user_dir == /* && $kit_user_dir != / ]] || fail '일반 사용자의 절대 HOME 경로가 필요합니다.'
  kit_bin_dir=$kit_user_dir/.local/bin
  temp_dir=''
}

find_binary() {
  local name=$1 candidate
  if candidate=$(command -v "$name" 2>/dev/null); then
    printf '%s\n' "$candidate"
  elif [[ -x $kit_bin_dir/$name ]]; then
    printf '%s\n' "$kit_bin_dir/$name"
  else
    return 1
  fi
}

package_installed() {
  local status
  status=$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) || return 1
  [[ $status == installed ]]
}

postgres_present() {
  package_installed postgresql && return 0
  # 다른 버전/저장소로 운영 중인 기존 클러스터도 보존합니다.
  command -v pg_lsclusters >/dev/null 2>&1 || return 1
  local clusters
  clusters=$(pg_lsclusters --no-header) || fail '기존 PostgreSQL 클러스터 상태를 확인하지 못했습니다. 설치를 중단합니다.'
  [[ -n $clusters ]]
}

existing_tailscale_path() {
  local path
  for path in /etc/apt/sources.list.d/tailscale.list \
    /usr/share/keyrings/tailscale-archive-keyring.gpg /var/lib/tailscale; do
    if [[ -e $path || -L $path ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

parse_args() {
  mode=plan
  mode_seen=''
  with_tailscale=false
  with_postgres=false
  while (($#)); do
    case $1 in
      --help|-h) usage; exit 0 ;;
      --plan|--dry-run|--apply)
        local selected=plan
        [[ $1 == --apply ]] && selected=apply
        [[ -z $mode_seen || $mode_seen == "$selected" ]] || fail '--apply와 --plan/--dry-run을 함께 지정할 수 없습니다.'
        mode=$selected
        mode_seen=$selected
        shift ;;
      --with)
        (($# >= 2)) || fail '--with 뒤에 tailscale,postgres 목록이 필요합니다.'
        [[ -n $2 && $2 != ,* && $2 != *, && $2 != *,,* ]] || fail '--with에 빈 항목을 넣을 수 없습니다.'
        local item
        local -a selections
        IFS=, read -r -a selections <<< "$2"
        for item in "${selections[@]}"; do
          case $item in
            tailscale) with_tailscale=true ;;
            postgres) with_postgres=true ;;
            *) fail "지원하지 않는 구성 요소: $item" ;;
          esac
        done
        shift 2 ;;
      *) fail "지원하지 않는 옵션: $1 (--help 참고)" ;;
    esac
  done
}

inspect_installation() {
  claude_present=false
  herdr_present=false
  tailscale_present=false
  pg_present=false
  find_binary claude >/dev/null && claude_present=true
  find_binary herdr >/dev/null && herdr_present=true
  if $with_tailscale; then
    find_binary tailscale >/dev/null && tailscale_present=true
  fi
  if $with_postgres; then
    postgres_present && pg_present=true
  fi

  # 실행 파일이 없는 기존 경로는 실패/사용자 파일일 수 있으므로 덮어쓰지 않습니다.
  local name
  for name in claude herdr; do
    if [[ -e $kit_bin_dir/$name || -L $kit_bin_dir/$name ]]; then
      [[ -x $kit_bin_dir/$name ]] || fail "기존 비실행 경로를 보존합니다: $kit_bin_dir/$name. 직접 확인 후 다시 실행하세요."
    fi
  done
  if ! $claude_present && [[ -e $kit_user_dir/.claude || -L $kit_user_dir/.claude ]]; then
    fail "Claude 실행 파일 없이 기존 설정 경로가 있습니다: $kit_user_dir/.claude. 기존 설정을 먼저 확인하세요."
  fi
  if $with_tailscale && ! $tailscale_present; then
    local previous_path
    if previous_path=$(existing_tailscale_path); then
      fail "Tailscale 실행 파일 없이 기존 설치 경로가 있습니다: $previous_path. 덮어쓰지 않고 중단합니다."
    fi
  fi
  missing_packages=()
  local package
  for package in ca-certificates curl git; do
    package_installed "$package" || missing_packages+=("$package")
  done
}

show_plan() {
  note "모드: $mode / 대상: $platform_id $platform_version $platform_arch"
  if ((${#missing_packages[@]})); then
    note "[설치 예정] sudo apt-get update; sudo apt-get install -y ${missing_packages[*]}"
  fi
  if $claude_present; then
    note '[유지] 기존 Claude Code'
  else
    note '[설치 예정] https://claude.ai/install.sh → 파일 저장 → bash 파일 stable (일반 사용자)'
  fi
  if $herdr_present; then
    note '[유지] 기존 Herdr'
  else
    note '[설치 예정] https://herdr.dev/install.sh → 파일 저장 → sh 파일 (일반 사용자)'
  fi
  if $with_tailscale; then
    if $tailscale_present; then
      note '[유지] 기존 Tailscale, tailnet/ACL/로그인 설정'
    else
      note '[설치 예정] https://tailscale.com/install.sh → 파일 저장 → sh 파일; 공식 프로그램이 필요한 패키지 단계에 sudo 사용'
      note '  공식 Tailscale 설치는 apt 저장소/키와 tailscaled 서비스를 준비할 수 있습니다. 로그인은 사용자가 별도 진행합니다.'
    fi
  fi
  if $with_postgres; then
    if $pg_present; then
      note '[유지] 기존 PostgreSQL 클러스터/설정'
    else
      note '[설치 예정] sudo apt-get update; sudo apt-get install -y postgresql (Ubuntu 기본 저장소, 기본 로컬 설정)'
    fi
  fi
  note '이 키트는 기존 설정/작업 폴더를 편집하지 않습니다. DB·지식 검색·MCP 구현은 후속 작업입니다.'
}

cleanup() {
  [[ -z ${temp_dir:-} ]] || rm -rf -- "$temp_dir"
}

download_installer() {
  local url=$1 target=$2 interpreter=$3
  note "[다운로드] $url"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error \
    --location --connect-timeout 15 --max-time 180 --output "$target" "$url"
  [[ -s $target ]] || fail "빈 설치 파일: $url"
  # HTML/프록시 에러 페이지를 설치 파일로 실행하지 않습니다.
  local first_line
  IFS= read -r first_line < "$target" || true
  [[ $first_line == '#!'* ]] || fail "셸 설치 파일이 아닙니다: $url"
  "$interpreter" -n "$target"
}

prepare_downloads() {
  temp_dir=$(mktemp -d -t linux-agent-kit.XXXXXXXX)
  trap cleanup EXIT
  if ! $claude_present; then
    stage='Claude Code 설치 파일 다운로드'
    download_installer 'https://claude.ai/install.sh' "$temp_dir/claude.sh" bash
  fi
  if ! $herdr_present; then
    stage='Herdr 설치 파일 다운로드'
    download_installer 'https://herdr.dev/install.sh' "$temp_dir/herdr.sh" sh
  fi
  if $with_tailscale && ! $tailscale_present; then
    stage='Tailscale 설치 파일 다운로드'
    download_installer 'https://tailscale.com/install.sh' "$temp_dir/tailscale.sh" sh
  fi
}

verify_binary() {
  local name=$1 executable
  executable=$(find_binary "$name") || fail "$name 설치 후 실행 파일을 찾지 못했습니다."
  "$executable" --version
}

apply_installation() {
  # root로 키트 전체를 실행하지 않으며, 시스템 설치 단계만 sudo를 사용합니다.
  if ((${#missing_packages[@]})) || { $with_postgres && ! $pg_present; } || { $with_tailscale && ! $tailscale_present; }; then
    command -v sudo >/dev/null || fail '시스템 패키지 설치에 sudo가 필요합니다.'
  fi
  if ((${#missing_packages[@]})); then
    stage='필수 패키지 설치'
    sudo apt-get update
    sudo apt-get install -y "${missing_packages[@]}"
  fi
  prepare_downloads
  if ! $claude_present; then
    stage='Claude Code 설치'
    bash "$temp_dir/claude.sh" stable
    verify_binary claude
  fi
  if ! $herdr_present; then
    stage='Herdr 설치'
    HERDR_INSTALL_DIR="$kit_bin_dir" sh "$temp_dir/herdr.sh"
    verify_binary herdr
  fi
  if $with_tailscale && ! $tailscale_present; then
    stage='Tailscale 설치'
    sh "$temp_dir/tailscale.sh"
    verify_binary tailscale
  fi
  if $with_postgres && ! $pg_present; then
    stage='PostgreSQL 설치'
    sudo apt-get update
    sudo apt-get install -y postgresql
    postgres_present || fail 'PostgreSQL 설치 뒤 패키지/클러스터를 찾지 못했습니다.'
  fi
  stage='완료'
  note '설치 단계 완료. 로그인과 첫 작업은 아래 순서로 직접 진행하세요.'
  note '1. 새 터미널을 열고 bash doctor.sh로 실행 파일 경로를 확인하세요.'
  note '2. herdr를 실행하고, 그 안에서 claude를 실행해 본인 계정으로 로그인하세요.'
  if $with_tailscale; then note '3. 원격 접속이 필요하면 본인이 sudo tailscale up을 실행해 로그인하세요. 기존 tailnet 설정을 확인하세요.'; fi
  # 사용자가 복사할 명령 예시이므로 HOME과 PATH를 여기서 확장하지 않습니다.
  # shellcheck disable=SC2016
  note '일반 사용자 홈의 ~/.local/bin이 PATH에 없으면 현재 터미널에서만 export PATH="$HOME/.local/bin:$PATH"를 실행하세요.'
}

main() {
  stage='옵션 확인'
  trap 'on_error "$?" "$LINENO"' ERR
  parse_args "$@"
  [[ $(id -u) != 0 ]] || fail 'sudo bash install.sh 또는 root 실행은 지원하지 않습니다. 일반 사용자로 실행하세요.'
  stage='지원 환경 확인'
  read_platform
  [[ $platform_id == ubuntu && $platform_version == 24.04 && $platform_arch == x86_64 ]] \
    || fail "지원 대상은 Ubuntu 24.04 LTS x86_64입니다. 현재: $platform_id $platform_version $platform_arch"
  resolve_paths
  stage='기존 설치 확인'
  inspect_installation
  show_plan
  if [[ $mode == plan ]]; then
    note '계획 출력만 완료했습니다. 실제 설치는 bash install.sh --apply [--with tailscale,postgres]로 실행하세요.'
    return 0
  fi
  apply_installation
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
