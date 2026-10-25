# Nidrew — A Local Agentic Operating Environment

> Set the stage for autonomous agents.

**Nidrew** is a local-first platform for provisioning, running, and managing isolated environments for autonomous coding agents.

It provides the infrastructure agents need to work: reproducible operating environments, development tools, package caches, source-code intelligence, persistent services, and controlled access to host capabilities.

Nidrew does not attempt to replace Claude Code, OpenAI Codex, GitHub Copilot, or other agent runtimes. Instead, it provides a common execution environment in which those agents can operate.

The central idea is simple:

**Agents should be able to work in disposable environments without making the developer's machine disposable.**

## 1. Motivation

Autonomous coding agents are increasingly capable of performing substantial development tasks. They can inspect repositories, install dependencies, execute commands, modify code, run tests, and coordinate complex workflows.

However, their execution environments remain a challenge.

Running agents directly on a developer's machine introduces several problems:

- Agents can unintentionally modify the host environment.
- Dependencies installed for one task may interfere with another.
- Repeated setup wastes time and network bandwidth.
- Long-running sessions accumulate unpredictable filesystem state.
- Different projects require incompatible toolchains.
- Agent environments are difficult to reproduce or reset.
- Local hardware and existing development tools are not always easy to expose selectively.
- Multiple agents may compete for shared resources.

Cloud-hosted agent environments address some of these problems but introduce others:

- Additional compute costs.
- Dependence on remote infrastructure.
- Latency when interacting with local tools and files.
- Difficulty accessing specialized local hardware.
- Restrictions imposed by hosted execution platforms.
- Reduced control over the environment.

Nidrew explores a different approach: **a local agentic operating environment built from existing operating-system and development infrastructure.**

Rather than inventing a new operating system, Nidrew orchestrates existing technologies to provide a coherent lifecycle for autonomous workers.

## 2. Design Philosophy

Nidrew follows several principles.

### Local-first

Execution happens on the developer's own machine by default.

The platform should take advantage of available CPU, memory, storage, and GPU resources without requiring a cloud account or remote compute subscription.

### Disposable execution

An agent environment should be easy to create, use, destroy, and replace.

Instead of trying to repair an environment after an agent has modified it, Nidrew prefers replacing it with a clean instance.

### Persistent infrastructure, ephemeral workers

Not everything should be disposable.

Package caches, source repositories, authentication configuration, and shared services benefit from persistence.

Nidrew separates these persistent services from temporary execution environments.

### Reproducible configuration

Agent environments should be defined declaratively wherever practical.

NixOS and Nix flakes provide a reproducible foundation for operating-system configuration, development tools, and runtime dependencies.

### Agent-runtime independence

Nidrew should support multiple agent implementations.

Claude Code, Codex, Copilot, and future agents should be able to use the same underlying environment-management infrastructure.

### Explicit capabilities

Agents should receive the host capabilities required for their tasks, rather than unrestricted access to the developer's machine.

This includes filesystem access, external applications, GPU services, and network resources.

### Pragmatic security

Nidrew aims to reduce accidental damage, environmental contamination, and unnecessary exposure.

It does not claim that a WSL instance is a hardened security boundary against a determined adversary.

Security controls should be proportional to the actual threat model.

### Minimal unnecessary abstraction

Existing tools should handle the problems they already solve well.

Nidrew should orchestrate them rather than recreate package managers, container runtimes, authentication systems, or development environments.

## 3. High-Level Architecture

The initial target platform is Windows with WSL.

