# `setting/window/setup-wsl-network.ps1`

## 책임

Windows 11에서 WSL2 미러링 네트워크와 Windows Firewall 및 Hyper-V Firewall 규칙을 설정한다. WSL 내부의 UFW와 OpenSSH 설정은 담당하지 않는다.

## 호출 구조

```text
setup-wsl-network.ps1
├─ 관리자 권한 확인
├─ ClusterIPs 유효성 검사
├─ Set-WslMirroredMode
├─ Set-WindowsFirewallAllowRule
├─ Set-HyperVFirewallAllowRule
└─ wsl.exe --shutdown
```

## 스크립트 파라미터

### `ClusterIPs: string[]`

- 값: 본인 클러스터 IP와 추가된 상대 클러스터 IP 목록
- 출처: 실행 시 `-ClusterIPs`로 전달한다.
- 사용처: Windows Firewall과 Hyper-V Firewall의 원격 주소로 사용한다.

## 함수와 메서드

### `Set-WslMirroredMode(Path: string)`

```text
입력: %USERPROFILE%\.wslconfig 경로
처리: [wsl2] 구역의 networkingMode를 mirrored로 설정하고 기존 설정을 유지한다.
외부 호출: Test-Path, Get-Content, System.IO.File.WriteAllLines
```

### `Set-WindowsFirewallAllowRule(Name, DisplayName, Protocol, RemoteAddresses, LocalPorts?)`

```text
입력: 규칙 정보, 프로토콜, 원격 주소, 선택적 로컬 포트
처리: 기존 규칙은 갱신하고 없으면 인바운드 허용 규칙을 생성한다.
외부 호출: Get-NetFirewallRule, Set-NetFirewallRule, New-NetFirewallRule
```

### `Set-HyperVFirewallAllowRule(Name, DisplayName, VMCreatorId, Protocol, RemoteAddresses, LocalPorts?)`

```text
입력: 규칙 정보, WSL VMCreatorId, 프로토콜, 원격 주소, 선택적 로컬 포트
처리: 기존 Hyper-V 규칙은 갱신하고 없으면 인바운드 허용 규칙을 생성한다.
외부 호출: Get-NetFirewallHyperVRule, Set-NetFirewallHyperVRule, New-NetFirewallHyperVRule
```

## 변수와 상수

- `$ClusterIPs`: `ClusterIPs` 파라미터에서 받은 IP 목록
- `$wslCreatorId`: WSL Hyper-V VM 식별자
- `$wslConfigPath`: `$env:USERPROFILE`에서 만든 `.wslconfig` 경로
- `$ErrorActionPreference`: `Stop`으로 설정해 오류 발생 시 중단한다.

## 외부 실행

- `wsl.exe --shutdown`: 변경된 `.wslconfig`를 다음 WSL 실행에 적용한다.
