# Server Setup

## Problem

This WSL Debian instance needs to serve as Nidrew's persistent Linux server.
README.md defines the intended architecture, but this repository does not yet
provide the setup for its build and cache services. Routine server work also
needs an owner separate from the user's personal account.

## Desired Result

Prepare this instance to build Nidrew images and serve its Nix store through a
signed binary cache. Provide repeatable setup and verification for a dedicated
`nidrew` account, multi-user Nix, Harmonia, and Skopeo. Record required manual
actions and any limitations.

Keep a concise journal of lessons and evidence so a future GitHub reader can
reproduce the setup and decide which exploratory work they can skip.

This work prepares the server side of the first milestone in GOAL.md; it does
not complete the full milestone or change its objective.

## Scope

### In Scope

- Configure this existing WSL Debian instance rather than create another one.
- Create the `nidrew` account and define ownership and permissions for routine
  server work, build outputs, and working directories.
- Git-clone `/mnt/c/projects/nidrew` into `/home/nidrew/nidrew`, owned by
  `nidrew`, with a configurable source path for other users. Keep Linux build
  data on Debian's filesystem and preserve the source checkout.
- Install and configure multi-user Nix, including the daemon and build users.
- Install and configure Harmonia as a persistent service with a dedicated
  signing key and an explicitly published public key.
- Provision the signing key once in protected root-owned Debian storage and
  deliver it to Harmonia through systemd `LoadCredential=`. Document optional
  Windows Credential Manager recovery storage and key lifecycle procedures.
- Install Skopeo for later image inspection and transfer workflows.
- Bootstrap Nix with a pinned upstream shell installer release and verified
  download checksum. Define Harmonia and Skopeo together using a committed
  server `flake.lock` that pins their nixpkgs revision.
- Configure Debian Nix to use `cache.nixos.org` and its trusted public key,
  without its own Harmonia endpoint as a substituter. Document the Harmonia
  endpoint and public key that future agent configuration will consume.
- Deliver reproducible setup and readiness checks with Windows PowerShell entry
  points under `scripts/host/` and Linux Bash scripts under `scripts/server/`.
  Each implementation task creates or extends the relevant scripts, with Debian
  owning the substantive logic.
- Verify account permissions, builds, signed cache use, image-tool readiness,
  and service recovery after a Debian restart.
- Provide a Windows Scheduled Task under the owning Windows user's credentials
  that runs `wsl.exe --distribution <DebianDistribution> --exec sleep infinity`
  to keep the server instance running. Include task setup and verification in
  the host scripts and document required manual actions.
- Preserve `journal.md` as planning history. When Claude starts checklist
  implementation, create `journal-2.md` for implementation lessons and link the
  continuation. Keep numbered continuations small, with a findings summary,
  dated evidence, failed approaches, and conditional guidance on what can be skipped.
  Turn settled results into current setup instructions for future users.

### Out of Scope

- Base, egress, or agent image definitions and builds for deployment.
- Agent YAML contracts, CLI authentication, and Windows Credential Manager
  integration.
- Egress networking, agent service grants, and container deployment through
  `wslc`.
- Container entry, restart, push, and teardown workflows.
- Another WSL distribution or a general-purpose server provisioning framework.
- Automatic startup of egress or agent containers at Windows sign-in, cache
  retention and garbage-collection policy, resource limits, and other README
  roadmap items. Debian server keepalive is in scope.
- Pull-through caching or automatic retention on Debian of packages downloaded
  only inside containers.
- Changes to AGENTS.md or the objective in GOAL.md.

## Constraints

- Follow README.md and AGENTS.md. Keep persistent services outside disposable
  agent containers.
- Use the existing account for administration through sudo. Routine `nidrew`
  work must not require general sudo or membership in Nix's `trusted-users`.
- Windows PowerShell runs as the invoking Windows user using that user's
  credentials. The user of this machine reports administrator rights; do not
  assume other users have Windows administrator rights or Linux sudo access.
  Check and document the required permissions separately for each environment.
- Explicitly document user-performed sudo commands and interactive login flows,
  including the execution environment, reason, and verification. Required manual
  actions must be completed and verified before dependent steps continue.
- Keep the Harmonia signing key out of the routine build account, repository,
  images, generated public configuration, and logs. Give required service
  identities only the access they need.
- Keep build and setup logic in Debian scripts; keep Windows automation thin.
- Make service exposure, directories, permissions, and privileged actions
  explicit. Do not grant agent access as part of server setup.
