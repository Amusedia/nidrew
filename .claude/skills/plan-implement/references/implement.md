# Implementation

Keep the work stream's implementation on one branch. For `next work/{short-name}/checklist.md`, read the plan and checklist, then take the first item whose Done section is empty. Complete that coherent context unit in this session, following repository coding and testing rules. Verify its behavior against the plan's Behavior Contract.

Use the checklist template below when filling the item. Summarize actual work under Summary. Commit the completed work, then record that commit's hash under Done; commit the checklist update separately so the branch is clean. An incomplete or blocked item keeps Done empty, with its state reported accurately.

Repeat in later sessions until every item is complete. When all items are done, present the work for user review or create a PR when that is the chosen review path. Address review feedback in the same work stream, updating the plan or checklist when the agreed work changes.

## Checklist Template

Use one block per item in `work/{short-name}/checklist.md`. Replace the work item name and steps. Leave Summary and Done empty until the item is implemented. Then list actual work under Summary and put the completing Git commit hash under Done.

```markdown
# <Work item name>

- <Step with a clear result>
- <Verification step>

## Summary

## Done
```
