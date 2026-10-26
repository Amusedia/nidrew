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
- Pin Nix by the installer script's SHA-256: the upstream `install` script
  embeds and checks the binary tarball hash, so one verified file pins both.
  Release `install.sha256` files exist beside each installer.
- The upstream multi-user installer runs correctly as root (no sudo inside)
  and accepts `--daemon --yes --no-channel-add` for unattended installation.
  It cannot resume a partial installation, so bootstrap stops on leftovers.
- Harmonia 3.x ships `harmonia-cache` (the HTTP cache), `harmonia-daemon`,
  and `harmonia`, a Nix-compatible CLI; `harmonia --version` prints a Nix
  version. Services use `harmonia-cache`.
- Nix resolves a relative `include` against the including file's directory,
  so `include nidrew.conf` works in `/etc/nix` and in a temporary copy used for
  validation with `NIX_CONF_DIR`. `nix config show` reports unknown settings
  as `warning:` lines with exit status 0; validation must check stderr.
- `nix config show experimental-features` lists implied features such as
  `fetch-tree`; compare features as a set.
- From Git Bash, pass `MSYS_NO_PATHCONV=1` to `wsl.exe` so Linux paths such as
  `/tmp/...` are not rewritten into Windows paths.
- Harmonia 3.1.0 `harmonia-cache` reads `/nix/var/nix/db/db.sqlite` directly
  (world-readable after the installer) and needs no daemon socket, store
  write access, or trust; it takes its key from `SIGN_KEY_PATHS` and exits 1
  on a missing key without printing key material. It accepts a
  systemd-inherited socket and supports `Type=notify` with a watchdog.
- A failing `Restart=on-failure` service hits the start limit within about a
  second; the limit also fails its socket and refuses later starts until
  `reset-failed`. `RestartSec=5` keeps retries under the limit. Meanwhile the
  socket accepts and holds connections, so clients need time limits.
- Windows PowerShell 5.1 sends a UTF-8 byte order mark to child standard
  input, through pipelines and `Process` alike, unless
  `[Console]::InputEncoding` is UTF-8 without one.
- In WSL NAT mode, Debian sees both the Windows host and `wslc` containers
  as the NAT gateway (here 172.30.208.1); `wslc` containers sit behind
  their own Docker bridge (172.17.0.0/16) and are masqueraded on the way.
  Debian has only a link-local IPv6 address. Allow the gateway, not a
  subnet; Debian cannot tell agents apart.
- A unit ordered before a socket needs `DefaultDependencies=no`; otherwise
  its implicit `After=basic.target` forms a cycle with `sockets.target`.
- nftables applies `table X; delete table X; table X { ... }` as one
  transaction, so the restrictions are replaced atomically and the first
  load needs no special case. A drop in any table is final, so the Nidrew
  table restricts the port without touching other rules.
- `curl --interface` cannot bind an IPv6 link-local address without a
  scope (errno 22); a link-local destination already selects the
  link-local source.
- `nix copy --to <dir>` as an untrusted user creates a fresh local store
  that applies the user's `--trusted-public-keys`, a cheap isolated
  substitution consumer.
- A Windows user without administrator rights cannot register an S4U task
  ("run whether the user is logged on or not" without a password): Access is
  denied. An interactive logon task with `conhost.exe --headless wsl.exe ...`
  runs without a visible window.
- `C:\Windows\System32\wsl.exe` starts a second `wsl.exe` with the same
  command line. Stopping a task kills only its top process, so the children
  and the Linux command keep running; killing the `wsl.exe` processes ends
  the Linux command.
- In PowerShell, a function that runs a child command and then returns
  `$LASTEXITCODE -eq 0` returns the child's output too; an `if` on it is
  true whenever there was output, and the output is lost. Run the child and
  test `$LASTEXITCODE` at the call site instead.

## 2026-10-26: Complete setup, recovery checks, and contract review (checklist item 8)

Environment: as for item 7; server checkout at a1027da.

Checks performed:

```sh
scripts/server/tests/setup-server-test.sh   # 17 passed; all other server tests pass
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\setup-server.ps1   # twice
```

```sh
# as root: a comment appended to /etc/nix/nix.conf before the second run
timeout -s TERM 4 bash /mnt/c/projects/nidrew/scripts/server/setup-server.sh   # stopped in step 3
timeout -s TERM 8 bash /mnt/c/projects/nidrew/scripts/server/setup-server.sh   # stopped in step 4
bash /mnt/c/projects/nidrew/scripts/server/setup-server.sh
bash /home/nidrew/nidrew/scripts/server/check-server.sh
```

