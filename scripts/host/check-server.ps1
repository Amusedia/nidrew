<#
.SYNOPSIS
Check Nidrew server readiness from Windows: the Debian checks, the keepalive
task, and the cache endpoint as seen from this host.

.DESCRIPTION
Runs as the invoking Windows user; Windows administrator rights are not
required. Runs every check even after a failure:
  1. scripts/server/check-server.sh from the server checkout, as Linux root
     through wsl.exe --user root (printed before it runs)
  2. scripts\host\keepalive-task.ps1 -Action Status
  3. scripts\host\get-cache-endpoint.ps1, which prints the endpoint and
     public key for deployment configuration
The checks never print the signing key.

Exit status: 0 when every check passed, 1 otherwise.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\check-server.ps1
#>
[CmdletBinding()]
param(
    # WSL distribution that hosts the Nidrew server.
    [string]$Distribution = 'Debian',
    # Cache port.
    [ValidateRange(1, 65535)]
    [int]$Port = 5000,
    # Server checkout as seen from Linux.
    [string]$Checkout = '/home/nidrew/nidrew'
)

# wsl.exe writes UTF-16 for its own messages unless WSL_UTF8 is set.
$env:WSL_UTF8 = '1'
$summary = @()

function Add-Result([string]$Label, [bool]$Passed) {
    $status = if ($Passed) { '[ ok ]' } else { '[FAIL]' }
    $script:summary += "$status $Label"
}

$checkScript = "$Checkout/scripts/server/check-server.sh"
Write-Output '== Debian server checks, as Linux root'
Write-Output "wsl.exe --distribution $Distribution --user root --exec bash $checkScript --port $Port"
& wsl.exe --distribution $Distribution --user root --exec bash $checkScript --port $Port
Add-Result 'debian server checks' ($LASTEXITCODE -eq 0)

Write-Output ''
Write-Output '== Keepalive task'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'keepalive-task.ps1') -Action Status -Distribution $Distribution
Add-Result 'keepalive task' ($LASTEXITCODE -eq 0)

Write-Output ''
Write-Output '== Cache endpoint from Windows'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'get-cache-endpoint.ps1') -Distribution $Distribution
Add-Result 'cache endpoint from windows' ($LASTEXITCODE -eq 0)

Write-Output ''
Write-Output '== Summary'
$summary
if ($summary -match '^\[FAIL\]') {
    Write-Output 'Server not ready.'
    exit 1
}
Write-Output 'Server ready.'
exit 0
