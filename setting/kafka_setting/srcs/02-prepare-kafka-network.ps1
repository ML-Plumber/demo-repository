#Requires -Version 5.1
<#
.SYNOPSIS
    Kafka 노드용 WSL 네트워크 모드와 Windows 방화벽을 준비합니다.

.EXAMPLE
    .\02-prepare-kafka-network.ps1

.EXAMPLE
    .\02-prepare-kafka-network.ps1 --networking-mode nat

.EXAMPLE
    .\02-prepare-kafka-network.ps1 -NetworkingMode nat -PeerIps 192.168.10.11,192.168.10.12
#>
[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    [Alias("networking-mode")]
    [ValidateSet("mirrored", "nat")]
    [string]$NetworkingMode = "mirrored",

    [string]$Distribution = "Ubuntu",

    [ValidateRange(1, 65535)]
    [int[]]$KafkaPorts = @(9092, 9093),

    [string[]]$PeerIps = @("LocalSubnet"),

    [string]$WindowsLanIp,

    [string]$ResultPath = (Join-Path $env:ProgramData "KafkaCluster\network-result.json"),

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$wslVmCreatorId = "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}"
$firewallGroup = "Kafka Cluster WSL"
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$script:InvocationCmdlet = $PSCmdlet

function Resolve-GnuNetworkingMode {
    param(
        [string]$CurrentMode,
        [string[]]$Arguments
    )

    if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
        return $CurrentMode.ToLowerInvariant()
    }

    $resolvedMode = $CurrentMode
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        if ($argument -eq "--networking-mode") {
            if ($index + 1 -ge $Arguments.Count) {
                throw "--networking-mode 뒤에 mirrored 또는 nat 값을 입력해야 합니다."
            }
            $index++
            $resolvedMode = $Arguments[$index]
            continue
        }

        if ($argument -match "^--networking-mode=(.+)$") {
            $resolvedMode = $Matches[1]
            continue
        }

        throw "지원하지 않는 인자입니다: $argument"
    }

    $resolvedMode = $resolvedMode.ToLowerInvariant()
    if ($resolvedMode -notin @("mirrored", "nat")) {
        throw "networking mode는 mirrored 또는 nat만 사용할 수 있습니다: $resolvedMode"
    }
    return $resolvedMode
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-SingleQuotedLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-ElevatedSelf {
    $scriptLiteral = ConvertTo-SingleQuotedLiteral $PSCommandPath
    $modeLiteral = ConvertTo-SingleQuotedLiteral $NetworkingMode
    $distributionLiteral = ConvertTo-SingleQuotedLiteral $Distribution
    $resultLiteral = ConvertTo-SingleQuotedLiteral $ResultPath
    $portLiteral = "@(" + (($KafkaPorts | ForEach-Object { [string]$_ }) -join ",") + ")"
    $peerLiteral = "@(" + (($PeerIps | ForEach-Object { ConvertTo-SingleQuotedLiteral $_ }) -join ",") + ")"

    $command = "& $scriptLiteral -NetworkingMode $modeLiteral -Distribution $distributionLiteral " +
        "-KafkaPorts $portLiteral -PeerIps $peerLiteral -ResultPath $resultLiteral"
    if (-not [string]::IsNullOrWhiteSpace($WindowsLanIp)) {
        $command += " -WindowsLanIp " + (ConvertTo-SingleQuotedLiteral $WindowsLanIp)
    }
    if ($WhatIfPreference) {
        $command += " -WhatIf"
    }

    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    exit $process.ExitCode
}

