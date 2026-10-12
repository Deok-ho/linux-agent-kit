#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Never installs software: OS, uid, packages, sudo, and downloads are mocked.
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t linux-agent-kit-tests.XXXXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=install.sh
source "$repo_dir/install.sh"

fail_test() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail_test "$1에 '$2'가 없습니다."; }
assert_absent() { ! grep -Fq -- "$2" "$1" || fail_test "$1에 '$2'가 있습니다."; }
assert_success() { [[ $main_status == 0 ]] || { cat "$case_root/stderr" >&2; fail_test "종료 코드 $main_status"; }; }
assert_failure() { [[ $main_status != 0 ]] || fail_test '실패해야 하는 요청이 성공했습니다.'; }

setup_case() {
  case_root=$test_root/$1
  mkdir -p "$case_root/packages" "$case_root/mock-bin" "$case_root/user"
  : > "$case_root/calls"
  touch "$case_root/packages/ca-certificates" "$case_root/packages/curl" "$case_root/packages/git"
  mock_uid=1000
  mock_os=ubuntu
  mock_version=24.04
  mock_arch=x86_64
  mock_cluster=''
  mock_cluster_failure=false
  mock_tailscale_path=''
  mock_download_fail=''
  mock_install_fail=''
  mock_bad_download=''
  export KIT_TEST_CASE=$case_root
  export KIT_TEST_INSTALL_FAIL=''
}

# The real environment and HOME are never replaced. All simulated installations
# target the per-case directory, and child installers contain mock code only.
read_platform() {
  platform_id=$mock_os
  platform_version=$mock_version
  platform_arch=$mock_arch
}
id() { [[ $1 == -u ]] || fail_test '예상하지 않은 id 호출'; printf '%s\n' "$mock_uid"; }
resolve_paths() {
  kit_user_dir=$case_root/user
  kit_bin_dir=$kit_user_dir/.local/bin
  temp_dir=''
  export KIT_TEST_BIN=$kit_bin_dir
  export KIT_TEST_INSTALL_FAIL=$mock_install_fail
}
find_binary() {
  if [[ -x $case_root/mock-bin/$1 ]]; then
    printf '%s\n' "$case_root/mock-bin/$1"
  elif [[ -x $kit_bin_dir/$1 ]]; then
    printf '%s\n' "$kit_bin_dir/$1"
  else
    return 1
  fi
}
package_installed() { [[ -f $case_root/packages/$1 ]]; }
pg_lsclusters() {
  ! $mock_cluster_failure || return 4
  printf '%s' "$mock_cluster"
}
existing_tailscale_path() {
  [[ -n $mock_tailscale_path ]] || return 1
  printf '%s\n' "$mock_tailscale_path"
}
mktemp() { command mktemp -d "$case_root/downloads.XXXXXXXX"; }
sudo() {
  printf 'sudo:%s\n' "$*" >> "$case_root/calls"
  [[ $1 == apt-get ]] || fail_test 'sudo가 패키지 단계 밖에서 사용되었습니다.'
  case $2 in
    update) return 0 ;;
    install)
      shift 3
      local package
      for package in "$@"; do touch "$case_root/packages/$package"; done ;;
    *) fail_test '예상하지 않은 apt-get 호출' ;;
  esac
}
curl() {
  local output='' url='' name
  while (($#)); do
    case $1 in
      --output) output=$2; shift 2 ;;
      https://*) url=$1; shift ;;
      *) shift ;;
    esac
  done
  [[ -n $output && -n $url ]] || fail_test 'curl은 URL과 저장 파일을 지정해야 합니다.'
  printf 'download:%s\n' "$url" >> "$case_root/calls"
  case $url in
    https://claude.ai/install.sh) name=claude ;;
    https://herdr.dev/install.sh) name=herdr ;;
    https://tailscale.com/install.sh) name=tailscale ;;
    *) fail_test "공식 URL 밖 다운로드: $url" ;;
  esac
  [[ $mock_download_fail != "$name" ]] || return 22
  if [[ $mock_bad_download == "$name" ]]; then
    printf '<html>proxy error</html>\n' > "$output"
    return 0
  fi
  printf '#!/bin/sh\nname=%s\n' "$name" > "$output"
  cat >> "$output" <<'MOCK'
set -eu
printf 'installer:%s\n' "$name" >> "$KIT_TEST_CASE/calls"
if [ "$KIT_TEST_INSTALL_FAIL" = "$name" ]; then exit 91; fi
if [ "$name" = claude ] && [ "${1:-}" != stable ]; then exit 92; fi
if [ "$name" = herdr ] && [ "${HERDR_INSTALL_DIR:-}" != "$KIT_TEST_BIN" ]; then exit 93; fi
mkdir -p "$KIT_TEST_BIN"
printf '#!/bin/sh\nprintf "mock version\\n"\n' > "$KIT_TEST_BIN/$name"
chmod +x "$KIT_TEST_BIN/$name"
MOCK
}

