# Windows 라우팅

## 책임

Windows 11에서 WSL 미러링 네트워크와 방화벽을 설정하는 파일별 문서로 연결한다.

## 계층별 호출 구조

```text
Windows 설정
└─ setup-window-network.ps1
   ├─ WSL 미러링 모드 설정
   ├─ Windows Firewall 규칙 설정
   ├─ Hyper-V Firewall 규칙 설정
   └─ WSL 종료를 통한 설정 반영 준비
```

- [setup-window-network.ps1 파일 문서](files/setup-window-network.ps1.md)

## 함수와 메서드

### `Set-WslMirroredMode(Path: string)`

```text
입력: .wslconfig 경로
처리: 기존 설정을 유지하며 WSL2 네트워크 모드를 mirrored로 설정
외부 호출: Test-Path, Get-Content, System.IO.File.WriteAllLines
```

### `Set-WindowsFirewallAllowRule(Name, DisplayName, Protocol, RemoteAddresses, LocalPorts?)`

```text
입력: Windows Firewall 규칙 정보
처리: 같은 규칙이 있으면 갱신하고 없으면 생성
외부 호출: Get-NetFirewallRule, Set-NetFirewallRule, New-NetFirewallRule
```

### `Set-HyperVFirewallAllowRule(Name, DisplayName, VMCreatorId, Protocol, RemoteAddresses, LocalPorts?)`

```text
입력: Hyper-V Firewall 규칙 정보와 WSL 식별자
처리: 같은 규칙이 있으면 갱신하고 없으면 생성
외부 호출: Get-NetFirewallHyperVRule, Set-NetFirewallHyperVRule, New-NetFirewallHyperVRule
```

## 변수와 상수

- `$ClusterIPs`: 실행 시 `-ClusterIPs`로 전달받은 클러스터 IP 목록이다.
- `$wslCreatorId`: WSL Hyper-V 환경을 식별하는 값이다.
- `$wslConfigPath`: `$env:USERPROFILE`에서 가져온 `.wslconfig` 경로다.
- `$ErrorActionPreference`: 오류가 발생하면 즉시 중단하도록 `Stop` 값을 가진다.
