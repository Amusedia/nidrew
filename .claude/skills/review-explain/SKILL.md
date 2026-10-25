---
name: review-explain
description: Review an existing branch against its parent branch and explain the behavior it changes. Use when asked for an independent branch review or a behavior change report under work/{short-name}/.
---

# Review and Explain

Produce `work/{short-name}/review.md` from the branch diff and the code it affects. Do not read `work/{short-name}/plan.md` or `work/{short-name}/checklist.md`; derive claims from the branch, relevant repository code, tests, configuration, and governing instructions. Keep this review independent of the work stream's intentions.

## Establish the comparison

- Use the parent branch named by the user. Otherwise use the branch's configured upstream when it is the parent; if that is unavailable, use the repository's `trunk` or `main` branch. Ask for the parent when these do not identify one unambiguously.
- Use the supplied short name. Otherwise use the branch's final path component when the matching `work/{short-name}/` directory exists. Ask for the output path if it remains ambiguous.
- Record the parent branch, merge-base commit, reviewed branch commit, and review date. Compare the merge base to the reviewed commit so later changes on the parent do not appear as branch changes.
- Review committed changes by default. State whether uncommitted changes were present and excluded. Do not overwrite an existing review without preserving still-valid content.

## Investigate

1. Inventory changed files and commits. Follow changed code through callers, public boundaries, tests, data formats, configuration, and deployment paths where relevant.
2. Explain observable behavior before and after the branch, including new behavior, changed defaults, errors, and compatibility effects. Distinguish observed facts from inferences. Do not claim the branch meets its intended requirements without an independent source for those requirements.
3. Assess every dimension below. Use `checked` with specific evidence, `concern` with a concrete finding, `n/a` when the branch does not affect the dimension, or `unknown` when it may matter but the evidence is insufficient. Give a short reason for every `n/a` or `unknown`. A passing test supports only the behavior it exercises.
4. Run focused verification when practical. Record exact commands and outcomes. State what was not verified and why.

## Dimensions

- Observable behavior and backward compatibility
- Architecture and dependency boundaries
- Data integrity, persistence, and migrations
- Security and privacy
- Errors, recovery, and failure modes
- Performance and resource use
- Concurrency, cancellation, and lifecycle
- Configuration, deployment, and operations
- Tests and documentation

Add a dimension when the branch exposes a material concern not covered above. For findings, give impact, the conditions that trigger the issue, and precise file references. Do not turn speculative risks into findings; mark them `unknown` and name the evidence needed.

## Report

Write `work/{short-name}/review.md` with these sections:

1. **Scope:** parent, merge base, reviewed commit, date, and working-tree scope.
2. **What changed:** concise description of the branch's main changes.
3. **Behavior compared with parent:** concrete before/after behavior, in a table when useful.
4. **Dimensions:** status, evidence or reason, and relevant file references for each dimension.
5. **Findings:** actionable concerns, ordered by impact; state when none were found.
6. **Verification and limits:** commands, results, and remaining unknowns.

Keep the report useful to a reader who has not seen the plan or checklist. Link claims to code, tests, commits, or command results. Preserve the difference between a verified result, a code-based inference, and an untested possibility.
