#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"
for script in install.sh doctor.sh scripts/verify.sh tests/install_test.sh; do
  bash -n "$script"
  printf 'PASS: Bash 문법 검사 (%s)\n' "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh doctor.sh scripts/verify.sh tests/install_test.sh
  printf 'PASS: ShellCheck\n'
else
  printf 'SKIP: ShellCheck가 없어 정적 검사를 실행하지 않았습니다.\n'
fi
bash tests/install_test.sh
printf '검증 범위: 격리된 모의 명령만 사용. 실제 다운로드/Ubuntu 설치/로그인/세션 유지 미검증.\n'