```text
┌──────────────────────────────────────────────────────────────┐
│                       Windows Host                           │
│                                                              │
│  ┌─────────────────────┐  ┌────────────────────────────────┐ │
│  │ VS Code             │  │ Nidrew Supervisor              │ │
│  │                     │  │                                │ │
│  │ Agent interfaces    │  │ Instance lifecycle             │ │
│  │ Plugins / MCP       │  │ Warm instance pool             │ │
│  │ User interaction    │  │ Resource allocation            │ │
│  └─────────────────────┘  │ Capability configuration       │ │
│                           └───────────────┬────────────────┘ │
│                                           │                  │
│  Local tools and resources                │                  │
│  - GPU / llama.cpp                        │                  │
│  - Godot and other applications           │                  │
│  - Selected host files                    │                  │
└───────────────────────────────────────────┼──────────────────┘
                                            │
                              WSL lifecycle management
                                            │
┌───────────────────────────────────────────┼──────────────────┐
│                           WSL                                │
│                                           │                  │
│  ┌────────────────────────────────────────▼────────────────┐ │
│  │              Disposable NixOS Agents                    │ │
│  │                                                         │ │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐           │ │
│  │  │ Agent A    │ │ Agent B    │ │ Warm spare │           │ │
│  │  │            │ │            │ │            │           │ │
│  │  │ Toolchain  │ │ Toolchain  │ │ Ready image│           │ │
│  │  │ Workspace  │ │ Workspace  │ │            │           │ │
│  │  └────────────┘ └────────────┘ └────────────┘           │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                Persistent Debian WSL                    │ │
│  │                                                         │ │
│  │  Nix build infrastructure                               │ │
│  │  Harmonia binary cache                                  │ │
│  │  Nexus package repository                               │ │
│  │  Git mirrors and source checkouts                       │ │
│  │  Source-code intelligence service                       │ │
│  │  Shared development infrastructure                      │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

The architecture separates three responsibilities:

1. **Windows:** Human interaction, orchestration, and host resources.
2. **Disposable NixOS instances:** Agent execution and task-local state.
3. **Persistent Debian instance:** Shared infrastructure, caches, builds, and research services.

## 4. Windows Host

Windows remains the developer's primary operating system.

It provides:

- VS Code and other user interfaces.
- Local hardware access.
- GPU-backed inference services.
- Existing development applications.
- Persistent user files.
- Credential storage.
- Agent-instance orchestration.

Nidrew does not require replacing Windows or moving the developer's entire workflow into Linux.

Instead, it provides isolated Linux environments alongside the existing desktop.

### 4.1 Supervisor

A persistent Windows-side supervisor manages the agent environment lifecycle.

Its responsibilities include:

- Creating WSL instances.
- Starting and stopping instances.
- Maintaining a pool of prewarmed environments.
- Assigning instances to agent sessions.
- Tracking instance ownership and leases.
- Cleaning up completed sessions.
- Replenishing the warm pool.
- Configuring allowed host capabilities.
- Coordinating access to persistent services.

The supervisor is distinct from the AI agent runtime.

An agent decides what work to perform. The supervisor decides where that work executes and manages the environment's lifecycle.

### 4.2 Host capabilities

Host resources should be exposed selectively.

Examples include:

- A specific project directory.
- A local inference endpoint.
- A GPU-backed service.
- A Godot automation interface.
- A designated build artifact directory.
- A host application exposed through a controlled tool interface.

Agents should not receive unrestricted Windows filesystem access by default.

In particular, automatically exposing the entire Windows drive through `/mnt/c` is undesirable.

Capabilities should be explicit and task-dependent.

## 5. Disposable NixOS Agent Environments

Each agent receives a Linux execution environment implemented as a WSL distribution.

NixOS provides the declarative operating-system configuration.

Nix flakes define the environment's tools and dependencies.

### 5.1 Image construction

Nidrew uses NixOS-WSL tooling to build importable WSL images from Nix configurations.

The intended workflow is:

1. Define the agent environment in a Nix flake.
2. Build a WSL-compatible NixOS image.
3. Import that image as a new WSL distribution.
4. Start the instance.
5. Assign it to an agent session.
6. Destroy the instance when its lifecycle ends.

This allows multiple environments to share a common reproducible definition.

### 5.2 Environment configuration

An agent image may include:

- Shell utilities.
- Git.
- Language runtimes.
- Compilers and build systems.
- Debuggers.
- Language servers.
- Agent runtimes.
- MCP integrations.
- Project-specific development tools.

Different image profiles may eventually support different workloads.

Examples:

- General-purpose coding.
- Python development.
- Rust development.
- .NET development.
- Game development.
- Repository research.

Initially, a small number of general-purpose profiles is preferable to a complicated image matrix.

### 5.3 WSL configuration

The baseline environment should minimize implicit host integration.

An illustrative NixOS-WSL configuration is:

```nix
wsl.wslConf = {
  automount.enabled = false;
  automount.mountFsTab = false;

  interop.enabled = false;
  interop.appendWindowsPath = false;
};
```

This reduces automatic Windows filesystem exposure and Windows executable interoperability.

Task-specific capabilities can be enabled explicitly when required.

These settings are useful operational boundaries, not proof of strong isolation.

### 5.4 Reset by replacement

Nidrew prefers destroying and replacing used agent environments over attempting to reverse arbitrary filesystem changes.

A Nix rebuild restores declarative configuration, but does not necessarily undo mutable filesystem state.

Similarly, reverting a filesystem layer does not automatically reset running processes, open handles, or other runtime state.

Replacing the complete WSL instance provides a simpler lifecycle model.

```text
Clean image
     │
     ▼
