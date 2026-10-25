# Scripts

Scripts are organized by where they run. Host scripts are thin PowerShell entry
points that call the Debian scripts through WSL; Debian scripts can also be run
directly on Linux without PowerShell.

| Script | Runs in | Purpose |
| --- | --- | --- |
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

[../nix/server/flake.nix](../nix/server/flake.nix) defines Harmonia and Skopeo
from one nixpkgs input pinned in the committed
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
| `/nix/var/nix/profiles/nidrew-server` | Profile with `bin/harmonia` and `bin/skopeo` |

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
