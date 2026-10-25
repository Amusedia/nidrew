# Nidrew

Nidrew (Nidus Crew) is a sandbox setup for agents working toward one goal. It combines reproducible Nix environments with disposable Nix-built containers, driven from a Windows host.

The user directs the work and decides when the goal is complete. Agents share a filesystem when they run in the same container; Nidrew does not provide agent-to-agent messaging or autonomous coordination in the initial version. The goal is recorded in `GOAL.md` in the shared workspace.

## Status

This README defines the initial scope and intended architecture. Setup scripts, image definitions, and runtime configuration are not implemented in this repository yet.

A proof of concept elsewhere has shown the core path works: it built a NixOS-based image from an `agent-x.nix` and `agent-x.yaml` pair, ran it through `wslc` with its own network namespace limited to an egress container, and had Claude Code complete a small task inside it. Build on that result instead of re-proving it.

Not yet exercised:

* Codex and GitHub Copilot CLI in the container.
* The from-scratch base image instead of a NixOS base. If it hits a blocking problem, fall back to the NixOS base and record the reason.

Treat these as ordinary implementation work, checked as they are built, not as separate experiments.

## Concepts

| Concept | Meaning |
| --- | --- |
| Goal | The shared objective, recorded in `GOAL.md`; completion is decided by the user |
| Crew | The agents working toward that goal |
| Nidus | A disposable, sandboxed, Nix-built agent container |
| Agent template | A matching `.nix` and `.yaml` pair defining one agent container |
| Base image | The common Nix-built layer for agent images, built without an upstream distribution image |
| Egress image | An image containing Squid and socat for controlled network access |
| Substituter | A Nix binary cache used to obtain prebuilt store paths |

Disposable describes the container lifecycle. Container state survives stops, restarts, and host shutdowns, so a crew can resume after an interruption. Agents push completed work to a git remote on the host; that push is the durability boundary. Delete the container once the work is pushed. Images are rebuilt and containers replaced rather than patched in place.

## Threat Model

The sandbox exists so agents can run without interactive permission prompts. Its boundary protects local systems, not the internet.

Protected:

* Windows, Debian, other agent containers, and private LAN destinations, except explicitly permitted services.
* Windows files, which are not mounted by default.
* Secret values outside the container that uses them.

Not protected in the initial version:

* Data exfiltration over the open internet.
* Credentials shared among agents in the same container; any agent or process there can read them.
* Work in a container that is deleted before it is pushed.
* Kernel exploits. Containers share the WSL kernel; this is not strong multi-tenant isolation.
* A malicious or prompt-injected agent acting within its granted access.
* Competition for host CPU, memory, and disk; resource limits are v2 scope.

Agent containers must not run Windows executables or reach Windows interop.

## Architecture

| Boundary | Responsibility |
| --- | --- |
| Windows host | Runs thin PowerShell automation and stores credentials in Windows Credential Manager |
| WSL Debian server | Runs Nix, Harmonia, and Skopeo; holds build and deployment logic; builds runtime images |
| Base image | Provides the common Nix-built environment |
| Agent image | Extends the base with development tools and agent CLIs |
| Shared egress container | Provides controlled network access for all agent containers |
| Agent container | Runs the crew's tools and holds its working filesystem |

Keep persistent build and cache services on Debian, outside disposable agent containers.

### Build and cache services

* Nix declares environments and builds images.
* Harmonia serves the Debian Nix store as a binary cache for image builds and for runtime installs inside agent containers. Sign it with a dedicated key; consumers trust only its public key and cache.nixos.org's.
* Skopeo inspects and transfers container images where the build and deployment workflow requires it.

## Agent Templates

Each template has two files with the same base name, such as `agent.nix` and `agent.yaml`.

* `agent.nix` defines the image, extending the common base with development tools and all three agent CLIs.
* `agent.yaml` defines runtime configuration, including credential references and allowed Windows and Debian services.

Every initial agent image intentionally includes all three CLIs, so templates differ mainly in runtime configuration.

Build images with `dockerTools.buildLayeredImage` from scratch. The base provides:

* A non-root agent user, `/etc/passwd`, `/bin/sh`, `/usr/bin/env`, and CA certificates.
* Basic development tools for shell use, source control, editing, and search.
* Single-user Nix, with `/nix` owned by the agent user.
* A compatibility layer for prebuilt binaries: `nix-ld`, a `/lib64/ld-linux-x86-64.so.2` loader link, and a common library set (such as zlib, OpenSSL, and libstdc++) on `NIX_LD_LIBRARY_PATH`.
* Agent instructions describing how to install packages at runtime.

The agent image adds:

* Claude Code, typically used for coding.
* Codex, typically used for brainstorming and writing.
* GitHub Copilot CLI, typically used for search and lookup.

These are the user's usual roles, not enforced assignments.

Use nixpkgs unstable for agent packages because they change frequently. Pin the selected revision for reproducible builds and provide an explicit update workflow. Verify CLI package availability and select the exact development toolset during implementation.

## Runtime Package Installs

Agents cannot know every package a goal needs ahead of time, and rebuilding an image for each one is too slow. Agents install packages at runtime instead:

* System tools: use `nix shell nixpkgs#<name>` for one-off use or `nix profile install nixpkgs#<name>` to keep a tool. Prefer Nix over other system package managers.
* Language packages: use pip, npm, cargo, and similar tools in the workspace as usual. The compatibility layer lets prebuilt wheels and binaries run; add missing system libraries with Nix.

Configuration:

* Pin the image's `nixpkgs` registry entry to the revision the image was built from, so runtime installs reuse store paths already in the image.
* Use Harmonia as the first substituter, through its declared Debian service entry, and cache.nixos.org second, through Squid.
* Runtime installs live in the container's `/nix` and workspace. They survive restarts and are removed with the container.

Promotion: agents record packages they installed in the workspace, alongside `nix profile list`. The user periodically moves useful packages into the base or template `.nix` file and rebuilds. Package names are the same at runtime and in the image, so promotion is a direct copy.

## Goal

Each crew works toward one goal recorded in `GOAL.md` at the root of the shared workspace. `GOAL.md` states the objective, completion criteria, constraints, and out-of-scope items. Agents read it before starting work and may check off completion criteria; only the user changes the objective or declares the goal complete. This repository's own `GOAL.md` follows the same format.

## Credentials and Authentication

Use subscription-based access for the agent CLIs. API billing is outside the intended workflow.

Store credentials in Windows Credential Manager. YAML maps required environment variables to Credential Manager key names; it contains references rather than secret values. Windows automation retrieves the values and injects them at container launch. Keep secret values out of Nix expressions, images, generated configuration files, and logs.

Intended environment variables:

| CLI | Variable | Source |
| --- | --- | --- |
| Claude Code | `CLAUDE_CODE_OAUTH_TOKEN` | Long-lived token from `claude setup-token` |
| Codex | `CODEX_ACCESS_TOKEN` | Subscription access token |
| GitHub Copilot CLI | `GH_TOKEN` | Fine-grained token with Copilot access |

The Claude Code variable works in the proof of concept. Confirm the Codex and Copilot variables, and how long their tokens last, while integrating each CLI. Scope `GH_TOKEN` to the minimum permissions, since `gh` and git also use it. Do not substitute an API key when subscription sign-in requires a different flow. Use only documented provider interfaces. If a CLI has no supported variable for subscription access, sign in once inside the container; its credential directory persists with container state. Document any required manual browser sign-in or credential preparation.

To rotate an injected credential, update Credential Manager, push outstanding work, and recreate the container. Revoke a compromised token at its provider.

## Networking and Isolation

Each agent container has its own network namespace on an internal network whose only route is the shared egress container. Initially, allow general internet access so agent services, search, and package downloads work. Explicit service-domain allowlisting is not required in this version.

Access to local systems is restricted:

* Deny access to Windows, Debian, other agent containers, and private LAN destinations by default.
* Declare permitted Windows and Debian services in each agent YAML by target, protocol, and destination port.
* Permit required cache services and the host git remote through explicit service entries.
* Use Squid for HTTP/HTTPS and socat for explicitly configured TCP forwards.
* Preserve each agent container's permissions through shared egress: give each agent container a stable address and apply per-source Squid ACLs and per-agent socat listeners. Do not combine all templates' permissions into a global allowlist.
* Enforce the boundary outside agent containers. Proxy environment variables alone do not enforce isolation.