function Assert-Inputs {
    if ([string]::IsNullOrWhiteSpace($Distribution)) {
        throw "Distribution은 비어 있을 수 없습니다."
    }
    if ($KafkaPorts.Count -eq 0) {
        throw "KafkaPorts에는 한 개 이상의 포트가 필요합니다."
    }
    if (($KafkaPorts | Sort-Object -Unique).Count -ne $KafkaPorts.Count) {
        throw "KafkaPorts에 중복 포트가 있습니다."
    }
    if ($PeerIps.Count -eq 0) {
        throw "PeerIps에는 LocalSubnet, IPv4 또는 IPv4 CIDR이 필요합니다."
    }

    foreach ($peer in $PeerIps) {
        if ($peer -eq "LocalSubnet") {
            continue
        }

        $addressText = $peer
        $prefixLength = $null
        if ($peer.Contains("/")) {
            $parts = $peer.Split("/", 2)
            $addressText = $parts[0]
            $parsedPrefix = 0
            if (-not [int]::TryParse($parts[1], [ref]$parsedPrefix) -or $parsedPrefix -lt 0 -or $parsedPrefix -gt 32) {
                throw "PeerIps의 CIDR prefix가 올바르지 않습니다: $peer"
            }
            $prefixLength = $parsedPrefix
        }

        $parsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($addressText, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "PeerIps에는 IPv4 또는 IPv4 CIDR만 사용할 수 있습니다: $peer"
        }
    }
}

function Test-WslDistribution {
    param([string]$Name)

    $names = @(& wsl.exe --list --quiet 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "WSL 배포판 목록을 읽지 못했습니다. 먼저 01-bootstrap-kafka-node.ps1을 실행하세요."
    }

    return [bool]($names | ForEach-Object { ($_ -replace "`0", "").Trim() } |
        Where-Object { $_ -eq $Name } | Select-Object -First 1)
}

function Assert-MirroredModeSupport {
    $versionInfo = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $buildNumber = [int]$versionInfo.CurrentBuildNumber
    if ($buildNumber -lt 22621) {
        throw "mirrored 모드는 Windows 11 22H2(build 22621) 이상이 필요합니다. 현재 build: $buildNumber"
    }

    if ($null -eq (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue)) {
        throw "Hyper-V 방화벽 cmdlet을 찾지 못했습니다. Windows와 WSL을 업데이트하거나 --networking-mode nat를 사용하세요."
    }
}

function Set-WslNetworkingMode {
    param(
        [string]$ConfigPath,
        [string]$Mode
    )

    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $ConfigPath) {
        foreach ($line in Get-Content -LiteralPath $ConfigPath -Encoding UTF8) {
            $lines.Add($line)
        }
    }

    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s*\[wsl2\]\s*$") {
            $sectionStart = $index
            for ($next = $index + 1; $next -lt $lines.Count; $next++) {
                if ($lines[$next] -match "^\s*\[[^]]+\]\s*$") {
                    $sectionEnd = $next
                    break
                }
            }
            break
        }
    }

    $newSetting = "networkingMode=$Mode"
    $settingIndexes = [Collections.Generic.List[int]]::new()
    if ($sectionStart -ge 0) {
        for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
            if ($lines[$index] -match "^\s*networkingMode\s*=") {
                $settingIndexes.Add($index)
            }
        }
    }

    if ($settingIndexes.Count -eq 1 -and
        $lines[$settingIndexes[0]] -match "^\s*networkingMode\s*=\s*$([regex]::Escape($Mode))\s*$") {
        return $false
    }

    if ($settingIndexes.Count -gt 0) {
        $lines[$settingIndexes[0]] = $newSetting
        for ($index = $settingIndexes.Count - 1; $index -ge 1; $index--) {
            $lines.RemoveAt($settingIndexes[$index])
        }
    } elseif ($sectionStart -ge 0) {
        $lines.Insert($sectionEnd, $newSetting)
    } else {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add("")
        }
        $lines.Add("[wsl2]")
        $lines.Add($newSetting)
    }

    if (($script:InvocationCmdlet).ShouldProcess($ConfigPath, "WSL networkingMode를 $Mode 로 설정")) {
        if ((Test-Path -LiteralPath $ConfigPath) -and -not (Test-Path -LiteralPath "$ConfigPath.kafka-network.bak")) {
            Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.kafka-network.bak"
        }

        $temporaryPath = "$ConfigPath.kafka-network.tmp"
        [IO.File]::WriteAllLines($temporaryPath, $lines, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $ConfigPath -Force
    }
    return $true
}

function Invoke-WslShutdown {
    if (($script:InvocationCmdlet).ShouldProcess("모든 WSL 배포판", "wsl.exe --shutdown")) {
        & wsl.exe --shutdown
        if ($LASTEXITCODE -ne 0) {
            throw "WSL 종료가 실패했습니다. 종료 코드: $LASTEXITCODE"
        }
    }
}

