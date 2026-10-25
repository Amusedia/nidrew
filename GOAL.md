# Goal

Only the user changes the objective or declares the goal complete. Agents may check off completion criteria as they are verified.

## Objective

Reach the first Nidrew milestone: Windows scripts set up Debian services, build a selected agent image, and deploy a usable agent container through `wslc`.

## Completion Criteria

- [ ] Prerequisite checks pass for Windows, PowerShell, WSL Debian, and `wslc`.
- [ ] Nix, Harmonia, and Skopeo are set up on Debian by rerunnable scripts.
- [ ] The base, egress, and one agent image build from Nix.
- [ ] An agent container deploys through `wslc` with credentials injected from Windows Credential Manager.
- [ ] Claude Code, Codex, and GitHub Copilot CLI work with subscription credentials.
- [ ] The Harmonia substituter is usable and signed, and consumers reject unsigned paths.
- [ ] An agent can install Nix packages at runtime as the non-root user, and prebuilt binaries and wheels run through the compatibility layer.
- [ ] Permitted local ports are reachable; unpermitted local destinations are blocked.
- [ ] One agent container's permissions do not grant access to another's permitted services.
- [ ] No Windows folders are mounted by default, and the container cannot run Windows executables.
- [ ] The start script brings up Debian services, egress, and an agent container in order after a host restart.
- [ ] The user can enter the container, and agent CLI commands run inside it.
- [ ] Container state survives a container restart and a WSL or host restart.
- [ ] Work can be pushed from the container to the host git remote.
- [ ] Teardown refuses to delete a container with uncommitted or unpushed work unless confirmed, and leaves caches, repositories, credentials, and images intact.

## Constraints

- Follow AGENTS.md and README.md.
- Keep secret values out of Nix expressions, images, generated configuration, and logs.
- Keep PowerShell thin; put build and deployment logic in Debian scripts.

## Out of Scope

- README Roadmap items (v2 and later), including Nexus CE, resource limits, and optional mounts.
- Agent-to-agent messaging and autonomous coordination.
- Internet domain allowlisting.
