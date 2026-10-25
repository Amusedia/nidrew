# Planning

Start a new work stream or pick up an existing item from `todo/`. Choose a short, descriptive name with the user when needed. Move through these checkpoints with the user; revise a checkpoint when they correct an assumption.

## Understand and bound

Ask what problem the user wants to solve and what result they want. Reflect those answers back, then propose what is in and out of scope. Iterate on these four points with the user before analyzing solutions. Preserve their terms where they carry meaning. Continue when the user agrees on the boundary.

## Analyze

Inspect the relevant code, documents, and existing behavior. Describe the current state or current step and the gap to the desired result. Ask the user to validate that account. Identify constraints that shape viable solutions.

## Explore

Offer three materially different approaches to close the validated gap. Explain their important tradeoffs against the constraints and desired result. Discuss open questions, alternative decisions, revisions, and combinations with the user. Continue until they choose a direction; retain the reason, consequential alternatives, and unresolved questions.

## Specify and write

State the observable behavior expected from the chosen direction. Cover existing behavior touched by this work that must remain valid, existing behavior that changes, and new behavior. Write `work/{short-name}/plan.md` with the agreed discussion, using this outline:

```markdown
# <Work stream name>

## Problem

## Desired Result

## Scope

### In Scope

### Out of Scope

## Constraints

## Current State

## Gap

## Behavior Contract

### Existing behavior that must remain valid

### Existing behavior that changes

### New behavior

## Approaches

## Decisions

## Open Questions
```

In Approaches, record the options considered, tradeoffs, combinations, and chosen direction with its reason. Distinguish decisions from open questions. Under behavior that remains valid, include only existing behavior touched by this work. Review the completed plan with the user and obtain their agreement before decomposing it.

## Decompose

Read the [checklist template](implement.md#checklist-template) and write `work/{short-name}/checklist.md`. Make each item a coherent context unit that can reasonably be completed in a separate session. Give it enough context and a clear result to pick up later; group related changes by outcome rather than by file.
