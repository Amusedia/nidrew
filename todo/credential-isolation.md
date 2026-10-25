# Credential Isolation Through a Trusted Proxy

Investigate keeping agent credentials outside the Nidus and injecting them at
a trusted proxy only for approved services. This is deferred work, outside the
server setup checklist; it does not replace the external egress boundary or
change Harmonia's signing-key design.

## Motivation

The initial design injects tokens into agent containers. Processes sharing a
container can read those credentials. A trusted proxy could reduce raw-token
exposure by accepting placeholders and supplying real credentials upstream.

## Questions to Resolve

- What does the pinned Codex version's experimental network proxy support?
  Distinguish destination filtering from credential isolation; enabling the
  proxy alone does not establish that secrets are hidden from agent processes.
- Is there a documented, supported credential-injection mechanism suitable for
  local Nidrew containers? OpenAI Cloud network secrets demonstrate the pattern
  but do not establish equivalent local proxy functionality.
- Can it support Claude Code, Codex, and GitHub Copilot CLI subscription
  authentication, including sign-in, refresh, streaming, and credential rotation,
  without switching to API billing or undocumented provider interfaces?
- Where would the trusted proxy run, how would it retrieve credentials from
  Windows Credential Manager, and how would per-agent access be enforced?
- How would direct connections, redirects, logs, errors, and unapproved targets
  be handled without exposing credentials or bypassing the egress boundary?

## Verification Needed

- Use harmless canary credentials to check that raw values are absent from
  agent-visible files, environment variables, process arguments, and logs.
- Verify injection only for the intended destination and request scope, and
  rejection of bypass attempts and cross-agent credential use.
- Verify supported subscription flows for each CLI. Record tested versions,
  limitations, and whether the complexity is justified before changing the
  initial credential model.

## Starting References

- [Codex permissions and network proxy scope](https://learn.chatgpt.com/docs/permissions)
- [OpenAI security cookbook, including Cloud network secrets](https://learn.chatgpt.com/docs/enterprise/security-cookbook)

Recheck current documentation when starting this investigation; experimental
capabilities and configuration may change.
