# kafka_setting/srcs/02-prepare-kafka-network.ps1

## 책임

- Windows에서 WSL2 네트워크 모드를 적용하고 실제 적용 모드를 확인한다.
- 기본값은 `mirrored`이며 `--networking-mode nat` 또는 `-NetworkingMode nat`로 NAT 모드를 선택한다.
- mirrored 모드에서는 Windows 방화벽과 WSL Hyper-V 방화벽을 준비한다.
- NAT 모드에서는 Windows 방화벽, IP Helper와 `netsh interface portproxy`를 준비한다.
- Kafka 설정 파일, node ID, cluster ID, 저장소와 프로세스는 다루지 않는다.

## 입력

| 파라미터 | 기본값 | 값과 용도 |
| --- | --- | --- |
| `NetworkingMode` / `--networking-mode` | `mirrored` | `mirrored` 또는 `nat` |
| `Distribution` | `Ubuntu` | 01에서 준비한 WSL 배포판 |
| `KafkaPorts` | `9092, 9093` | Windows와 WSL에서 허용할 broker/controller TCP 포트 |
| `PeerIps` | `LocalSubnet` | 접속을 허용할 IPv4, IPv4 CIDR 또는 로컬 서브넷. 실행 시 실제 CIDR로 변환 |
| `WindowsLanIp` | 자동 감지 | 기본 gateway가 있는 활성 인터페이스의 IPv4. 모호하면 명시 입력 |
| `ResultPath` | `%ProgramData%\KafkaCluster\network-result.json` | 03이 읽을 네트워크 준비 결과 |
| `WhatIf` | 해제 | 변경 없이 수행 예정 작업 확인 |

`PeerIps=LocalSubnet`은 인터넷 전체를 허용하지 않으면서 같은 LAN의 가변 노드 수를 지원하는 초기 기본값이다. 실제 클러스터 서버 주소가 확정되면 각 peer IPv4 또는 CIDR로 좁힌다.

## 상수와 내부 변수

| 이름 | 값 또는 출처 |
| --- | --- |
| `wslVmCreatorId` | WSL Hyper-V creator ID `{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}` |
| `firewallGroup` | `Kafka Cluster WSL` |
| `wslConfigPath` | `%USERPROFILE%\.wslconfig` |
| `reportedMode` | WSL 내부 `wslinfo --networking-mode` 결과 |
| `resolvedWindowsLanIp` | 명시 입력 또는 활성 기본 경로에서 감지한 IPv4 |
| `resolvedWslIp` | NAT 모드에서 기본 IPv4 route의 `src`로 감지한 WSL IPv4 |
| `resolvedPeerIps` | `LocalSubnet`을 Windows LAN IP의 실제 CIDR로 변환한 결과 |

## 호출 구조

```text
PowerShell 시작
  -> GNU 형식 --networking-mode 해석
  -> 입력 포트·peer 주소 검증
  -> 관리자 권한이 아니면 동일 인자로 UAC 재실행
  -> WSL 배포판 존재 확인
  -> mirrored이면 Windows build와 Hyper-V cmdlet 확인
  -> .wslconfig의 [wsl2] networkingMode 갱신
       -> 기존 파일 최초 변경 시 .kafka-network.bak 보관
       -> 값이 바뀌면 wsl.exe --shutdown
  -> wslinfo --networking-mode로 실제 모드 대조
  -> Windows LAN IPv4 확정
  -> Kafka 포트별 Windows 방화벽 규칙 생성·갱신
  -> mirrored
       -> 포트별 Hyper-V 방화벽 규칙 생성·갱신
  -> nat
       -> IP Helper 시작
       -> WSL IPv4 확인
       -> 포트별 v4tov4 portproxy 생성·갱신
  -> network-result.json 원자적 저장
```

## 함수 의사코드

