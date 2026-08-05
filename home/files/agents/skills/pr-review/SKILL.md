---
name: pr-review
description: Performs deep, evidence-driven review of a GitHub pull request for defects, regressions, maintainability degradation, test quality, and dependency-contract violations. Use ONLY when the user explicitly requests a PR review, pre-merge self-check, senior-level review, or review preparation for an incoming GitHub PR.
---

# PR Review

Review the pull request at a senior software engineer quality bar. Optimize for
technical correctness and actionable signal, not for the number of findings.

## Contract

- Review a GitHub pull request, not the repository in general.
- Focus on defects, regressions, debugging, maintainability, test quality,
  dependency contracts, security, performance, and operational safety.
- Leave product desirability and high-level business decisions to the user.
  Read the PR description, linked issues, and specifications only as needed to
  understand intended behavior and technical contracts.
- Do not edit files, switch branches, install dependencies, create commits,
  post review comments, approve, or request changes unless explicitly asked.
- Do not manufacture findings to make the review appear useful.

## Resolve The Pull Request

Resolve the target in this order:

1. A PR URL or number supplied by the user.
2. The pull request associated with the current branch.

Use `gh pr view` and `gh pr diff` to inspect the PR without checking it out.
If no PR can be resolved, stop and request an explicit PR target rather than
guessing a branch comparison.

Record the repository, PR number, title, base and head revisions, author,
description, changed files, commits, linked issues, and current check status.
State the exact revisions reviewed. Refresh metadata before the final report if
the head may have changed during a long review.

## Learn The Repository

Before judging the diff:

1. Read all repository and path-scoped instructions that apply to changed
   files, including `AGENTS.md` files.
2. Understand the relevant project structure, architecture, build and test
   workflow, generated-code boundaries, and conventions.
3. Inspect representative neighboring implementations and important call
   sites, interfaces, tests, schemas, and data flows affected by the change.
4. Use history or blame when it can explain a non-obvious design choice or
   establish whether behavior predates the PR.

Existing code is context and a comparison baseline, not an invitation to audit
the whole repository. Do not emit findings until repository understanding is
sufficient to evaluate the changed behavior.

## Establish Coverage And Risk

Account for every changed human-written file. Identify which of these lenses
apply to each changed area:

- Public APIs, schemas, serialization, and compatibility
- State transitions, validation, error handling, and cleanup
- Persistence, migrations, data integrity, and rollback
- Authentication, authorization, privacy, and secret handling
- Concurrency, retries, idempotency, ordering, and resource ownership
- Performance, limits, cancellation, and failure isolation
- Configuration, deployment, observability, and operational recovery
- UI behavior, accessibility, and user-visible failure states
- Tests, documentation, developer ergonomics, and generated artifacts
- External SDK, protocol, and dependency contracts

Skip irrelevant lenses rather than applying a generic checklist mechanically.
Review the complete changed behavior, not only the most visually interesting
part of the diff.

## Use Independent Reviewers

For a substantial PR, use the smallest useful set of fresh, read-only reviewers
available. The active supervisor owns delegation, worker lifecycle, and pane
management; follow its orchestration and permission rules.

Cover independent perspectives for:

1. Correctness, regressions, security, and failure behavior.
2. Maintainability, repository conventions, clarity, and API design.
3. Tests, QA scenarios, dependency specifications, and operational safety.

For a large PR, split coverage by subsystem as well as by perspective. For a
small PR, reduce the worker count or review directly. Give reviewers the exact
PR revisions and require file-and-line evidence. Keep candidate generation
independent; inspect existing review comments afterward to deduplicate rather
than anchoring the initial analysis.

## Review Code Quality

Check whether the PR:

- Diverges materially from established repository patterns without reason
- Adds unnecessary complexity, duplication, indirection, state, or coupling
- Weakens naming, boundaries, ownership, invariants, or misuse resistance
- Has a simpler implementation that concretely reduces invalid states,
  branching, duplication, or future maintenance cost
