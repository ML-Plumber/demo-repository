#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Subsystem for Linux(WSL)와 Linux 배포판을 설치합니다.

.EXAMPLE
    # 관리자 PowerShell에서 실행
    .\install-wsl.ps1

.EXAMPLE
    # Ubuntu 대신 Debian을 설치
    .\install-wsl.ps1 -Distribution Debian
#>

[CmdletBinding()]
param(
    # 설치할 Linux 배포판 이름입니다. "wsl --list --online"으로 목록을 확인할 수 있습니다.
    [string]$Distribution = "Ubuntu"
)

$ErrorActionPreference = "Stop"

# WSL 설치는 선택적 Windows 기능을 바꾸므로 관리자 권한이 필요합니다.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    Write-Error "이 스크립트는 관리자 권한 PowerShell에서 실행해야 합니다. PowerShell을 '관리자 권한으로 실행'한 후 다시 시도하세요."
    exit 1
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "wsl.exe를 찾을 수 없습니다. 지원되는 Windows 10 버전 2004 이상 또는 Windows 11에서 실행하세요."
    exit 1
}

Write-Host "WSL과 '$Distribution' 배포판 설치를 시작합니다..." -ForegroundColor Cyan

# 이미 같은 배포판이 설치되어 있으면 중복 설치하지 않습니다.
$installedDistributions = @(wsl.exe --list --quiet 2>$null)
if ($installedDistributions -contains $Distribution) {
    Write-Host "'$Distribution' 배포판이 이미 설치되어 있습니다." -ForegroundColor Yellow
}
else {
    & wsl.exe --install --distribution $Distribution
    if ($LASTEXITCODE -ne 0) {
        throw "WSL 설치 명령이 종료 코드 $LASTEXITCODE 로 실패했습니다. 'wsl --list --online'으로 배포판 이름을 확인하세요."
    }
}

# 새 배포판과 이후 생성되는 배포판이 WSL 2를 사용하도록 기본값을 설정합니다.
& wsl.exe --set-default-version 2
if ($LASTEXITCODE -ne 0) {
    Write-Warning "WSL 2 기본 버전 설정을 완료하지 못했습니다. 재시작 후 'wsl --set-default-version 2'를 실행하세요."
}

Write-Host "설치 명령이 완료되었습니다." -ForegroundColor Green
Write-Host "재시작이 필요하다는 메시지가 표시됐다면 Windows를 재시작한 뒤 Start 메뉴에서 '$Distribution'을 실행해 초기 사용자 계정을 만드세요."