- Preserve the existing user's environment and unrelated repository changes.
- Use ASCII in repository-authored text. Test behavior changes through
  red-green-refactor where applicable and verify actual infrastructure behavior.
- Follow supported installation and service interfaces. Use the upstream Nix
  shell installer and pinned nixpkgs for Harmonia and Skopeo; select and record
  the exact release, download checksum, and nixpkgs revision during implementation.
- Keep server and agent package pins independently updateable. Setup must not
  silently update them; changes are explicit and followed by relevant checks
  and a journal entry recording tested versions and results.

## Current State

- README.md describes the intended system; setup scripts and runtime definitions
  are not implemented in this repository.
- Inspection reports Debian 13 (trixie), x86_64, on WSL2.
- `/etc/wsl.conf` contains `[boot]` with `systemd=true`.
- The current session runs as `peijen`.
- `nix`, `harmonia`, and `skopeo` were not found on this session's PATH. Targeted
  Debian package queries did not report installed packages with those names.
  Installation elsewhere has not been ruled out.
- The session cannot access the system systemd bus. Service health and actual
  host configuration still require verification from an authorized host context;
  this restriction is not evidence that systemd is broken.
- The user reports that this machine needs a Windows Scheduled Task running
  `sleep infinity` in Debian to keep it available. Task configuration, WSL
  version, and behavior have not been independently verified in this session.
- Existing unrelated edits in LICENSE and todo/brainstorming.md must be preserved.

## Gap

The instance has not been verified as a working Nidrew server. It needs a
dedicated operational identity, defined storage ownership, installed tools,
managed services, cache signing and trust, and repeatable readiness checks.
Installation details and service exposure remain to be settled.

## Behavior Contract

### Existing behavior that must remain valid

- The existing user can continue using and administering this Debian instance.
- Existing WSL configuration and personal files remain intact except for
  explicitly required and documented server configuration changes.
- Existing repository content and unrelated edits remain intact.

### Existing behavior that changes

- Routine Nidrew server work uses `nidrew` rather than the personal account.
- Server builds use committed revisions in the Linux-native clone at
  `/home/nidrew/nidrew` rather than the Windows-backed source checkout.
- Debian gains the Nix daemon, a managed Harmonia service, Skopeo, and the
  configuration needed to use them.

### New behavior

- `nidrew` can perform an ordinary Nix build without sudo; the daemon executes
  builds using dedicated build users.
- The server checkout is a Git clone of the selected source repository, owned
  by `nidrew`. Setup records the selected commit and never treats uncommitted
  source edits as transferred. Reruns preserve local work and explain checkout
  conflicts instead of discarding changes.
- Bootstrap verifies the pinned Nix release download before execution and
  rejects a checksum mismatch. Harmonia and Skopeo resolve from the committed
  server nixpkgs lock rather than a moving channel or an unpinned reference.
- Repeated setup preserves the selected versions. The explicit update workflow
  changes the intended pins, runs relevant checks, and records tested versions
  and results without changing agent package pins as a side effect.
- Effective server-wide Nix settings enable `nix-command` and `flakes`, require
  build sandboxing and signatures, and disable automatic acceptance of
  flake-provided configuration. No additional trusted users are granted.
- The system `nixpkgs` registry entry matches the committed server lock and is
  updated with it. `nix-path = nixpkgs=flake:nixpkgs` makes legacy `<nixpkgs>`
  lookups, such as `nix-shell -p`, resolve through that entry; no channels are
  added. Build scripts use explicit locked inputs independently of
  registry shorthand and `<nixpkgs>`. Conflicts with existing configuration are reported rather
  than silently overriding local settings or weakening the required behavior.
- `nidrew` can inspect and transfer images with Skopeo to an explicitly selected
  test destination without general administrative access.
- Harmonia serves an existing test store path as a signed cache entry. A fresh
  consumer using the published public key can substitute that path; a consumer
  without the trusted key rejects its untrusted signature when signature
  enforcement is enabled.
- Debian uses local store paths directly and fetches available substitutes from
  `cache.nixos.org`, trusting its public key. Its substituter configuration does
  not include its own Harmonia endpoint. Harmonia exposes paths already in the
  Debian store without fetching upstream misses.
- The routine build account cannot read the cache signing key.
- Harmonia receives its signing key through systemd credentials and can restart
  using the persistent protected Debian copy without Windows reinjection. A
  missing or unreadable key prevents successful readiness reporting. Generated
  service configuration contains only the key reference, not its value.
