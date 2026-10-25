<#
.SYNOPSIS
Keep an optional recovery copy of the Harmonia signing key in Windows
Credential Manager, or restore the key from it into Debian.

.DESCRIPTION
Runs as the invoking Windows user; administrator rights are not required. The
copy is a generic credential stored for this user on this computer only. The
key is read and written through wsl.exe as the Linux user given by -LinuxUser
(root by default), passed over standard input and output only, and never
printed. Restore refuses to replace an existing key file; afterwards run
setup-harmonia.sh, which checks the key and its public key.

Harmonia does not need this copy to start: it loads the key from Debian.

Exit status: 0 on success, 1 otherwise.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\harmonia-key-recovery.ps1 -Action Save

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\harmonia-key-recovery.ps1 -Action Restore
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Save', 'Restore')]
    [string]$Action,
    # WSL distribution that hosts the Nidrew server.
    [string]$Distribution = 'Debian',
    # Linux user that can read and create the key file.
    [string]$LinuxUser = 'root',
    # Key file in Debian.
    [string]$KeyPath = '/etc/harmonia/secret-key',
    # Credential Manager target name.
    [string]$Target = 'nidrew-harmonia-secret-key'
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NidrewCredential {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL {
        public int Flags; public int Type; public string TargetName; public string Comment;
        public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
        public int Persist; public int AttributeCount; public IntPtr Attributes;
        public string TargetAlias; public string UserName;
    }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredWriteW(ref CREDENTIAL credential, int flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredReadW(string target, int type, int flags, out IntPtr credential);
    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr buffer);
    const int Generic = 1, LocalMachine = 2;

    public static void Write(string target, string userName, byte[] secret) {
        var credential = new CREDENTIAL { Type = Generic, TargetName = target, UserName = userName,
            Persist = LocalMachine, CredentialBlobSize = secret.Length,
            CredentialBlob = Marshal.AllocHGlobal(secret.Length) };
        try {
            Marshal.Copy(secret, 0, credential.CredentialBlob, secret.Length);
            if (!CredWriteW(ref credential, 0)) throw new System.ComponentModel.Win32Exception();
        } finally {
            Marshal.FreeHGlobal(credential.CredentialBlob);
        }
    }
    public static byte[] Read(string target) {
        IntPtr pointer;
        if (!CredReadW(target, Generic, 0, out pointer)) return null;
        try {
            var credential = (CREDENTIAL)Marshal.PtrToStructure(pointer, typeof(CREDENTIAL));
            var secret = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, secret, 0, secret.Length);
            return secret;
        } finally {
            CredFree(pointer);
        }
    }
}
'@

$env:WSL_UTF8 = '1'
if ($KeyPath -notmatch '^/[A-Za-z0-9._/-]+$') {
    Write-Error "KeyPath must be an absolute Linux path without spaces or quotes."
    exit 1
}
$keyPattern = '^[A-Za-z0-9._-]+:[A-Za-z0-9+/]+={0,2}$'

if ($Action -eq 'Save') {
    $secret = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec cat $KeyPath) -join ''
    if ($LASTEXITCODE -ne 0 -or $secret -notmatch $keyPattern) {
        Write-Error "Cannot read a Nix signing key from $KeyPath in $Distribution as $LinuxUser."
        exit 1
    }
    $name = $secret.Split(':')[0]
    [NidrewCredential]::Write($Target, $name, [Text.Encoding]::ASCII.GetBytes($secret))
    $secret = $null
    Write-Output "Saved key $name from ${Distribution}:$KeyPath as Credential Manager target $Target."
    exit 0
}

$bytes = [NidrewCredential]::Read($Target)
if ($null -eq $bytes) {
    Write-Error "Credential Manager has no target $Target for this user."
    exit 1
}
$secret = [Text.Encoding]::ASCII.GetString($bytes)
if ($secret -notmatch $keyPattern) {
    Write-Error "Credential Manager target $Target does not hold a Nix signing key."
    exit 1
}
# The key arrives on standard input as raw bytes. Windows PowerShell opens
# child standard input with the console input encoding, whose UTF-8 form writes
# a byte order mark first, so select UTF-8 without one. The file is created
# with mode 0600 and never replaces an existing one.
[Console]::InputEncoding = New-Object Text.UTF8Encoding $false
$restore = 'umask 077; test ! -e $1 || { echo $1 exists and was not replaced >&2; exit 1; }; cat > $1'
$start = New-Object Diagnostics.ProcessStartInfo 'wsl.exe'
$start.Arguments = '--distribution {0} --user {1} --exec sh -c "{2}" sh {3}' -f $Distribution, $LinuxUser, $restore, $KeyPath
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$process = [Diagnostics.Process]::Start($start)
$process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
$process.StandardInput.Close()
$process.WaitForExit()
$status = $process.ExitCode
$secret = $null
$bytes = $null
if ($status -ne 0) {
    Write-Error "Restore to ${Distribution}:$KeyPath failed."
    exit 1
}
Write-Output "Restored key $($Target) to ${Distribution}:$KeyPath (mode 0600)."
Write-Output 'Next, in Debian: sudo bash /home/nidrew/nidrew/scripts/server/setup-harmonia.sh'
exit 0
