# Windows 11 네트워크 설정

Windows 11 호스트에서 WSL2의 mirrored 네트워크 모드와 Windows·Hyper-V 방화벽 규칙을 설정한다. WSL 내부의 SSH 서버나 UFW는 별도로 [WSL 설정 안내](../wsl/README.md)를 따른다.

## 실행 환경

- Windows 11에서 저장소 루트 폴더를 연 관리자 권한 PowerShell
- WSL2가 설치되어 있는 Windows 계정
- 서로 통신을 허용할 클러스터 노드들의 IPv4 주소

## 설정 스크립트 실행

`-ClusterIPs`에는 이 Windows 노드로 들어오는 클러스터 통신을 허용할 **상대 노드의 IPv4 주소**를 전달한다. 포트 번호는 넣지 않는다. 아래 예시는 현재 노드가 `192.168.0.11`일 때의 명령이며, 각 노드에서 실행할 때는 자기 주소를 제외한 상대 노드 주소를 지정한다.

```powershell
.\setting\srcs\window\setup-window-network.ps1 -ClusterIPs '192.168.0.12','192.168.0.13','192.168.0.14'
```

스크립트는 다음 작업을 수행한다.

1. 사용자 프로필의 `.wslconfig`에서 WSL2 네트워크 모드를 `mirrored`로 설정한다.
2. Windows Firewall과 Hyper-V Firewall에서 SSH `TCP/22` 인바운드를 모든 원격 주소에 허용한다.
3. Windows Firewall과 Hyper-V Firewall에서 `-ClusterIPs`에 지정한 원격 주소의 모든 프로토콜과 포트 인바운드를 허용한다.
4. `wsl.exe --shutdown`으로 WSL을 종료해 다음 실행부터 설정이 적용되게 한다.

이 설정은 WSL의 네트워크 모드를 mirrored로 바꾸고 방화벽 통신을 허용한다. 포트 번호를 다른 포트로 전달하는 포트 포워딩은 설정하지 않는다. 특히 SSH `TCP/22` 규칙은 현재 모든 원격 주소에 적용된다.

새 노드가 추가되거나 IP가 바뀌면 각 Windows 노드에서 상대 노드 IP 목록을 갱신해 스크립트를 다시 실행한다. 방화벽 허용 규칙은 해당 스크립트가 기존 규칙을 갱신한다.

스크립트의 함수와 호출 구조는 [Windows 라우팅 README](setting-routing/ROUTING-README.md), 입력값과 상세 동작은 [setup-window-network.ps1 문서](setting-routing/files/setup-window-network.ps1.md)를 참고한다.