```text
Resolve-GnuNetworkingMode(CurrentMode, Arguments) -> mode
  --networking-mode <mode>와 --networking-mode=<mode>를 해석
  mirrored 또는 nat가 아니거나 알 수 없는 인자가 있으면 중단
  외부 호출 없음

Test-Administrator() -> bool
  현재 Windows identity의 Administrators 역할 여부 반환
  외부 호출 없음

ConvertTo-SingleQuotedLiteral(Value) -> string
  UAC 재실행 명령에 안전한 PowerShell 문자열 literal 생성
  외부 호출 없음

Invoke-ElevatedSelf()
  현재 파라미터를 배열까지 보존한 encoded command 생성
  관리자 PowerShell을 열고 종료 코드 반환까지 대기
  외부 호출: Start-Process powershell.exe -Verb RunAs

Assert-Inputs()
  배포판, 포트 중복, PeerIps의 IPv4·CIDR 형식 검증
  외부 호출 없음

Test-WslDistribution(Name) -> bool
  WSL 배포판 목록에서 정확한 이름 확인
  외부 호출: wsl.exe --list --quiet

Assert-MirroredModeSupport()
  Windows build가 22621 이상인지 확인
  New-NetFirewallHyperVRule 제공 여부 확인
  외부 호출: Windows registry, Get-Command

Set-WslNetworkingMode(ConfigPath, Mode) -> changed
  기존 .wslconfig의 다른 section과 key 보존
  [wsl2]의 networkingMode만 추가 또는 교체
  최초 변경 시 백업, 임시 파일 작성 후 원자적 교체
  외부 호출: Copy-Item, Move-Item

Invoke-WslShutdown()
  변경된 전역 WSL 설정 적용을 위해 모든 WSL 배포판 종료
  외부 호출: wsl.exe --shutdown

Get-WslNetworkingMode(DistroName) -> mode
  WSL 내부에서 실제 적용 모드 조회
  조회 불가 또는 빈 결과면 적용 완료로 처리하지 않고 중단
  외부 호출: wsl.exe, sh, wslinfo

Get-WindowsLanIpv4(RequestedAddress) -> IPv4
  명시 주소가 현재 인터페이스에 존재하는지 검사
  미지정이면 기본 gateway가 있는 활성 인터페이스에서 한 주소 선택
  외부 호출: Get-NetIPAddress, Get-NetIPConfiguration

Get-WslIpv4(DistroName) -> IPv4
  기본 IPv4 route의 src 주소를 NAT portproxy 대상으로 선택
  외부 호출: wsl.exe, ip route

ConvertTo-Ipv4Cidr(IpAddress, PrefixLength) -> CIDR
  IPv4와 Windows 인터페이스 prefix로 network CIDR 계산
  외부 호출 없음

Resolve-PeerAddresses(Addresses, LanIp) -> addresses
  LocalSubnet을 Hyper-V 방화벽도 받는 실제 IPv4 CIDR로 변환
  중복 주소 제거
  외부 호출: Get-NetIPAddress, ConvertTo-Ipv4Cidr

Ensure-IpHelper()
  NAT portproxy가 사용하는 iphlpsvc를 활성화하고 시작
  외부 호출: Get-Service, Set-Service, Start-Service

Ensure-NatPortProxy(ListenAddress, ListenPort, ConnectAddress, ConnectPort)
  같은 listen endpoint를 제거한 뒤 정확한 WSL 대상 규칙으로 재생성
  외부 호출: netsh interface portproxy delete/add v4tov4

Ensure-WindowsFirewallRule(Port, LocalAddress, RemoteAddresses)
  스크립트 소유 이름의 기존 규칙을 교체해 중복 없이 유지
  외부 호출: Get-NetFirewallRule, Remove-NetFirewallRule, New-NetFirewallRule

Ensure-HyperVFirewallRule(Port, RemoteAddresses)
  WSL creator ID에 포트별 Hyper-V 인바운드 허용 규칙 유지
  외부 호출: Get-NetFirewallHyperVRule,
             Remove-NetFirewallHyperVRule, New-NetFirewallHyperVRule

Write-NetworkResult(Path, Mode, ReportedMode, LanIp, LinuxIp)
  적용 모드·주소·포트·peer 범위·NAT 매핑을 JSON으로 기록
  임시 파일 저장 후 최종 경로로 이동
  외부 호출: ConvertTo-Json, Move-Item
```

## 모드별 결과

| 구분 | mirrored | nat |
| --- | --- | --- |
| `.wslconfig` | `networkingMode=mirrored` | `networkingMode=nat` |
| 다른 노드가 접근할 주소 | Windows LAN IPv4 | Windows LAN IPv4 |
| WSL Kafka bind 주소 | 이후 설정에서 `0.0.0.0` 또는 검증된 로컬 주소 | 이후 설정에서 `0.0.0.0` 또는 WSL IPv4 |
| NAT portproxy | 생성하지 않음 | Windows LAN IP에서 WSL IPv4로 포트별 생성 |
| Windows 방화벽 | 생성·갱신 | 생성·갱신 |
| Hyper-V 방화벽 | 생성·갱신 | 별도 규칙 생성하지 않음 |
| WSL IP 변경 영향 | portproxy 없음 | WSL 재시작 후 스크립트를 다시 실행해 갱신 필요 |

## 실행

```powershell
# 기본값: mirrored
.\02-prepare-kafka-network.ps1

# 요청한 GNU 형식: NAT
.\02-prepare-kafka-network.ps1 --networking-mode nat

# 실제 클러스터 peer만 허용
.\02-prepare-kafka-network.ps1 -PeerIps 192.168.10.11,192.168.10.12

# 변경 예정 내용만 확인
.\02-prepare-kafka-network.ps1 -WhatIf
```

`networkingMode`는 특정 Ubuntu 하나가 아니라 Windows 사용자의 모든 WSL2 배포판에 적용되는 전역 설정이다. 값이 바뀌면 `wsl --shutdown`으로 모든 WSL 배포판이 종료된다. 스크립트는 Linux UFW, 클라우드 보안 그룹과 외부 라우터를 변경하지 않는다.
