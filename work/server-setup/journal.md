# Server Setup Journal

This file holds the planning history. Implementation lessons continue in
[journal-2.md](journal-2.md).

## Findings

- [Harmonia deployment](#2026-10-25-harmonia-deployment):
  use a dedicated service identity with read access and a restricted configurable
  endpoint discovered from Windows. Implementation and network checks are pending.
- [Configuration ownership](#2026-10-25-configuration-ownership):
  manage an explicit set of Nidrew files, preserve administrator configuration,
  detect local edits, and verify progress before resuming partial setup.
- [Server-wide Nix defaults](#2026-10-25-server-wide-nix-defaults):
  enable flakes and the modern CLI system-wide, require sandboxing and
  signatures, and align the system registry pin with the server lock.
- [Package layers and Nix settings](#2026-10-25-package-layers-and-nix-settings):
  keep runtime foundations in the base image, development tools in the agent
  image, and server packages and operational settings separate.
- [Credential and signing-key storage](#2026-10-25-credential-and-signing-key-storage):
  use Windows Credential Manager for agent tokens and protected Debian storage
  with systemd credential delivery for Harmonia's operational key.
- [Cache consumption topology](#2026-10-25-cache-consumption-topology):
  Debian uses upstream directly; containers try Harmonia before upstream.
  Harmonia serves the Debian store rather than fetching upstream misses.
- [Server storage and source checkout](#2026-10-25-server-storage-and-source-checkout):
  use a Linux-native clone at `/home/nidrew/nidrew` sourced from the current
  Windows checkout. Paths are decided; cloning and permissions are not tested.
- [Debian keepalive requirement](#2026-10-25-debian-keepalive-requirement):
  the user reports a Scheduled Task running `sleep infinity` in Debian is needed
  on this machine. Initial server setup now includes it; verification is pending.
- [Installation sources and version policy](#2026-10-25-installation-sources-and-version-policy):
  use the upstream Nix shell installer and a shared pinned server nixpkgs input
  for Harmonia and Skopeo. Exact versions and runtime verification are pending.
- [Initial inspection and account layout](#2026-10-25-initial-inspection-and-account-layout):
  the plan targets this Debian instance with a dedicated `nidrew` account.
  Tool installation and service health are not yet verified. Reproducers can
  reuse the account rationale but must inspect their own instance.

## 2026-10-25: Harmonia deployment

Question: how do the Harmonia service and cache exposure decisions relate?

Decision: the user accepted one deployment model covering both. Run Harmonia
as a dedicated `harmonia` account with required store and metadata read access,
its systemd-delivered signing credential, and no store writes, general sudo, or
Nix trusted-user privileges. Expose one configurable port to intended consumers
through explicit Debian service access, blocking unrelated LAN clients. Windows
automation discovers the Debian address and supplies the endpoint to deployment.

Reason: local permissions limit what the service can access; network rules limit
who can reach it. Package signatures establish trust but do not restrict
downloads. Debian-side service exposure belongs to server setup; per-agent grants
and routes belong to later egress work.

What can be skipped: readers accepting this deployment model can skip revisiting
the separation of service identity and client access. Exact permissions, listen
address, default port, and access rules still require implementation checks with
the pinned Harmonia version and actual WSL networking. No service or network
configuration was changed during this decision.

## 2026-10-25: Configuration ownership

Question: which configuration should Nidrew control, and how should setup
handle existing settings and interrupted runs?

Decision: the user accepted limited, explicit ownership. Commit defaults, pins,
and templates; accept machine-specific script parameters; preserve existing
administrator configuration and keep secrets separate. Use a dedicated Nix
include, a Harmonia unit, named systemd drop-ins, and the named Windows task.

Setup leaves matching state unchanged and updates previously managed files only
when unedited locally. Track managed paths and last-applied checksums. Stop
affected steps on unexpected files or edits with resolution instructions,
validate before activation, retain previous configuration for recovery, and
verify completed steps when resuming partial installs.

Reason: the setup needs to reproduce Nidrew settings without taking ownership
of the entire Debian instance or erasing another user's configuration.

What can be skipped: readers can reuse this ownership policy. Conflict handling,
validation, recovery, and partial-install resumption still require implementation
and tests; no system configuration was modified during this decision.

## 2026-10-25: Server-wide Nix defaults

Question: should the dedicated server use system-wide Nix defaults or scope
CLI settings and the registry pin only to the `nidrew` account?

Reviewed the [Nix settings reference](https://nix.dev/manual/nix/2.30/command-ref/conf-file)
and [registry documentation](https://nix.dev/manual/nix/2.25/command-ref/new-cli/nix3-registry).
No configuration was installed or build performed during this decision.

Decision: the user selected system-wide defaults for this dedicated server.
Enable `nix-command` and `flakes`, set `sandbox = true`, require signatures,
leave automatic flake configuration acceptance disabled, and add no trusted
users. Pin the system `nixpkgs` registry to the server lock and update both
together. Build scripts use explicit locked inputs.

Reason: system-wide defaults reduce configuration contexts to operate and
troubleshoot. Account-scoped settings would better preserve unrelated users'
CLI defaults but add complexity unnecessary for the chosen server role.

What can be skipped: readers accepting the dedicated-server scope can reuse
these settings without revisiting their scope. They still need to inspect
effective settings, resolve conflicts, and verify sandboxed builds and registry
alignment. This resolves the earlier entry's pending server-settings decision.

## 2026-10-25: Package layers and Nix settings

Question: should the base include tools such as ripgrep, or should they belong
to the agent layer?

Decision: the user accepted a minimal base containing runtime foundations, with
Git, ripgrep, editors, other development tools, and the three CLIs in the agent
layer. Server packages remain independent. This supersedes the README's earlier
placement of basic development tools in the base.

Lesson: package selection and Nix operational settings are separate concerns.
Server and container settings differ in daemon mode and cache topology, so keep
their configurations explicit. No images or settings were implemented or tested.

What can be skipped: readers can reuse this package boundary. Exact tool lists
still need selection and verification during image implementation. The later
[server-wide defaults decision](#2026-10-25-server-wide-nix-defaults) resolves the
server-settings question that was open at this point.

## 2026-10-25: Credential and signing-key storage

Question: can Windows Credential Manager or Apple Passwords hold credentials
and the Harmonia signing key?

Reviewed the [Windows credential retrieval API](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw),
[Apple Passwords on Windows](https://support.apple.com/guide/icloud-windows/manage-passwords-icwa812f1681/icloud),
and [systemd service credentials](https://systemd.io/CREDENTIALS/). Windows
provides retrieval under the current logon context. Apple's documentation
describes interactive password access; no general scripted retrieval interface
was established in this review. No secret was read or provisioned.

Decision: the user accepted Windows Credential Manager for agent tokens and a
protected root-owned persistent Debian signing key delivered to Harmonia through
`LoadCredential=`. A Windows Credential Manager recovery copy is optional.
Apple Passwords can support human login preparation but will not be required by
automated startup.

Reason: a Windows-only runtime key would require reinjection after Debian shuts
down. A protected Debian copy allows independent service restarts while keeping
the key inaccessible to the routine build account.

What can be skipped: readers can reuse this storage model without evaluating
Apple Passwords automation. They must still verify credential permissions,
service delivery, signed substitution, and restart behavior. The exact key path
and lifecycle procedures remain implementation follow-up, not a tested setup.

## 2026-10-25: Cache consumption topology

Question: should both Debian and containers consume Harmonia as a cache in front
of upstream?

Reviewed [Harmonia's documented store-serving behavior](https://github.com/nix-community/harmonia)
and [Nix's prioritized substituter configuration](https://nix.dev/guides/recipes/add-binary-cache.html).
Harmonia serves the existing Debian store; it is not an upstream-fetching cache.
Debian already has direct access to that store, so consuming its own endpoint
does not add reuse. No cache topology was deployed or tested in this session.

Decision: the user accepted Debian using its local store and `cache.nixos.org`,
while containers try Harmonia first and upstream through egress second. Debian
trusts the upstream public key; containers trust upstream and the dedicated
Harmonia key. Container-only downloads are not automatically retained on Debian.
Defer an additional fetch-and-retain mechanism until repeated downloads show a
meaningful cost.

What can be skipped: readers can skip testing Debian's own Harmonia endpoint as
a way to improve cache hits in that same store. They still need to verify signed
substitution from a separate consumer and upstream access. Do not assume a
container download warms the shared cache.

## 2026-10-25: Server storage and source checkout

Question: where should the operational account, source checkout, and build data
live, and how should source reach Debian?

Reviewed the [Filesystem Hierarchy Standard](https://specifications.freedesktop.org/fhs/latest/)
and [Microsoft's WSL filesystem guidance](https://learn.microsoft.com/en-us/windows/wsl/filesystems).
These inform directory roles and the preference for Linux-native storage when
using Linux tools. This was documentation research, not a storage benchmark.

Decision: the user accepted the proposed directory layout and specified that
`/mnt/c/projects/nidrew` should be Git-cloned into Debian. Use
`/home/nidrew/nidrew` for that clone and `/home/nidrew/artifacts` for deliberate
exports. Keep Nix builds in `/nix/store`, configuration under `/etc`, and service
state and caches under their respective `/var` directories. The full layout is
recorded in the [README](../../README.md#server-accounts-and-storage).

Lesson: a server clone provides a committed source snapshot on the Linux
filesystem; it does not transfer uncommitted Windows checkout edits. Explicitly
select the build revision and preserve local work when refreshing the clone.

What can be skipped: readers accepting the layout can reuse these paths and
configure their own source repository path. They still need to verify clone and
fetch permissions, ownership, and the selected revision. No clone or directory
creation was performed as part of this documentation decision.

## 2026-10-25: Debian keepalive requirement

Question: is Debian server keepalive already captured in the initial setup?

Evidence: the user reports finding that a Windows Scheduled Task executing
`sleep infinity` in Debian is needed to keep this instance running. The README
previously mentioned a possible sign-in task only under v2, and this plan
excluded automatic sign-in startup. No task inspection or runtime test was
performed in this session; the WSL version and exact working settings remain
to be recorded.

Decision: include the Debian keepalive task in initial server setup, using
`wsl.exe --distribution <DebianDistribution> --exec sleep infinity` under the
owning Windows user's credentials. The user subsequently specified that the
trigger is that user's Windows login and the current distribution is `Debian`.
Use `wsl.exe --distribution Debian --exec sleep infinity` here, keeping the
distribution configurable. Keep automatic egress startup in v2.

Lesson: enabling Linux services and keeping their WSL instance alive are
separate requirements. Verification must cover availability after interactive
shells close, as well as recovery at the configured task trigger.

What can be skipped: readers can reuse the intended keepalive approach, but
cannot skip checking task settings and behavior on their WSL version. Restart,
sign-out, and power-state behavior remain unverified. See the plan's
[open questions](plan.md#open-questions).

## 2026-10-25: Installation sources and version policy

Question: which installation sources provide a reproducible server baseline
without adding unnecessary maintenance work?

Reviewed the [upstream Nix installation guidance](https://nixos.org/download/),
[Harmonia documentation](https://github.com/nix-community/harmonia), and Debian's
[Nix](https://packages.debian.org/trixie/nix-bin) and
[Skopeo](https://packages.debian.org/trixie/skopeo) package information. Compared
a Nix-centered approach with Debian-centered and mixed installation sources.
This was documentation research, not an installation test.

Decision: the user selected the upstream multi-user Nix shell installer and
Harmonia and Skopeo from one pinned nixpkgs revision. Pin the Nix bootstrap
release and download checksum, commit the server `flake.lock`, keep server and
agent pins independently updateable, and make updates explicit with checks and
a record of tested versions. Privileged installation remains a documented
user-performed step.

Reason: one locked definition for the server tools gives future readers a known
baseline, while the upstream installer provides the Nix bootstrap. Debian
service integration remains our responsibility; NixOS service-module examples
do not configure a Debian host directly.

What can be skipped: readers following this approach can skip comparing package
sources. They must still verify bootstrap downloads and run the applicable setup
checks. No exact release, checksum, or nixpkgs revision has been selected or
tested yet; see [the plan](plan.md#open-questions).

## 2026-10-25: Initial inspection and account layout

Question: what is already available on this instance, and which account should
own routine Nidrew server work?

Environment: inspection reported Debian 13 (trixie), x86_64, and WSL2. The agent
session runs under restrictions that limit host service inspection.

Checks performed:

```sh
cat /etc/os-release
uname -a
cat /etc/wsl.conf
command -v nix harmonia skopeo systemctl
dpkg-query -W nix-bin skopeo harmonia
systemctl is-system-running
```

Observed: WSL configuration enables systemd, and `systemctl` is on PATH. Nix,
Harmonia, and Skopeo were not found on the session's PATH; targeted package
queries did not report them installed. The systemd query failed because access
to the system bus was denied. These observations do not rule out installations
elsewhere or establish that host services are unhealthy.

Decision: use the existing account for administration, a dedicated `nidrew`
account for routine work without general sudo or Nix trusted-user privileges,
and multi-user Nix on Debian. This separates ownership without introducing
another WSL distribution. See [the plan](plan.md#approaches) for alternatives
and [open questions](plan.md#open-questions) for unresolved implementation details.

Lesson: distinguish restrictions of the inspecting session from failures of the
server. Repeat service checks from an authorized host context before diagnosing
or changing systemd configuration.

What can be skipped: readers accepting this account layout can skip reconsidering
the three account/instance alternatives. They still need to check their own
installed tools, service status, and permissions. No installation procedure or
working cache has been validated yet.
