---
name: plan-sprint
description: Proposes a Hylite sprint from approved January work — prioritised issues with acceptance criteria, estimates, dependencies, owners and parallel lanes — for the product owner to approve. Use when asked to plan a sprint, the next week of work, or what to build next.
argument-hint: "[sprint length or dates] [focus area]"
---

# Plan a sprint

This skill is read-only. It proposes a sprint; it doesn't start any work. Input: $ARGUMENTS

## 1. Collect approved scope
Read these:
- CLAUDE.md §2: priorities and the feature freeze
- `docs/specifications/release-audit.md`: proposed issues and decisions Q1–Q19, noting which are still open
- `docs/specifications/ui-migration-plan.md` and the UI rework task board: https://claude.ai/artifact/6NYWMKQmuuRJeHrKJSM1yS (read its `tasks` collection with ArtifactData)
- open GitHub issues (`gh issue list`), if `gh` is available

Only work that is approved, or on the board, goes in. Anything else becomes a question for the owner.

## 2. Check capacity and dates
- Use the owner's stated capacity. If none is given, assume about 35 hours a week and say so.
- Key dates:
  - Founding-team beta: Jan 4, 2027
  - App submission freeze: Jan 8
  - Public release: Jan 18
- Keep a defect reserve of about 15% of capacity.

## 3. Select and order
- Order by CLAUDE.md priority: P0 security and data integrity first, then UI, then reliability, and so on.
- Dependencies come first: tokens before components, components before screens, contracts before frontends.
- Use the planner agent for a deeper look at a single item if needed.

## 4. Produce the proposal
For each issue give:
- objective
- scope and exclusions
- acceptance criteria
- priority
- estimate
- dependencies
- recommended agent
- platforms affected
- likely files
- tests required
- target sprint

Then add:
- **Lanes:** up to three parallel implementation lanes with no file overlap. For each, the starting point and what it hands over.
- **Risks** and the **decisions needed** from the owner.
- **Out of scope:** what this sprint explicitly leaves out.

## 5. Present for approval
- Present the sprint as a short table plus the decision list.
- Offer to create the GitHub issues and board tasks only after the owner approves. Do not create them before then.
