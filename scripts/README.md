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
