#Requires -Version 5.1
<#
.SYNOPSIS
빈 Windows에서 WSL Ubuntu와 Kafka 4.3.1 실행 환경을 준비합니다.

.EXAMPLE
.\01-bootstrap-kafka-node.ps1 -RestartIfRequired
#>

[CmdletBinding()]
param(
    [string]$Distribution = "Ubuntu",
    [string]$LinuxUser,
    [switch]$RestartIfRequired,
    [switch]$ResumeAfterRestart
)

$ErrorActionPreference = "Stop"
$resumeTaskName = "KafkaBootstrapResume"


function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}


function Get-DefaultLinuxUser {
    $name = (
        $env:USERNAME.ToLowerInvariant() -replace "[^a-z0-9_-]", ""
    )

    if ([string]::IsNullOrWhiteSpace($name)) {
        return "kafka"
    }

    return $name
}


function Assert-LinuxUser {
    param(
        [string]$Name
    )

    if ($Name -notmatch "^[a-z_][a-z0-9_-]{0,31}$") {
        throw "LinuxUser는 영문 소문자, 숫자, _, -만 사용하며 숫자로 시작할 수 없습니다: $Name"
    }
}


function Test-WslDistribution {
    param(
        [string]$Name
    )

    $names = @(
        & wsl.exe --list --quiet 2>$null
    )

    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    foreach ($item in $names) {
        $normalized = ($item -replace "`0", "").Trim()

        if ($normalized -eq $Name) {
            return $true
        }
    }

    return $false
}


function Assert-WslInstallSupportsNoLaunch {
    # 오래된 WSL은 --no-launch를 지원하지 않아 설치 뒤 대화형 Ubuntu 셸이 열릴 수 있습니다.
    $helpOutput = @(
        & wsl.exe --help 2>$null
    )
    # wsl.exe 도움말이 UTF-16으로 전달될 때 문자 사이에 들어오는 NUL 문자를 제거합니다.
    $helpText = ($helpOutput -join "`n") -replace "`0", ""

    # 일부 WSL은 정상 도움말을 출력한 뒤에도 종료 코드 -1을 반환하므로 내용만 검사합니다.
    if ($helpText -notmatch "--no-launch") {
        throw (
            "현재 WSL은 --no-launch 옵션을 지원하지 않습니다. " +
            "Ubuntu 최초 실행 셸이 PowerShell을 붙잡지 않도록 WSL을 업데이트한 뒤 다시 실행하세요."
        )
    }
}


function Test-WslReady {
    param(
        [string]$Name,
        [int]$RetryCount = 36,
        [int]$RetryDelaySeconds = 5
    )

    Write-Host "WSL $Name 실행 준비 상태를 확인합니다..." -ForegroundColor Cyan

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {

        & wsl.exe `
            --distribution $Name `
            --user root `
            --exec /bin/sh -c "exit 0" `
            2>$null | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "WSL $Name 준비 완료" -ForegroundColor Green
            return $true
        }

        Write-Host "WSL 준비 대기 중... ($attempt/$RetryCount)"

        if ($attempt -lt $RetryCount) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    return $false
}


function Register-Resume {
    param(
        [string]$ScriptPath,
        [string]$DistroName,
        [string]$TargetLinuxUser
    )

    $quotedScript = '"' + $ScriptPath.Replace('"', '""') + '"'
    $quotedDistro = '"' + $DistroName.Replace('"', '""') + '"'
    $quotedUser = '"' + $TargetLinuxUser.Replace('"', '""') + '"'

    $arguments = (
        "-NoProfile -ExecutionPolicy Bypass " +
        "-File $quotedScript " +
        "-Distribution $quotedDistro " +
        "-LinuxUser $quotedUser " +
        "-ResumeAfterRestart"
    )

    $accountName = "$env:USERDOMAIN\$env:USERNAME"

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument $arguments `
        -WorkingDirectory (Split-Path -Parent $ScriptPath)

    $trigger = New-ScheduledTaskTrigger `
        -AtLogOn `
        -User $accountName

    $principal = New-ScheduledTaskPrincipal `
        -UserId $accountName `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $resumeTaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Force | Out-Null
}


function Remove-Resume {
    Unregister-ScheduledTask `
        -TaskName $resumeTaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue
}


