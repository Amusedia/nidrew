---
name: workflow-retrospective
description: Review completed development work and available past sessions to propose reusable automation. Use when the user requests a workflow retrospective or asks what repeated work should become scripts or skills; do not invoke for ordinary implementation tasks.
---

# Workflow Retrospective

Review completed work separately from implementation. Produce recommendations for the user to select; leave automation and repository instructions unchanged during the review.

## Review

1. Establish the requested scope, such as a project, milestone, or set of sessions. Use available session records, repository history, diffs, test results, and existing scripts or skills. Do not imply access to sessions that are unavailable; identify evidence gaps in the report.
2. Find repeated multi-step procedures, recurring errors, and manual steps that are expensive or easy to get wrong. Cite concrete examples and distinguish a recurring pattern from a single incident.
3. Check whether an existing command, script, skill, test, or project workflow already covers each candidate. Prefer extending its owner when that avoids overlap.
4. Recommend the smallest useful form: a repository command or script for deterministic steps, a skill for a reusable decision-making workflow, or a test or documentation change for a recurring failure that automation would not solve. Recommend no new asset when the evidence is weak.

## Report

For each candidate, give the supporting examples, expected benefit, proposed owner and asset, and any important uncertainty. Rank candidates by likely value and effort. State which candidates should wait for more evidence. Ask the user which recommendations to pursue in a separate implementation task.

For approved follow-up work, follow the repository's tooling conventions. Keep scripts with their owning skill or repository tooling, and update the owning `SKILL.md` when skill scripts change. Propose changes to `AGENTS.md` for the user to apply manually.
