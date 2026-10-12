#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

case ${1:-} in
  --help|-h)
    printf '사용법: bash doctor.sh\n실행 파일·배포판·서비스 상태만 읽습니다. 로그인/토큰/메모 내용은 조회하지 않습니다.\n'
    exit 0 ;;
  '') (($# == 0)) || { printf '오류: 옵션을 지원하지 않습니다.\n' >&2; exit 1; } ;;
  *) printf '오류: 옵션을 지원하지 않습니다.\n' >&2; exit 1 ;;
esac

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  printf '환경: %s / %s\n' "${PRETTY_NAME:-알 수 없음}" "$(uname -m)"
  if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 || $(uname -m) != x86_64 ]]; then
    printf '참고: 이 키트의 설치 지원 대상은 Ubuntu 24.04 LTS x86_64입니다.\n'
  fi
fi

missing=0
for name in claude herdr; do
  executable=''
  if executable=$(command -v "$name" 2>/dev/null); then
    :
  elif [[ -x ${HOME:?}/.local/bin/$name ]]; then
    executable=$HOME/.local/bin/$name
    printf '[PATH 확인 필요] %s: %s\n' "$name" "$executable"
  else
    printf '[없음] %s\n' "$name"
    missing=1
    continue
  fi
  # version 실행조차 하지 않는 읽기 진단: CLI가 자동 갱신/세션을 시작할 여지를 줄입니다.
  printf '[실행 파일 있음] %s: %s\n' "$name" "$executable"
done

for name in tailscale pg_lsclusters; do
  if executable=$(command -v "$name" 2>/dev/null); then
    printf '[선택 구성 있음] %s: %s\n' "$name" "$executable"
  else
    printf '[선택 구성 없음] %s\n' "$name"
  fi
done

if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
  for service in tailscaled postgresql; do
    state=$(systemctl is-active "$service" 2>/dev/null) || true
    printf '[서비스] %s: %s\n' "$service" "${state:-확인 불가}"
  done
fi

printf '실행 파일 존재는 로그인, 실제 에이전트 작업, 재접속 지속성, DB 검색 성공을 보장하지 않습니다.\n'
exit "$missing"