run_main() {
  # An unconditional subshell preserves errexit, including within helper calls.
  set +e
  (set -Eeuo pipefail; main "$@") > "$case_root/stdout" 2> "$case_root/stderr"
  main_status=$?
  set -e
}

dry_run_leaves_environment() {
  setup_case dry-run
  local before_path=$PATH
  printf '사용자 설정\n' > "$case_root/user/.bashrc"
  run_main --with tailscale,postgres
  assert_success
  [[ ! -s $case_root/calls && ! -d $case_root/user/.local ]] || fail_test '계획이 설치 또는 파일 생성을 실행했습니다.'
  [[ $before_path == "$PATH" && $(cat "$case_root/user/.bashrc") == '사용자 설정' ]] || fail_test '계획이 PATH/사용자 파일을 바꿨습니다.'
  assert_contains "$case_root/stdout" '설치 예정'
  assert_contains "$case_root/stdout" '계획 출력만 완료'
}

dry_run_alias() {
  setup_case alias
  run_main --dry-run
  assert_success
  [[ ! -s $case_root/calls ]] || fail_test '--dry-run이 실행했습니다.'
}

base_installs_user_tools_only() {
  setup_case base
  run_main --apply
  assert_success
  [[ -x $case_root/user/.local/bin/claude && -x $case_root/user/.local/bin/herdr ]] || fail_test '기본 실행 파일이 없습니다.'
  assert_contains "$case_root/calls" 'installer:claude'
  assert_contains "$case_root/calls" 'installer:herdr'
  assert_absent "$case_root/calls" 'sudo:'
  assert_absent "$case_root/calls" 'tailscale'
  [[ ! -f $case_root/packages/postgresql ]] || fail_test '기본 설치가 DB를 설치했습니다.'
}

reapply_preserves_installed_tools() {
  setup_case reapply
  run_main --apply
  assert_success
  local before
  before=$(cat "$case_root/calls")
  run_main --apply
  assert_success
  [[ $(cat "$case_root/calls") == "$before" ]] || fail_test '재실행이 기존 설치를 교체했습니다.'
}

selected_components() {
  setup_case optional
  run_main --apply --with tailscale,postgres
  assert_success
  assert_contains "$case_root/calls" 'installer:tailscale'
  assert_contains "$case_root/calls" 'sudo:apt-get install -y postgresql'
  assert_absent "$case_root/calls" 'tailscale up'
  assert_absent "$case_root/calls" 'systemctl'
  assert_absent "$case_root/calls" 'upgrade'
  [[ -f $case_root/packages/postgresql ]] || fail_test '선택 DB 준비를 누락했습니다.'
}

existing_settings_and_cluster() {
  setup_case existing
  mkdir -p "$case_root/user/.claude" "$case_root/user/.local/bin"
  printf 'keep\n' > "$case_root/user/.claude/settings.json"
  printf 'keep\n' > "$case_root/user/.bashrc"
  local name
  for name in claude herdr tailscale; do
    printf '#!/bin/sh\nexit 0\n' > "$case_root/user/.local/bin/$name"
    chmod +x "$case_root/user/.local/bin/$name"
  done
  mock_cluster='18 main 5432 online postgres /existing/data /existing/log'
  run_main --apply --with tailscale,postgres
  assert_success
  [[ ! -s $case_root/calls ]] || fail_test '기존 설치/클러스터를 변경했습니다.'
  [[ $(cat "$case_root/user/.claude/settings.json") == keep && $(cat "$case_root/user/.bashrc") == keep ]] || fail_test '기존 설정을 바꿨습니다.'
}

missing_prerequisites_use_scoped_apt() {
  setup_case prerequisites
  rm "$case_root/packages/curl" "$case_root/packages/git"
  run_main --apply
  assert_success
  assert_contains "$case_root/calls" 'sudo:apt-get install -y curl git'
  assert_absent "$case_root/calls" 'upgrade'
}

download_failure_stops_before_installers() {
  setup_case download-failure
  mock_download_fail=herdr
  run_main --apply --with postgres
  assert_failure
  assert_contains "$case_root/stderr" 'Herdr 설치 파일 다운로드'
  assert_contains "$case_root/stderr" '종료 코드 22'
  assert_absent "$case_root/calls" 'installer:'
  assert_absent "$case_root/calls" 'sudo:'
  [[ ! -d $case_root/user/.local ]] || fail_test '실패한 다운로드 뒤 도구를 설치했습니다.'
}