PowerShell discovers the relevant Windows and Debian addresses rather than hardcoding them.

Agent containers have no Windows folder mounts by default. Agents in the same container share its filesystem.

## Lifecycle and Operations

* Start order: Debian services, then the egress container, then agent containers. The start script checks each is ready before starting the next and is safe to rerun after a host restart.
* Entry: a script opens a shell in a selected agent container.
* Output: only work pushed to the host git remote is retained. Uncommitted, untracked, and ignored files, build artifacts, and logs are lost when the container is deleted.
* Teardown: the delete script lists uncommitted changes and unpushed commits and refuses to delete while they exist unless the user confirms. A failed push leaves the container in place. Teardown removes only the container; it never removes Debian caches, host git repositories, Credential Manager entries, or images without a separate, confirmed request.

## Initial Workflow

Every step is started by scripts invoked from the Windows host. Keep PowerShell thin: prerequisite checks, credential retrieval, and invoking scripts in Debian. Keep build and deployment logic in Debian scripts.

1. Check Windows, PowerShell, WSL Debian, and `wslc` prerequisites.
2. Set up Nix, Harmonia, and Skopeo on Debian.
3. Configure Nix substituters.
4. Build the base and egress images.
5. Build an agent image from the selected `.nix` file.
6. Read its matching YAML, resolve credential references, and configure runtime access.
7. Deploy through `wslc` and verify the agent CLIs and network boundaries.
8. Enter the container and work toward the goal in `GOAL.md`, retaining container state across interruptions.
9. Push completed work to the host git remote, then delete the container through the teardown script.

Scripts should be safe to rerun and explain any required manual actions. When Codex or Claude Code cannot perform a step, guide the user through it and verify the resulting state before continuing.

## Verification

The first milestone is complete when Windows scripts can set up Debian services, build a selected agent image, and deploy a usable container through `wslc`.

Check each item as the piece it covers is built, using quick end-to-end checks rather than separate experiments:

* All three CLIs work with the intended subscription credentials.
* The Harmonia substituter is usable and signed, and consumers reject unsigned paths.
* An agent can install a Nix package at runtime as the non-root user, using Harmonia first and cache.nixos.org second.
* A prebuilt binary or Python wheel installed at runtime runs through the compatibility layer.
* Permitted local ports are reachable and unpermitted local destinations are blocked, including direct connections that skip the proxy and IPv6.
* One agent container's permissions do not grant access to another's permitted services.
* No Windows folders are mounted by default, and the container cannot run Windows executables.
* The start script brings up Debian services, egress, and an agent container in order after a host restart.
* The user can enter the container, and agent CLI commands run inside it.
* Container state survives a container restart and a WSL or host restart.
* Work can be pushed from the container to the host git remote.
* Teardown refuses to delete a container with uncommitted or unpushed work unless confirmed, and leaves caches, repositories, credentials, and images intact.

Report any manual steps and unresolved limitations.

## Roadmap

### v2: Operations and caching

* Nexus CE package caching for npm, PyPI, and NuGet, possibly Maven and Cargo, with optional Docker registry caching. Verify support in the deployed Nexus CE version and edition.
* Per-container CPU, memory, disk, and concurrency limits declared in YAML.
* Cache maintenance: storage limits, retention, garbage collection, and health checks.
* Automatic startup of Debian services and egress at Windows sign-in, such as a current-user Scheduled Task. Validate the mechanism before adopting it.
* Optional read-only or writable project and artifact mounts declared in YAML.
* Collection of non-git outputs such as build artifacts, test reports, and logs.

### Later: candidates to validate

Adopt these only when an actual workflow or measurement shows the need.

* Source-code research service: upstream git mirrors, revision metadata, indexes, language servers, mapping installed Nix packages to source revisions, and answers citing repository, revision, file, and line. Possibly exposed through MCP or a headless research agent. Running Copilot CLI is not equivalent.
* Editor integration: a VS Code attach workflow, MCP configuration, and a skills and hooks bundle.
* Host capabilities: GPU and local inference access, and host applications such as Godot.
* Warm container pool and a persistent supervisor, only if measured startup time justifies them.
* Agent coordination: messaging and handoffs between agents.
* Provenance and observability: audit trails and startup, cache, and resource metrics.
* Portability to other hosts, runtime backends, and remote nodes.
