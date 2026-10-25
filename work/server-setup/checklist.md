# Implementation Notes

Follow [plan.md](plan.md) and the plan-implement skill. Implement one numbered
item per session on the work stream's implementation branch. Use
red-green-refactor for testable behavior changes and verify actual infrastructure
behavior. Each item creates or extends reproducible scripts in `scripts/host/`
and/or `scripts/server/`, reusing existing entry points where appropriate.
Keep privileged commands and interactive actions explicit for the user, and
verify their results before continuing dependent work. Preserve unrelated edits.

Leave each Summary and Done empty until implementation. Then record actual
changes and verification in Summary, commit the implementation, and put its
commit hash in Done. Commit the checklist update separately. Keep Done empty
for incomplete work; document pending manual verification accurately.

## Journal Continuation for Claude

When Claude starts implementing this checklist, create
`work/server-setup/journal-2.md` and write implementation lessons there. Keep
`journal.md` as the planning history and add a short continuation link to it.
Start the new file with a concise findings summary and add dated entries only
for meaningful results, including tested versions, evidence, limitations, and
what reproducing users can skip. Continue with `journal-3.md` and later files
when needed to keep journals small; link each continuation. Promote settled
instructions into setup documentation rather than making users read the logs.

# 1. Establish host and server prerequisite checks

- Create thin Windows preflight and directly invocable Debian checks. Accept a
  distribution parameter defaulting to `Debian` and report WSL, Debian, Bash,
  systemd, Git, and download/verification tool availability and versions.
- Distinguish missing Windows permissions, Linux sudo access, and restrictions
  of the agent session. Document administrator commands and required manual
  actions without assuming the invoking Windows user is an administrator.
- Check the source repository and selected committed revision; explain that
  uncommitted source edits will not reach the server clone.
- Verify useful failure output for missing prerequisites and unavailable host
  service inspection, then run the checks on this machine from the proper
  Windows and Debian contexts. Record unperformed checks explicitly.

## Summary

- Added `scripts/host/check-prerequisites.ps1` (`-Distribution Debian`,
  `-Source`, `-Revision`): reports Windows, PowerShell, elevation (not
  required), WSL version (minimum tested 3.0.3; `wslc` needs 2.9 or later),
  distribution presence and WSL 2, and Task Scheduler
  query access, then runs the Debian check through `wsl.exe --exec`.
- Added `scripts/server/check-prerequisites.sh` (`--source`, `--revision`):
  reports Debian, WSL kernel, Bash, systemd as PID 1 and system state, Git,
  curl, sha256sum, tar, xz, sudo access, and the source repository, selected
  commit, and uncommitted edits that will not reach the server clone. Missing
  items print exact manual actions; exit 1 on missing requirements.
- Distinguished session restrictions (no_new_privs, system bus denied) from
  missing sudo access or a password requirement.
- Found that Linux Git reports a Windows CRLF checkout as fully modified; the
  check uses `git diff` with `core.autocrlf=true`. Added `.gitattributes` to
  keep `*.sh` LF in the Windows checkout. Added `scripts/README.md`.
- Verification: `scripts/server/tests/check-prerequisites-test.sh` passes 12
  tests in Debian, including stubbed failure output. The host check passed on
  this machine and failed usefully for an unknown distribution. Not performed:
  interactive sudo, a real restricted session, or a Windows user without Task
  Scheduler access. Details in [journal-2.md](journal-2.md).

## Done

8b30ffe, 00ef72f

# 2. Provision the operational account and Linux-native checkout

- Add rerunnable account and storage setup for `nidrew`, `/home/nidrew/nidrew`,
  and `/home/nidrew/artifacts`, without general sudo or Nix trusted privileges.
- Clone the configurable source, currently `/mnt/c/projects/nidrew`, into the
  server checkout with independent Git data. Fetch and select an explicit
  committed revision; preserve source files, local work, and conflicting state.
- Provide the initial invocation from the source checkout so provisioning does
  not depend on a server clone that does not exist yet. Document required
  administrative commands and narrowly scoped source access.
