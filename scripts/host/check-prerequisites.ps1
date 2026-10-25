<#
.SYNOPSIS
Check Windows and WSL prerequisites for Nidrew server setup, then run the
Debian checks in scripts/server/check-prerequisites.sh.

.DESCRIPTION
Runs as the invoking Windows user and changes nothing. Administrator rights are
not required. The Debian checks run as the distribution's default user.

Exit status: 0 when required prerequisites are met, 1 otherwise.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\check-prerequisites.ps1 -Distribution Debian
#>
[CmdletBinding()]
param(
    # WSL distribution that hosts the Nidrew server.
    [string]$Distribution = 'Debian',
    # Source Git repository as seen from Linux.
    [string]$Source = '/mnt/c/projects/nidrew',
    # Committed revision the server clone will use.
    [string]$Revision = 'HEAD',
    # Minimum WSL version; the tested version. wslc requires 2.9 or later.
    [version]$MinimumWslVersion = '3.0.3'
)

$script:failures = 0
$script:actions = @()

function Report([string]$Status, [string]$Label, [string]$Detail) {
    Write-Output ('[{0}] {1}: {2}' -f $Status, $Label, $Detail)
}
function Fail([string]$Label, [string]$Detail) {
    Report 'FAIL' $Label $Detail
    $script:failures++
}

# wsl.exe writes UTF-16 for its own messages unless WSL_UTF8 is set.
$env:WSL_UTF8 = '1'

Report ' ok ' 'windows' ([Environment]::OSVersion.Version.ToString())
Report ' ok ' 'powershell' $PSVersionTable.PSVersion.ToString()

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
Report ' ok ' 'windows user' ('{0} (elevated: {1}; not required)' -f $identity.Name, $elevated)

$wslReady = $false
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail 'wsl' 'wsl.exe not found'
    $script:actions += 'Install WSL from an administrator PowerShell: wsl.exe --install --distribution Debian'
} else {
    # wslc (WSL containers) needs WSL 2.9 or later; Nidrew is tested with 3.0.3.
    $version = & wsl.exe --version 2>&1
    $parsed = $null
    if ($LASTEXITCODE -eq 0 -and
        [version]::TryParse((($version | Select-Object -First 1) -replace '^\D*', '').Trim(), [ref]$parsed)) {
        if ($parsed -ge $MinimumWslVersion) {
            Report ' ok ' 'wsl' $parsed.ToString()
        } else {
            Fail 'wsl' ('{0} is older than the tested {1}' -f $parsed, $MinimumWslVersion)
            $script:actions += "Update WSL to $MinimumWslVersion or later: wsl.exe --update"
        }
    } else {
        Fail 'wsl' 'wsl.exe --version did not report a version; this may be the inbox WSL'
        $script:actions += "Update WSL to $MinimumWslVersion or later: wsl.exe --update"
    }

    $list = & wsl.exe --list --verbose 2>&1
    $entry = $list | ForEach-Object { ($_ -replace '^\*', '').Trim() } |
        Where-Object { ($_ -split '\s+')[0] -eq $Distribution } | Select-Object -First 1
    if (-not $entry) {
        $names = ($list | Select-Object -Skip 1 | ForEach-Object { (($_ -replace '^\*', '').Trim() -split '\s+')[0] }) -join ', '
        Fail 'distribution' ('{0} is not installed (installed: {1})' -f $Distribution, $names)
        $script:actions += "Install it with 'wsl.exe --install --distribution $Distribution' or pass -Distribution."
    } else {
        $fields = $entry -split '\s+'
        if ($fields[2] -ne '2') {
            Fail 'distribution' ('{0} uses WSL {1}; WSL 2 is required' -f $Distribution, $fields[2])
            $script:actions += "Convert it: wsl.exe --set-version $Distribution 2"
        } else {
            Report ' ok ' 'distribution' ('{0}, WSL 2, {1}' -f $Distribution, $fields[1])
            $wslReady = $true
        }
    }
}

# The keepalive task (checklist item 7) is registered under this user.
try {
    Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Out-Null
    Report ' ok ' 'task scheduler' 'current user can query scheduled tasks'
} catch {
    Report 'warn' 'task scheduler' ('cannot query scheduled tasks as {0}: {1}' -f $identity.Name, $_.Exception.Message)
    $script:actions += 'Check that this Windows user may use Task Scheduler; the keepalive task needs it.'
}

if ($script:actions.Count -gt 0) {
    Write-Output ''
    Write-Output 'Windows manual actions:'
    $script:actions | ForEach-Object { Write-Output "  - $_" }
}

$serverStatus = 1
if ($wslReady) {
    $hostScript = Join-Path $PSScriptRoot '..\server\check-prerequisites.sh'
    $linuxScript = & wsl.exe --distribution $Distribution --exec wslpath -a -u ((Resolve-Path $hostScript).Path)
    if ($LASTEXITCODE -ne 0) {
        Fail 'debian checks' "could not translate the script path in ${Distribution}: $linuxScript"
    } else {
        Write-Output ''
        Write-Output "Debian checks ($Distribution, default user):"
        & wsl.exe --distribution $Distribution --exec bash $linuxScript --source $Source --revision $Revision
        $serverStatus = $LASTEXITCODE
    }
} else {
    Report 'skip' 'debian checks' 'WSL distribution is not available'
}

Write-Output ''
if ($script:failures -gt 0 -or $serverStatus -ne 0) {
    Write-Output 'Overall: required prerequisites are missing; see the actions above.'
    exit 1
}
Write-Output 'Overall: required prerequisites are met.'