Import instance
     │
     ▼
Assign agent
     │
     ▼
Execute task
     │
     ▼
Collect outputs
     │
     ▼
Destroy instance
     │
     ▼
Replenish from clean image
```

More sophisticated snapshot or overlay mechanisms can be explored later if measurements justify them.

## 6. Warm Instance Pool

Creating a WSL distribution on demand may introduce noticeable startup latency.

Nidrew addresses this with a pool of prewarmed instances.

### 6.1 Pool lifecycle

```text
               Image builder
                    │
                    ▼
              Clean WSL image
                    │
                    ▼
             Warm instance pool
               /     |     \
              /      |      \
          Ready    Ready    Ready
             │
             ▼
         Lease to agent
             │
             ▼
           Active
             │
             ▼
          Destroy
             │
             ▼
       Replenish pool
```

The supervisor maintains a configurable number of ready instances.

When an agent requests an environment:

1. The supervisor selects a compatible ready instance.
2. The instance is assigned exclusively to the session.
3. The agent begins work.
4. A replacement instance is prepared asynchronously.
5. The used instance is destroyed after the session.

### 6.2 Performance considerations

Early WSL experiments with Alpine Linux showed approximately:

| Operation | Observed time |
|---|---:|
| Cold instance startup | 15 seconds |
| Warm instance startup | 6.3 seconds |
| Execute command in running instance | 0.14 seconds |

These are exploratory measurements, not NixOS performance guarantees.

NixOS image size, initialization, and service configuration may produce different results.

The design should be validated against actual NixOS workloads before optimizing further.

### 6.3 Pool management

Potential pool controls include:

- Minimum ready instances.
- Maximum concurrent instances.
- Idle timeout.
- Resource limits.
- Image version.
- Health checks.
- Lease expiration.
- Failed-instance replacement.

The initial implementation should remain simple.

A fixed pool with exclusive leases and automatic replenishment is a reasonable starting point.

## 7. Persistent Debian Infrastructure

A dedicated Debian WSL distribution hosts services that should survive individual agent sessions.

This instance acts as Nidrew's local infrastructure server.

It is intentionally persistent, unlike the disposable NixOS workers.

### 7.1 Responsibilities

The Debian instance provides:

- Nix builds.
- Nix binary caching.
- General package caching.
- Git mirrors.
- Source-code checkouts.
- Repository indexing.
- Language-server infrastructure.
- Shared research services.
- Potential future coordination services.

Centralizing these services avoids repeatedly downloading, rebuilding, or indexing the same dependencies for every agent.

### 7.2 Keeping Debian running

WSL may stop a distribution when its processes terminate or the instance becomes idle.

The proposed approach is a Windows Scheduled Task or background service that starts Debian under the current user account and keeps a process running:

```powershell
wsl -d Debian --exec sleep infinity
```

This also allows systemd services inside Debian to initialize and remain available.

The approach is preferable to globally disabling WSL instance idle shutdown, because disposable agent instances should retain independent lifecycles.

## 8. Dependency and Build Caching

Agent environments repeatedly install similar tools and dependencies.

Nidrew uses persistent caches to reduce startup time, network traffic, and redundant work.

### 8.1 Nix binary cache

**Harmonia** serves a Nix binary cache backed by the persistent Debian Nix store.

This allows agent instances to retrieve prebuilt Nix store paths rather than rebuilding everything independently.

The cache should use appropriate signing and trusted-key configuration.

### 8.2 Package repository

**Sonatype Nexus Repository Community Edition** provides a centralized package repository and proxy for supported ecosystems.

Potential ecosystems include:

- npm.
- PyPI.
- NuGet.
- Maven.
- Cargo.
- OCI container artifacts.

Exact format support and edition-specific limits should be verified against the deployed Nexus version.

Nexus provides a practical alternative to implementing a custom content-addressable package cache.

### 8.3 Cache policy

Caches should have explicit maintenance policies.

Possible controls include:

- Storage quotas.
- Retention windows.
- Unused-artifact cleanup.
- Garbage collection.
- Repository health monitoring.
- Cache hit and miss statistics.

The goal is to make repeated agent execution inexpensive without allowing caches to grow indefinitely.

## 9. Source-Code Intelligence

One of Nidrew's more distinctive proposed services is a persistent source-code research system.

Coding agents frequently need to understand the tools they use.

Documentation may be incomplete, outdated, or ambiguous.

When necessary, the most authoritative explanation of a tool's behavior is its implementation.

Nidrew aims to make upstream source code readily available for investigation.

### 9.1 Local source library

The Debian infrastructure instance maintains:

- Bare Git mirrors of selected upstream repositories.
- Local source checkouts.
- Revision metadata.
- Search indexes where useful.
- Language-server support for relevant languages.

Repositories can be added on demand and updated according to configurable policies.

### 9.2 Connecting binaries to source

When an agent investigates a tool installed through Nix, the research service should attempt to identify the corresponding source revision.

Possible sources of information include:

- Nix derivations.
- Flake locks.
- Package definitions.
- Source hashes.
- Upstream repository metadata.
- Build inputs.

Not every installed binary will have a directly recoverable source checkout or unambiguous Git commit.

The service should distinguish exact matches from approximate upstream references.

### 9.3 Research agent

A headless research agent, potentially using the GitHub Copilot SDK, can investigate implementation questions using:

- `rg` and other text-search tools.
- Git history.
- Language servers.
- Local repository checkouts.
- On-demand upstream source retrieval.
- Structured source references.

For example:

```text
Question:
  How does this CLI discover its configuration file?

