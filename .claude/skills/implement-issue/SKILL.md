---
name: implement-issue
description: The standard Hylite workflow for implementing one approved issue end to end — requirements, baseline tests, owner approval, delegation to worktree agents, integration, independent QA and security review, regression and a completion report. Use when asked to implement, build or fix a GitHub issue or a task-board item.
argument-hint: "<issue number, board task code or short description>"
---

# Implement an issue

You run this as the **orchestrator** (main session). Do every step in order, and record what you found at each step so it can go into the completion report.

**Step 6 is a hard stop.** Do not delegate or write code until the owner approves.

Target: $ARGUMENTS

## 1. Requirements analysis
- Read the issue or board task. Find the relevant specs in `docs/specifications/` and any mock-up or UI guide section.
- Check the issue is approved for January (CLAUDE.md §2, the release audit and the task board). If the work is only in a spec or mock-up, stop and ask.
- Write down the objective, what's in scope and what's explicitly out.

## 2. Repository inspection
- Find the current implementation on both platforms: app, website, API and rules. Use the route map (`docs/specifications/navigation-route-map.md`) for anything to do with navigation.
- Note what already exists and can be reused, and anything that conflicts with the spec. Report conflicts; don't settle them yourself.

## 3. Dependency planning
- List the shared pieces this needs: tokens, components, API contracts, rules, fixtures. These must land before the work that depends on them.
- Split the work into tasks with **separate file ownership**. Two agents never own the same file.
- Mark which tasks can run in parallel, and which order the others must follow.

## 4. Acceptance criteria
- Write testable criteria, including:
  - authorized and unauthorized behaviour
  - invalid input
  - loading, empty, error and offline states
  - light and dark themes
  - phone and desktop widths
  - app/website parity
- Name the tests that will prove each criterion: unit, widget, golden, Playwright, rules or API.

## 5. Baseline testing
- Record the baseline: `git rev-parse feature/jan-4-release`.
- Run the relevant existing suites and record the counts. Report failures that were already there separately. Use `run-regression` with the scopes this issue touches.

## 6. Product owner approval: STOP
- Present the objective, scope, exclusions, plan, file ownership, acceptance criteria, tests, estimate, risks and any approval items. Approval items are:
  - new dependencies
  - schema, payment or contract changes
  - deploys
- Then wait. Continue only after the owner explicitly approves. If they change the plan, update it and present it again.

## 7. Agent delegation
- Use flutter-developer, web-developer and backend-developer, which work in worktrees.
- Each assignment includes:
  - the baseline SHA
  - the task
  - the files the agent owns and the files it must not touch
  - the acceptance criteria
  - the tests to add and run
  - the completion-report format
- If there is a shared dependency, assign it first, review it, and commit it to the integration branch. Then dependent tasks start from that new SHA.

## 8. Parallel implementation where appropriate
- Run at most **three** implementation agents at once, and only on independent tasks with no file overlap.
- Keep working while they run. Never predict or invent their results.

## 9. Integration
- Review each agent's diff yourself; don't rely only on its report.
- Bring the work into `feature/jan-4-release` locally with a merge or cherry-pick, then resolve conflicts.
- Run the affected suites on the **integrated** code.

## 10. Independent QA review
- Assign qa-engineer to the integrated commit, with the acceptance criteria.
- QA returns PASS, FAIL or INCOMPLETE. Send any FAIL back to the developer who owns the code, then run QA again.

## 11. Independent security review where applicable
- This is required when the change touches any of the following. Use the `security-audit` skill, scoped to the change set.
  - authentication or authorization
  - rules
  - the API
  - private data
  - messages or media
  - payments
  - user input that reaches the server
- Critical or high findings block the issue.

## 12. Regression testing
- Run `run-regression` on the full affected scope: both platforms if shared tokens or components changed.
- For UI changes, compare goldens and screenshots with `docs/ui-baseline/` and run `review-ui`.

## 13. Completion reporting
Report the following, keeping what you verified separate from what you assume:
1. Objective
2. Implementation summary
3. Files modified
4. Tests added
5. Tests run
6. Passed, failed, skipped and not-run tests, with failures that were already there listed separately
7. Security considerations
8. Known limitations
9. Remaining manual and physical-device validation
10. Recommended next steps

Then:
- Update the issue and the task board.
- Do not push, open a pull request or merge without the owner's approval.
