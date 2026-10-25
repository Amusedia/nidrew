# Brainstorming compared with the current design

This review compares [brainstorming.md](brainstorming.md) with [README.md](../README.md), [GOAL.md](../GOAL.md), and [AGENTS.md](../AGENTS.md). README.md is the intended file named REAMD.md in the request.

The brainstorming document is an exploration, not a verified specification. The current documents preserve its core idea while choosing a smaller first milestone: reproducible, disposable agent containers with persistent Debian infrastructure and explicit local access. Missing ideas below are candidates for discussion, not additions to the goal.

## Evidence and experiment boundaries

- Brainstorming section 15 labels several things implemented or prototyped, including NixOS-WSL builds, lifecycle scripts, and Claude credential injection. Those statements describe earlier work; they do not establish implementation or verification in this repository.
- Brainstorming section 6.2 reports exploratory Alpine WSL timings: about 15 seconds cold, 6.3 seconds warm, and 0.14 seconds to execute a command in a running instance. The document itself says these are not NixOS guarantees. They also do not establish container performance or a need for a container warm pool.
- README's Status records the later experiment: in a separate environment, `wslc` ran Nix-built OCI images, provided separate container network namespaces, and restricted an agent container's network to the egress container. This supports the change in runtime design. The supplied documents do not contain the experiment procedure or raw results, so this review treats those findings as reported validation.
- That experiment does not establish the entire proposed deployment: subscription authentication for all three CLIs, per-agent egress permissions, target-machine IPv4/IPv6 enforcement, cache access, restart persistence, and git output preservation still need the checks listed in README and GOAL.
- README explicitly says setup scripts, image definitions, and runtime configuration are not implemented yet. Improvements discussed below are improvements to the proposal and its verification plan, not claims of working infrastructure.

## Ideas not captured, or only partly captured

