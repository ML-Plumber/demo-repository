#!/usr/bin/env bash
set -Eeuo pipefail

# 실패한 명령과 종료 코드를 출력하고 즉시 종료한다.
trap 'exit_code=$?; printf "설정 실패: %s 명령 실행 중 오류가 발생했습니다. (종료 코드: %d)\n" "$BASH_COMMAND" "$exit_code" >&2; exit "$exit_code"' ERR

if (( EUID != 0 )); then
    printf '설정 실패: sudo 권한으로 실행해야 합니다.\n' >&2
    exit 1
fi

ufw disable
apt-get update
apt-get install -y openssh-server
systemctl enable --now ssh