installer_failure_stops_following_steps() {
  setup_case installer-failure
  mock_install_fail=claude
  run_main --apply --with tailscale,postgres
  assert_failure
  assert_contains "$case_root/stderr" 'Claude Code 설치'
  assert_contains "$case_root/stderr" '종료 코드 91'
  assert_absent "$case_root/calls" 'installer:herdr'
  assert_absent "$case_root/calls" 'installer:tailscale'
  assert_absent "$case_root/calls" 'sudo:'
}

html_download_is_rejected() {
  setup_case html-download
  mock_bad_download=claude
  run_main --apply
  assert_failure
  assert_contains "$case_root/stderr" '셸 설치 파일이 아닙니다'
  assert_absent "$case_root/calls" 'installer:'
}

root_is_rejected() {
  setup_case root
  mock_uid=0
  run_main --apply
  assert_failure
  assert_contains "$case_root/stderr" 'root 실행은 지원하지 않습니다'
  [[ ! -s $case_root/calls ]] || fail_test 'root 실행이 환경을 수정했습니다.'
}

unsupported_os_is_rejected() {
  setup_case unsupported-os
  mock_os=debian
  run_main --apply
  assert_failure
  assert_contains "$case_root/stderr" '지원 대상은 Ubuntu 24.04'
  [[ ! -s $case_root/calls ]] || fail_test '미지원 OS를 수정했습니다.'
}

unsupported_version_arch_are_rejected() {
  setup_case unsupported-version
  mock_version=26.04
  run_main --apply
  assert_failure
  mock_version=24.04
  mock_arch=aarch64
  run_main --apply
  assert_failure
  [[ ! -s $case_root/calls ]] || fail_test '미지원 버전/아키텍처를 수정했습니다.'
}

invalid_options_are_rejected() {
  setup_case invalid-options
  local options
  for options in '--apply --plan' '--with' '--with tailscale,' '--with ,postgres' '--with tailscale,,postgres' '--with postgres,unknown' '--wat'; do
    local -a words
    read -r -a words <<< "$options"
    run_main "${words[@]}"
    assert_failure
  done
  [[ ! -s $case_root/calls ]] || fail_test '잘못된 옵션이 설치를 실행했습니다.'
}

existing_nonexecutables_are_preserved() {
  setup_case collision
  mkdir -p "$case_root/user/.local/bin"
  printf 'my file\n' > "$case_root/user/.local/bin/herdr"
  run_main --apply
  assert_failure
  [[ $(cat "$case_root/user/.local/bin/herdr") == 'my file' ]] || fail_test '기존 파일을 덮어썼습니다.'
  [[ ! -s $case_root/calls ]] || fail_test '경로 충돌인데 다운로드했습니다.'
  rm "$case_root/user/.local/bin/herdr"
  ln -s missing-binary "$case_root/user/.local/bin/herdr"
  run_main --apply
  assert_failure
  [[ -L $case_root/user/.local/bin/herdr ]] || fail_test '깨진 기존 링크를 덮어썼습니다.'
}

partial_configurations_are_preserved() {
  setup_case partial-config
  mkdir -p "$case_root/user/.claude"
  printf 'keep\n' > "$case_root/user/.claude/settings.json"
  run_main --apply
  assert_failure
  assert_contains "$case_root/stderr" '기존 설정 경로'
  [[ ! -s $case_root/calls ]] || fail_test '불완전한 기존 설정 위에 설치했습니다.'
  rm -r "$case_root/user/.claude"
  mock_tailscale_path='/etc/apt/sources.list.d/tailscale.list'
  run_main --apply --with tailscale
  assert_failure
  assert_contains "$case_root/stderr" '기존 설치 경로'
  [[ ! -s $case_root/calls ]] || fail_test 'Tailscale의 기존 설정 위에 설치했습니다.'
}

unreadable_cluster_stops_installation() {
  setup_case cluster-failure
  mock_cluster_failure=true
  run_main --apply --with postgres
  assert_failure
  assert_contains "$case_root/stderr" '클러스터 상태를 확인하지 못했습니다'
  [[ ! -s $case_root/calls ]] || fail_test '클러스터 조회 실패 뒤 설치했습니다.'
}

tests=(dry_run_leaves_environment dry_run_alias base_installs_user_tools_only
  reapply_preserves_installed_tools selected_components existing_settings_and_cluster
  missing_prerequisites_use_scoped_apt download_failure_stops_before_installers
  installer_failure_stops_following_steps html_download_is_rejected root_is_rejected
  unsupported_os_is_rejected unsupported_version_arch_are_rejected
  invalid_options_are_rejected existing_nonexecutables_are_preserved
  partial_configurations_are_preserved unreadable_cluster_stops_installation)
for test_name in "${tests[@]}"; do
  "$test_name"
  printf 'PASS: %s\n' "$test_name"
done
printf 'PASS: %s개 모의 설치 동작 검사\n' "${#tests[@]}"