- Harmonia runs as `harmonia`, with only required store and metadata read access,
  its systemd signing credential, and no store write access, general sudo, or
  Nix trusted-user privileges. Debian-side network rules restrict the configured
  cache port to intended consumers and block unrelated LAN access. Host scripts
  discover the Debian address and publish the endpoint for later deployment.
- Setup can be rerun without duplicating accounts, replacing a valid signing
  key, or overwriting unrelated configuration. Conflicting state produces an
  actionable explanation.
- Setup preserves matching configuration and detects local edits using managed
  paths and last-applied checksums. Unexpected files or edits stop the affected
  step with a conflict description and resolution instructions. Validate changes
  before activation, retain previous managed configuration for recovery, and
  verify completed steps before resuming a partial installation.
- Readiness checks report tool versions, daemon and cache availability, and
  failures without disclosing secrets.
- Required services become usable after a Debian restart. Verification records
  the actual result and any manual recovery needed.
- Host setup creates or updates the Debian keepalive task without duplicate
  tasks. Checks confirm it targets the intended distribution and owning Windows
  user, remains running after interactive shells close, and restores server
  availability at its configured trigger. Document task settings, tested WSL
  versions, and behavior across restarts. Do not claim it prevents explicit WSL
  shutdown or Windows shutdown.
- Documentation identifies the cache endpoint and public key, how to invoke
  setup and checks, and which steps need administrator or Windows access.
- A Windows reproducer can run PowerShell entry points under `scripts/host/` to
  perform the implemented setup and verify its result. Linux users can invoke
  the Bash scripts under `scripts/server/` directly without PowerShell. Their
  documentation states prerequisites, parameters, required privileges, and
  manual actions, including Debian-specific requirements. Rerunning them is
  safe, and failures explain what needs attention.
- A reader can follow the current setup instructions without reading the full
  investigation history. Journal entries identify tested versions, reproducible
  checks, unverified assumptions, and conditions for reusing or revisiting results.
- Checks distinguish missing Windows permissions, missing Linux sudo access,
  and restrictions of the agent session. Missing privileges produce specific
  administrator instructions while identifying which steps can still run.
- Required manual steps are listed with exact commands or login actions and
  verification instructions. Setup does not report success for steps waiting on
  user action. CLI login integration remains outside this work stream, but the
  same manual-action convention applies when that integration is implemented.

## Approaches

The account and instance layout discussion considered three approaches:

| Approach | Benefit | Tradeoff |
| --- | --- | --- |
| Use the existing personal account | Least initial configuration | Mixes server working files and configuration with personal work |
| Use a dedicated `nidrew` account in this instance | Clear ownership and predictable paths for automation | Requires explicit account and directory permissions |
| Create a separate WSL distribution | More separation from the development environment | Adds another Linux instance to provision and maintain |

Chosen direction: use a dedicated `nidrew` account in this instance. It provides
a useful ownership boundary without maintaining another distribution. It is not
the agent sandbox boundary; agent isolation remains the responsibility of the
future container and egress setup.

Installation approaches considered:

| Approach | Benefit | Tradeoff |
| --- | --- | --- |
| Upstream Nix bootstrap; pinned nixpkgs for Harmonia and Skopeo | Shared reproducible server tool definition | Requires explicit Debian service integration |
| Debian packages for Nix and Skopeo; Nix for Harmonia | Familiar Debian package administration | Multiple package sources and release schedules |
| Upstream Nix bootstrap; Nix for Harmonia; Debian Skopeo | Convenient native Skopeo installation | Exact tool reproduction spans APT and Nix |

Chosen direction: the Nix-centered approach with the upstream shell installer.
Harmonia and Skopeo share one pinned server nixpkgs input. This provides a known
baseline for reproducing the experiment. Alternative Nix installers were
discussed but are not part of the selected setup. Exact versions and service
configuration remain implementation questions.

## Decisions

- Prepare this existing WSL Debian instance as Nidrew's persistent Linux server.
- Use limited, explicit configuration ownership: the repository owns defaults,
  pins, and templates; users supply machine-specific script parameters; the
  administrator owns existing system settings; secrets remain separate.
- Install Nix settings in `/etc/nix/nidrew.conf` with a single include in the
  existing `nix.conf`. Preserve unrelated settings, use a dedicated Harmonia
  unit and named drop-ins for installer-owned units, and manage only the named
  Nidrew Scheduled Task. Track managed paths and last-applied checksums rather
  than introducing a general configuration-management framework.
