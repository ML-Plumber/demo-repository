#Requires -Version 5.1
<#
.SYNOPSIS
    빈 Windows에서 WSL Ubuntu와 Kafka 4.3.1 실행 환경을 준비합니다.

.EXAMPLE
    .\00-bootstrap-kafka-node.ps1 -RestartIfRequired
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
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultLinuxUser {
    $name = ($env:USERNAME.ToLowerInvariant() -replace "[^a-z0-9_-]", "")
    if ([string]::IsNullOrWhiteSpace($name)) { return "kafka" }
    return $name
}

function Assert-LinuxUser {
    param([string]$Name)

    if ($Name -notmatch "^[a-z_][a-z0-9_-]{0,31}$") {
        throw "LinuxUser는 영문 소문자, 숫자, _, -만 사용하며 숫자로 시작할 수 없습니다: $Name"
    }
}

function Test-WslDistribution {
    param([string]$Name)

    $names = @(& wsl.exe --list --quiet 2>$null)
    return $names | Where-Object { $_.Trim() -eq $Name } | Select-Object -First 1
}

function Test-WslReady {
    param(
        [string]$Name,
        [int]$RetryCount = 12,
        [int]$RetryDelaySeconds = 5
    )

    # 배포판 목록에 보여도 재시작 전에는 실제 Linux 명령 실행이 실패할 수 있습니다.
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        & wsl.exe --distribution $Name --user root -- /bin/sh -c "exit 0" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        if ($attempt -lt $RetryCount) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    return $false
}

