# Scripts

Scripts are organized by where they run. Host scripts are thin PowerShell entry
points that call the Debian scripts through WSL; Debian scripts can also be run
directly on Linux without PowerShell.

| Script | Runs in | Purpose |
| --- | --- | --- |
| [host/check-prerequisites.ps1](host/check-prerequisites.ps1) | Windows PowerShell, invoking user | Check WSL and the distribution, then run the Debian checks |
| [server/check-prerequisites.sh](server/check-prerequisites.sh) | Debian, administrative account | Check systemd, tools, sudo access, and the source revision |

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
the check warns about uncommitted edits. Run tests for Debian scripts with
`scripts/server/tests/*-test.sh`.