Observed: the first host run completed but showed that the host wrapper
hid child output and ignored host step failures (fixed in a1027da). The
second run selected a1027da, changed nothing except restarting
`nix-daemon.service` (the appended comment made `nix.conf` newer than the
daemon), kept the comment, left the keepalive task unchanged and running,
and reported the server ready, with the endpoint reachable from Windows.
Interrupted runs stopped in steps 3 and 4; the next run completed and the
checks passed. These interruptions hit matching state; resumption of
partially applied files and partial Nix installations is covered by the
item 3 to 5 tests and refusals.

Restart: after the Windows restart at 07:18 on 2026-10-26 the keepalive
started Debian at 07:19:31 and `nix-daemon.socket`, `harmonia-firewall.service`,
and `harmonia.socket` were active with no manual action (item 7 entry).
Harmonia and its restrictions stayed in the units started at 07:19:32 during
every later run, so the passing `check-harmonia.sh` signed substitution and
rejection checks above are the repeated cache check after that restart.

### Behavior contract review

| Contract item | Status | Evidence |
| --- | --- | --- |
| Existing user, WSL configuration, personal files, and repository content kept | Met | Only documented managed files changed; `nix.conf` local line kept |
| Routine work as `nidrew`; builds from the Linux-native clone | Met | Items 2 and 4; `check-account.sh` |
| Nix daemon, Harmonia, Skopeo installed | Met | `check-server.sh` |
| `nidrew` builds without sudo through build users | Met | `check-nix.sh` |
| Checkout records the selected commit; local work preserved | Met | Item 2 sync tests and host refusals |
| Nix download verified before execution | Met | Item 3 checksum refusal on the host |
| Harmonia and Skopeo from the committed lock; reruns keep versions | Met | Item 4; the profile unchanged on reruns |
| Explicit update workflow | Partly | `update-server-lock.sh` exists; a real pin update was not exercised |
| Server-wide settings, registry, `<nixpkgs>`, no channels or extra trusted users | Met | `check-nix-config.sh` |
| Skopeo inspect and copy as `nidrew` | Met | `check-nix-config.sh` |
| Signed substitution with the key; rejection without it | Met | `check-harmonia.sh` |
| Upstream substitution only; no self Harmonia substituter | Met | `nidrew.conf`; `check-nix-config.sh` |
| Signing key unreadable by `nidrew`; systemd credential; restart without Windows | Met | Item 5; `check-harmonia.sh --restart` |
| Harmonia least privilege and port restrictions | Met | Item 6; per-agent grants await egress |
| Endpoint and public key published | Met | `get-cache-endpoint.ps1`, `cache-endpoint.sh` |
| Reruns without duplicates or key replacement; conflicts explained | Met | Item tests; reruns on the host |
| Managed files, checksums, previous copies, validation, resumption | Met | Items 4 to 5 tests; interrupted runs above |
| Readiness checks without secrets | Met | `check-server.sh`; key-absence checks |
| Services usable after a Debian restart | Met | Windows restart above; Nix and Harmonia active |
| Keepalive task settings and behavior | Met with limitation | Item 7; two of six logons did not start Debian |
| Host and Linux entry points; documentation | Met | `scripts/README.md` |
| Permissions distinguished; manual actions listed | Met | Item 1; manual actions in `scripts/README.md` |

Not verified in this work stream: per-agent access through egress,
substitution by Nix inside an agent container, a LAN client, mirrored
networking, a real pin update, key rotation, and the cause of the two
logons that did not start the keepalive. Container, CLI, and egress
milestones in GOAL.md are not part of this work stream.

## 2026-10-25: Windows keepalive task (checklist item 7)

Environment: Windows 11 Pro 10.0.26200, WSL 3.0.3.0, kernel 6.18.54.1-1;
Windows user `PLING\peijen`, a member of no administrator group; Pester
3.4.0 (shipped with Windows PowerShell 5.1). No earlier WSL task existed.

Checks performed:

