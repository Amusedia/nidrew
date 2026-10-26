<#
.SYNOPSIS
Set up the Nidrew Debian server from Windows: prerequisites, the Debian setup,
the keepalive task, and the readiness checks.

.DESCRIPTION
Runs as the invoking Windows user; Windows administrator rights are not
required. Steps, stopping at the first failure:
  1. scripts\host\check-prerequisites.ps1
  2. scripts/server/setup-server.sh in the distribution as Linux root, through
     wsl.exe --user root. The Windows user who owns the distribution can do
     this without a Linux password; the command is printed before it runs.
  3. scripts\host\keepalive-task.ps1 -Action Register, then -Action Start
  4. scripts\host\check-server.ps1
Every step keeps matching state, so rerun after resolving a failure or an
interruption. Only committed changes in the source repository reach the
server checkout.

Exit status: 0 when the server is set up and ready, 1 otherwise.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\setup-server.ps1
#>
[CmdletBinding()]
param(
    # WSL distribution that hosts the Nidrew server.
    [string]$Distribution = 'Debian',
    # Source Git repository as seen from Linux.
    [string]$Source = '/mnt/c/projects/nidrew',
    # Committed revision the server checkout will use.
    [string]$Revision = 'HEAD',
    # Cache port.
    [ValidateRange(1, 65535)]
    [int]$Port = 5000,
    # Name for a newly generated signing key; an existing key is always kept.
    [string]$KeyName = ''
)

# wsl.exe writes UTF-16 for its own messages unless WSL_UTF8 is set.
$env:WSL_UTF8 = '1'

function Stop-Setup([string]$Step) {
    Write-Output ''
    Write-Output "Setup stopped at: $Step. Resolve the message above and rerun this script; completed steps are kept."
    exit 1
}

# Runs a sibling host script; its output passes through and the caller checks
# $LASTEXITCODE.
function Invoke-HostScript([string]$Name, [string[]]$Arguments) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Name) @Arguments
}

Write-Output '== Prerequisites'
Invoke-HostScript 'check-prerequisites.ps1' @('-Distribution', $Distribution, '-Source', $Source, '-Revision', $Revision)
if ($LASTEXITCODE -ne 0) { Stop-Setup 'prerequisites' }

$linuxArgs = @('--source', $Source, '--revision', $Revision, '--port', "$Port")
if ($KeyName) { $linuxArgs += @('--key-name', $KeyName) }
$setupScript = "$Source/scripts/server/setup-server.sh"
Write-Output ''
Write-Output '== Debian server setup, as Linux root'
Write-Output "wsl.exe --distribution $Distribution --user root --exec bash $setupScript $($linuxArgs -join ' ')"
& wsl.exe --distribution $Distribution --user root --exec bash $setupScript @linuxArgs
if ($LASTEXITCODE -ne 0) { Stop-Setup 'Debian server setup' }

Write-Output ''
Write-Output '== Keepalive task'
Invoke-HostScript 'keepalive-task.ps1' @('-Action', 'Register', '-Distribution', $Distribution)
if ($LASTEXITCODE -ne 0) { Stop-Setup 'keepalive task registration' }
Invoke-HostScript 'keepalive-task.ps1' @('-Action', 'Start', '-Distribution', $Distribution)
if ($LASTEXITCODE -ne 0) { Stop-Setup 'keepalive task start' }

Write-Output ''
Invoke-HostScript 'check-server.ps1' @('-Distribution', $Distribution, '-Port', "$Port")
if ($LASTEXITCODE -ne 0) { Stop-Setup 'readiness checks' }
exit 0
