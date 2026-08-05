---
name: repo-qa
description: Performs repository-wide QA to identify and prioritize existing reliability risks, maintainability hotspots, weak test boundaries, architectural friction, and refactoring opportunities. Use ONLY when the user explicitly requests repo QA, codebase QA, technical-debt assessment, reliability analysis, or refactoring priorities. Do not use for pull-request review.
---

# Repository QA

Assess the existing repository at a senior software engineer quality bar. The
goal is decision support: identify where reliability and maintainability work
will produce the greatest value, not every possible defect or code smell.

## Contract

- Audit an existing repository or an explicitly scoped subsystem.
- Include existing defects, technical debt, test weaknesses, architectural
  friction, and operational risks when supported by evidence.
- Prioritize remediation value over issue count.
- Do not use this workflow to review a pull request or attribute findings to a
  feature branch.
- Do not edit files, install dependencies, create commits, or open issues unless
  explicitly asked.
- Do not recommend a rewrite merely because a design is old or unfamiliar.

## Establish Scope And Baseline

Identify the repository, baseline revision, requested scope, and available
evidence before auditing. Prefer the repository's default branch unless the
user specifies another baseline. Do not silently mix uncommitted or feature
branch changes into a baseline audit.

For a large repository, map the whole repository first, then deep-dive into the
highest-risk areas. State which areas received deep inspection and which were
only sampled. If the requested scope is ambiguous in a way that would change
the result materially, resolve it before proceeding.

## Learn The Repository

1. Read applicable `AGENTS.md` files and repository documentation.
2. Map the architecture, runtime boundaries, data stores, external services,
   public APIs, build system, deployment model, and test layers.
3. Identify generated code, vendored code, experiments, deprecated areas, and
   components with different ownership or quality expectations.
4. Understand how the repository records failures: tests, CI, issue trackers,
   logs, incidents, migrations, changelogs, and operational documentation.

Do not judge unfamiliar patterns before understanding their local purpose and
constraints.

## Build An Evidence Map

Use available evidence rather than intuition alone:

- Change frequency, recurring bug-fix history, and frequently co-changed files
- Complexity, branching, statefulness, coupling, duplication, and dependency
  concentration
- Public contracts, schema boundaries, migration paths, and compatibility
- Error handling, cleanup, retries, idempotency, concurrency, and cancellation
- Authentication, authorization, data exposure, secret handling, and unsafe
  defaults
- Test distribution, missing boundary tests, flaky checks, weak assertions,
  slow feedback, and code that is difficult to isolate
- Build, lint, type-check, static-analysis, coverage, and CI results already
  supported by the repository
- Operational visibility, rollback, recovery, and failure containment
- Ownership concentration, documentation gaps, and knowledge bottlenecks

Treat commit-message heuristics, raw churn, and metric thresholds as leads, not
proof. Verify them against actual code and behavior.

## Use Independent Auditors

For a non-trivial repository, use fresh, read-only workers when available. The
active supervisor owns delegation and worker lifecycle; follow its
orchestration and permission rules.

Divide work by subsystem and cover independent lenses for:

1. Reliability, correctness, security, and operational failure modes.
2. Maintainability, architecture, dependency boundaries, and change friction.
3. Testability, QA coverage, observability, and safe-refactoring prerequisites.
4. Repository history and hotspot evidence.

Use the smallest pool that still gives meaningful coverage. Require auditors
to return evidence, affected paths, impact, and counterevidence, not generic
best-practice lists.

## Validate Hotspot Candidates

For each candidate hotspot:

1. Establish a concrete failure mode or recurring maintenance cost.
2. Confirm the issue in current baseline code and its reachable context.
3. Check history, neighboring code, tests, and documentation for intentional
   constraints or existing mitigations.
4. Distinguish symptoms that share one root cause.
5. Run focused repository-provided checks when they materially improve
   confidence. Do not install missing dependencies or alter source to run them.
6. Reject candidates that are subjective, low-impact, obsolete, generated,
   adequately isolated, or unsupported by evidence.

Do not enumerate low-value smells. A short, defensible portfolio is more useful
than an exhaustive backlog.

## Prioritize Work

Evaluate each validated hotspot across these dimensions without hiding the
judgment behind a single pseudo-precise score:

- Impact and blast radius
- Likelihood or demonstrated recurrence
- Change pressure and maintenance frequency
- Strength of the current test and operational safety net
- Improvement leverage and problems removed together
- Delivery cost, migration risk, and reversibility
- Confidence in the evidence

Assign it to:

- **Now**: urgent reliability risk or high-leverage work blocking safe change
- **Next**: valuable improvement that should follow prerequisite safety work
- **Later**: legitimate debt best addressed opportunistically or after higher
  leverage work
- **Do not prioritize**: real but currently isolated, low-value, or too risky
  relative to its benefit

Prefer incremental boundaries, characterization tests, observability, and
reversible migrations before invasive refactors. Explain when leaving code
alone is the better engineering decision.

## Design QA And Refactoring Guidance

For each recommended area, describe:

- The component and affected paths
- The observed failure or maintenance mode
- Evidence and counterevidence
- Why it matters now
- A bounded remediation direction
- Characterization, regression, integration, or operational tests required
  before changing it
- Migration, rollout, rollback, or compatibility constraints
- Expected leverage, rough effort, and confidence

Separate confirmed defects from structural risks and refactoring opportunities.
Do not claim that missing tests prove broken behavior.

## Report

Present the result in this order:

1. Prioritized `Now`, `Next`, and `Later` recommendations
2. Confirmed reliability and correctness risks
3. Maintainability and architectural hotspots
4. QA safety-net gaps and prerequisite tests
5. Areas explicitly not worth changing now
6. Audit scope, evidence used, checks run, coverage limits, and residual risks

Lead with the decisions the user can act on. For each recommendation, include
specific file references and enough evidence for another engineer to verify the
claim. If no high-value work survives validation, say so rather than padding
the report with minor issues.
