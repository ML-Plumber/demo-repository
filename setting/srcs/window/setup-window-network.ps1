[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ClusterIPs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

trap {
    [Console]::Error.WriteLine("설정 실패: {0}", $_.Exception.Message)
    exit 1
}

function Set-WslMirroredMode {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path | ForEach-Object { [void]$lines.Add($_) }
    }

    $sectionStart = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ieq '[wsl2]') {
            $sectionStart = $index
            break
        }
    }

    if ($sectionStart -eq -1) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') {
            [void]$lines.Add('')
        }
        [void]$lines.Add('[wsl2]')
        [void]$lines.Add('networkingMode=mirrored')
    }
    else {
        $sectionEnd = $lines.Count
        for ($index = $sectionStart + 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^\s*\[[^]]+\]\s*$') {
                $sectionEnd = $index
                break
            }
        }

        $settingIndex = -1
        for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
            if ($lines[$index] -match '^\s*networkingMode\s*=') {
                $settingIndex = $index
                break
            }
        }

        if ($settingIndex -eq -1) {
            $lines.Insert($sectionEnd, 'networkingMode=mirrored')
        }
        else {
            $lines[$settingIndex] = 'networkingMode=mirrored'
        }
    }

    [System.IO.File]::WriteAllLines(
        $Path,
        $lines,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Set-WindowsFirewallAllowRule {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Protocol,

        [Parameter(Mandatory)]
        [string[]]$RemoteAddresses,

        [string[]]$LocalPorts
    )

    $ruleParameters = @{
        Name          = $Name
        Direction     = 'Inbound'
        Action        = 'Allow'
        Enabled       = 'True'
        Profile       = 'Any'
        Protocol      = $Protocol
        RemoteAddress = $RemoteAddresses
    }
    if ($LocalPorts) {
        $ruleParameters.LocalPort = $LocalPorts
    }

    if (Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue) {
        Set-NetFirewallRule @ruleParameters -NewDisplayName $DisplayName | Out-Null
    }
    else {
        New-NetFirewallRule @ruleParameters -DisplayName $DisplayName | Out-Null
    }
}

function Set-HyperVFirewallAllowRule {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$VMCreatorId,

        [Parameter(Mandatory)]
        [string]$Protocol,

        [Parameter(Mandatory)]
        [string[]]$RemoteAddresses,

        [string[]]$LocalPorts
    )

    $ruleParameters = @{
        Name            = $Name
        Direction       = 'Inbound'
        Action          = 'Allow'
        Enabled         = 'True'
        Profiles        = 'Any'
        VMCreatorId     = $VMCreatorId
        Protocol        = $Protocol
        RemoteAddresses = $RemoteAddresses
    }
    if ($LocalPorts) {
        $ruleParameters.LocalPorts = $LocalPorts
    }

    if (Get-NetFirewallHyperVRule -Name $Name -ErrorAction SilentlyContinue) {
        Set-NetFirewallHyperVRule @ruleParameters -NewDisplayName $DisplayName | Out-Null
    }
    else {
        New-NetFirewallHyperVRule @ruleParameters -DisplayName $DisplayName | Out-Null
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '관리자 권한 PowerShell에서 실행해야 합니다.'
}

foreach ($clusterIp in $ClusterIPs) {
    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($clusterIp, [ref]$parsedIp)) {
        throw "올바르지 않은 클러스터 IP입니다: $clusterIp"
    }
}

$wslCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'

Set-WslMirroredMode -Path $wslConfigPath

Set-WindowsFirewallAllowRule `
    -Name 'WSL-SSH-22' `
    -DisplayName 'WSL SSH 22' `
    -Protocol 'TCP' `
    -LocalPorts '22' `
    -RemoteAddresses 'Any'

Set-HyperVFirewallAllowRule `
    -Name 'WSL-SSH-22' `
    -DisplayName 'WSL SSH 22' `
    -VMCreatorId $wslCreatorId `
    -Protocol 'TCP' `
    -LocalPorts '22' `
    -RemoteAddresses 'Any'

Set-WindowsFirewallAllowRule `
    -Name 'MLOps-Cluster-Internal' `
    -DisplayName 'MLOps Cluster Internal' `
    -Protocol 'Any' `
    -RemoteAddresses $ClusterIPs

Set-HyperVFirewallAllowRule `
    -Name 'WSL-MLOps-Cluster-Internal' `
    -DisplayName 'WSL MLOps Cluster Internal' `
    -VMCreatorId $wslCreatorId `
    -Protocol 'Any' `
    -RemoteAddresses $ClusterIPs

wsl.exe --shutdown