- Verify ownership, clone/fetch access as `nidrew`, the selected revision,
  matching-state reruns, and refusal to discard local changes.

## Summary

- Added `scripts/server/provision-account.sh` (root; `--source`,
  `--revision`): creates `nidrew` with a locked password and no sudo,
  `/home/nidrew` (0700) and `/home/nidrew/artifacts` (0750), refuses on another
  home, administrative groups or sudo rules, or wrongly owned directories, then
  runs the sync as `nidrew`. Without root it prints the exact sudo command.
- Added `scripts/server/sync-checkout.sh` (`nidrew`; `--source`, `--checkout`,
  `--revision`): `--no-local` clone with independent objects, fetch into an
  existing clone, detached checkout of the selected commit recorded as
  `refs/nidrew/selected`. Refuses other content at the path, another origin,
  uncommitted changes, in-progress operations, and orphaning commits; reports
  uncommitted source edits that are not transferred.
- Source access: Git refuses a source owned by another user in `upload-pack`
  and drops `-c` settings there, so the clone stores a trusting
  `remote.origin.uploadpack`; no global Git configuration. The server keeps
  the default writable `/mnt/c` mount by decision.
- Added `scripts/server/check-account.sh` (root, read-only) and documented the
  workflow in `scripts/README.md`.
- Verification: 15 sync tests and 2 non-root provisioning tests pass. On this
  host, provisioning selected 2b54b90; `check-account.sh` passed; a matching
  sync and provisioning rerun changed nothing; local changes were refused and
  kept. Conflict refusals in provisioning were not exercised on the host.
  Details in [journal-2.md](journal-2.md).

## Done

37ccdc6, 2b54b90, 974ac2d

# 3. Bootstrap pinned multi-user Nix

- Select a supported upstream Nix release and record its artifact URL and
  verified checksum. Implement download verification before execution, using
  the upstream shell installer for multi-user installation.
- Inspect existing installations and partial state; preserve compatible setup
  and explain conflicts instead of reinstalling blindly. Document the exact
  user-performed privileged installation command and how to resume afterward.
- Verify checksum mismatch rejection before installer execution, daemon and
  build-user setup, and an ordinary build as `nidrew` without sudo or trusted
  privileges. Record the actual installed version and relevant results.

## Summary

- Added `scripts/server/nix-release.conf` pinning Nix 2.35.4: installer URL,
  installer SHA-256 (matches the published `install.sha256`), and for
  reference the x86_64-linux tarball hash the installer embeds and checks.
- Added `scripts/server/fetch-nix-installer.sh` (any user): downloads over
  https only, keeps the installer only on a checksum match, never runs it.
- Added `scripts/server/bootstrap-nix.sh` (root): verifies the pinned version
  when installed; refuses another version, a single-user installation, or
  partial-installation leftovers without changes, listing the paths and the
  uninstall guide. Otherwise fetches, verifies, and runs
  `install --daemon --yes --no-channel-add`. Without root it prints the sudo
  command without downloading.
- Added `scripts/server/check-nix.sh` (root): version, daemon units, `nixbld`
  build users, `trusted-users = root`, sandbox, `nidrew` on the daemon store
  untrusted, and a sandboxed build as `nidrew` without sudo. Documented the
  workflow in `scripts/README.md`.
- Verification: 7 fetch and 6 bootstrap tests pass. As root on this host, an
  all-zero pinned checksum was refused before execution; the real run
  installed Nix 2.35.4 and `check-nix.sh` passed (32 build users, gid 30000);
  a rerun reported nothing to install. Leftover and other-version refusals
  were not exercised on the host. Details in [journal-2.md](journal-2.md).

## Done

6d7f1df

# 4. Lock server packages and apply explicit Nix configuration

- Define Harmonia and Skopeo using one pinned server nixpkgs input and commit
  its `flake.lock`, independent of future agent pins. Build from explicit locked
  inputs and expose a stable package location for service use.
- Apply server-wide `nix-command` and `flakes`, `sandbox = true`,
  `require-sigs = true`, and `accept-flake-config = false`. Configure upstream
  substitution and its key, with no self-Harmonia endpoint or extra trusted users.