Research service:
  1. Identify the installed CLI version.
  2. Locate the corresponding source.
  3. Search configuration-loading code.
  4. Follow relevant symbols.
  5. Inspect tests and call sites.
  6. Return an explanation with references.
```

Results should include precise evidence where possible:

```text
Repository: upstream/project
Revision:   abc123...
File:       src/config/loader.ts
Lines:      42-79
```

### 9.4 MCP interface

A thin MCP adapter exposes the research service to coding agents.

Example conceptual tools:

```text
source.find_repository
source.search
source.explain
source.trace_symbol
source.inspect_version
```

These are proposed interfaces, not finalized API contracts.

The research service should return concise findings with supporting references rather than large unstructured dumps.

### 9.5 Scope and limitations

The Copilot SDK does not automatically provide every capability available in the VS Code Copilot experience.

In particular, workspace indexing and semantic search behavior should not be assumed to transfer automatically.

Language servers, repository search, and Git provide a more explicit and portable foundation.

The research agent should also operate within controlled permissions rather than freely modifying its own infrastructure.

## 10. Agent Runtime Integration

Nidrew is not itself an AI model or agent reasoning engine.

It provides infrastructure for existing agent runtimes.

Initial candidates include:

- Claude Code.
- OpenAI Codex.
- GitHub Copilot.
- Other CLI-based or extensible agent systems.

### 10.1 VS Code integration

VS Code is the primary user interface in the initial design.

An Agent Plugin can package:

- MCP server configuration.
- Skills.
- Agent instructions.
- Hooks.
- Documentation.
- Integration conventions.

The plugin teaches compatible agents how to request and use Nidrew environments.

However, a VS Code Agent Plugin is not itself a complete execution supervisor.

Nidrew still needs an independent component to manage WSL instances, leases, and cleanup.

### 10.2 Execution routing

A critical integration problem remains:

**How does an agent's normal filesystem and terminal activity execute inside its assigned WSL environment?**

Providing an MCP server does not automatically redirect every built-in agent tool.

Possible integration approaches include:

1. Running the agent runtime inside the assigned WSL instance.
2. Using supported agent-host APIs to bind execution to a remote environment.
3. Providing explicit terminal and filesystem tools through an adapter.
4. Using a hybrid model where the UI remains on Windows and execution occurs in WSL.

The correct approach depends on the capabilities and extension points of each agent runtime.

This should be validated experimentally rather than assumed.

### 10.3 Separation of responsibilities

```text
User / VS Code
      │
      ▼