function Register-Resume {
    param([string]$ScriptPath, [string]$DistroName, [string]$TargetLinuxUser)

    $quotedScript = '"' + $ScriptPath.Replace('"', '""') + '"'
    $quotedDistro = '"' + $DistroName.Replace('"', '""') + '"'
    $quotedUser = '"' + $TargetLinuxUser.Replace('"', '""') + '"'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript -Distribution $quotedDistro -LinuxUser $quotedUser -ResumeAfterRestart"

    # RunOnce는 재개 시 다시 UAC 승인을 요구할 수 있으므로, 로그인 때 관리자 권한으로
    # 한 번만 실행되는 작업을 등록합니다.
    $accountName = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory (Split-Path -Parent $ScriptPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $accountName
    $principal = New-ScheduledTaskPrincipal -UserId $accountName -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $resumeTaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
}

function Remove-Resume {
    Unregister-ScheduledTask -TaskName $resumeTaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Request-WslRestart {
    param([string]$DistroName, [string]$TargetLinuxUser)

    Register-Resume -ScriptPath $PSCommandPath -DistroName $DistroName -TargetLinuxUser $TargetLinuxUser
    if ($RestartIfRequired) {
        Write-Host "WSL 설치 완료를 위해 Windows를 다시 시작합니다. 로그인하면 Kafka 설치를 자동 재개합니다." -ForegroundColor Yellow
        Restart-Computer -Force
    }

    Write-Warning "WSL이 아직 실행 준비 상태가 아닙니다. Windows를 재시작하고 같은 계정으로 로그인하면 Kafka 설치가 자동 재개됩니다. 즉시 재시작하려면 -RestartIfRequired 옵션으로 실행하세요."
}

function Ensure-Wsl {
    param([string]$DistroName, [string]$TargetLinuxUser)

    if (Test-WslDistribution $DistroName) {
        if (Test-WslReady $DistroName) { return $true }

        Request-WslRestart -DistroName $DistroName -TargetLinuxUser $TargetLinuxUser
        return $false
    }

    Write-Host "WSL과 $DistroName 설치를 시작합니다..." -ForegroundColor Cyan
    # wsl --install이 재시작을 요구하는 경우를 대비해 설치 전에 재개 작업을 만듭니다.
    Register-Resume -ScriptPath $PSCommandPath -DistroName $DistroName -TargetLinuxUser $TargetLinuxUser
    & wsl.exe --install --distribution $DistroName
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        Remove-Resume
        throw "WSL 설치가 종료 코드 $exitCode 로 실패했습니다."
    }

    # 목록 표시가 아닌 실제 root 명령 성공을 기준으로 다음 단계 진행 여부를 판단합니다.
    if ((Test-WslDistribution $DistroName) -and (Test-WslReady $DistroName)) {
        Remove-Resume
        return $true
    }

    Request-WslRestart -DistroName $DistroName -TargetLinuxUser $TargetLinuxUser
    return $false
}

function Invoke-WslKafkaInstall {
    param([string]$DistroName, [string]$TargetLinuxUser)

    # root는 패키지를 설치하고, Kafka 파일은 일반 Linux 사용자의 홈에 만듭니다.
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

if ! id -u "$target_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$target_user"
fi

target_home="$(getent passwd "$target_user" | cut -d: -f6)"
[[ -d "$target_home" ]] || die "Linux 사용자 홈을 찾지 못했습니다: $target_user"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl openjdk-17-jdk

java_bin="$(update-alternatives --list java 2>/dev/null | grep -E '/java-17-[^/]*/bin/java$' | head -n 1 || true)"
[[ -n "$java_bin" ]] || die "JDK 17 실행 파일을 찾지 못했습니다."
java_bin="$(readlink -f "$java_bin")"
java_home="${java_bin%/bin/java}"
"$java_home/bin/java" -version

# 새 배포판에서만 WSL 기본 사용자를 설정합니다.
if [[ ! -f /etc/wsl.conf ]]; then
  printf '[user]\ndefault=%s\n' "$target_user" > /etc/wsl.conf
fi

runuser -u "$target_user" -- env HOME="$target_home" JAVA_HOME="$java_home" \
  KAFKA_VERSION="$kafka_version" KAFKA_SCALA_VERSION="$kafka_scala_version" \
  KAFKA_ARCHIVE="$kafka_archive" KAFKA_URL="$kafka_url" bash -s <<'USER_INSTALL'
set -Eeuo pipefail

package_dir="$HOME/packages"
version_dir="$HOME/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}"
kafka_home="$HOME/kafka"
env_file="$HOME/.kafka-env"
env_marker="# Managed by 00-bootstrap-kafka-node.ps1"
archive_path="$package_dir/$KAFKA_ARCHIVE"
checksum_path="$archive_path.sha512"

die() {
  echo "오류: $*" >&2
  exit 1
}

mkdir -p "$package_dir"
if [[ ! -f "$archive_path" ]]; then
  curl -fL "$KAFKA_URL" -o "${archive_path}.part"
  mv "${archive_path}.part" "$archive_path"
fi

curl -fL "${KAFKA_URL}.sha512" -o "${checksum_path}.part"
mv "${checksum_path}.part" "$checksum_path"

# 체크섬이 다르면 압축 해제·환경 파일 변경을 하지 않습니다.
expected_sha512="$(grep -Eo '[A-Fa-f0-9]{8}' "$checksum_path" | tr -d '\n')"
actual_sha512="$(sha512sum "$archive_path" | awk '{ print toupper($1) }')"
[[ ${#expected_sha512} -eq 128 ]] || die "공식 SHA-512 파일 형식이 올바르지 않습니다."
[[ "$actual_sha512" == "$expected_sha512" ]] || die "$KAFKA_ARCHIVE SHA-512 검증에 실패했습니다."

if [[ ! -d "$version_dir" ]]; then
  tar -xzf "$archive_path" -C "$HOME"
fi
[[ -x "$version_dir/bin/kafka-storage.sh" ]] || die "Kafka 설치 경로가 올바르지 않습니다: $version_dir"

if [[ -e "$kafka_home" && ! -L "$kafka_home" ]]; then
  die "$kafka_home 가 일반 디렉터리로 존재합니다. 자동으로 덮어쓰지 않습니다."
fi
ln -sfn "$version_dir" "$kafka_home"

if [[ -f "$env_file" ]] && ! grep -qF "$env_marker" "$env_file"; then
  die "$env_file 는 스크립트가 관리하는 파일이 아닙니다."
fi

temporary_env_file="$(mktemp "$HOME/.kafka-env.XXXXXX")"
{
  printf '%s\n' "$env_marker"
  printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"
  printf 'export KAFKA_HOME=%q\n' "$kafka_home"
  printf 'export PATH="\$JAVA_HOME/bin:\$KAFKA_HOME/bin:\$PATH"\n'
} > "$temporary_env_file"
mv "$temporary_env_file" "$env_file"

touch "$HOME/.bashrc"
if ! grep -qF 'source ~/.kafka-env' "$HOME/.bashrc"; then
  printf '\nsource ~/.kafka-env\n' >> "$HOME/.bashrc"
fi

source "$env_file"
"$JAVA_HOME/bin/java" -version
echo "KAFKA_HOME=$KAFKA_HOME"
"$KAFKA_HOME/bin/kafka-storage.sh" random-uuid >/dev/null
USER_INSTALL

echo "Kafka $kafka_version 준비 완료: $target_home/kafka"
'@

    $bashPayload | & wsl.exe --distribution $DistroName --user root -- bash -s -- $TargetLinuxUser
    if ($LASTEXITCODE -ne 0) {
        throw "WSL 내부 Kafka 설치가 종료 코드 $LASTEXITCODE 로 실패했습니다."
    }
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = Get-DefaultLinuxUser
}
Assert-LinuxUser $LinuxUser

if (-not (Test-Administrator)) {
    $quotedScript = '"' + $PSCommandPath.Replace('"', '""') + '"'
    $quotedDistro = '"' + $Distribution.Replace('"', '""') + '"'
    $quotedUser = '"' + $LinuxUser.Replace('"', '""') + '"'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript -Distribution $quotedDistro -LinuxUser $quotedUser"
    if ($ResumeAfterRestart) { $arguments += " -ResumeAfterRestart" }
    if ($RestartIfRequired) { $arguments += " -RestartIfRequired" }
    $elevatedProcess = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $elevatedProcess.ExitCode
}

if (-not (Ensure-Wsl -DistroName $Distribution -TargetLinuxUser $LinuxUser)) {
    exit 0
}

Invoke-WslKafkaInstall -DistroName $Distribution -TargetLinuxUser $LinuxUser
Remove-Resume

Write-Host "완료: WSL $Distribution 의 Linux 사용자 $LinuxUser 에 Kafka 4.3.1을 설치했습니다." -ForegroundColor Green
Write-Host "다음 단계에서 WSL의 ~/kafka 경로를 사용하세요."
