# Agent orchestration setup: for review

**Status:** proposal, prepared 2026-11-26 on `feature/jan-4-release` (baseline `2c54ca2`).

**Applied 2026-11-26:** the settings (§4) and the CLAUDE.md additions (§5). **Not yet committed.**

**Untouched:** application code, deployments, branches, schemas and production data.

## 1. What was already there

The nine agents in `.claude/agents/` and `.claude/settings.json` (`{"agent": "orchestrator"}`) already existed. They were written by the owner just before this setup. **None was replaced.**
- Each keeps its frontmatter and original text unchanged.
- New sections were appended after the marker `<!-- hylite-orchestration v1 -->`.
- The originals are backed up in the session scratchpad.

`.claude/launch.json` (git-ignored), `settings.local.json` and the empty `.claude/worktrees/` folder were left alone.

## 2. Agents

| Agent | Model | Tools | Isolation | What was added |
|---|---|---|---|---|
| orchestrator | Opus | All | Main session (`settings.json` → `agent`) | Integration branch and baseline rule, worktree start-point warning, limit of three implementation agents, the fact that subagents can't nest, five approval gates, skills list, progress tracking, Windows path note |
| planner | Sonnet | Read, Grep, Glob | — | Read-only working note, project rules |
| flutter-developer | Sonnet | All | Worktree | Start-up checks (location, baseline SHA, `flutter pub get`, baseline tests), file ownership, project rules, completion report |
| web-developer | Sonnet | All | Worktree | Same, plus the Next.js version warning and a rule against adding dependencies without approval |
| backend-developer | Sonnet | All | Worktree | Same, plus API contract first, rules tests, and approval for schema/payment/deploy |
| ui-ux-reviewer | Sonnet | Read, Grep, Glob | — | Read-only working note, approved design decisions, project rules |
| qa-engineer | Sonnet | All | — | Test files only (stated rule), Windows-only goldens, completion report |
| security-reviewer | Opus | Read, Grep, Glob | — | Read-only working note, project rules |
| release-engineer | Sonnet | All | — | List of commands it must never run (push, deploy, prod), project rules |

**Project rules added to every agent.** Subagents don't see the owner's private notes, so these were copied in:
- Never open secret files.
- Never push or merge to `development` or `main` without approval.
- No deploys.
- No production data.
- Pass `--dart-define-from-file` on every Flutter run/build.
- Use MVVM with `provider`.
- No USA Ultimate data or features.
- Keep the app and website in parity.
- No product renaming.
- Use the approved UI references.

**File ownership:**

| Area | Owner |
|---|---|
| `apps/mobile/**` | flutter-developer |
| `apps/web/**` | web-developer |
| `apps/api/**`, `firebase/**`, `packages/shared/src/**` | backend-developer |
| `**/test/**`, `**/tests/**` | qa-engineer, when assigned |
| `.github/workflows/**`, `codemagic.yaml` | release-engineer, when assigned |

The shared areas below are assigned per task by the orchestrator, so no two agents own them at once:
- `lib/ui/core/**`
- `lib/routing/**`
- the website CSS and `AppFrame.tsx`
- `packages/shared/fixtures/**`

## 3. Skills (`.claude/skills/<name>/SKILL.md`)

| Skill | Purpose | Writes code? |
|---|---|---|
| `plan-sprint` | Propose a sprint from approved work, with lanes, estimates and decisions | No |
| `audit-feature` | Requirement-by-requirement audit of one feature on every layer, with file:line evidence | No |
| `implement-issue` | The 13-step workflow; step 6 (owner approval) is a hard stop | Yes, after approval |
| `review-ui` | Goldens, screenshots and axe compared with the before-pictures and the approved design | No (runs tests) |
| `run-regression` | Every suite with exact counts; failures that were already there kept separate | No (runs tests) |
| `security-audit` | Independent review of a change set; critical or high findings block | No (runs emulator tests) |
| `release-check` | Go/no-go for a beta, store or web release, with commands for the owner | No |

`run-regression` covers these suites:

| Suite | Command |
|---|---|
| App analyze | `flutter analyze` |
| App tests | `flutter test` |
| Web typecheck | `pnpm typecheck` |
| Web component tests | `pnpm test` |
| Web browser tests | `pnpm test:e2e` |
| API | `pnpm --filter @stall10/api test` |
| Shared | `pnpm --filter @stall10/shared test` |
| Versions | `node scripts/check-versions.mjs` |
| Firebase rules | `npm run test:rules` |

## 4. Settings (applied to `.claude/settings.json`)

