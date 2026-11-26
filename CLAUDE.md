# Stall10 — Engineering Instructions

## 1. Product Overview

Stall10 is an ultimate frisbee ecosystem combining:

- Athlete social networking
- Team and organization management
- Community and pickup management
- Messaging and communication
- Scheduling and event management
- Statistics and performance tracking
- Playbooks and video analysis
- Tournament and league management
- Registration and payments

Stall10 will remain focused on ultimate frisbee for the initial release. Multi-sport expansion and rebranding are deferred.

## 2. Current Release Objective

- Founding-team beta: January 4, 2027
- Public release target: January 18, 2027

Current priorities, in order:

1. Security and data integrity
2. UI/UX modernization
3. Reliability of existing functionality
4. Automated testing and regression prevention
5. Application performance
6. Production and release readiness
7. User onboarding and retention

Major new features are frozen unless explicitly approved by the product owner.

## 3. Technology Stack

- Mobile: Flutter and Dart
- Web: Next.js and TypeScript
- Backend: Fastify and TypeScript
- Authentication: Firebase Authentication
- Database: Cloud Firestore
- File storage: Firebase Storage
- Notifications: Firebase Cloud Messaging
- Infrastructure: Google Cloud Run
- Payments: Stripe Connect
- Real-time audio/video: LiveKit
- Source control: GitHub monorepo

Verify the actual repository structure and installed dependencies before implementation.

Do not introduce major architectural changes, database migrations or replacement frameworks without approval.

## 4. Documentation

Product specifications are located in `docs/specifications/`.

These documents define the intended long-term product behavior. They do not establish that a feature is currently implemented or approved for January.

Before implementing a task:

1. Identify the relevant product specifications.
2. Review the current implementation.
3. Review approved release scope.
4. Identify discrepancies and dependencies.
5. Confirm acceptance criteria.

Prefer approved UI-updated specifications for visual design decisions.

Do not silently resolve conflicting requirements.

Documentation is not authorization to implement a feature.

## 5. Planning and Task Management

GitHub Projects and GitHub Issues are the source of truth for implementation progress.

Every implementation task should include:

- Feature or epic
- Objective
- Scope
- Acceptance criteria
- Priority
- Dependencies
- Estimated effort
- Target sprint
- Testing requirements

Priority definitions:

- P0: Release blocker, critical security issue or data integrity issue
- P1: Important January improvement
- P2: Non-blocking improvement
- P3: Future development

Do not expand an issue's scope without approval.

## 6. Subagent Organization

Use specialized subagents when appropriate:

- Planning agent
- Flutter development agent
- Web development agent
- Backend development agent
- QA and testing agent
- Security review agent
- UI/UX review agent
- Release and infrastructure agent

Parallelize independent work using isolated Git worktrees.

Before delegating parallel tasks:

- Identify shared dependencies.
- Establish API and component contracts.
- Define file ownership.
- Prevent conflicting modifications.
- Confirm the starting Git commit.

Initially limit concurrent implementation agents to three.

QA and security reviews should be independent of implementation whenever practical.

## 7. UI/UX Standards

Follow the approved Stall10 UI specifications.

The application should feel modern, athletic, social-first and consistent across platforms.

Prioritize:

- Shared design tokens
- Reusable components
- Light, dark and system themes
- Consistent typography and spacing
- Predictable navigation
- Responsive desktop and mobile layouts
- Accessible controls
- Loading, empty, error and success states

Avoid unnecessary screen-specific components and duplicated styling.

Do not change existing business logic solely to accomplish a visual redesign.

## 8. Backend and Security Standards

- Validate sensitive operations on the server.
- Never trust client-provided authorization or ownership claims.
- Verify authentication and resource-level permissions.
- Prevent unauthorized cross-team and cross-community access.
- Protect private messages, media and personal information.
- Validate all external inputs.
- Use idempotency where duplicate requests could cause harm.
- Handle concurrency and transactional operations safely.
- Never expose credentials or secrets.
- Never bypass security controls to resolve functionality problems.

Review both API authorization and Firebase security rules independently.

