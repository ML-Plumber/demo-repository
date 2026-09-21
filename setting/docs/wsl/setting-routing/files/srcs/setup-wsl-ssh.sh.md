# `setting/wsl/srcs/setup-wsl-ssh.sh`

## 책임

WSL 내부의 UFW를 비활성화하고 OpenSSH Server를 설치·활성화한다.

## 호출 구조

```text
setup-wsl-ssh.sh
├─ root 권한 확인
├─ ufw disable
├─ apt-get update
├─ apt-get install -y openssh-server
└─ systemctl enable --now ssh
```

## 함수와 메서드

별도 함수나 메서드는 사용하지 않는다.

## 변수와 상수

- `EUID`: 실행 사용자의 권한 확인에 사용한다.
- `BASH_COMMAND`: 오류가 발생한 명령을 오류 메시지에 사용한다.
- `exit_code`: 실패한 명령의 종료 코드를 저장한다.

## 외부 호출

- `ufw disable`: WSL 내부 UFW를 비활성화한다.
- `apt-get update`: 패키지 목록을 갱신한다.
- `apt-get install -y openssh-server`: OpenSSH Server를 설치한다.
- `systemctl enable --now ssh`: SSH 서비스를 활성화하고 즉시 실행한다.
