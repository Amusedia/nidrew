# Server Setup Journal 2: Implementation

Continues [journal.md](journal.md), which holds the planning history. This file
records implementation lessons from the [checklist](checklist.md).

## Findings Summary

- Run the prerequisite checks with `scripts/host/check-prerequisites.ps1` from
  Windows, or `scripts/server/check-prerequisites.sh` directly in Debian. Both
  change nothing and need no administrator rights.
- A Windows checkout with `core.autocrlf=true` contains CRLF files. Linux Git
  reports every such file as modified, and `git status` still does so with
  `-c core.autocrlf=true`, because it treats a size change as a modification.
  Use `git diff` with `core.autocrlf=true` to find real uncommitted edits.
- Shell scripts must keep LF endings in the Windows checkout because Debian
  runs them from `/mnt/c`; `.gitattributes` enforces `*.sh text eol=lf`.
- Commands run through `wsl.exe --distribution Debian --exec ...` from the
  Claude desktop session on Windows reached the system bus; the restriction
  noted in journal.md came from a different, sandboxed Linux session.
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
with the installed distribution names and exit status 1.

Not performed: no interactive sudo command was run. The bus-denied,
no_new_privs, sudo-denied, and missing-tool outputs were verified with stub
commands in the test, not in a real restricted session or a host missing those
tools. A Windows user who cannot query Task Scheduler was not tested.

What can be skipped: a reader whose check reports no failures can continue to
the account setup. A Debian instance without systemd needs `/etc/wsl.conf`
changes and `wsl.exe --shutdown` first, as the check prints.