Financial functionality requires explicit approval and additional security validation before public activation.

## 9. Testing Requirements

Every implementation task must include appropriate testing.

Testing layers:

- Flutter unit and widget tests
- Flutter golden tests
- Mobile integration and end-to-end tests
- Web component tests
- Playwright browser tests
- Backend unit and API integration tests
- Firebase security rules tests
- Performance and load tests
- Physical-device acceptance testing

Use existing test frameworks where appropriate. Do not introduce redundant frameworks.

### Mandatory rules

- Run relevant existing tests before modifying code.
- Add regression tests for bug fixes where feasible.
- Test authorized and unauthorized behavior.
- Test invalid inputs and failure scenarios.
- Never remove, weaken or skip tests to make builds pass.
- Never claim a test passed without executing it.
- Report pre-existing failures separately.
- Identify tests requiring physical-device validation.

Automated tests must use isolated test environments and synthetic data.

Never run destructive tests against production.

## 10. Mobile Device Testing

The product owner currently has a physical iPhone and uses TestFlight.

Use the following testing environments as appropriate:

- iOS Simulator
- Android Emulator
- Flutter integration tests
- Maestro mobile workflows
- Firebase Test Lab
- TestFlight
- Google Play testing tracks

Physical-device validation remains necessary for notifications, camera, microphone, media playback, background behavior, network transitions and native permissions.

Do not claim physical-device compatibility based solely on simulator results.

## 11. Git and Pull Request Workflow

- Production branch: `main`
- Integration branch: `development`
- Implementation: isolated feature or fix branches

Confirm the current branch strategy before making changes.

Branch naming examples:

- `feature/123-home-redesign`
- `fix/124-team-authorization`
- `test/125-rsvp-regression`

Every pull request should include:

- Associated GitHub issue
- Summary of changes
- Acceptance criteria
- Tests executed
- Security implications
- Screenshots for visual changes
- Known limitations

Do not merge, deploy or modify production resources without explicit approval.

## 12. Definition of Done

An issue is complete only when:

- Acceptance criteria are satisfied.
- Relevant automated tests pass.
- Security implications are reviewed.
- Existing functionality is preserved.
- Relevant platforms are validated.
- Documentation is updated where necessary.
- Remaining manual testing is identified.
- The product owner approves the change.

Compilation alone does not establish completion.

## 13. Agent Completion Report

At the end of every implementation task, report:

1. Objective
2. Implementation summary
3. Files modified
4. Tests added
5. Tests executed
6. Passed, failed, skipped and unexecuted tests
7. Security considerations
8. Known limitations
9. Remaining manual validation
10. Recommended next steps

Clearly distinguish verified results from assumptions.

## 14. Restrictions

Do not perform the following without explicit approval:

- Add major new features
- Change product requirements
- Change payment processing behavior
- Modify database schemas
- Introduce major dependencies
- Replace architectural patterns
- Delete existing functionality
- Modify production data
- Deploy infrastructure
- Merge production releases
- Expand into additional sports

When uncertain, document the concern and request clarification.

## 15. Engineering Philosophy

Prefer simple, maintainable and testable implementations.

Prioritize correctness over development speed.

Reuse existing functionality before creating replacements.

The January objective is a polished, secure and reliable Stall10 release, not completion of the entire long-term product vision.

## UI/UX Implementation Authority

Reference `docs/design-system/Stall10_UI_Implementation_Guide.md` for all UI modernization tasks.

Consult Document 17 and the UI-updated product specifications for original visual concepts and mockups.

Requirements:

- Use shared semantic design tokens rather than hardcoded colors.
- Maintain visual consistency across Flutter and Next.js.
- Support light, dark and system themes.
- Implement reusable components before redesigning individual screens.
- Preserve existing functionality, permissions and navigation.
- Follow the documented responsive layout conventions.
- Include loading, empty, error, offline and success states.
- Add widget, golden or browser screenshot tests where appropriate.
- Do not introduce new functionality solely because it appears in a design concept.
- Obtain product owner approval for deviations from the design system.