```powershell
powershell -ExecutionPolicy Bypass -Command "Invoke-Pester scripts\host\tests"   # 12 passed
scripts\host\keepalive-task.ps1 -Action Status      # before: task missing, exit 1
scripts\host\keepalive-task.ps1 -Action Register    # twice
scripts\host\keepalive-task.ps1 -Action Start       # twice
scripts\host\keepalive-task.ps1 -Action Status
# a foreign task named 'Nidrew Keepalive Conflict'; Register -TaskName on it
# ExecutionTimeLimit changed to PT72H with Set-ScheduledTask; Status; Register twice
scripts\host\keepalive-task.ps1 -Action Stop        # then Start and Status
```

Observed: Register created the task and the rerun reported it unchanged.
The registered task has principal `peijen`, Interactive, Limited; a logon
trigger for `PLING\peijen`; `ExecutionTimeLimit` PT0S, `IgnoreNew`, no
battery conditions, `RestartCount` 0, no wake. Start ran the keepalive with
no visible window; a second Start reported it running without a duplicate,
and Debian had one `sleep infinity` as `nidrew`. The foreign task was
reported as a conflict and kept unchanged (exit 1). The changed time limit
was reported as a difference and Register restored it without stopping the
running keepalive. Stop ended three processes and the Linux sleep.

Not observed: Debian stopping without the keepalive. Docker Desktop and the
Claude desktop bridge keep their own `wsl.exe` processes in Debian on this
machine, so the instance stayed running for 90 s with no keepalive and no
shell.

### 2026-10-26: User-performed disruptive checks

The user signed out and in, restarted Windows, let the computer sleep, and
ran `wsl.exe --shutdown`, without starting anything else in WSL. Times come
from Winlogon 7001/7002 and Kernel-Power events, WSL VM network ports
(Hyper-V VmSwitch 67/69), Debian's `journalctl --list-boots` (each WSL
instance start is a boot), and the task's last run. Task Scheduler history is
disabled and enabling it needs administrator rights.

| Time | Event | Debian |
| --- | --- | --- |
| 06:38:29 | sign-out | stopped 06:38:30 |
| 06:38:55 | sign-in | started 06:39:46 |
| 06:40:46 | sign-out | stopped 06:40:46; VM removed 06:41:25 |
| 06:41:45 | sign-in | not started |
| 06:49:24 | restart; sign-in 06:50:31 | not started; WSL network removed 06:50:38 |
| 06:51-06:55 | modern standby | |
| 06:56:04 | sign-in | started 06:56:09; task last run 06:56:04 |
| 06:56:48 | `wsl.exe --shutdown` | stopped; task result 0x0; stayed stopped |
| 06:58:40 | `-Action Start` | started 06:58:28 |
| 07:08-07:11 | modern standby | keepalive kept running |
| 07:15:26 | sign-out | stopped; VM removed 07:16:06 |
| 07:15:56 | sign-in | started 07:16:13; task last run 07:15:56 |
| 07:18:11 | restart; sign-in 07:19:18 | started 07:19:31; task last run 07:19:22 |

Observed: sign-out stops Debian, as expected for a task that runs only while
the user is logged on. The logon trigger restored Debian at three logons,
including one while the previous VM was still shutting down and one after a
restart; Nix and Harmonia were active after the restart. Sleep and resume
kept the keepalive running. After `wsl.exe --shutdown` the task ended with
0x0 and Debian stayed stopped until `-Action Start`.

Unexplained: two logons (06:41:45 and 06:50:31) did not start Debian. Each
run overwrites the task's last result, so whether the trigger fired or
`wsl.exe` failed is unknown. Recovery is `-Action Start`. To diagnose a
recurrence, an administrator can enable the history with
`wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true`.

## 2026-10-25: Restricted cache endpoint (checklist item 6)

