# 나만의 리눅스 에이전트 시작 키트

**리눅스 명령어를 먼저 외우지 않아도, 설치한 에이전트에게 한국어로 첫 작업을 시킬 수 있습니다.**

Ubuntu 24.04 LTS x86_64 한 대에 Claude Code와 Herdr를 준비하는 작은 시작 키트입니다.
필요하면 같은 서버에 Tailscale과 PostgreSQL을 추가합니다. 웹 UI, 별도 API 진입점, MCP 서버는 설치하지 않습니다.

이 저장소의 코드는 실제 Ubuntu 24.04 기기에 설치하기 전 단계입니다. 모의 검사 통과와 실제 설치 성공을 구분해서 확인하세요.

## 실행

저장소를 내려받은 디렉터리에서 **일반 사용자**로 실행합니다. 운영 중인 서버보다 새 Ubuntu 24.04 LTS 테스트 기기에서 시작하세요.
`sudo bash install.sh`로 전체 스크립트를 실행하지 않습니다.

```bash
bash install.sh
```

기본은 계획 출력입니다. 다운로드, PATH 변경, 파일 생성, 로그인, 서비스 변경을 실행하지 않습니다.
출력된 계획을 확인한 다음 실제 설치를 실행합니다.

```bash
bash install.sh --apply
```

원격 접속과 DB가 필요하면 같은 서버에 선택 구성을 추가합니다.

```bash
bash install.sh --apply --with tailscale,postgres
bash doctor.sh
```

`--with tailscale` 또는 `--with postgres`만 선택할 수도 있습니다.
기존 실행 파일과 PostgreSQL 클러스터가 있으면 유지합니다. 업데이트 도구로 사용하지 마세요.
실행 파일 없이 이전 Claude/Tailscale 설정이나 불완전한 설치 경로만 남아 있으면,
덮어쓰기 대신 중단하고 확인할 경로를 안내합니다.

## 첫 작업

설치 후 새 터미널에서 `herdr`를 실행하고, Herdr 안에서 `claude`를 실행합니다.
Claude 로그인은 자신의 계정으로 직접 진행합니다. 계정의 사용 권한과 비용은 별도로 확인하세요.
PATH 안내가 표시되면 현재 터미널에서 `export PATH="$HOME/.local/bin:$PATH"`를 실행할 수 있습니다.
키트는 `.bashrc`나 기존 에이전트 설정을 편집하지 않습니다.

Claude에게 첫 요청을 전달하세요.

> 현재 환경을 읽기 전용으로 확인하고 설명해줘. 내가 지정한 새 작업 폴더 안에 간단한 메모 저장 기능을 만들어줘. 예시 메모를 저장하고 다시 읽어 결과를 확인해줘. 기존 설정을 바꾸거나 파일을 삭제하기 전에 변경 내용과 영향 범위를 설명해줘. 비밀값은 출력하지 마.

Tailscale 로그인은 필요할 때 본인이 `sudo tailscale up`으로 진행합니다.
키트는 인증 키, SSH 모드, ACL, 방화벽, 포트 포워딩을 설정하지 않습니다.

## 설치 범위

| 구성 | 설치 방식 | 여기서 완료하지 않는 것 |
| --- | --- | --- |
| Claude Code | 공식 네이티브 설치 파일, stable 채널, 일반 사용자 | 계정 로그인·결제·토큰 처리·첫 작업 |
| Herdr | 공식 설치 파일, 사용자 `~/.local/bin` | 세션 생성·연결 종료 후 작업 지속성 실증 |
| Tailscale (선택) | 공식 설치 파일; 필요한 패키지 단계에 sudo | tailnet 로그인·접근 정책 변경 |
| PostgreSQL (선택) | Ubuntu 기본 `postgresql` 패키지와 기본 로컬 설정 | DB/사용자/테이블·임베딩·장기 기억·MCP 구현 |

다운로드는 HTTPS 파일로 저장하고 셸 문법을 확인한 뒤 실행합니다.
공식 설치 프로그램 자체는 게시 시점에 따라 바뀔 수 있으며, 현재 stable 바이너리를 내려받습니다.
이 키트의 버전 고정만으로 모든 외부 설치 결과까지 동일해지지는 않습니다.
실제 설치 도중 실패하면 이후 단계는 중단되지만 이미 설치된 패키지를 자동으로 제거하지 않습니다.

PostgreSQL 설치는 지식 관리 구현 완료를 뜻하지 않습니다. pgvector도 첫 설치에서 필수로 넣지 않습니다.
DB 비밀번호 파일, `pg_hba.conf`, 기존 DB, 기존 사용자, root 암호를 바꾸지 않습니다.
전체 `apt upgrade`도 실행하지 않습니다.

## 검증

```bash
bash scripts/verify.sh
```

Bash 문법, ShellCheck(설치되어 있는 경우), 격리된 모의 설치 검사를 수행합니다.
모의 검사는 root/미지원 환경 거절, 옵션 오류, dry-run 무변경, 재실행 보존,
선택 설치, 다운로드/설치 실패 시 중단을 확인합니다. 실제 sudo/apt나 네트워크 다운로드를 실행하지 않습니다.

**현재 한계:** 실제 공식 설치 파일 실행, 새 Ubuntu 24.04 기기 설치, 계정 로그인,
Tailscale 원격 재접속, Herdr 작업 지속성, PostgreSQL 저장·검색은 아직 검증하지 않았습니다.
`doctor.sh`는 파일과 서비스 상태를 읽는 진단이며 실행 파일 존재만으로 설치·작업 성공을 보장하지 않습니다.

## 공식 출처

설치 방식 확인: 2026-10-12 KST.

- [Claude Code 설치 및 인증](https://code.claude.com/docs/en/setup)
- [Herdr 설치](https://herdr.dev/docs/install/), [세션 시작](https://herdr.dev/docs/quick-start/)
- [Tailscale Linux 설치](https://tailscale.com/docs/install/linux)
- [PostgreSQL Ubuntu 패키지](https://www.postgresql.org/download/linux/ubuntu/)

## 라이선스

이 키트의 소스는 [Apache License 2.0](LICENSE)을 따릅니다.
외부 제품의 라이선스와 서비스 약관은 각 제품에 적용됩니다. 이름 사용은 공식 제휴를 뜻하지 않습니다.