Agent runtime
      │
      ├── Plans and reasons
      ├── Uses tools
      └── Requests an execution environment
                     │
                     ▼
              Nidrew supervisor
                     │
                     ├── Allocates WSL instance
                     ├── Applies capabilities
                     ├── Tracks lease
                     └── Cleans up afterward
```

The agent controls the task.

Nidrew controls the environment lifecycle.

## 11. Authentication and Credentials

Nidrew should support the normal subscription-based authentication mechanisms of compatible agent runtimes where officially supported.

The goal is to avoid requiring separate usage-billed API credentials when an agent runtime can legitimately operate through an existing user subscription.

Authentication mechanisms differ between providers and may change over time.

### 11.1 Windows credential storage

The current Claude integration uses the following approach:

1. Generate an appropriate Claude authentication token.
2. Store it in Windows Credential Manager.
3. Retrieve it through the trusted Windows-side launcher.
4. Inject it into the agent runtime's environment when needed.
5. Avoid embedding the token in the NixOS image or repository.

This keeps persistent credential storage outside disposable agent images.

### 11.2 Codex authentication

Codex supports ChatGPT-account authentication through its official login flow.

A persistent credential directory or a supported token-based mechanism can be used, subject to the authentication features available in the installed Codex version.

Nidrew should rely on documented provider authentication interfaces rather than scraping internal credentials or assuming undocumented token formats.

### 11.3 Credential threat model

Runtime credential injection is a deliberate tradeoff.

An agent that can execute arbitrary commands may be able to access credentials available to its process or execution environment.

Destroying the WSL instance afterward does not undo actions performed with a credential during the session.

For the initial local, single-user deployment, the proposed policy is:

- Store persistent secrets on Windows.
- Inject only the credentials required for the session.
- Avoid logging credentials.
- Avoid placing credentials in reusable images.
- Minimize unnecessary host access.
- Support credential rotation and revocation.
- Document the trust boundary.

A more isolated credential broker can be considered later if the threat model requires it.

Nidrew should not introduce substantial complexity solely to defend against hypothetical threats without a clear operational benefit.

## 12. Security Model

Nidrew aims to provide practical isolation for autonomous development workflows.

### 12.1 What Nidrew attempts to protect

- The developer's normal working environment.
- Persistent host files.
- Other agent sessions.
- Reproducibility of future sessions.
- Shared infrastructure from accidental modification.
- Credentials that do not need to be exposed.
- Task-specific resource boundaries.

### 12.2 What Nidrew does not guarantee

WSL distributions share a Windows-managed Linux kernel.

They should not be treated as equivalent to strongly isolated virtual machines with independent kernels.

Nidrew's initial design does not claim:

- Protection against arbitrary kernel exploits.
- Perfect containment of malicious agents.
- Complete prevention of credential theft.
- Strong multi-tenant isolation.
- Protection against every prompt-injection attack.
- Elimination of all host exposure.

### 12.3 Practical controls

The initial controls include:

- Disabled implicit Windows drive mounting.
- Disabled Windows executable interoperability by default.
- Disposable worker filesystems.
- Explicit host capability grants.
- Persistent credentials stored outside worker images.
- Separation between worker and infrastructure instances.
- Exclusive instance assignment.
- Destruction and replacement after use.

Additional controls can be introduced based on observed risks.

The guiding principle is:

**Make capabilities explicit, and make recovery cheap.**

## 13. Distribution and Installation

Nidrew should be easy to install, inspect, and modify.

The initial distribution mechanism is a Git repository containing PowerShell scripts and Nix configuration.

A dedicated installer framework is not required initially.

### 13.1 Proposed repository structure

```text
nidrew/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
│
├── setup.ps1
├── start.ps1
├── stop.ps1
├── update.ps1
├── uninstall.ps1
│
├── nix/
│   ├── flake.nix
│   ├── flake.lock
│   └── modules/
│
├── supervisor/
│
├── services/
│   ├── cache/
│   ├── nexus/
│   └── source-research/
│
├── integrations/
│   ├── vscode/
│   ├── claude/
│   └── codex/
│
└── docs/
```

This is an illustrative layout rather than an established repository contract.

### 13.2 Bootstrap process

The intended installation flow is:

1. Clone the Nidrew repository.
2. Run the PowerShell bootstrap script.
3. Validate Windows and WSL prerequisites.
4. Prepare the persistent Debian infrastructure.
5. Bootstrap Nix where required.
6. Build the NixOS-WSL image.
7. Configure shared services.
8. Register the supervisor and startup behavior.
9. Prepare the initial warm instance pool.
10. Configure supported agent integrations.

The installation should be idempotent where practical.

### 13.3 Safe teardown

Uninstallation should distinguish between:

- Disposable agent instances.
- Supervisor configuration.
- Generated images.
- Persistent package caches.
- Source repositories.
- User-owned workspaces.
- Credentials.

Destroying disposable instances is expected.

Deleting persistent caches, credentials, or user data should require explicit confirmation.

## 14. Operational Lifecycle

A typical agent session follows this sequence.

### Step 1: Request

A user starts an agent task from VS Code or another supported interface.

### Step 2: Allocation

The agent integration requests a compatible environment from the Nidrew supervisor.

### Step 3: Preparation

The supervisor assigns a clean, ready WSL instance.

It configures the required workspace and approved capabilities.

### Step 4: Execution

The agent runs inside or against the assigned environment.

It can:

- Read and modify task-local files.
- Install dependencies.
- Build software.
- Run tests.
- Query shared source-code intelligence.
- Retrieve packages from persistent caches.
- Use explicitly granted host capabilities.

### Step 5: Output collection

Relevant results are preserved outside the disposable instance.

Examples include:

- Source changes.
- Git commits or patches.
- Build artifacts.
- Test reports.
- Logs selected for retention.

### Step 6: Cleanup

The supervisor terminates the session and destroys its WSL instance.

### Step 7: Replenishment

A clean instance is prepared to restore the warm pool.

The next task begins from a known baseline.

## 15. Current Implementation Status

Nidrew is an evolving prototype.

The following items have been discussed or partially implemented.

### Implemented or prototyped

- Persistent Debian WSL infrastructure instance.
- Local Nix bootstrap in Debian.
- NixOS-WSL image build process.
- PowerShell-based setup and lifecycle scripting.
- Initial WSL startup performance experiments.
- Windows credential storage and runtime injection for Claude authentication.

### Architectural decisions

- Windows as the primary host and user interface.
- NixOS-WSL as the disposable agent environment.
- Debian WSL as persistent infrastructure.
- Nix flakes for declarative environment configuration.
- Harmonia for Nix binary caching.
- Nexus for general dependency caching.
- Warm spare pool managed by a Windows supervisor.
- Replacement instead of in-place rollback.
- Selective host capabilities.
- VS Code integration through plugins and MCP.
- Agent-runtime independence.

### Planned or requiring validation

- Complete supervisor implementation.
- Reliable NixOS warm-pool lifecycle.
- Actual NixOS startup and resource benchmarks.
- End-to-end agent execution routing.
- Source-code intelligence service.
- Copilot SDK research integration.
- Source revision mapping for installed packages.
- Credential handling across different agent runtimes.
- Resource quotas and concurrency policies.
- Robust output preservation and cleanup.
- Installation and teardown hardening.

These categories should be updated as implementation progresses.

## 16. Open Design Questions

Several decisions remain intentionally unresolved.

### Agent execution model

Should each agent runtime execute directly inside its assigned NixOS instance, or should the agent process remain outside and control the environment remotely?

The answer may differ between Claude, Codex, and Copilot.

### Workspace persistence

What is the preferred mechanism for preserving source changes?

Candidates include:

- Git commits and patches.
- Explicit artifact export.
- Controlled persistent workspace mounts.
- Synchronization with a host repository.

This requires balancing convenience against isolation.

### Resource scheduling

How should Nidrew allocate CPU, RAM, disk, and access to shared GPU services across concurrent agents?

### Image specialization

When is a specialized image worth maintaining instead of installing additional dependencies into a general-purpose environment?

### Network policy

Which network destinations should be available by default?

Should the system distinguish package retrieval, model-provider access, and arbitrary outbound connections?

### Source-code intelligence

How much repository indexing should be persistent, and how much should be performed on demand?

### Agent coordination

Should Nidrew remain strictly an execution-environment manager, or eventually provide higher-level multi-agent coordination?

The initial architecture favors keeping orchestration of agent reasoning outside Nidrew's core.

## 17. Non-Goals

At least initially, Nidrew is not intended to be:

- A replacement for Windows or Linux.
- A new general-purpose operating-system kernel.
- A new AI model.
- A replacement for Claude Code, Codex, or Copilot.
- A general cloud-computing platform.
- A hardened multi-tenant security boundary.
- A replacement for Nix.
- A replacement for existing package repositories.
- A full container-orchestration system.
- A proprietary agent protocol.
- A mandatory hosted service.

Its purpose is narrower:

**Make local autonomous-agent execution reproducible, disposable, efficient, and manageable.**

## 18. Potential Future Directions

Once the basic lifecycle works reliably, Nidrew could explore:

- Additional host operating systems.
- Alternative isolation backends.
- Remote execution nodes.
- Agent-specific environment profiles.
- Dynamic resource scheduling.
- Shared artifact management.
- Environment provenance and audit trails.
- More sophisticated network and credential isolation.
- Cross-agent workspace handoffs.
- Project-specific capability policies.
- Metrics for startup time, cache efficiency, and resource usage.

These are possibilities, not commitments.

The architecture should remain small enough that new features are driven by actual workloads.

## 19. Licensing

The proposed license is **Apache License 2.0**.

This provides permissive commercial and noncommercial use, an explicit patent grant, and relatively low friction for integration with other development tools.

Dependencies and redistributed third-party components retain their own licenses.

## 20. Summary

Nidrew combines existing technologies into a local execution platform for autonomous coding agents.

Its key architectural choices are:

1. **Windows remains the human operating system.**
2. **Disposable NixOS-WSL instances run agent workloads.**
3. **A persistent Debian instance hosts shared infrastructure.**
4. **Nix provides reproducible environment definitions.**
5. **Harmonia and Nexus reduce repeated dependency work.**
6. **A supervisor manages instance allocation and cleanup.**
7. **A warm pool reduces agent startup latency.**
8. **Source-code intelligence helps agents investigate tools.**
9. **Agent runtimes remain interchangeable.**
10. **Host capabilities are granted explicitly.**

The broader vision is to treat an autonomous agent's computer as a replaceable resource.

A developer should be able to summon a prepared environment, let an agent work, preserve the results, and discard the environment without worrying about what the agent installed or changed along the way.

**Nidrew sets the stage. The agents do the work.**