Environment: as for item 5; WSL networking mode `nat`, Debian
172.30.217.209/20 on eth0, gateway 172.30.208.1, no global IPv6. nftables
1.1.6 from the server lock (Debian's 1.1.3 used only for prototyping).

Network path probe: a throwaway busybox image built with
`dockerTools.buildImage` from the pinned nixpkgs, loaded with `wslc load`,
connected to a temporary socat listener in Debian. The container (172.17.0.2)
and Windows both arrived from 172.30.208.1; Debian's own connections came
from 127.0.0.1, ::1, or 172.30.217.209. The container had no IPv6 route. The
probe image and files were removed afterwards.

Checks performed:

```sh
scripts/server/tests/harmonia-firewall-test.sh   # 13 passed
scripts/server/tests/cache-endpoint-test.sh      # 10 passed
scripts/server/tests/setup-harmonia-test.sh      # 46 passed
# all other server tests unchanged and passing
sudo -u nidrew -i bash /home/nidrew/nidrew/scripts/server/sync-checkout.sh --revision 2f7961e
sudo bash /home/nidrew/nidrew/scripts/server/apply-nix-config.sh
sudo bash /home/nidrew/nidrew/scripts/server/setup-harmonia.sh       # twice
sudo bash /home/nidrew/nidrew/scripts/server/check-harmonia.sh --restart
# stop harmonia-firewall.service; delete the table with nft; --port 5001 and back
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\host\get-cache-endpoint.ps1
wslc run --rm nidrew-probe:1 wget -qO- http://172.30.217.209:5000/nix-cache-info
```

Observed: apply added nftables to the profile; setup installed the
restrictions and socket and the check passed. The rerun changed nothing.
`127.0.0.1` and `[::1]` were served; connections from 172.30.217.209 and
from fe80::215:5dff:fe8d:a4b9 were dropped and counted. As `nidrew`, a
locally built path was substituted into a fresh store with the Harmonia key
and refused ("lacks a signature by a trusted key") with only the upstream
key. From Windows the script reported `http://172.30.217.209:5000` with the
public key and `Reachable: True`; the `wslc` container fetched
`nix-cache-info`. Stopping `harmonia-firewall.service` also stopped the socket
and service and removed the table, so nothing listened; setup restored them.
Deleting the table with `nft` left the socket listening: the check failed
three items, including non-allowed sources being served, and the printed
restore command fixed it. `--port 5001` moved the listener and rules and the
check passed; returning to 5000 did the same.

First attempt: the IPv6 rejection probe bound `--interface` to the
link-local address and failed before reaching the rule (fixed in 2f7961e).

Not performed: a client on another LAN host (none available; NAT mode gives
the LAN no route to Debian), a Windows port proxy, mirrored networking, a
substitution by Nix inside a container (needs agent images), per-agent
access, and restrictions after a Debian restart (item 8).

What can be skipped: readers do not need to discover the container source
address again on WSL NAT mode, use IPv6 global addresses, or bind the socket
to the Debian address.

## 2026-10-25: Harmonia service and signing key (checklist item 5)

Environment: as for item 4; systemd 257. Harmonia 3.1.0 from the server lock.
Key `nidrew-pling-1:0ExDE4UoQWcn7UhE5Jr7xesP+FsJS17leDIJnm5FWG0=` (public).

Checks performed:

```sh
scripts/server/tests/setup-harmonia-test.sh      # 33 passed
scripts/server/tests/apply-nix-config-test.sh    # 23 passed after the refactor
sudo bash /home/nidrew/nidrew/scripts/server/setup-harmonia.sh       # twice
sudo bash /home/nidrew/nidrew/scripts/server/check-harmonia.sh --restart
# move secret-key aside, restart, check; move it back, wait 8 s, check
```

```powershell
# throwaway key and target, as peijen in /tmp
harmonia-key-recovery.ps1 -Action Save|Restore -LinuxUser peijen -KeyPath ... -Target nidrew-test-recovery
```

Observed: setup created `harmonia` (uid 994, `/usr/sbin/nologin`, only group
`harmonia`), generated the key (root:root 0600) and public key, and started
the socket-activated service on `127.0.0.1:5000` only. As `nidrew`, `nix store
verify` of the locally built `nidrew-server` path from the cache passed with
the public key and reported "untrusted" with only the upstream key. Neither
`nidrew` nor `harmonia` could read the key file; the key value was absent from
the units, configuration, and journal. Reruns kept the key and changed nothing;
`--restart` served again from the Debian key copy. With the key moved aside the
service failed at step CREDENTIALS ("Protocol error", status 243) and the check
failed; restoring it recovered the service within 8 s without intervention.
The Credential Manager round trip restored identical bytes with mode 0600 and
refused to replace an existing file.

Failed first attempts: without `RestartSec`, the missing-key test hit the start
limit, failed `harmonia.socket`, and the restart after restoring the key was
refused (fixed in 6595a9e). The check then hung in `curl` against the held
socket (fixed in 7f42446). The first recovery script added a byte order mark
to the restored key.

Afterwards the user saved the real key with `-Action Save` (as root, target
`nidrew-harmonia-secret-key`).

Not performed: restoring the real key from Credential Manager, rotation,
conflicting existing `harmonia` accounts, and a Debian restart (item 8).
Harmonia warns that the systemd credential copy has mode 0440; it is visible
only inside the service.

What can be skipped: readers do not need `harmonia-daemon` or a Nix daemon
socket for the cache, or `DynamicUser`.

## 2026-10-25: Server Nix configuration and packages (checklist item 4)

Environment: as for item 3. Locked `nix/server/flake.nix` to the newest
`nixos-26.05` commit, `1f607aa79b6356ed45d3cd3c8079c196e79efa2c`
(narHash `sha256-Mg3rRjsb...P9eg=`, lib.version 26.05pre-git): Harmonia 3.1.0
and Skopeo 1.22.2, both substituted from `cache.nixos.org`. Test image:
busybox 1.37.0 index `sha256:bdf57e52...f82e` (amd64 manifest
`sha256:66a6306d...86e4`).

Checks performed:

```sh
scripts/server/tests/apply-nix-config-test.sh    # 23 passed
sudo -u nidrew -i bash /home/nidrew/nidrew/scripts/server/sync-checkout.sh --revision 72b52ea
sudo bash /home/nidrew/nidrew/scripts/server/apply-nix-config.sh   # twice
# append '# local edit' to /etc/nix/nidrew.conf, apply again, restore with cp -p
sudo bash /home/nidrew/nidrew/scripts/server/check-nix-config.sh
```

Observed: the first apply installed `nidrew.conf` and `registry.json`, added
the include to `nix.conf` (previous copy retained), restarted the daemon, and
built the `nidrew-server` profile; all checks passed. Effective settings for
`nidrew` matched the template; `flake:nixpkgs` and `<nixpkgs>` resolved to the
locked revision with no channels; a sandboxed build as `nidrew` succeeded; as
`nidrew`, Skopeo inspected the digest-pinned image and copied it to an `oci:`
layout in a temporary directory. The rerun reported every step unchanged. The
local edit was refused with nothing changed; after restoring the file the
check passed again. The file tests cover template updates, unexpected files,
`nix.conf` conflicts, resumption, and invalid settings.

Not performed: `update-server-lock.sh` was not run against a newer revision;
template updates, unexpected files, and `nix.conf` conflicts were exercised
only by the file tests, not on `/etc/nix`. The daemon check compares its start
time with configuration file times, so touching a file without changing it
requires a daemon restart.

What can be skipped: readers do not need channels, `NIX_PATH`, or a separate
registry pin; `apply-nix-config.sh` derives the registry from the lock.

## 2026-10-25: Pinned multi-user Nix (checklist item 3)

Environment: as for item 1. Selected Nix 2.35.4, the newest release listed at
`https://nix-releases.s3.amazonaws.com/?prefix=nix/` on this date. Installer
SHA-256 `118c3dfa...1ee1` matched the published `install.sha256`; the embedded
x86_64-linux tarball hash `ff66236d...18c3` matched the downloaded tarball.

Checks performed:

```sh
scripts/server/tests/fetch-nix-installer-test.sh   # 7 passed
scripts/server/tests/bootstrap-nix-test.sh         # 6 passed before install
sudo bash scripts/server/bootstrap-nix.sh --release-file /tmp/nidrew-bad-release.conf
sudo bash scripts/server/bootstrap-nix.sh
bash scripts/server/bootstrap-nix.sh               # rerun as peijen
```

Observed: with an all-zero pinned checksum, bootstrap as root refused with
"checksum mismatch" before running anything and no `/nix` was created. The
real run installed Nix 2.35.4; `check-nix.sh` passed: socket enabled and
active, service linked and active, `nixbld` gid 30000 with 32 members,
`trusted-users = root`, `sandbox = true`, `nidrew` on `Store URL: daemon` with
`Trusted: 0`, and a sandboxed `/bin/sh` derivation built as `nidrew` without
sudo. `nix` is on `nidrew`'s login PATH. The installer wrote only
`build-users-group = nixbld` to `/etc/nix/nix.conf` and backed up
`/etc/bash.bashrc`. The rerun reported "nothing to install". After
installation the non-root bootstrap tests skip because `/nix` exists.

Not performed: the leftover, other-version, and single-user refusals were
reviewed in code only; no partial installation was created on the host.

What can be skipped: readers do not need to verify the tarball separately or
add channels; item 4 applies the Nix settings and the pinned registry.

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
