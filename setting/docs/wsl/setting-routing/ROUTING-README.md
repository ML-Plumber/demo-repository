# WSL 라우팅

## 책임

WSL 내부의 SSH 실행 환경을 설정하는 파일별 문서로 연결한다.

## 계층별 호출 구조

```text
WSL 설정
└─ setup-wsl-ssh.sh
   └─ UFW 비활성화 및 OpenSSH Server 설치·활성화
```

- [setup-wsl-ssh.sh 파일 문서](files/srcs/setup-wsl-ssh.sh.md)

## 함수와 메서드

별도 함수나 메서드는 사용하지 않는다.

## 변수와 상수

- `EUID`: 실행 사용자의 권한 정보에서 가져온다.
- `BASH_COMMAND`: Bash가 실행 중인 명령에서 가져온다.
- `exit_code`: 실패한 명령의 종료 코드 값을 가진다.
