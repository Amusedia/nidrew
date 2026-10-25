# Nidrew

Mission Statement: Nidrew (Nidus Crew) is a sandbox for multiple agents working toward one goal. It provides reproducible environments and disposable, sandboxed runtimes.

> Read README.md, when present, for the project vision, system boundaries, and architectural direction before making design changes.

## Core Rules

- Coding agents must propose changes to AGENTS.md to the user. The user applies those changes manually.
- Use ASCII characters in repository-authored text unless Unicode is required by the content.
- Keep repository instructions explicit and concise. Prefer stating the desired behavior.
- Keep changes within the requested scope. Record unrelated discoveries in todo/.
- Prefer simple, explicit implementations. Introduce abstractions when they serve an established need.

## Architecture

Apply named concepts at their appropriate boundaries.

| Concern | Concept | Purpose |
|---|---|---|
| Environment definition | Infrastructure as Code | Declare environments with Nix |
| Runtime lifecycle | Immutable Infrastructure | Rebuild images and replace containers; push work to git before deletion |
| Agent isolation | Sandboxing, Least Privilege | Limit access to explicitly granted resources |
| Collaboration | Multi-Agent Coordination | Align multiple agents around one goal |

## System Boundaries

- Windows host: runs WSL and hosts the surrounding development environment.
- WSL Debian: runs Nix, Harmonia, and Skopeo, holds build and deployment logic, and builds runtime images.
- Harmonia: serves the Debian Nix store as a binary cache.
- Egress container: provides the agent containers' only network route and enforces per-agent access.
- Nix-built container (Nidus): provides the disposable, sandboxed agent runtime.
- Crew: the agents working together inside a Nidus toward one goal.
- Goal: the shared objective, recorded in GOAL.md, that defines the crew's work and completion criteria. Only the user changes the objective or declares it complete.

Keep persistent services outside the disposable runtime. Make host access, network access, credentials, and persistent mounts explicit.

Keep Windows automation thin. Put build and deployment logic in Debian scripts.

## Agent Templates

An agent template consists of two files sharing the same base name:

- agent-x.nix: declares the agent's environment and dependencies.
- agent-x.yaml: declares the agent's configuration.

Keep environment definitions in Nix and agent configuration in YAML. Define their exact contracts as implementation requirements emerge.

## Testing

Use red-green-refactor for testable behavior changes.

- Red: add or change a test for the required observable behavior and verify it fails for the expected reason.
- Green: make the smallest implementation change that makes the test pass.
- Refactor: improve the implementation while keeping tests passing.
- Preserve valid tests.
- For infrastructure changes, verify the relevant configuration, build, or runtime behavior and report the results.

## Workflow Retrospectives

Keep implementation focused on the requested task. Review opportunities for reusable automation in a separate, user-requested workflow retrospective. Use the workflow-retrospective skill when available.