- Leave matching configuration alone. Update unchanged managed files, preserve
  local edits and unexpected files, and stop affected steps with resolution
  instructions. Validate before activation, retain the previous configuration
  for recovery, and verify progress when resuming partial installation.
- Include a Windows Scheduled Task running `sleep infinity` in Debian as part
  of initial server setup, based on the user's finding that it is needed to keep
  this instance running. Verify its behavior during implementation. Automatic
  egress and agent container startup remain separate work.
- Trigger the keepalive at the owning Windows user's login. Use
  `wsl.exe --distribution Debian --exec sleep infinity` on this machine, with
  the distribution name configurable for other users. This is the existing
  keepalive mechanism, not a separate supervisor or Linux service.
- Use a dedicated `nidrew` account for routine server work, without general sudo
  or Nix `trusted-users` access. Keep administration in the existing account.
- Use `/home/nidrew` for the account home, `/home/nidrew/nidrew` for the server
  checkout, and `/home/nidrew/artifacts` for exported images and build reports.
  These paths are owned by `nidrew` and live on Debian's Linux filesystem.
- Git-clone the current `/mnt/c/projects/nidrew` repository into that server
  checkout. Make the source path configurable for other users, transfer only
  committed changes through Git, and explicitly select the revision to build.
  Preserve the source checkout and grant only required clone/fetch access.
- Keep administrator-managed configuration in `/etc/nix/` and `/etc/harmonia/`;
  use service-owned `/var/lib/<service>/` for state and `/var/cache/<service>/`
  for regenerable caches where needed. Signing-key placement and permissions
  remain part of the Harmonia service decision below.
- Leave Nix-managed builds and store paths under `/nix/store`; copy deliberate
  exports to the artifacts directory. Use unique temporary directories under
  `/tmp`, or `/var/tmp` when files must survive reboot. Neither is durable
  storage. No `/srv/nidrew` directory is needed for this account's working files.
- Use multi-user Nix on Debian. The README's single-user Nix requirement applies
  inside agent containers, not to the persistent Debian server.
- Bootstrap Nix with the upstream shell installer, pinning the Nix release and
  verifying its download checksum before execution.
- Install Harmonia and Skopeo from the same pinned nixpkgs revision through a
  committed server `flake.lock`, independent of agent package pins.
- Update pins explicitly, verify the resulting setup, and journal tested
  versions and results. Document privileged installation as user-performed
  commands with verification.
- Use dedicated server-wide defaults rather than settings scoped only to
  `nidrew`: enable `nix-command` and `flakes`; set `sandbox = true`,
  `require-sigs = true`, and `accept-flake-config = false`; retain the agreed
  upstream cache trust without adding trusted users. Investigate sandbox
  failures instead of silently disabling sandboxing.
- Pin the system `nixpkgs` registry entry to the server lock's revision and
  update them together. Set `nix-path = nixpkgs=flake:nixpkgs` so legacy
  `<nixpkgs>` follows the same entry instead of a channel; bootstrap adds no
  channels. Use explicit locked inputs in build scripts. The
  server-wide scope simplifies operation on this dedicated instance; the
  alternative of account-scoped CLI defaults would preserve more independence
  for unrelated users but add configuration contexts to verify.
- Run persistent services under appropriate service identities; protect the
  cache signing key from routine build access.
- Treat Harmonia service permissions and cache exposure as one deployment
  decision. Use a dedicated `harmonia` account with required store and metadata
  read access, the agreed systemd credential, and no store write access, general
  sudo, or Nix trusted-user privileges.
- Expose one configurable cache port through explicitly permitted Debian
  service access. Discover the current Debian address in Windows automation
  and pass the endpoint to deployment instead of hardcoding WSL addresses.
  Restrict Debian-side access to intended consumers and block unrelated LAN
  clients; implement per-agent grants and routes in later egress work. Signing
  establishes package trust and does not replace network access restrictions.
- Store Harmonia's operational signing key in protected root-owned Debian
  storage, provisioned once, and pass it through systemd `LoadCredential=`.
  An optional recovery copy can live in Windows Credential Manager. Preserve
  valid keys on reruns and document provisioning, backup, recovery, and rotation.
- Keep agent tokens in Windows Credential Manager, with runtime references
  rather than secret values in configuration. Agent credential integration
  remains separate work. Apple Passwords can support manual login preparation
  but is not an automated secret source for startup.
- Debian uses its local store and `cache.nixos.org`, trusting the upstream key;
  it does not use its own Harmonia endpoint. Future containers try Harmonia
  first, then `cache.nixos.org` through egress, trusting the dedicated Harmonia
  key and upstream key. Container configuration remains separate work.
