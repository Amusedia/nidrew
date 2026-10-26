# Scripts

Scripts are organized by where they run. Host scripts are thin PowerShell entry
points that call the Debian scripts through WSL; Debian scripts can also be run
directly on Linux without PowerShell.

## Reproduce the Nidrew server

This sets up the existing WSL Debian instance as the persistent Nidrew server:
the `nidrew` account and checkout, pinned multi-user Nix, the server Nix
configuration and packages (Harmonia, Skopeo, nftables), and the restricted,
signed Harmonia cache, plus the Windows keepalive task. It does not build or
run agent containers, the egress container, or CLI logins; those are later
work.

Prerequisites: Windows with WSL 3.0.3 or later, a WSL 2 Debian distribution
with systemd, and this repository cloned on Windows (default
`C:\projects\nidrew`, seen from Linux as `/mnt/c/projects/nidrew`). Commit
the changes you want first: the server checkout receives only committed
revisions. The setup downloads the pinned Nix installer and packages.

From Windows, as the user who owns the WSL distribution (no Windows
administrator rights needed):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\setup-server.ps1
powershell -ExecutionPolicy Bypass -File scripts\host\check-server.ps1
```

`setup-server.ps1` (`-Distribution Debian`, `-Source /mnt/c/projects/nidrew`,
`-Revision HEAD`, `-Port 5000`, `-KeyName NAME`) runs the prerequisite
check, then [server/setup-server.sh](server/setup-server.sh) as Linux root
through `wsl.exe --user root`, which the distribution's owner can do without
a Linux password; the command is printed before it runs. It then registers
and starts the keepalive task and runs `check-server.ps1`. It stops at the
first failure with the step and the message to resolve; every step keeps
matching state, so rerun it after resolving a failure or an interruption.
`check-server.ps1` runs the Debian checks, the keepalive status, and the
endpoint check from Windows, and prints the cache endpoint and public key for
deployment configuration.

On Linux without PowerShell, an administrator runs the same Debian steps and
checks; the keepalive task is Windows-only:

```sh
sudo bash /mnt/c/projects/nidrew/scripts/server/setup-server.sh --source /mnt/c/projects/nidrew --revision HEAD
sudo bash /home/nidrew/nidrew/scripts/server/check-server.sh
bash /home/nidrew/nidrew/scripts/server/cache-endpoint.sh
```

Manual actions:

- Back up the Harmonia signing key once after the first setup; see
  [Signing key backup, recovery, and rotation](#signing-key-backup-recovery-and-rotation).
- After signing in to Windows, Debian should be running; if
  `keepalive-task.ps1 -Action Status` reports no keepalive, run
  `-Action Start`.
- Update pins only deliberately, with `server/update-server-lock.sh` or
  `server/nix-release.conf`, then commit and rerun the setup.

The sections below describe each step, its managed files, and recovery. Tested
versions and evidence are in
[../work/server-setup/journal-2.md](../work/server-setup/journal-2.md).

## Scripts

| Script | Runs in | Purpose |
| --- | --- | --- |
| [host/setup-server.ps1](host/setup-server.ps1) | Windows PowerShell, invoking user | Run the prerequisites, Debian setup, keepalive task, and readiness checks |
| [host/check-server.ps1](host/check-server.ps1) | Windows PowerShell, invoking user | Run the Debian checks, keepalive status, and cache endpoint check |
| [server/setup-server.sh](server/setup-server.sh) | Debian, root through sudo | Run account, Nix, configuration, and Harmonia setup in order |
| [server/check-server.sh](server/check-server.sh) | Debian, root through sudo | Run the account, Nix configuration, and Harmonia checks and summarize |
| [host/check-prerequisites.ps1](host/check-prerequisites.ps1) | Windows PowerShell, invoking user | Check WSL 3.0.3 or later and the distribution, then run the Debian checks |
| [server/check-prerequisites.sh](server/check-prerequisites.sh) | Debian, administrative account | Check systemd, tools, sudo access, and the source revision |
| [server/provision-account.sh](server/provision-account.sh) | Debian, root through sudo | Create `nidrew`, `/home/nidrew/artifacts`, and the server checkout |
| [server/sync-checkout.sh](server/sync-checkout.sh) | Debian, `nidrew` | Clone or fetch the source and select a committed revision |
| [server/check-account.sh](server/check-account.sh) | Debian, root through sudo | Check the account, storage, checkout, and fetch access |
| [server/bootstrap-nix.sh](server/bootstrap-nix.sh) | Debian, root through sudo | Install the pinned multi-user Nix after verifying the installer |
| [server/fetch-nix-installer.sh](server/fetch-nix-installer.sh) | Debian, any user | Download the pinned Nix installer and verify its checksum |
| [server/check-nix.sh](server/check-nix.sh) | Debian, root through sudo | Check the Nix version, daemon, build users, trust, and a build as `nidrew` |
| [server/apply-nix-config.sh](server/apply-nix-config.sh) | Debian, root through sudo | Apply the server Nix settings and registry, and build the locked server packages |
| [server/check-nix-config.sh](server/check-nix-config.sh) | Debian, root through sudo | Check settings, registry, `<nixpkgs>`, packages, and Skopeo as `nidrew` |
| [server/update-server-lock.sh](server/update-server-lock.sh) | Debian, ordinary user in the source checkout | Deliberately update the server nixpkgs pin |
| [server/setup-harmonia.sh](server/setup-harmonia.sh) | Debian, root through sudo | Create the `harmonia` account and signing key, restrict the cache port, and run Harmonia |
| [server/check-harmonia.sh](server/check-harmonia.sh) | Debian, root through sudo | Check the key protection, service, port restrictions, and signed substitution as `nidrew` |
| [server/cache-endpoint.sh](server/cache-endpoint.sh) | Debian, any user | Print the current cache endpoint and public key |
| [host/get-cache-endpoint.ps1](host/get-cache-endpoint.ps1) | Windows PowerShell, invoking user | Discover the cache endpoint and public key and check the cache from Windows |
| [host/harmonia-key-recovery.ps1](host/harmonia-key-recovery.ps1) | Windows PowerShell, invoking user | Optionally save or restore the signing key in Windows Credential Manager |
| [host/keepalive-task.ps1](host/keepalive-task.ps1) | Windows PowerShell, invoking user | Register, inspect, start, or stop the login task that keeps Debian running |

WSL containers (`wslc`) require WSL 2.9 or later. The host check requires the
tested WSL 3.0.3 or later; update with `wsl.exe --update`.

Neither check changes the system or needs administrator rights. Each prints
`[ ok ]`, `[warn]`, `[FAIL]`, or `[skip]` lines, then any manual actions with
the exact commands to run and who must run them. Exit status is 0 when required
prerequisites are met and 1 otherwise.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\check-prerequisites.ps1 -Distribution Debian -Source /mnt/c/projects/nidrew -Revision HEAD
```

