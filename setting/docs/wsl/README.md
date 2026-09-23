# WSL SSH 설정

WSL 내부에서 UFW를 비활성화하고 OpenSSH Server를 설치·활성화한다. WSL 네트워크 모드와 Windows·Hyper-V 방화벽은 [Windows 네트워크 설정 안내](../window/README.md)에서 별도로 설정한다.

## 실행 환경

- 각 클러스터 노드의 WSL2 Debian 또는 Ubuntu 계열 배포판
- 저장소 루트 폴더에서 실행하는 Bash 셸
- `sudo` 권한

## SSH 서버 설정

각 WSL 노드에서 다음 명령을 실행한다.

```bash
sudo bash setting/srcs/wsl/setup-wsl-ssh.sh
```

스크립트는 root 권한을 확인한 다음 UFW를 비활성화하고, 패키지 목록을 갱신한 뒤 `openssh-server`를 설치한다. 마지막으로 SSH 서비스를 시스템 시작 시 활성화하고 즉시 실행한다.

UFW 비활성화는 WSL 내부 방화벽 전체에 적용된다. 외부에서 SSH에 접속할 수 있도록 Windows 및 Hyper-V 방화벽 규칙도 별도로 준비해야 한다. 스크립트에는 인자가 없다.

호출 구조와 오류 처리 변수는 [WSL 라우팅 README](setting-routing/ROUTING-README.md), 세부 명령은 [setup-wsl-ssh.sh 문서](setting-routing/files/srcs/setup-wsl-ssh.sh.md)를 참고한다.
