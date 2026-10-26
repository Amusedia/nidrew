<#
.SYNOPSIS
Discover the Harmonia cache endpoint and public key from Windows and check
that the cache answers from this host.

.DESCRIPTION
Runs as the invoking Windows user; administrator rights are not required.
Runs scripts/server/cache-endpoint.sh in the distribution to find the current
Debian address, the cache port, and the public key, then requests
nix-cache-info from Windows. The WSL NAT address can change when WSL restarts,
so run this again instead of recording the address. Also reports Windows port
proxy rules for the cache port: forwarded connections reach Debian from the
Windows host's address, which the Debian restrictions allow.

Writes an object with Distribution, Address, Port, Endpoint, PublicKey, and
Reachable; pipe it to ConvertTo-Json for deployment configuration.

Exit status: 0 when the cache answers, 1 otherwise.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\get-cache-endpoint.ps1
#>
[CmdletBinding()]
param(
    # WSL distribution that hosts the Nidrew server.
    [string]$Distribution = 'Debian'
)

# wsl.exe writes UTF-16 for its own messages unless WSL_UTF8 is set.
$env:WSL_UTF8 = '1'
$hostScript = Join-Path $PSScriptRoot '..\server\cache-endpoint.sh'
$linuxScript = & wsl.exe --distribution $Distribution --exec wslpath -a -u ((Resolve-Path $hostScript).Path)
if ($LASTEXITCODE -ne 0 -or -not $linuxScript) {
    Write-Error "Cannot reach distribution $Distribution; run scripts\host\check-prerequisites.ps1."
    exit 1
}
$lines = & wsl.exe --distribution $Distribution --exec bash $linuxScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "Debian did not report the cache endpoint; see the message above."
    exit 1
}
$values = @{}
foreach ($line in $lines) {
    if ($line -match '^([a-z_]+)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
}
foreach ($name in 'address', 'port', 'endpoint', 'public_key') {
    if (-not $values[$name]) {
        Write-Error "cache-endpoint.sh did not report $name."
        exit 1
    }
}

$reachable = $false
try {
    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri "$($values.endpoint)/nix-cache-info"
    $reachable = $response.Content -match 'StoreDir: /nix/store'
} catch {
    Write-Warning "$($values.endpoint)/nix-cache-info failed from Windows: $($_.Exception.Message)"
}

$proxies = & netsh.exe interface portproxy show all 2>$null |
    Where-Object { $_ -match "\s$($values.port)\s*$" }
foreach ($proxy in $proxies) {
    Write-Warning "A Windows port proxy forwards to port $($values.port), exposing the cache to its clients: $($proxy.Trim())"
}

[pscustomobject]@{
    Distribution = $Distribution
    Address      = $values.address
    Port         = [int]$values.port
    Endpoint     = $values.endpoint
    PublicKey    = $values.public_key
    Reachable    = $reachable
}
if (-not $reachable) { exit 1 }
exit 0