- Accept that container-only downloads do not populate Debian's store and can
  be repeated by other containers. Defer fetch-and-retain caching until measured
  repeated downloads justify the added mechanism.
- Keep image construction, container deployment, and egress implementation in
  separate work streams.
- Keep server package definitions separate from agent environments. Future
  image work uses a minimal runtime base and places Git, ripgrep, editors, and
  other development tools in the agent layer alongside the three CLIs. Share
  tool declarations across templates where useful. This records the boundary;
  image implementation remains out of scope.
- Treat Nix operational settings separately from package selection. Keep server
  and container configurations explicit rather than inheriting server settings
  into containers.
- Organize scripts by execution environment: Windows PowerShell in
  `scripts/host/`, Linux Bash in `scripts/server/`. Keep host entry points thin
  and server scripts directly invocable without PowerShell. This work targets
  Debian; support other distributions only when a concrete need arises.
- Host scripts use the invoking Windows user's credentials. Elevated Windows
  rights on this machine are not a prerequisite assumption for all users.
  Identify per-step permissions and explicitly hand off required manual sudo
  commands or login actions to the user, then verify the resulting state.
- Each implementation task creates or extends the scripts needed to reproduce
  its work. Reuse existing entry points when they cover a task. Procedures must
  not exist only in the journal or terminal history; link scripts and their
  verification results from the work stream's records.
- Use this plan as the local specification and decision record. Keep lessons and
  supporting evidence in `journal.md`, following README.md's Learning and
  Reproduction convention. Separate specs, ADRs, and RFCs are optional and should
  not duplicate the plan or journal.
- The user authorized decomposition into [checklist.md](checklist.md). Resolve
  the remaining keepalive task settings during its implementation item and
  record them here. Preserve planning history in `journal.md`; Claude starts
  implementation lessons in `journal-2.md` with a continuation link, using
  further numbered files as needed to keep journals small.

## Implementation and Verification Follow-up

These are follow-up tasks under the agreed decisions, not unresolved policy
choices:

- Map each step's Windows and Linux permission requirements. Host scripts run
  as the invoking Windows user; routine Linux work uses `nidrew`, and privileged
  setup is handed to the existing administrative account. Provide exact manual
  commands and resumable checks where the agent session cannot act.
- Verify that `nidrew` can clone and fetch from the configured source path,
  that the server checkout owns its own Git data, and that reruns preserve
  existing work. Check the intended commit before invoking server builds.
- Select and verify the exact Nix release, artifact checksum, and shared server
  nixpkgs revision during implementation. Record bootstrap metadata and commit
  the server lock. Provide explicit update and verification commands; do not
  revisit the agreed installation sources or update policy.
- Verify the effective server-wide Nix settings, a sandboxed build, signature
  enforcement, and the system registry's match with the server lock. Report
  conflicting existing overrides for administrator resolution.
- Implement and verify matching-state reruns, managed-file updates, local-edit
  conflict detection, and resumption after partial installation. Document the
  managed file set and recovery procedure. Use script parameters and defaults
  for machine-specific values; add a local settings file only if needed later.
- Choose a small test derivation, isolated consumer store, and Skopeo test
  destination that verify the behavior contract without relying on an already
  populated store or changing deployment state.
- Verify service readiness from Windows after a WSL restart. Document any
  user-performed restart commands and recovery actions.
- Verify the keepalive task without assuming Windows elevation. Record the WSL
  version and observed behavior after shells close, sign-out/sign-in,
  sleep/resume, and explicit WSL shutdown, including required manual recovery.
- Choose the protected Debian signing-key path and implement its provisioning,
  optional Windows recovery copy, backup, recovery, and deliberate rotation
  procedures. Verify systemd credential delivery, key permissions, and signed
  cache access after restarting Harmonia without Windows reinjection.
- Verify the pinned Harmonia version's store and metadata access requirements
  under the dedicated service identity without granting write or trusted-user
  privileges. Select the listen address and default configurable port for the
  intended WSL network path, implement endpoint discovery and Debian-side access
  restrictions, and verify permitted access and rejection of unrelated clients.
  Document the endpoint contract for later egress integration and identify any
  per-agent verification deferred until that integration exists.

## Open Questions

Only unresolved decisions are listed here. Move each answer into Decisions or
the relevant contract when agreed; keep pending checks in the follow-up above.

- Keepalive task: which Linux user, task name, restart-on-failure policy,
  execution time limit, and power settings should be used?