function Request-WslRestart {
    param(
        [string]$DistroName,
        [string]$TargetLinuxUser
    )

    Register-Resume `
        -ScriptPath $PSCommandPath `
        -DistroName $DistroName `
        -TargetLinuxUser $TargetLinuxUser

    if ($RestartIfRequired) {

        Write-Host ""
        Write-Host "WSL 설치 완료를 위해 Windows를 다시 시작합니다." -ForegroundColor Yellow
        Write-Host "로그인하면 Kafka 설치를 자동 재개합니다." -ForegroundColor Yellow

        Restart-Computer -Force
        return
    }

    Write-Warning (
        "WSL이 아직 실행 준비 상태가 아닙니다. " +
        "Windows를 재시작하고 같은 계정으로 로그인하면 Kafka 설치가 자동 재개됩니다. " +
        "즉시 재시작하려면 -RestartIfRequired 옵션으로 실행하세요."
    )
}


function Ensure-Wsl {
    param(
        [string]$DistroName,
        [string]$TargetLinuxUser
    )

    if (Test-WslDistribution $DistroName) {

        Write-Host "기존 WSL 배포판 발견: $DistroName" -ForegroundColor Cyan

        if (Test-WslReady $DistroName) {
            return $true
        }

        Request-WslRestart `
            -DistroName $DistroName `
            -TargetLinuxUser $TargetLinuxUser

        return $false
    }


    Write-Host ""
    Write-Host "WSL과 $DistroName 설치를 시작합니다..." -ForegroundColor Cyan
    Write-Host "Ubuntu 최초 사용자명/비밀번호 입력 셸은 실행하지 않습니다." -ForegroundColor Cyan
    Write-Host "Linux 사용자 $TargetLinuxUser 는 다음 단계에서 만들거나 재사용합니다." -ForegroundColor Cyan

    # 대화형 최초 실행으로 PowerShell이 멈추지 않는 WSL 버전만 사용합니다.
    Assert-WslInstallSupportsNoLaunch

    # 재부팅이 필요할 가능성이 있으므로 미리 재개 작업 등록
    Register-Resume `
        -ScriptPath $PSCommandPath `
        -DistroName $DistroName `
        -TargetLinuxUser $TargetLinuxUser


    # 중요:
    # --no-launch를 사용해서 Ubuntu 설치 후
    # 사용자명/비밀번호 입력 셸이 PowerShell을 붙잡지 않게 합니다.
    & wsl.exe `
        --install `
        --distribution $DistroName `
        --no-launch

    $exitCode = $LASTEXITCODE


    if ($exitCode -ne 0 -and $exitCode -ne 3010) {

        Remove-Resume

        throw "WSL 설치가 종료 코드 $exitCode 로 실패했습니다."
    }


    Write-Host ""
    Write-Host "WSL 배포판 설치 명령 완료. Linux root 실행 가능 여부를 확인합니다." -ForegroundColor Cyan


    if (
        (Test-WslDistribution $DistroName) -and
        (Test-WslReady $DistroName)
    ) {

        Remove-Resume
        return $true
    }


    Request-WslRestart `
        -DistroName $DistroName `
        -TargetLinuxUser $TargetLinuxUser

    return $false
}


function Invoke-WslKafkaInstall {
    param(
        [string]$DistroName,
        [string]$TargetLinuxUser
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "WSL 내부 Java / Kafka 설치를 시작합니다." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $bashPayload = @'
set -Eeuo pipefail

target_user="$1"

kafka_version="4.3.1"
kafka_scala_version="2.13"

kafka_archive="kafka_${kafka_scala_version}-${kafka_version}.tgz"
kafka_url="https://downloads.apache.org/kafka/${kafka_version}/${kafka_archive}"


die() {
    echo "오류: $*" >&2
    exit 1
}


echo
echo "========================================"
echo "[1/6] Linux 사용자 확인"
echo "========================================"

if ! id -u "$target_user" >/dev/null 2>&1; then
    echo "Linux 사용자 생성: $target_user"

    useradd \
        --create-home \
        --shell /bin/bash \
        "$target_user"
else
    echo "기존 Linux 사용자 사용: $target_user"
fi


target_home="$(getent passwd "$target_user" | cut -d: -f6)"

[[ -d "$target_home" ]] ||
    die "Linux 사용자 홈을 찾지 못했습니다: $target_user"


echo
echo "========================================"
echo "[2/6] Ubuntu 패키지 목록 업데이트"
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

apt-get update


echo
echo "========================================"
echo "[3/6] JDK 17 / curl 설치"
echo "========================================"

apt-get install -y \
    ca-certificates \
    curl \
    openjdk-17-jdk


java_bin="$(
    update-alternatives --list java 2>/dev/null |
    grep -E '/java-17-[^/]*/bin/java$' |
    head -n 1 ||
    true
)"

if [[ -z "$java_bin" ]]; then
    java_bin="$(
        find /usr/lib/jvm \
            -type f \
            -path '*/bin/java' \
            -path '*java-17*' \
            2>/dev/null |
        head -n 1 ||
        true
    )"
fi


[[ -n "$java_bin" ]] ||
    die "JDK 17 실행 파일을 찾지 못했습니다."


java_bin="$(readlink -f "$java_bin")"
java_home="${java_bin%/bin/java}"


echo
echo "JAVA_HOME=$java_home"
"$java_home/bin/java" -version


# 새 WSL 배포판이라면 이 사용자를 기본 사용자로 설정
if [[ ! -f /etc/wsl.conf ]]; then

    printf '[user]\ndefault=%s\n' "$target_user" > /etc/wsl.conf

else

    echo
    echo "/etc/wsl.conf가 이미 존재하므로 자동으로 덮어쓰지 않습니다."

fi


echo
echo "========================================"
echo "[4/6] Kafka 다운로드 / 검증"
echo "========================================"


runuser -u "$target_user" -- \
env \
HOME="$target_home" \
JAVA_HOME="$java_home" \
KAFKA_VERSION="$kafka_version" \
KAFKA_SCALA_VERSION="$kafka_scala_version" \
KAFKA_ARCHIVE="$kafka_archive" \
KAFKA_URL="$kafka_url" \
bash -s <<'USER_INSTALL'

set -Eeuo pipefail


package_dir="$HOME/packages"

version_dir="$HOME/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}"
kafka_home="$HOME/kafka"

env_file="$HOME/.kafka-env"
env_marker="# Managed by 01-bootstrap-kafka-node.ps1"

archive_path="$package_dir/$KAFKA_ARCHIVE"
checksum_path="$archive_path.sha512"


die() {
    echo "오류: $*" >&2
    exit 1
}


mkdir -p "$package_dir"


echo
echo "Kafka 다운로드 URL:"
echo "$KAFKA_URL"
echo


if [[ ! -f "$archive_path" ]]; then

    rm -f "${archive_path}.part"

    curl \
        --fail \
        --location \
        --show-error \
        --progress-bar \
        "$KAFKA_URL" \
        --output "${archive_path}.part"

    mv "${archive_path}.part" "$archive_path"

else

    echo "기존 Kafka 압축 파일 사용:"
    echo "$archive_path"

fi


rm -f "${checksum_path}.part"

curl \
    --fail \
    --location \
    --show-error \
    --progress-bar \
    "${KAFKA_URL}.sha512" \
    --output "${checksum_path}.part"


mv \
    "${checksum_path}.part" \
    "$checksum_path"


echo
echo "SHA-512 검증 중..."


# Apache SHA512 파일은 8자리 해시 블록을 여러 줄로 나눌 수 있으므로 하나로 합칩니다.
expected_sha512=""
while IFS= read -r checksum_line; do
    if [[ "$checksum_line" == *:* ]]; then
        checksum_line="${checksum_line#*:}"
    fi

    checksum_line="${checksum_line//[[:space:]]/}"

    if [[ "$checksum_line" =~ ^[[:xdigit:]]+$ ]]; then
        expected_sha512+="$checksum_line"
    fi
done < "$checksum_path"

expected_sha512="${expected_sha512^^}"


actual_sha512="$(
    sha512sum "$archive_path" |
    awk '{ print toupper($1) }'
)"


[[ ${#expected_sha512} -eq 128 ]] ||
    die "공식 SHA-512 파일 형식이 올바르지 않습니다."


[[ "$actual_sha512" == "$expected_sha512" ]] ||
    die "$KAFKA_ARCHIVE SHA-512 검증에 실패했습니다."


echo "Kafka SHA-512 검증 성공"


echo
echo "========================================"
echo "[5/6] Kafka 압축 해제 / 환경 변수 설정"
echo "========================================"


if [[ ! -d "$version_dir" ]]; then

    tar \
        -xzf "$archive_path" \
        -C "$HOME"

else

    echo "기존 Kafka 설치 디렉터리 사용:"
    echo "$version_dir"

fi


[[ -x "$version_dir/bin/kafka-storage.sh" ]] ||
    die "Kafka 설치 경로가 올바르지 않습니다: $version_dir"


if [[ -e "$kafka_home" && ! -L "$kafka_home" ]]; then
    die "$kafka_home 가 일반 디렉터리로 존재합니다. 자동으로 덮어쓰지 않습니다."
fi


ln \
    -sfn \
    "$version_dir" \
    "$kafka_home"


if [[ -f "$env_file" ]] &&
   ! grep -qF "$env_marker" "$env_file"; then

    die "$env_file 는 스크립트가 관리하는 파일이 아닙니다."

fi


temporary_env_file="$(
    mktemp "$HOME/.kafka-env.XXXXXX"
)"


{
    printf '%s\n' "$env_marker"
    printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"
    printf 'export KAFKA_HOME=%q\n' "$kafka_home"
    printf 'export PATH="$JAVA_HOME/bin:$KAFKA_HOME/bin:$PATH"\n'
} > "$temporary_env_file"


mv \
    "$temporary_env_file" \
    "$env_file"


touch "$HOME/.bashrc"


if ! grep -qF 'source ~/.kafka-env' "$HOME/.bashrc"; then

    printf '\nsource ~/.kafka-env\n' >> "$HOME/.bashrc"

fi


echo
echo "========================================"
echo "[6/6] Java / Kafka 실행 검증"
echo "========================================"


source "$env_file"


"$JAVA_HOME/bin/java" -version


echo
echo "KAFKA_HOME=$KAFKA_HOME"


"$KAFKA_HOME/bin/kafka-storage.sh" random-uuid >/dev/null


echo
echo "Kafka 설치 검증 성공"

USER_INSTALL


echo
echo "========================================"
echo "Kafka $kafka_version 준비 완료"
echo "경로: $target_home/kafka"
echo "========================================"
'@

    # PowerShell here-string의 CRLF를 WSL Bash가 해석할 수 있는 LF로 바꿉니다.
    $bashPayload = $bashPayload -replace "`r`n", "`n"

    $bashPayload |
        & wsl.exe `
            --distribution $DistroName `
            --user root `
            --exec bash -s -- $TargetLinuxUser


    if ($LASTEXITCODE -ne 0) {
        throw "WSL 내부 Kafka 설치가 종료 코드 $LASTEXITCODE 로 실패했습니다."
    }
}



# ============================================================
# Main
# ============================================================

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = Get-DefaultLinuxUser
}


Assert-LinuxUser $LinuxUser


if (-not (Test-Administrator)) {

    Write-Host "관리자 권한 PowerShell로 다시 실행합니다..." -ForegroundColor Yellow

    $quotedScript = '"' + $PSCommandPath.Replace('"', '""') + '"'
    $quotedDistro = '"' + $Distribution.Replace('"', '""') + '"'
    $quotedUser = '"' + $LinuxUser.Replace('"', '""') + '"'

    $arguments = (
        "-NoProfile -ExecutionPolicy Bypass " +
        "-File $quotedScript " +
        "-Distribution $quotedDistro " +
        "-LinuxUser $quotedUser"
    )

    if ($ResumeAfterRestart) {
        $arguments += " -ResumeAfterRestart"
    }

    if ($RestartIfRequired) {
        $arguments += " -RestartIfRequired"
    }


    $elevatedProcess = Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -ArgumentList $arguments `
        -Wait `
        -PassThru


    exit $elevatedProcess.ExitCode
}


Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Kafka WSL bootstrap 시작" -ForegroundColor Cyan
Write-Host "Distribution : $Distribution"
Write-Host "Linux user   : $LinuxUser"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""


if (
    -not (
        Ensure-Wsl `
            -DistroName $Distribution `
            -TargetLinuxUser $LinuxUser
    )
) {
    exit 0
}


Invoke-WslKafkaInstall `
    -DistroName $Distribution `
    -TargetLinuxUser $LinuxUser


Remove-Resume


Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "완료" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "WSL $Distribution 의 Linux 사용자 $LinuxUser 에 Kafka 4.3.1을 설치했습니다." -ForegroundColor Green

Write-Host ""
Write-Host "Kafka 경로: ~/$LinuxUser 가 아니라 해당 Linux 사용자의 ~/kafka 입니다."
Write-Host "다음 단계에서 WSL의 ~/kafka 경로를 사용하세요."