| Brainstorming idea | Coverage in the current documents | What is still missing |
| --- | --- | --- |
| Persistent source-code research service (section 9) | Copilot CLI is described as usually used for search and lookup. | The larger service is absent: upstream Git mirrors and checkouts, revision metadata, indexes, language servers, mapping installed Nix packages to source revisions, and concise answers with repository/revision/file/line evidence. Running Copilot CLI is not an equivalent service. |
| Headless research agent and MCP adapter (sections 9.3-9.5) | No service or interface is specified. | The possible Copilot SDK integration, conceptual source tools, exact-versus-approximate revision matching, and controlled research-agent permissions are not recorded as future work. These were proposals requiring validation, including the warning not to assume VS Code indexing transfers to the SDK. |
| VS Code integration (sections 10.1-10.2) | Agent CLIs run inside the container, selecting one of brainstorming's execution approaches. | No primary UI, attachment workflow, plugin, MCP configuration, skills/hooks bundle, or per-CLI terminal/filesystem routing check is described. A plugin is optional; a usable way to enter the container and verify where tools execute remains an implementation detail to resolve. |
| Keeping Debian services available (section 7.2) | Persistent services belong on Debian; restart persistence is tested for agent state. | No startup/keepalive policy for Debian, Harmonia, or egress, service readiness checks, or recovery order is specified. Brainstorming suggested a current-user Scheduled Task or background service, but that mechanism still needs validation rather than automatic adoption. |
| Cache trust and maintenance (sections 8.1 and 8.3) | Harmonia and substituter usability are required. | Explicit signing/trusted-key configuration, storage limits, retention, garbage collection, health monitoring, and cache statistics are absent. Trust belongs in cache setup; extensive metrics can wait for a demonstrated need. |
| General dependency caching (section 8.2) | Nexus CE is explicitly deferred to v2 for npm, PyPI, NuGet, and optional Docker registry caching. | Brainstorming also names Maven and Cargo as possibilities and requires deployed-version/edition support checks. Those possibilities and that verification caveat are not preserved in the v2 note. This is mostly a deliberate deferral, not an overlooked first-milestone requirement. |
| Resource and concurrency policies (sections 6.3 and 16) | Multiple containers and per-container permissions are anticipated. | CPU, memory, disk, concurrency, and shared-GPU allocation policies are unspecified. Network isolation does not address competition for host resources. Warm-pool controls are a separate, replaced design choice. |
| Broader host capabilities (sections 4.2 and 16) | YAML grants access to specific Windows and Debian services; Windows mounts are absent by default. | No contract exists for optional project/artifact mounts, read-only versus writable access, host application tools such as Godot, or GPU/inference access. Network service grants cover some examples, but not every capability originally proposed. |
| Output collection beyond source control (sections 14 and 16) | Pushing work to a host git remote is the durability boundary. | Policies for untracked or ignored files, build artifacts, test reports, retained logs, and interrupted/failed pushes are unspecified. The current rule is clear for pushed work, but does not define whether these other outputs should be retained. |
| Safe teardown and lifecycle commands (sections 13.1 and 13.3) | Images are replaced and containers deleted after work is pushed; scripts should be rerunnable. | No teardown/uninstall contract distinguishes disposable state from caches, host repositories, credentials, and user data. Brainstorming explicitly required confirmation before deleting persistent data. Named start/stop/update/uninstall commands are illustrative there, not a required script layout. |
| Credential operations and supported interfaces (sections 11.2-11.3) | Credential Manager references, launch injection, secret hygiene, refresh verification, and manual browser preparation are covered. | Rotation/revocation procedures and an explicit requirement to use documented provider interfaces are absent. Brainstorming allowed a supported persistent Codex credential directory as an alternative; current documents emphasize environment injection, subject to verification. Neither source proves the proposed Codex token variable works. |
| Isolation limitations and Windows interoperability (sections 5.3 and 12) | Current threat model is explicit about local protection, shared credentials, internet exfiltration, and absent Windows mounts. | Brainstorming's explicit disclaimers about shared kernels, kernel exploits, malicious agents, strong multi-tenancy, and prompt injection are not repeated. Disabling Windows executable interoperability is also not specified. The old NixOS-WSL settings do not directly transfer to containers; equivalent exposure needs assessment for the chosen runtime. |
| Future portability and observability (section 18) | Current scope is Windows/WSL with explicit template pairs. | Other hosts/backends, remote nodes, artifact management, provenance/audit trails, cross-agent handoffs, and startup/cache/resource metrics are not retained as possibilities. These were speculative directions, not commitments. |

## Ideas deliberately replaced or bounded

| Brainstorming proposal | Current decision | Assessment |
| --- | --- | --- |
| One disposable NixOS-WSL distribution per agent (sections 3 and 5) | Nix-built OCI containers deployed through `wslc`; multiple agents may share one container. | An intentional backend and isolation-unit change, supported by the reported experiment. The per-distribution configuration and exclusive per-agent ownership model should not be carried over unchanged. |
| Persistent Windows supervisor, leases, warm pool, and asynchronous replenishment (sections 4.1 and 6) | User-started scripts, thin PowerShell, and Debian build/deployment logic. | Removes a substantial management subsystem from the first milestone. Container startup performance should be measured before deciding whether pooling or a supervisor is worthwhile. Lifecycle safety still matters without a daemon. |
| Destroy the worker after a session (sections 5.4 and 14) | Preserve container state through interruptions; push work before deletion. | Better matches long-running work that must resume. A stop or host restart is distinguished from intentional disposal. |
| Open questions about execution, persistence, image profiles, and network policy (section 16) | In-container CLIs, host git remote, common base plus template images, and general internet access with local destinations restricted. | Converts several open questions into implementation choices that can be tested. These choices have tradeoffs; open internet access does not prevent exfiltration. |
| Broad future agent integration (sections 2 and 10) | All initial images include Claude Code, Codex, and Copilot CLI; usual roles are advisory. | A concrete initial integration target. Support for future runtimes remains possible but is not a defined compatibility contract. |
| Possible higher-level agent coordination (sections 7 and 16) | Shared filesystem and user-directed goal; messaging and autonomous coordination are explicitly out of scope. | Bounds the first version. AGENTS.md's term "Multi-Agent Coordination" describes alignment around a goal, not an implemented coordination service. |