function Get-WslNetworkingMode {
    param([string]$DistroName)

    $output = @(& wsl.exe --distribution $DistroName --exec sh -lc `
        "command -v wslinfo >/dev/null 2>&1 && wslinfo --networking-mode" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "WSL 네트워크 모드를 확인하지 못했습니다. Windows 관리자 PowerShell에서 wsl --update를 실행한 뒤 다시 시도하세요."
    }

    $mode = (($output -join "`n").Trim()).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($mode)) {
        throw "wslinfo가 빈 네트워크 모드를 반환했습니다."
    }
    return $mode
}

function Get-WindowsLanIpv4 {
    param([string]$RequestedAddress)

    if (-not [string]::IsNullOrWhiteSpace($RequestedAddress)) {
        $parsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($RequestedAddress, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "WindowsLanIp는 IPv4여야 합니다: $RequestedAddress"
        }
        if ($null -eq (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $RequestedAddress -ErrorAction SilentlyContinue)) {
            throw "WindowsLanIp가 현재 Windows 인터페이스에 존재하지 않습니다: $RequestedAddress"
        }
        return $RequestedAddress
    }

    $configuration = Get-NetIPConfiguration |
        Where-Object { $null -ne $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
        Sort-Object { $_.NetIPv4Interface.InterfaceMetric } |
        Select-Object -First 1
    if ($null -eq $configuration) {
        throw "기본 IPv4 gateway가 있는 활성 Windows 네트워크 인터페이스를 찾지 못했습니다. -WindowsLanIp를 지정하세요."
    }

    $address = @($configuration.IPv4Address |
        Where-Object { $_.IPAddress -notmatch "^(127\.|169\.254\.)" } |
        Select-Object -ExpandProperty IPAddress -First 1)
    if ($address.Count -ne 1) {
        throw "Windows LAN IPv4를 하나로 결정하지 못했습니다. -WindowsLanIp를 지정하세요."
    }
    return $address[0]
}

function Get-WslIpv4 {
    param([string]$DistroName)

    $routeCommand = "ip -4 route get 1.1.1.1 | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n 1"
    $output = @(& wsl.exe --distribution $DistroName --exec sh -lc $routeCommand 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "$DistroName 배포판의 기본 경로 IPv4를 확인하지 못했습니다."
    }

    foreach ($candidate in (($output -join " ") -split "\s+")) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $parsedAddress = $null
        if ([Net.IPAddress]::TryParse($candidate, [ref]$parsedAddress) -and
            $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
            $candidate -notmatch "^(127\.|169\.254\.)") {
            return $candidate
        }
    }
    throw "$DistroName 배포판의 기본 경로에서 사용할 IPv4를 찾지 못했습니다."
}

function ConvertTo-Ipv4Cidr {
    param(
        [string]$IpAddress,
        [ValidateRange(0, 32)][int]$PrefixLength
    )

    $bytes = [Net.IPAddress]::Parse($IpAddress).GetAddressBytes()
    [uint32]$addressValue = ([uint32]$bytes[0] -shl 24) -bor
        ([uint32]$bytes[1] -shl 16) -bor
        ([uint32]$bytes[2] -shl 8) -bor
        [uint32]$bytes[3]
    [uint32]$mask = if ($PrefixLength -eq 0) {
        0
    } else {
        [uint64]$hostBits = [uint64]([Math]::Pow(2, 32 - $PrefixLength) - 1)
        [uint32]([uint64]4294967295 - $hostBits)
    }
    [uint32]$networkValue = $addressValue -band $mask

    $networkAddress = "{0}.{1}.{2}.{3}" -f
        (($networkValue -shr 24) -band 0xFF),
        (($networkValue -shr 16) -band 0xFF),
        (($networkValue -shr 8) -band 0xFF),
        ($networkValue -band 0xFF)
    return "$networkAddress/$PrefixLength"
}