- Omits comments for a non-obvious reason, invariant, workaround, external
  constraint, or safety property
- Adds comments that merely restate code, obscure behavior, or are inaccurate

Do not report personal style preferences as defects. "More elegant" is not
sufficient evidence unless the alternative has a concrete maintenance or
correctness benefit and fits the repository's conventions.

## Debug And Verify Specifications

Trace important execution paths through surrounding code. Consider malformed,
empty, large, duplicated, reordered, concurrent, cancelled, and partially
failed inputs when applicable.

For external SDKs, protocols, and dependencies:

1. Determine the version actually selected by the repository.
2. Prefer local type definitions, schemas, lockfiles, authoritative versioned
   documentation, changelogs, or upstream source over memory.
3. Verify defaults, error behavior, lifecycle requirements, deprecations, and
   version-specific constraints used by the PR.
4. Do not assume documentation for the latest release applies to the pinned
   version.

## Validate Every Candidate

Before reporting a candidate:

1. Try to disprove it.
2. Read enough surrounding code and call sites to establish a reachable path.
3. Confirm that the PR introduced it or materially worsened, exposed, or
   depended on it.
4. Check whether types, validation, tests, generated checks, or invariants
   already prevent it.
5. Run focused repository-provided checks when safe and useful. Do not install
   missing dependencies or mutate source merely to run a check.
6. Deduplicate candidates that share one root cause.

Classify surviving material as:

- **Finding**: concrete, actionable, and caused or materially affected by the PR
- **Concern**: plausible but dependent on missing technical, runtime, or
  operational information
- **QA scenario**: behavior worth testing without claiming it is broken
- **Rejected**: disproved, unrelated, pre-existing, purely subjective, or
  already enforced mechanically

A missing test is a finding only when it leaves a concrete changed behavior or
regression path unprotected. Otherwise report it as a QA scenario or coverage
gap. Do not repeat formatter or linter output unless the check actually fails
and blocks PR readiness.

## Handle Pre-Existing Issues

The primary scope is behavior and code-quality degradation introduced by the
PR. Do not proactively search for unrelated existing defects.

When PR investigation reveals a pre-existing issue, include it in a separate
appendix only when all of these are true:

- Concrete evidence supports the issue.
- It is independently Critical or High severity.
- The affected execution path is currently reachable.
- It has meaningful security, data-integrity, availability, or major
  correctness impact.

Label it `Pre-existing` and explain why it is not attributed to the PR. Do not
include Medium, Low, stylistic, speculative, or maintainability-only existing
issues.

Pre-existing appendix items do not affect the PR verdict unless the PR relies
on, worsens, or exposes the issue. In that case, report the interaction as a
normal PR finding and describe the pre-existing root cause.

## Severity

- **Critical**: credible security compromise, data loss, severe outage, or
  irreversible corruption
- **High**: likely functional failure, contract break, major regression, or
  unsafe production behavior
- **Medium**: concrete edge-case failure, meaningful test gap, or maintenance
  degradation that should be addressed before merge
- **Low**: localized hygiene, clarity, documentation, or simplification issue
  with a concrete maintenance benefit

Do not inflate severity because a finding is interesting.

## Report

Present the report in this order:

1. Confirmed findings grouped by severity, highest first
2. Open concerns and questions
3. QA scenarios and missing coverage
4. Verification performed, results, and checks not run
5. Critical or High pre-existing issues appendix
6. PR scope, verdict, residual risks, and human review hotspots

For every finding include:

- A concise title
- `file:line` location using the smallest useful range
- Category and severity
- Evidence and triggering path
- Concrete impact
- Recommended direction, without implementing it
- Verification performed

Use `ready`, `ready with follow-ups`, or `not ready` for the verdict. If no
findings survive validation, say so explicitly and still report the reviewed
scope, verification, QA scenarios, and residual risks.