## What the current proposal does better

These judgments concern clarity, scope, and testability. They do not imply that unimplemented behavior has been demonstrated.

1. **A concrete first milestone.** Brainstorming spans environment provisioning, research, integrations, pooling, and scheduling. GOAL defines one end-to-end outcome with observable completion criteria. This makes progress and remaining work easier to assess without requiring the whole platform first.

2. **An experiment-informed runtime choice.** README replaces full NixOS-WSL workers with Nix-built OCI containers after the reported `wslc` checks. This removes the need to provision a complete NixOS distribution for each worker and avoids committing to the old warm-pool architecture. Size, speed, and resource improvements still require measurement.

3. **A specific network enforcement design.** Brainstorming asks what network policy should be; the current proposal identifies an external egress boundary, Squid and socat roles, local destination restrictions, explicit service grants, and per-source permissions. Stable addresses and per-agent listeners address permission leakage through shared egress. Direct bypass and IPv4/IPv6 checks make the intended boundary reviewable.

4. **A clearer practical threat model.** README states both what local resources should be protected and what the first version does not protect, particularly internet exfiltration and credentials shared inside a container. This is more actionable than relying only on general selective-capability principles, although the older shared-kernel caveat remains useful.

5. **Explicit image and runtime configuration boundaries.** Matching `.nix` and `.yaml` files separate environment dependencies from credentials and access policy. A common from-scratch base, `dockerTools.buildLayeredImage`, a non-root user, required filesystem basics, and all three CLIs give implementation a clearer starting point. Pinning nixpkgs unstable and requiring an update workflow also makes the reproducibility policy more concrete.

6. **Simpler placement of automation.** Debian owns build/deployment logic; Windows handles prerequisites, credential retrieval, and invocation. Compared with a Windows supervisor managing many concerns, this keeps Linux infrastructure work together and limits PowerShell's role.

7. **An explicit durability and resumption rule.** Brainstorming lists several possible output-preservation mechanisms. README selects a host git remote, defines a successful push as the durability boundary, and requires restart survival. This resolves a central lifecycle ambiguity while keeping Windows folders unmounted by default.

8. **More precise authentication acceptance criteria.** The current documents turn subscription access into an end-to-end requirement for all three CLIs, separate secret references from values, and require checking token names, lifetime, refresh, permissions, and browser steps before injection. The listed variables remain hypotheses until those checks pass.

9. **User ownership of the shared objective.** GOAL records completion criteria, constraints, and exclusions; only the user changes the objective or declares completion. AGENTS makes this part of the operating rules. This gives a crew a clearer common direction than the brainstorming's general task/session model.

10. **A verification and contribution contract.** GOAL and README enumerate runtime checks, while AGENTS requires red-green-refactor for testable behavior and appropriate infrastructure verification. Scope control, explicit boundaries, and user-applied AGENTS changes reduce drift during implementation. Those rules were not specified in brainstorming.

## Suggested follow-up priorities

These are review recommendations only; this comparison does not change README, GOAL, or AGENTS.

- Preserve source-code intelligence as a separate future-design candidate. It is the largest distinctive idea that disappeared, and is not equivalent to installing a search CLI.
- Resolve operational details while implementing the existing milestone: Debian/egress startup and readiness, cache trust, supported authentication flows, entering the container, and preserving work safely before deletion.
- Record explicit decisions about resource limits, non-git outputs, safe teardown, optional mounts, and credential rotation before implementing features that depend on them.
- Retain the warm pool, supervisor, research SDK/MCP integration, and broad portability as hypotheses. Reconsider them when measurements or actual workflows establish a need.
- Preserve an experiment record with commands, versions, networking configuration, results, and limits when available. The current summary identifies what was verified but is insufficient to reproduce it independently.

No AGENTS.md edit is needed to deliver this review. Any later instruction changes should be proposed to the user for manual application.