function Resolve-PeerAddresses {
    param(
        [string[]]$Addresses,
        [string]$LanIp
    )

    $resolved = [Collections.Generic.List[string]]::new()
    foreach ($address in $Addresses) {
        if ($address -ne "LocalSubnet") {
            $resolved.Add($address)
            continue
        }

        $lanAddress = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $LanIp -ErrorAction Stop |
            Select-Object -First 1
        $resolved.Add((ConvertTo-Ipv4Cidr -IpAddress $LanIp -PrefixLength $lanAddress.PrefixLength))
    }
    return @($resolved | Sort-Object -Unique)
}

function Ensure-IpHelper {
    $service = Get-Service -Name "iphlpsvc" -ErrorAction Stop
    if ($service.StartType -eq "Disabled" -and ($script:InvocationCmdlet).ShouldProcess("iphlpsvc", "시작 유형을 Automatic으로 변경")) {
        Set-Service -Name "iphlpsvc" -StartupType Automatic
    }
    if ($service.Status -ne "Running" -and ($script:InvocationCmdlet).ShouldProcess("iphlpsvc", "서비스 시작")) {
        Start-Service -Name "iphlpsvc"
    }
}

function Ensure-NatPortProxy {
    param(
        [string]$ListenAddress,
        [int]$ListenPort,
        [string]$ConnectAddress,
        [int]$ConnectPort
    )

    $target = "$ListenAddress`:$ListenPort -> $ConnectAddress`:$ConnectPort"
    if (($script:InvocationCmdlet).ShouldProcess($target, "Kafka NAT portproxy 생성 또는 갱신")) {
        & netsh.exe interface portproxy delete v4tov4 `
            listenaddress=$ListenAddress listenport=$ListenPort 2>$null | Out-Null

        & netsh.exe interface portproxy add v4tov4 `
            listenaddress=$ListenAddress listenport=$ListenPort `
            connectaddress=$ConnectAddress connectport=$ConnectPort | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "NAT portproxy 설정에 실패했습니다: $target"
        }
    }
}

function Ensure-WindowsFirewallRule {
    param(
        [int]$Port,
        [string]$LocalAddress,
        [string[]]$RemoteAddresses
    )

    $ruleName = "KafkaCluster-WSL-TCP-$Port"
    $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($null -ne $existingRule -and ($script:InvocationCmdlet).ShouldProcess($ruleName, "기존 관리 규칙 갱신을 위한 제거")) {
        Remove-NetFirewallRule -Name $ruleName
    }

    if (($script:InvocationCmdlet).ShouldProcess($ruleName, "Windows Kafka 인바운드 규칙 생성")) {
        New-NetFirewallRule -Name $ruleName -DisplayName $ruleName -Group $firewallGroup `
            -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP `
            -LocalAddress $LocalAddress -LocalPort $Port -RemoteAddress $RemoteAddresses | Out-Null
    }
}

function Ensure-HyperVFirewallRule {
    param(
        [int]$Port,
        [string[]]$RemoteAddresses
    )

    $ruleName = "KafkaCluster-WSL-HyperV-TCP-$Port"
    $existingRule = Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($null -ne $existingRule -and ($script:InvocationCmdlet).ShouldProcess($ruleName, "기존 Hyper-V 관리 규칙 갱신을 위한 제거")) {
        Remove-NetFirewallHyperVRule -Name $ruleName
    }

    if (($script:InvocationCmdlet).ShouldProcess($ruleName, "WSL Hyper-V Kafka 인바운드 규칙 생성")) {
        New-NetFirewallHyperVRule -Name $ruleName -DisplayName $ruleName -Direction Inbound `
            -VMCreatorId $wslVmCreatorId -Protocol TCP -LocalPorts $Port `
            -RemoteAddresses $RemoteAddresses -Action Allow | Out-Null
    }
}

function Write-NetworkResult {
    param(
        [string]$Path,
        [string]$Mode,
        [string]$ReportedMode,
        [string]$LanIp,
        [AllowNull()][string]$LinuxIp,
        [string[]]$ResolvedRemoteAddresses
    )

    $parentPath = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        throw "ResultPath에는 상위 디렉터리가 포함되어야 합니다: $Path"
    }

    $mappings = @()
    if ($Mode -eq "nat") {
        $mappings = @($KafkaPorts | ForEach-Object {
            [ordered]@{
                listen_address  = $LanIp
                listen_port     = $_
                connect_address = $LinuxIp
                connect_port    = $_
            }
        })
    }

    $result = [ordered]@{
        schema_version       = 1
        managed_by           = "02-prepare-kafka-network.ps1"
        generated_at         = [DateTimeOffset]::Now.ToString("o")
        distribution         = $Distribution
        requested_mode       = $Mode
        reported_mode        = $ReportedMode
        windows_lan_ip       = $LanIp
        wsl_ip               = $LinuxIp
        kafka_ports          = @($KafkaPorts)
        requested_remote_ips = @($PeerIps)
        allowed_remote_ips   = @($ResolvedRemoteAddresses)
        nat_port_mappings    = $mappings
        wsl_config_path      = $wslConfigPath
    }

    if (($script:InvocationCmdlet).ShouldProcess($Path, "네트워크 준비 결과 JSON 저장")) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        $temporaryPath = "$Path.tmp"
        [IO.File]::WriteAllText(
            $temporaryPath,
            ($result | ConvertTo-Json -Depth 5),
            [Text.UTF8Encoding]::new($false)
        )
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
}

$NetworkingMode = Resolve-GnuNetworkingMode -CurrentMode $NetworkingMode -Arguments $CliArguments
Assert-Inputs

if (-not (Test-Administrator)) {
    Invoke-ElevatedSelf
}

if (-not (Test-WslDistribution -Name $Distribution)) {
    throw "$Distribution WSL 배포판이 없습니다. 먼저 01-bootstrap-kafka-node.ps1을 실행하세요."
}

if ($NetworkingMode -eq "mirrored") {
    Assert-MirroredModeSupport
}

$currentMode = Get-WslNetworkingMode -DistroName $Distribution
$configChanged = Set-WslNetworkingMode -ConfigPath $wslConfigPath -Mode $NetworkingMode
if ($configChanged -or $currentMode -ne $NetworkingMode) {
    Invoke-WslShutdown
}

$reportedMode = "whatif"
if (-not $WhatIfPreference) {
    $reportedMode = Get-WslNetworkingMode -DistroName $Distribution
    if ($reportedMode -ne $NetworkingMode) {
        throw "요청한 WSL 모드와 실제 모드가 다릅니다. 요청=$NetworkingMode, 실제=$reportedMode"
    }
}

$resolvedWindowsLanIp = Get-WindowsLanIpv4 -RequestedAddress $WindowsLanIp
$resolvedPeerIps = Resolve-PeerAddresses -Addresses $PeerIps -LanIp $resolvedWindowsLanIp
$resolvedWslIp = $null

foreach ($port in $KafkaPorts) {
    Ensure-WindowsFirewallRule -Port $port -LocalAddress $resolvedWindowsLanIp -RemoteAddresses $resolvedPeerIps
}

if ($NetworkingMode -eq "mirrored") {
    foreach ($port in $KafkaPorts) {
        Ensure-HyperVFirewallRule -Port $port -RemoteAddresses $resolvedPeerIps
    }
} else {
    Ensure-IpHelper
    $resolvedWslIp = Get-WslIpv4 -DistroName $Distribution
    foreach ($port in $KafkaPorts) {
        Ensure-NatPortProxy -ListenAddress $resolvedWindowsLanIp -ListenPort $port `
            -ConnectAddress $resolvedWslIp -ConnectPort $port
    }
}

Write-NetworkResult -Path $ResultPath -Mode $NetworkingMode -ReportedMode $reportedMode `
    -LanIp $resolvedWindowsLanIp -LinuxIp $resolvedWslIp -ResolvedRemoteAddresses $resolvedPeerIps

if ($WhatIfPreference) {
    Write-Host "WhatIf 완료: 실제 네트워크 설정은 변경하지 않았습니다." -ForegroundColor Yellow
    exit 0
}

Write-Host "완료: WSL 네트워크 모드=$reportedMode, Windows LAN IP=$resolvedWindowsLanIp" -ForegroundColor Green
if ($NetworkingMode -eq "nat") {
    Write-Host "NAT 전달 대상 WSL IP=$resolvedWslIp"
}
Write-Host "Kafka 허용 포트=$($KafkaPorts -join ', '), 원격 범위=$($resolvedPeerIps -join ', ')"
Write-Host "결과 파일=$ResultPath"
