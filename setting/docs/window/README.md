# Windows 11 세팅

1. `setup-wsl-network.ps1`로 Windows 환경의 IP 주소 미러링, SSH 포트 바인딩, 본인 클러스터 IP 지정을 한 번에 실행한다.

   관리자 권한 PowerShell 스크립트 하나로 다음 작업을 순서대로 실행한다.

   - WSL2 네트워크 모드를 `mirrored`로 설정한다.
   - WSL의 Hyper-V `VMCreatorId`와 본인 클러스터 IP를 변수로 지정한다.
   - Windows Firewall에서 SSH `22/tcp` 인바운드를 허용한다.
   - Hyper-V Firewall에서 WSL의 SSH `22/tcp` 인바운드를 허용한다.
   - Windows Firewall과 Hyper-V Firewall에서 지정한 클러스터 IP의 모든 프로토콜과 포트를 허용한다.

2. 클러스터 노드가 추가되면 상대 IP 주소를 직접 추가한다.
