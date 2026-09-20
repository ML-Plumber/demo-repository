# `setting/srcs/install-wsl.ps1`

## 책임과 경계

- 계층: Windows 설치 진입 스크립트.
- 책임: 관리자 권한과 `wsl.exe` 존재 여부를 확인하고, 지정한 Linux 배포판을 WSL에 설치한 뒤 WSL 2를 기본 버전으로 설정한다.
- 호출 대상: Windows 보안 주체 API, PowerShell 명령 탐색, `wsl.exe`, 콘솔 출력 API.
- 비책임: Linux 초기 사용자 생성, Windows 재시작 실행, 배포판 온라인 목록 조회, 다른 설정 파일의 관리.

## 호출 구조

```text
PowerShell 관리자 세션
  -> install-wsl.ps1
       -> WindowsIdentity / WindowsPrincipal: 관리자 여부 확인
       -> Get-Command wsl.exe: WSL CLI 존재 확인
       -> wsl.exe --list --quiet: 설치된 배포판 조회
       -> (미설치 시) wsl.exe --install --distribution <Distribution>
       -> wsl.exe --set-default-version 2
       -> Write-Host / Write-Warning / Write-Error: 결과 안내
```

## 입력과 상태값

| 항목 | 값 또는 출처 | 용도 |
| --- | --- | --- |
| `Distribution` | PowerShell 파라미터, 기본값 `Ubuntu` | 설치하거나 설치 여부를 검사할 배포판 이름 |
| `$ErrorActionPreference` | 문자열 `Stop` | PowerShell 오류를 예외 흐름으로 전환 |
| `$currentIdentity` | `WindowsIdentity.GetCurrent()` 반환값 | 현재 실행 사용자 식별 |
| `$currentPrincipal` | `$currentIdentity`로 생성한 `WindowsPrincipal` | Windows 역할 확인 주체 |
| `$isAdministrator` | `Administrator` 역할 검사 결과 | 관리자 권한 실패 시 종료 여부 |
| `$installedDistributions` | `wsl.exe --list --quiet` 표준 출력 | 중복 설치 방지용 배포판 목록 |
| `$LASTEXITCODE` | 직전 외부 프로세스 종료 코드 | WSL 설치 성공 여부 판단 |

## 처리 의사코드

### 스크립트 진입점

```text
install-wsl.ps1(Distribution: string = "Ubuntu")
  오류 처리 정책을 Stop으로 설정한다.

  currentIdentity <- WindowsIdentity.GetCurrent()
  currentPrincipal <- WindowsPrincipal(currentIdentity)
  isAdministrator <- currentPrincipal.IsInRole(Administrator)
  if isAdministrator가 false이면
    Write-Error(관리자 PowerShell 실행 안내)
    exit(1)

  if Get-Command("wsl.exe") 결과가 없으면
    Write-Error(지원 Windows 및 wsl.exe 필요 안내)
    exit(1)

  Write-Host(설치 시작 안내)
  installedDistributions <- wsl.exe --list --quiet 호출 결과
  if installedDistributions에 Distribution이 포함되면
    Write-Host(이미 설치됨 안내)
  else
    wsl.exe --install --distribution Distribution 호출
    if LASTEXITCODE가 0이 아니면
      throw(설치 실패 및 배포판 목록 확인 안내)

  wsl.exe --set-default-version 2 호출
  if LASTEXITCODE가 0이 아니면
    Write-Warning(재시작 후 수동 설정 안내)

  Write-Host(완료 및 재시작·초기 사용자 생성 안내)
```

## 외부 호출 계약

| 호출 | 입력 | 기대 결과 | 실패 처리 |
| --- | --- | --- | --- |
| `WindowsIdentity.GetCurrent()` | 없음 | 현재 사용자 ID | PowerShell 오류 정책에 따라 중단 |
| `WindowsPrincipal.IsInRole()` | `Administrator` 역할 | 관리자 여부 Boolean | `false`이면 오류 출력 후 종료 |
| `Get-Command wsl.exe` | `wsl.exe` | 실행 파일 명령 정보 | 없으면 오류 출력 후 종료 |
| `wsl.exe --list --quiet` | 없음 | 설치된 배포판 이름 목록 | 표준 오류는 숨기고 빈 목록으로 처리 가능 |
| `wsl.exe --install --distribution` | `Distribution` | WSL 기능·배포판 설치 | 0 이외 종료 코드면 예외 발생 |
| `wsl.exe --set-default-version 2` | WSL 버전 `2` | 이후 배포판의 기본 버전 설정 | 실패 시 경고만 출력 |