- Install `/etc/nix/nidrew.conf` with one include in the existing configuration;
  align the system `nixpkgs` registry with the server lock. Track managed paths
  and last-applied checksums, preserve local edits, validate before activation,
  retain previous configuration, and resume verified partial installs.
- Provide an explicit package/bootstrap update workflow with verification and
  journaled versions. Keep normal setup from silently updating pins.
- Verify effective settings, registry alignment, a sandboxed build, conflict
  handling and reruns. As `nidrew`, use Skopeo to inspect and transfer a small
  known image to an isolated test destination; do not deploy agent images.

## Summary

## Done

# 5. Run Harmonia with protected signing credentials

- Provision a dedicated `harmonia` account and a validated systemd service
  using the pinned package. Verify required read access to store metadata and
  contents without store write access, sudo, or trusted-user privileges.
- Choose the protected root-owned signing-key path, provision the key once,
  and publish its public key. Deliver the key through `LoadCredential=` and
  preserve a valid key on reruns. Initially restrict listening to local access
  until the network controls in item 6 are ready.
- Document user-performed key provisioning, backup, recovery, deliberate
  rotation, and an optional Windows Credential Manager recovery copy. Keep
  secret values out of configuration, arguments, repository files, and logs.
- Verify that `nidrew` cannot read the key, missing credentials fail readiness,
  and Harmonia serves a signed store path after restarting without Windows
  reinjection. Check matching-state reruns and recovery instructions.

## Summary

## Done

# 6. Expose and verify the restricted cache endpoint

- Select and document the listen address and configurable default port for the
  actual WSL network path. Discover the current Debian address from Windows and
  publish the endpoint and public key for future deployment configuration.
- Implement Debian-side access restrictions for intended consumers, including
  IPv4 and IPv6, without replacing unrelated firewall configuration. Apply
  restrictions before exposing the listener beyond local access.
- Verify permitted access and rejection of unrelated clients from relevant
  network contexts. Use an isolated consumer to substitute a known signed path;
  verify rejection without the trusted key and with signature enforcement on.
- Document which tests await a future egress/agent deployment. Do not claim
  per-agent isolation has been verified in this server-only work stream.

## Summary

## Done

# 7. Register and verify the Windows login keepalive task

- Create or update one named Scheduled Task under the owning Windows user,
  triggered at that user's login. Run `wsl.exe` with the configured distribution
  and `--exec sleep infinity`; choose and document the Linux execution user.
- Resolve and record the remaining task name, restart-on-failure policy,
  execution time limit, and power settings. Support an indefinitely running
  task, prevent duplicate instances, and avoid assuming elevated Windows rights.
- Provide rerunnable registration, inspection, and manual start instructions.
  Preserve a conflicting task and explain the required resolution.
- Verify the actual task principal, action, trigger, and settings; confirm Debian
  and its services remain available after interactive shells close. Check login
  triggering and record observed restart, sign-out, sleep/resume, and explicit
  shutdown behavior. Arrange user-performed disruptive checks explicitly.

## Summary

## Done

# 8. Complete reproducible setup, recovery checks, and user documentation

- Connect the existing scripts into documented host setup and readiness entry
  points, preserving direct Linux invocation. Document parameters, prerequisites,
  selected source revision, versions, permissions, and all manual actions.
- Exercise the complete setup and a matching-state rerun on this instance;
  verify resumption after interruption and preservation of local configuration.
- With user-performed restart/login actions where required, verify that the
  keepalive starts Debian and Nix and Harmonia become ready. Repeat the signed
  cache check after restart and record actual outcomes and limitations.
- Publish the current reproduction path and checks so readers can skip the
  investigation history. Link scripts, endpoint/public-key output, update and
  recovery instructions, and relevant journal evidence. Clearly separate server
  results from the unimplemented container, CLI, and egress milestone criteria.
- Review every applicable behavior-contract item, report remaining limitations,
  and present the server work for user review. Do not declare GOAL.md complete.

## Summary

## Done
