# Server Setup Journal 2: Implementation

Continues [journal.md](journal.md), which holds the planning history. This file
records implementation lessons from the [checklist](checklist.md).

## Findings Summary

- Run the prerequisite checks with `scripts/host/check-prerequisites.ps1` from
  Windows, or `scripts/server/check-prerequisites.sh` directly in Debian. Both
  change nothing and need no administrator rights.
- Require WSL 3.0.3 or later, the tested version. WSL containers (`wslc`)
  need 2.9 or later; asking for the tested version avoids untested ranges.
- A Windows checkout with `core.autocrlf=true` contains CRLF files. Linux Git
  reports every such file as modified, and `git status` still does so with
  `-c core.autocrlf=true`, because it treats a size change as a modification.
  Use `git diff` with `core.autocrlf=true` to find real uncommitted edits, and
  `core.safecrlf=false` to silence conversion warnings for LF working files.
- Shell scripts must keep LF endings in the Windows checkout because Debian
  runs them from `/mnt/c`; `.gitattributes` enforces `*.sh text eol=lf`.
- Commands run through `wsl.exe --distribution Debian --exec ...` from the
  Claude desktop session on Windows reached the system bus; the restriction
  noted in journal.md came from a different, sandboxed Linux session.
- A local clone or fetch from a repository owned by another user fails in
  `upload-pack` with "dubious ownership" for the source `.git` path. Git drops
  `-c safe.directory=...` for local transports, so pass a trusting command with
  `--upload-pack` and store it as `remote.origin.uploadpack` in the clone.
- `/mnt/c` is drvfs mounted without metadata, so every Linux user can read and
  write the source checkout. This is accepted for the server; the restriction
  of `/mnt/c` applies to agent containers.
- `wsl.exe` writes its own messages as UTF-16 unless `WSL_UTF8=1` is set.
  Windows PowerShell 5.1 also mangles inline `bash -c` scripts containing
  double quotes; run script files with `--exec bash <path> <args>` instead.

## 2026-10-25: Prerequisite checks (checklist item 1)

Environment: Windows 10.0.26200, Windows PowerShell 5.1.26100, WSL 3.0.3.0
with kernel 6.18.54.1, Debian 13 (trixie) on WSL 2, Windows user `peijen` not
elevated, Debian default user `peijen`.

Checks performed:

```sh
scripts/server/tests/check-prerequisites-test.sh   # in Debian: 12 passed
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\check-prerequisites.ps1
powershell -ExecutionPolicy Bypass -File scripts\host\check-prerequisites.ps1 -Distribution NoSuchDistro
```

Observed on this machine: systemd 257 running as PID 1, Bash 5.2.37, Git
2.47.3, curl 8.14.1, coreutils 9.7, GNU tar 1.35, and XZ Utils 5.8.1. `peijen`
is in group `sudo` and sudo requires a password. The current user can query
Task Scheduler without elevation. The unknown distribution produced a failure
with the installed distribution names and exit status 1. Raising
`-MinimumWslVersion` to 3.0.4 failed the WSL check with the update command.

Not performed: no interactive sudo command was run. The bus-denied,
no_new_privs, sudo-denied, and missing-tool outputs were verified with stub
commands in the test, not in a real restricted session or a host missing those
tools. A Windows user who cannot query Task Scheduler was not tested.

What can be skipped: a reader whose check reports no failures can continue to
the account setup. A Debian instance without systemd needs `/etc/wsl.conf`
changes and `wsl.exe --shutdown` first, as the check prints.

## 2026-10-25: Account and server checkout (checklist item 2)

Environment: as for item 1; Git 2.47.3 in Debian. `/mnt/c` is a 9p drvfs
mount with `uid=1000,gid=1000` and mode 777 files.

Checks performed:

```sh
scripts/server/tests/sync-checkout-test.sh       # 15 passed
scripts/server/tests/provision-account-test.sh   # 2 passed (non-root only)
sudo bash scripts/server/provision-account.sh --source /mnt/c/projects/nidrew --revision HEAD
sudo bash scripts/server/check-account.sh
```

Observed: the first provisioning run created `nidrew` (uid 1001, gid 1002)
and its directories, then the clone failed with "dubious ownership" for
`/mnt/c/projects/nidrew/.git`. The ownership test with
`GIT_TEST_ASSUME_DIFFERENT_OWNER=1` reproduced it; `-c safe.directory` on the
clone did not help, and `--upload-pack` with the trusting command did. The
rerun reused the account and directories and selected 2b54b90. As root:
`check-account.sh` passed; `nidrew` is only in group `nidrew`, has no sudo
privileges and no global Git configuration, and could not write to `/etc`. A
matching sync and a provisioning rerun reported "already at"; sync with an
untracked file in the checkout was refused and the file was kept.

Not performed: provisioning with conflicting existing state (another home,
administrative group membership, wrongly owned directories) ran only through
code review, not on a host.

What can be skipped: readers can use `--upload-pack` directly instead of
trying `-c safe.directory` or global `safe.directory` configuration.