**The most important change is `worktree.baseRef: "head"`.**
- With today's default (`fresh`), a worktree agent starts from `origin/main`. This was **verified**: a probe worktree was created at `090e7b4` (`main`), which has no monorepo and none of the January work.
- With `head`, worktrees start from the checked-out commit, which is the integration branch.
- The orchestrator also passes each agent a baseline SHA, and the agent stops if its worktree doesn't match.

**Permissions:**
- **deny:**
  - Reading or editing secret files: `*.local.json`, `.env`, `.env.local`, Firebase plists and `google-services.json`, signing keys, `Secrets.xcconfig`.
  - Force-pushing.
  - Deploying to `--project prod`.
- **ask:** push, merge, rebase, hard reset, creating or merging pull requests, `firebase deploy`, Cloud Run deploy and replace, Cloud Build submit, `vercel`.

**Limits:**
- A `Read(...)` deny doesn't stop a shell command such as `cat`. The written rules in every agent still matter.
- The limit of three agents is a written rule. Nothing in the settings enforces it.

Applied, keeping `"agent": "orchestrator"`.

## 5. CLAUDE.md additions (applied: naming note in §1, integration branch in §11, UI guide path, new §16)

**Naming.** CLAUDE.md §1 says "rebranding is deferred" and uses Stall10, while the agents say "Hylite, previously Stall10". These need to agree. The proposal:
- Use Hylite as the working name in engineering docs.
- Keep the rule that the product itself (app strings, bundle IDs, domains, package names) is not renamed without approval.

**Integration branch.** CLAUDE.md §11 names `development`, but January work is on `feature/jan-4-release` by the owner's decision. The proposal is to add that this branch reaches `development` only through an approved pull request.

**Owner rules that live only in private memory today.** The proposal is to copy these into CLAUDE.md so every session and agent sees them:
- secret files;
- asking before each push;
- deploys by named group;
- `--dart-define-from-file`;
- MVVM with `provider`;
- no USA Ultimate data;
- parity;
- Windows-only goldens.

## 6. Verification

| Item | Result |
|---|---|
| Nine agents load | **Verified**: the session lists all nine agent types, with tools and descriptions matching the files |
| Agent text amended, originals kept | **Verified**: frontmatter and opening lines unchanged (diffed against the backups) |
| Seven skills load | **Verified**: the session now lists all seven skills with their descriptions |
| Test commands in skills | **Verified** they exist in `package.json` / `pubspec` (api `test`, shared `test`, functions `test:rules`, web `test`/`test:e2e`) |
| Worktree start point | **Verified wrong today** (probe at `main` `090e7b4`). The probe worktree and its branch were removed |
| Worktree isolation on this machine | **Verified blocked** when Claude Code is started from `C:\Users\brian\git\frisbee_app` (lowercase). Git reports `C:/Users/brian/Git/...`, and isolation refuses the mismatch. Start from `C:\Users\brian\Git\frisbee_app` |
| Paths named in agents and skills | **Verified** they exist: the UI guide, the four boards, the security reviews, the release audit, the route map, `AGENTS.md`, `codemagic.yaml`, the workflows and `check-versions.mjs` |
| `"agent": "orchestrator"` | Takes effect in new sessions. **Not verified** in this session |

## 7. Still needs configuration or a decision

1. Approve and apply the proposed settings (§4), above all `worktree.baseRef: "head"`.
2. Restart Claude Code from `C:\Users\brian\Git\frisbee_app` (capital G). Then re-run the worktree probe to confirm the start commit matches the integration branch.
3. Decide on naming: Hylite in CLAUDE.md, or keep Stall10 (§5).
4. Approve the CLAUDE.md additions (§5). Also fix one broken path: CLAUDE.md points to `docs/design-system/Stall10_UI_Implementation_Guide.md`, which doesn't exist. The guide is at `docs/specifications/audit/Stall10_UI_Implementation_Guide.md`, and the agents and skills use that path.
5. Decide whether `.claude/agents`, `.claude/skills` and `.claude/settings.json` are committed, so they are shared through git. `settings.local.json`, `launch.json` and `worktrees/` are already ignored.
6. Set up `gh` CLI authentication if agents should read and write GitHub Issues/Projects. It wasn't found on PATH in this shell.
7. Optional: a signed-in **test account** on the dev project, so browser tests can cover member pages. Its password must stay out of the repo.
8. Optional: update Node to 22.19+ or 24 LTS, so the website test setup can use the current jsdom.

After approval: a read-only repository audit and a proposed first sprint (using `plan-sprint`). These build on `release-audit.md` and the task board rather than repeating the seven-agent audit.