```sh
scripts/server/check-prerequisites.sh --source /mnt/c/projects/nidrew --revision HEAD
```

The server clone receives only committed changes from the source repository;
the check warns about uncommitted edits.

## Account and checkout

An administrator creates the account and the first checkout from the source
checkout, because no server clone exists yet:

```sh
sudo bash /mnt/c/projects/nidrew/scripts/server/provision-account.sh --source /mnt/c/projects/nidrew --revision HEAD
sudo bash /mnt/c/projects/nidrew/scripts/server/check-account.sh
```

`nidrew` gets a locked password and no sudo access. Later revisions can be
selected as `nidrew` without sudo, for example after
`sudo -u nidrew -i` or from a `nidrew` shell:

```sh
bash ~/nidrew/scripts/server/sync-checkout.sh --revision <commit>
```

The checkout is detached at the selected commit, recorded as
`refs/nidrew/selected`. Sync refuses, without changing anything, when the
checkout has uncommitted changes, an operation in progress, another origin, or
a commit that is not on any branch or tag. Source access is read through Git
only: the clone's `remote.origin.uploadpack` trusts the source's `.git`
directory, and no global Git configuration is changed. Run tests for Debian scripts with
`scripts/server/tests/*-test.sh`.

## Multi-user Nix

[server/nix-release.conf](server/nix-release.conf) pins the upstream Nix
release and the SHA-256 of its shell installer. An administrator installs it:

```sh
sudo bash /mnt/c/projects/nidrew/scripts/server/bootstrap-nix.sh
```

The script downloads the installer, refuses it unless the checksum matches,
and runs it as `install --daemon --yes --no-channel-add`; the installer checks
the binary tarball against the hash it embeds. No channel is added. The
installer creates `/nix`, `/etc/nix/nix.conf`, group `nixbld` with 32 build
users, and the `nix-daemon` systemd units, and loads Nix in shells through
`/etc/profile.d/nix.sh` and `/etc/bash.bashrc` (backed up as
`/etc/bash.bashrc.backup-before-nix`). Open a new shell afterwards.

Rerunning with the pinned version installed changes nothing and runs the
checks. Another installed version, a single-user installation, or leftovers
from an interrupted installation stop the script without changes and name the
paths to inspect; the upstream installer cannot resume, so remove them
following the [uninstall guide](https://nix.dev/manual/nix/stable/installation/uninstall.html)
and rerun. Verify at any time with:

```sh
sudo bash /mnt/c/projects/nidrew/scripts/server/check-nix.sh
```

`nidrew` builds through the daemon without sudo and is not a trusted user.
Change the pin only deliberately, then rerun the checks and record the result
in the work journal.

## Server Nix configuration and packages

[../nix/server/flake.nix](../nix/server/flake.nix) defines Harmonia, Skopeo,
and nftables from one nixpkgs input pinned in the committed
[../nix/server/flake.lock](../nix/server/flake.lock), independent of agent
pins. [../nix/server/nidrew.conf](../nix/server/nidrew.conf) holds the
server-wide settings: `nix-command` and `flakes`, `sandbox = true`,
`require-sigs = true`, `accept-flake-config = false`,
`nix-path = nixpkgs=flake:nixpkgs`, and `cache.nixos.org` with its key. No
trusted users are added and the server does not use its own Harmonia.

Commit changes first and select them in the server checkout, then apply from
that checkout as an administrator:

```sh
sudo -u nidrew -i bash /home/nidrew/nidrew/scripts/server/sync-checkout.sh --revision <commit>
sudo bash /home/nidrew/nidrew/scripts/server/apply-nix-config.sh
sudo bash /home/nidrew/nidrew/scripts/server/check-nix-config.sh
```

Apply manages exactly these files:

| Path | Content |
| --- | --- |
| `/etc/nix/nidrew.conf` | Copy of `nix/server/nidrew.conf` |
| `/etc/nix/registry.json` | System registry pinning `nixpkgs` to the locked revision |
| `/etc/nix/nix.conf` | One added line, `include nidrew.conf`; other content is kept |
| `/var/lib/nidrew/managed.sha256` | Last-applied checksums of the managed files |
| `/var/lib/nidrew/previous/` | The previous version of each file apply replaced |
| `/nix/var/nix/profiles/nidrew-server` | Profile with `bin/harmonia-cache` (Harmonia), `bin/skopeo`, and `bin/nft` |

Apply plans every file before changing any. Matching files are left alone and
unchanged managed files are updated. A managed file edited locally, an
existing file Nidrew did not write, or a `nix.conf` line setting a managed key
stops the run without changes and names the resolution. The complete candidate
configuration is validated in a temporary directory before activation. Apply
restarts `nix-daemon.service` when it predates its configuration, and builds
the profile with `--no-update-lock-file`. Reruns resume an interrupted apply.
To recover, copy a file from `/var/lib/nidrew/previous/` back and rerun the
check, or roll back the profile with
`sudo nix-env --profile /nix/var/nix/profiles/nidrew-server --rollback`.

The check runs `check-nix.sh`, then verifies the files, the effective settings
for `nidrew`, the daemon restart, that `flake:nixpkgs` and `<nixpkgs>` resolve
to the locked revision without channels, the profile, and that `nidrew` can
inspect and copy a digest-pinned busybox image with Skopeo into a temporary
directory. It needs network access.

Update the pin only deliberately, in the source checkout:

```sh
scripts/server/update-server-lock.sh
```

It prints the old and new nixpkgs revision and tool versions and the steps to
commit, sync, apply, check, and record the result in the work journal. To
update Nix itself, change `server/nix-release.conf` the same way.

## Harmonia cache

Harmonia serves the Debian Nix store as a signed binary cache. Apply the
server Nix configuration first; it installs `harmonia-cache` in the
`nidrew-server` profile. Then, as an administrator:

```sh
sudo bash /home/nidrew/nidrew/scripts/server/setup-harmonia.sh
sudo bash /home/nidrew/nidrew/scripts/server/check-harmonia.sh --restart
```

Setup creates the system account `harmonia` (no login shell, no sudo, only
its own group, not a Nix trusted user), generates the signing key once, and
installs and starts the service. Its output ends with the public key, which
consumers add to `trusted-public-keys`. `--key-name NAME` names a newly
generated key; the default is `nidrew-<hostname>-1`. `--port PORT` selects the
cache port (default 5000); pass the same port to every later setup and check.

| Path | Content |
| --- | --- |
| `/etc/harmonia/secret-key` | Signing key, root:root mode 0600; created once, never replaced |
| `/etc/harmonia/public-key` | Public key derived from it, mode 0644 |
| `/etc/harmonia/harmonia.toml` | Copy of [server/harmonia/harmonia.toml](server/harmonia/harmonia.toml) |
| `/etc/harmonia/firewall.sh` | Copy of [server/harmonia/firewall.sh](server/harmonia/firewall.sh): loads the port restrictions |
| `/etc/systemd/system/harmonia-firewall.service` | Copy of [server/harmonia/harmonia-firewall.service](server/harmonia/harmonia-firewall.service) |
| `/etc/systemd/system/harmonia.socket` | Copy of [server/harmonia/harmonia.socket](server/harmonia/harmonia.socket): listens on `[::]:5000` |
| `/etc/systemd/system/harmonia.service` | Copy of [server/harmonia/harmonia.service](server/harmonia/harmonia.service) |

The configuration and units are managed files with checksums in
`/var/lib/nidrew/managed.sha256`, handled like the Nix configuration above;
`@PORT@` in the templates becomes the selected port.
systemd passes the key to the service with `LoadCredential=`, so the unit
holds only the path and Harmonia restarts from the Debian copy without any
other input. The service runs as `harmonia` from the inherited socket with no
network access of its own and a read-only system; it reads the Nix database
directly and cannot write the store. Neither `nidrew` nor `harmonia` can read
the key file. Without a readable key the service fails at its credentials
step and retries every 5 seconds, so it recovers by itself once the key is
back; rerunning setup also clears a failed state.

The check verifies the account, the key's protection and that its value is
absent from the units, configuration, and journal, the managed files, the
port restrictions and listener, loopback access, that connections from this
instance's own eth0 and IPv6 link-local addresses are dropped, and that
`nidrew` can substitute a locally built path from the cache into a fresh store
with the public key and signatures required, and that the path is rejected
without the key. `--restart` restarts the service first.

### Cache endpoint and network restrictions

The socket listens on all IPv4 and IPv6 addresses. `harmonia-firewall.service`
loads the nftables table `inet nidrew_harmonia` before the socket starts and
the socket stops whenever it stops, so the port is never open unrestricted.
The table accepts the port only from `127.0.0.0/8`, `::1`, and the WSL NAT
gateway (the default route, discovered at each start), and drops every other
IPv4 and IPv6 source. Other tables and rules are left alone. The script
refuses WSL networking modes other than `nat`.

In NAT mode the Windows host and WSL containers (`wslc`) both reach Debian
from the gateway address, so the Debian rules cannot tell them apart or grant
individual agents; per-agent grants belong to the egress container. LAN
clients have no route to the NAT network. A Windows port proxy to the cache
port would forward LAN clients from the gateway address and bypass this
restriction; the endpoint script warns about one.

The Debian address can change when WSL restarts. Discover the endpoint and
public key for deployment configuration from Windows, which also checks that
the cache answers from the host:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\get-cache-endpoint.ps1
```

In Debian, `bash scripts/server/cache-endpoint.sh` prints the same values as
`address=`, `port=`, `endpoint=`, and `public_key=` lines.

Do not enable Debian's `nftables.service` with its default
`/etc/nftables.conf`: its `flush ruleset` removes the Nidrew table while the
socket keeps listening. `check-harmonia.sh` reports a missing table; restore
it with `sudo systemctl restart harmonia-firewall.service harmonia.socket`.

### Signing key backup, recovery, and rotation

Back up the key once after setup and keep the copy outside this instance, for
example in a password manager. Reading it shows the secret on your terminal:

```sh
sudo cat /etc/harmonia/secret-key
```

Optionally, keep a recovery copy in Windows Credential Manager for the
invoking Windows user on this computer. The key passes through `wsl.exe` as
root and is never printed:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\harmonia-key-recovery.ps1 -Action Save
```

To recover a lost key, restore it as `/etc/harmonia/secret-key` with mode
0600, owned by root, then rerun setup, which checks it against
`/etc/harmonia/public-key` and restarts the service. From Credential Manager,
which refuses to replace an existing file:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\harmonia-key-recovery.ps1 -Action Restore
```

From another backup, in Debian (paste the key, then press Ctrl-D):

```sh
sudo sh -c 'umask 077; cat > /etc/harmonia/secret-key'
sudo bash /home/nidrew/nidrew/scripts/server/setup-harmonia.sh
```

Setup refuses a public key without a secret key, so a lost key is never
replaced silently. If no backup exists, or the key may have been exposed,
rotate it deliberately: move both files aside, generate a key with the next
name, update every consumer's `trusted-public-keys`, then remove the old
files and any old Credential Manager copy.

```sh
sudo mv /etc/harmonia/secret-key /etc/harmonia/secret-key.retired
sudo mv /etc/harmonia/public-key /etc/harmonia/public-key.retired
sudo bash /home/nidrew/nidrew/scripts/server/setup-harmonia.sh --key-name nidrew-<hostname>-2
```

## Windows keepalive task

WSL stops an idle instance once no Windows process uses it, which would stop
systemd, the Nix daemon, and Harmonia. A Scheduled Task keeps Debian running
from your Windows logon. Register it as the Windows user who owns the WSL
installation; administrator rights are not required. Provision `nidrew`
first, because the keepalive runs as that unprivileged account:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\keepalive-task.ps1 -Action Register
powershell -ExecutionPolicy Bypass -File scripts\host\keepalive-task.ps1 -Action Start
powershell -ExecutionPolicy Bypass -File scripts\host\keepalive-task.ps1 -Action Status
```

The task is `\Nidrew Keepalive <Distribution>` in the Task Scheduler root
folder (`-TaskName` overrides it; `-Distribution` and `-LinuxUser` default to
`Debian` and `nidrew`). It runs only while you are logged on, starts at your
logon, and runs this command through `conhost.exe --headless`, so no window
opens:

```text
wsl.exe --distribution Debian --user nidrew --exec sleep infinity
```

Settings: no execution time limit; a second start is ignored while one runs;
no restart on failure; starts and keeps running on battery; no idle
conditions; never wakes the computer. Registration is rerunnable: a matching
task is left alone, a task this script created is updated, and any other task
with the name is kept and reported, with nothing changed. Delete such a task
in Task Scheduler if it is an older keepalive, or choose another name.

Task Scheduler tracks only `conhost.exe`. Ending the task there leaves
`wsl.exe` and the sleep running, so use `-Action Stop`, which ends both.
`-Action Start` does nothing while the keepalive runs. Running a task as
"whether the user is logged on or not" without a stored password (S4U) needs
administrator rights, so the task runs in your interactive session instead.

The keepalive does not prevent an explicit `wsl.exe --shutdown` or a Windows
shutdown. After `wsl.exe --shutdown`, Debian stays stopped until your next
logon or `-Action Start`. Signing out ends the task and stops Debian; it
survives sleep and resume. In testing, two of six logons did not start the
keepalive for an unknown reason; check with `-Action Status` after signing in
and recover with `-Action Start`.
