# Deep Research Runtime: Bounded Research, Authorship, and Review

## 1. Status and scope

This document defines the target design. A first runtime implementation now exists
in this branch; Section 12.9 distinguishes implemented behavior and offline checks
from the remaining delivery and production gates. It has not been deployed.
**Decision: use one author with source-grounded review and bounded correction
for the initial implementation. Do not make independent chapter contributors
the default.** The magazine-style candidate was implemented as a limited
feasibility experiment, including recovery from saved chapters, but did not earn
its additional coordination cost in the tested case: the independent AI grader
scored the single-author result 91/100 and the magazine result 85/100.

Retain the useful editorial principles: durable manuscripts, bounded requests,
explicit responsibilities, source-backed findings, and runtime-owned references.
Defer an independent contributor pool until a task demonstrates its value.
Section 3 defines the selected implementation; Section 12 records the experiments,
their protocol changes, and limitations. Unverified behavior is a release gate,
not an implied capability. These observations are not a universal judgment about
multi-author research and do not constitute human evaluation or production approval.

The product goal is one user request in Open WebUI producing a useful,
source-grounded research report in the requested language. A long collection of
excerpts, successful HTTP response, valid JSON, or passing contract tests is not
a successful research report. The initial research scope is public web and
public PDF sources; private connectors and arbitrary local file access are not
part of this redesign.

The specification covers the Open WebUI entry point, research runtime,
Sakura/Kimi execution boundary, evidence storage, editorial workflow, recovery,
publication, and acceptance criteria. It does not replace ordinary chat models,
Open WebUI Computer, or unrelated services.

**MUST** denotes a required invariant. Numerical operating defaults below are
explicit engineering choices unless identified as measured or provider
documented. They are not claims of model quality or guaranteed completion time.

**Practical quality objective:** aim for a useful high-quality delivery within
at most two candidate generations, not a proof of perfect consistency. The user
explicitly accepts bounded regeneration when a report is unsatisfactory. Ordinary
uncertainty, cosmetic imperfections, and optional citation refinements must not
make an otherwise useful report unavailable. Security, artifact integrity, and
explicit resource limits remain separate hard execution requirements.

## 2. Constraints and architectural decisions

### 2.1 Non-negotiable constraints

1. Treat Sakura's five-minute inference timeout as a provider boundary. A longer
   SDK, proxy, or research-job timeout cannot extend it. Streaming is not an
   assumed exemption.
2. Do not rely on Open WebUI compacting an in-progress tool turn. Internal
   research transcripts MUST remain outside the Open WebUI conversation.
3. A model's advertised context window is not a reliable-memory guarantee.
   Admission MUST account for the complete serialized model input and reserve
   space for generation according to the provider's accounting rules.
4. Preserved-thinking tool conversations MUST retain the required original
   reasoning and complete tool-call/result relationships while that conversation
   continues. Do not silently trim or summarize an open tool turn.
5. Source documents, accepted drafts, budgets, and publication state MUST survive
   a later writer failure. Incomplete material MUST NOT be labeled completed.
6. Provider attempts are billable external actions. Database idempotency does
   not provide exactly-once provider execution.

### 2.2 Chosen division of responsibility

| Component | Owns | Does not own |
| --- | --- | --- |
| Open WebUI adapter | Authenticated submission, progress, cancellation request, exact result delivery | Research context, autonomous model polling, editorial judgment |
| Runtime scheduler | Assignment state, admission, deadlines, budgets, persistence, validation | Hard-coded search strategy or the truth of a claim |
| Researcher | Scope, adaptive investigation, source adequacy, counterevidence, unresolved questions | Budget overrides or an independent worker pool |
| Author/editor | One coherent report, its outline, bounded draft revisions, terminology and synthesis | Inventing evidence or relying on an indefinitely retained conversation |
| Reviewer | Source-grounded, revision-specific findings against the complete user question | Unconditionally authoritative edits or mechanical truth guarantees |
| Source store | Immutable extracted documents and addressable evidence | Treating model summaries as original sources |
| Sakura gateway | Credential isolation, shared account admission, one outbound transmission per physical attempt | Hidden retry, model substitution, silent reasoning-effort downgrade |

These are roles/invocations, not different model deployments or long-lived agents.
The initial implementation uses the existing Kimi provider and Python dependencies,
one author role, and provider concurrency **one**. A fresh reviewer invocation
does not share the author's private reasoning. Later sequential writing segments
can share one editorial authority without introducing independent contributors.

### 2.3 Retain and replace

Retain FastAPI, SQLite/WAL, safe HTTP/PDF extraction, provenance, credential
isolation, cancellation handling, and exact final-output delivery where their
contracts still apply. Reuse the existing Kimi adapter when native tool
continuation is used.

Replace these behaviors rather than preserving them behind a fallback:

- Discarding extracted documents after producing one short excerpt.
- Excluding different pages simply because they share a host.
- Equating distinct-host counts with semantic requirement completion.
- Isolated chapter generation followed by unreviewed concatenation.
- Copying evidence excerpts into failed chapters to fill a report-shaped output.
- Letting a general-purpose proxy retry research requests invisibly.

No new vector database, agent graph framework, message broker, or generalized
workflow engine is required. Use the existing asynchronous runtime and SQLite.

## 3. Editorial workflow

```text
submit -> scope and adaptive research <-> source store
       -> one author: complete bounded draft
       -> fresh source-grounded review using runtime-owned block IDs
       -> verify findings -> correct only justified issues if needed
       -> publication validation -> immutable publication -> exact delivery
```

### 3.1 Scope and research

Convert the request into an explicit question checklist, scope exclusions,
language, time horizon, and expected source types. Preliminary findings inform
the outline; do not fix a report's chapters before examining evidence.

The researcher can search, select candidate documents, read stored passages,
follow references through safe fetch, and investigate counterevidence. The
scheduler validates operations and budgets, not a predetermined fetch order.
It must not reduce adaptive investigation to filling uncovered IDs with queries.

Persist the question checklist, source/evidence references, findings, relevant
conditions, and unresolved questions. Every bounded assignment receives its
purpose, current evidence index, limits, and expected output. Changing an outline
or splitting work never increases the original job budget.

### 3.2 Single-author drafting

The author receives the original request, research findings, a source index with
read access to relevant passages, and the current editorial state. It produces
one coherent plain-Markdown report, including its introduction and conclusion.
Do not pay another model call merely to add framing to an already complete report.

Research and writing are separate bounded actions. The default `single_unit`
profile writes one draft unit. The explicit `sequential_long` profile supports
two to four saved units under the same author role. This implements the bounded
mechanism in Section 3.4, not a guarantee of arbitrary report length or unattended
quality. A request outside the admitted scope requires an explicit limit response,
not silent shortening.

The durable manuscript state contains the draft, outline, material claim/source
references, numeric conditions, gaps, and source/input revisions. Use research
findings and the review output to maintain this state; do not wrap the complete
prose in JSON just to obtain metadata. The runtime owns block IDs, provenance,
the bibliography, and structural validation.

### 3.3 Scientific supervision

Review the manuscript against the original checklist and actual source passages,
not only an abstract. Check entailment, numeric units/conditions, primary-source
adequacy, counterevidence, gaps, contradictions, repetition, and whether comparisons
are comparable. Different hosts do not establish independence: syndicated reports
of one original study remain one evidence origin.

Reviews reference exact draft revisions. A review returns concrete issues and
the smallest affected scope. Corrections return to the author/editor.
An unverified objection is not automatically a publication blocker. Keep it as a
qualified note or dismiss it unless concrete evidence establishes a material
consequence. A demonstrated decision-changing defect requires correction or a
new candidate. Editing consumes the original budget and is bounded.

A model review is a **fallible change proposal**, not an authority to overwrite
correct text. Before alleging an omission, the reviewer must inspect the actual
relevant passage and assess coverage across the whole report. It must not require
each chapter to repeat information already supplied by another chapter. Findings
must explain their source-grounded, decision-relevant consequence; cosmetic
preferences alone should not trigger expensive rewriting.

Classify findings by the action they justify:

- **Material:** changes the answer, violates an explicit user requirement,
  misrepresents a comparison, invents a source/result, or makes an operational
  recommendation materially wrong. The finding identifies affected blocks and
  explains the concrete consequence of leaving them unchanged.
- **Benign:** style, redundant co-citations where another cited source supports
  the claim, optional detail, or ordinary uncertainty that is stated honestly.
  Publish with an appropriate caveat if useful; do not schedule mandatory edits.
- **Unsupported:** a mistaken or speculative reviewer proposal. Preserve the
  reason for dismissal; never apply it simply because a reviewer said so.

The presence or count of comments is not the gate. A good report with five minor
notes is preferable to an unavailable report after five needless repair cycles.

The runtime assigns stable block IDs to an immutable draft revision. A review
selects these IDs; the runtime resolves the owning segment and exact original
text. Do not ask the model to reproduce a long quote and then make byte-for-byte
copying a condition of successful review. A valid block reference proves which
text was examined, not that the criticism is correct.

For example, a minimal proposed finding is:

```json
{"patches":[{"block_ids":["D:r3:p004"],"ledger_ids":["K-LAT"],"source_ids":["S1"],"reason":"Explain the concrete material consequence."}],"notes":[],"regenerate_reason":null}
```

Only IDs admitted in the current review's revision manifest are valid. Missing,
foreign, or stale references fail validation. Quote text and segment ownership
are derived from the manifest, not supplied redundantly by the model. The same
principle applies to evidence: select stored passage IDs and obtain verbatim text
from the source store rather than treating a regenerated quote as original data.

The author/editor checks a proposed correction against the current draft
and sources and may reject an unsupported finding with a recorded explanation.
Preserve the original revision and the finding even when rejected. Separate
actionable patches from notes rather than treating every `issues` entry as work
that must be completed. Do not ask for a redundant `needs_revision` flag.
Source-backed dismissals must be visible to any subsequent checker, so it does
not blindly reassert the old proposal. Recheck changed material, not every
unchanged passage or every harmless disagreement.

### 3.4 Editing without a full-report context window

One author/editor owns coherence; this does not require one huge model call or
an indefinitely retained context. For a small report, a bounded full-draft revision
is acceptable and was observed in the experiment. Do not rewrite a correct report
when the review has no justified issues.

The sequential implementation uses the following rules under the same author role;
production quality calibration remains separate:

1. Preserve an outline, accepted key claims, terminology, and outstanding issues.
2. Generate a bounded segment, commit it, and start the next bounded invocation
   with that state and addressable earlier text. Do not spawn independent authors.
3. Reopen related segments and source passages to resolve specific inconsistencies;
   summaries are navigation, not the only surviving evidence.
4. Replace only affected blocks/segments against their exact base revisions.
   Revalidate changed claims and invalidate dependent review acceptance.
5. Check the complete question coverage and synthesis before assembly. Unchanged
   accepted segments remain intact; do not regenerate the entire report to edit one part.

The single-draft path and a calibrated four-unit sequential prototype were
exercised. The latter produced more than 14,000 prose characters, resumed from a
saved two-unit checkpoint without regenerating earlier units, and repaired one
controlled defect locally in a separate diagnostic copy. Section 12.7 records
the exact evidence and calibration.
This closes a limited generation/checkpoint feasibility question, **not** the
unattended long-report publication gate: ordinary review left unresolved findings.

Before promoting long reports, strengthen the public editorial state beyond
arbitrary selected paragraphs. Persist each adopted decision's stable ID, metric,
unit, comparator, acceptance direction, applicable execution mode/stage, unresolved
threshold owner, and the source/draft block supporting it. Later prose must reuse
that declaration; a material change requires an explicit next-candidate revision,
not a silent mid-candidate edit. A p95 gate must not
silently become p99; an expected GIL state must depend on the selected execution
mode, not become an unconditional startup assertion. A small record beside the
existing checkpoint is sufficient; this is not a requirement for a new graph engine.

The follow-up in Section 12.8 exercises a small decision ledger and materiality-based
editing. It supports the mechanism, not a claim of unattended reliability: the
harness needed explicit reconciliation and the ledger itself remained fallible.
Reviews must distinguish substantive contradictions from optional citation/style
changes and reserve both correction and recheck capacity. An empty issue list or
a high aggregate AI grade is not a completeness certificate. Keep unresolved work
visible rather than blindly spending more calls or promoting a merely long
candidate to completed publication.

The ledger is small public editorial state, not a truth database or an ontology
of every claim. Track roughly 8–12 important cross-section commitments. Separate
configuration modes from transition conditions; `gil=enabled/disabled` is an
expected state, not a place to bury an ambiguous conditional paragraph. Each
criterion records its metric, unit, comparison basis, applicable mode/stage,
condition, and whether it is a source fact, user requirement, proposal, or unknown.

Use one reference namespace for provenance with explicit document, request, and
draft-block identities. A proposed criterion originating in an earlier manuscript
must be able to reference that block; it must not be mislabeled as a fact from an
external source. The runtime resolves references and preserves their provenance.

For goals and acceptance thresholds, explicit user requirements outrank author
proposals. For factual reality, primary evidence outranks an erroneous premise;
user assumptions remain labeled assumptions. The ledger never overrides the
original request or sources. Retrospective extraction preserves an unresolved
conflict instead of silently choosing the later wording as canonical.

Commit the ledger before drafting a candidate and keep it immutable within that
candidate. If the ledger itself is wrong, create an explicit revised ledger for
the next candidate, retaining original user constraints and evidence. Do not build
a dynamic dependency-update engine merely to hot-edit the ledger mid-candidate.

### 3.5 Publication

The runtime assembles revisions accepted by the bounded practical editorial
policy, not revisions claimed to be mathematically proven consistent. In one
transaction it records the ordered revision set, final Markdown, bibliography,
limitations, and publication identity. Publication is immutable. A later update
produces a new publication rather than modifying an already delivered result.

Use three explicit quality outcomes:

- `publish`: useful, essential scope covered, major claims traceable, and no
  remaining substantiated material blocker.
- `publish_with_caveats`: the same useful report, with benign warnings or honestly
  stated uncertainty that does not make the conclusion misleading.
- `retryable_quality_failure`: material error, missing essential scope, or a
  sufficiently poor report warrants another candidate instead of publication
  as an approved result.

Apply at most one bounded editorial pass per candidate. If the result remains
materially poor, permit one fresh second candidate using the collected evidence,
unchanged explicit user requirements, and specific failure feedback. Avoid
repeating a bad ledger or an identical unhelpful strategy. Do not require a second
candidate when the first delivered report is already good.

Bound the edit by admitted input/output, time, and one round, not an arbitrary
number of findings or changed blocks. Supply the actual target blocks, evidence,
ledger, and a small whole-report heading/handoff map so local missing detail is
not mistaken for a global omission. If material work does not fit, use the second
candidate or return `needs_review`; do not silently omit targets. A recheck covers
both replacements and evidence-backed dismissals within that workspace.

After two unsuccessful candidates, retain the best available draft and explain
its remaining gaps as `needs_review`; do not fabricate replacement chapters or
mislabel a known poor result as a good completed report. An explicit later user
regeneration is new authorization, not an infinite internal repair loop.

`needs_review` is a `delivery_status` label for an incomplete editorial package
(`status=incomplete`), not an additional run status or quality outcome. Set
`quality_outcome=retryable_quality_failure` for a completed negative quality
decision, or `null` if review could not finish. Do not infer poor content merely
from an execution failure. Authorization or artifact-integrity failures remain
`status=failed`; this presentation label does not weaken those boundaries.

Automatic publication is an orchestrated decision based on bounded checks and
model judgment. It is not a guarantee that all semantic errors were found.
Measure false acceptance and overblocking through independent quality checks and
user feedback, rather than increasing review layers until every critic is silent.

### 3.6 Evaluated, deferred alternative: independent chapter contributors

The tested magazine candidate independently generated two chapters, reviewed them
together, revised only affected chapters, and used an editor for short framing
before mechanical assembly. This mechanism eventually completed after replacing
model-copied quotes with runtime-owned references. Its output scored lower and
used more calls/tokens than the single-author result in this case.

Do not implement a contributor pool, parallel authoring, or a separate mandatory
magazine execution path in the initial release. Reconsider only when independent
research streams or a measured long-report bottleneck justify it. Require a
pre-registered, representative comparison including coordination failures and
recovery cost. Keep this alternative as a documented research result, not a hidden
fallback or speculative production scaffold.

## 4. Provider requests, contexts, and budgets

### 4.1 Three different units

| Unit | Definition |
| --- | --- |
| Research job | One user-authorized investigation, including research, writing, review, and editing |
| Assignment | A bounded research, writing, review, or editing task with persisted inputs/outputs |
| Physical attempt | One HTTP inference request transmitted to Sakura |

An SDK invocation or tool loop may contain multiple physical attempts. All of
them MUST be metered, including structured-output repair and continuation.

Each **physical attempt** has a **240-second total client deadline**, leaving
60 seconds below the assumed provider ceiling. The runtime first acquires its
local concurrency permit, then commits the attempt ID, reservation, and absolute
expiry before dispatching to the gateway. The gateway acquires its shared account
lease within that same expiry; no separate distributed lease protocol is needed.
This conservative deadline includes any gateway queueing, connection setup,
request transmission, response headers, and response streaming, not merely
socket-idle time. Neither SDK nor gateway may reset it. Waiting for the runtime's
local permit consumes job time without transmitting an inference request.

The runtime owns the durable budget/attempt journal; the gateway owns account
leases and the single upstream transmission. Distinguish a reserved/dispatch-intent
attempt from a confirmed transmission. A trusted gateway can report that it never
sent a request, but loss of the response is not such evidence: retain a conservative
reservation and unknown state. No caller may turn an uncertain count into zero.

Reserve job time for parsing, validation, and persistence before starting a model
request. A response that finished within its request deadline is not made late
merely because its subsequent database commit uses that reserved tail. Conversely,
an incomplete stream or a late response is never promoted to an accepted draft.

Native tool continuation and corrective generation are new physical attempts,
each with a new ID, a reservation, and their own bounded deadline. The aggregate
assignment/job may exceed five minutes. A timeout without confirmed provider
completion produces `unknown`, not a known failed or safely cancelled inference.
The client deadline protects the local budget; it cannot guarantee model completion
or prove upstream cancellation.

Research mode MUST disable SDK and proxy retries. The current proxy's general
chat retry policy is not an acceptable research transport. Add a narrowly scoped,
authenticated research mode to the existing gateway, sharing account leases and
rate-limit state with normal traffic. Its request identity, deadline, and
physical-attempt accounting must be explicit. Do not silently change normal
chat's behavior or copy provider credentials into prompts or the UI.

### 4.2 Context admission and reconstruction

Upstream Kimi documentation describes K2.7-Code as a 256K-context model with
always-on preserved thinking. It does not support `reasoning_effort`, disabling
thinking, or `tool_choice: "required"`. Do not copy a generic OpenAI parameter
profile or use forced-tool structured output as an assumed capability. Sakura's
`preview/Kimi-K2.7-Code` alias must be checked separately; upstream documentation
and a gateway accepting a parameter are not proof of identical behavior.

Writing/editorial calls should use ordinary completion content with validated
citation references. Small action envelopes can be parsed and validated without
requiring a forced tool call. Native research tools use only the supported
selection modes. A complete response with invalid structure is a known failed
assignment, not grounds for hidden SDK repair loops. `finish_reason=length` is
not an accepted finished draft.

Before each physical attempt, account for system instructions, tool schemas,
retained messages and required reasoning replay, source passages, draft/editorial
state, and output reservation under the provider's token rules. A message count
or character-to-token guess is not a certified token budget.

Use a verified tokenizer/accounting method and a conservative operating ceiling
below the documented model maximum. Confirm the estimator against provider
`usage` on representative Japanese and English inputs. If a valid bound cannot
be established, do not admit arbitrarily larger prompts or claim long-context
safety. Context admission methodology is a release gate.

The working set is bounded while original evidence remains in durable storage.
Select passages and reopen neighboring spans; do not repeatedly summarize
summaries as the only surviving evidence. Persist the public task state needed
for a new assignment, not private chain-of-thought.

Rotation happens at a completed interaction boundary. A fresh assignment is a
new conversation reconstructed from durable artifacts, not a truncated version
of an open Kimi tool turn. Within a native tool conversation, retain required
reasoning and tool relationships in memory. If that in-flight state is lost,
do not invent replacement reasoning to resume the same turn.

### 4.3 Whole-job budgets

Admission MUST enforce both per-assignment limits and shared job limits:
physical attempts, admitted tokens, searches, fetched documents/bytes, stored
bytes, elapsed time, and active provider requests. Reservations and actual
consumption are different counters; never report an allowance as measured usage.

Before scheduling more research, reserve capacity for the remaining writing,
source-grounded review, correction, and publication. Stop scheduling work that
would consume those reserves. Draft units and final output have explicit caps.

The initial operating profile and its supporting measurements are specified in
Section 12. Broader context, additional authoring segments, and larger output
require evidence; they are not automatic consequences of the model's advertised
window. Reconnection and restart MUST NOT reset budgets or the original deadline.

## 5. Durable state and source provenance

Use SQLite transactions and the existing private runtime data volume. The
following are logical records, not a requirement for a generic artifact framework:

| Record | Required state |
| --- | --- |
| Run | Owner, submission identity, request hash, language/scope, phase, deadline, reservations/consumption, editorial board, cancellation state |
| Source blob | Immutable bounded retrieved bytes, canonical and final URL, retrieval time, media type, content identity |
| Extraction revision | Source-blob ID, extractor/version, immutable normalized text, page/span map where available, content identity |
| Evidence reference | Extraction revision, exact location, verbatim span, claim relevance and limitations |
| Draft/segment revision | Task/outline version, Markdown, navigation summary, claim references, dependency revisions, review decisions and unresolved issues |
| Attempt | Run/assignment ID, admitted budget, dispatch state, timestamps, safe usage/status, committed result reference |
| Publication | Ordered accepted revisions, final Markdown, source list, content identity, delivery state |

Keep both the bounded original HTML/PDF bytes and their extraction revision in
SQLite, avoiding a second filesystem-commit protocol in the initial implementation.
Original bytes allow inspection of a missing table or later re-extraction without
pretending the current live page is the same retrieved source. Re-extraction creates
a new revision; it never silently changes the text behind an accepted citation.

Define text locators against immutable normalized Unicode text; validate offsets
and exact span equality before accepting a citation. PDF extraction must retain
page identity where available. Extraction may miss tables, figures, or footnotes;
record that limitation instead of claiming the extracted text is a perfect copy.
Stored source bytes are not rendered as active HTML or exposed as unrestricted
files. Apply access, size, and retention limits to both raw and extracted forms.

Deduplicate exact URLs/content where appropriate, not entire hosts. Keep access
control, run-level storage limits, and a retention policy for stored documents.
Source text is untrusted data, never an instruction source or permission grant.

Use optimistic revision checks for draft edits and review acceptance. A stale
editor result MUST be rejected rather than overwriting a newer author revision.
Persist complete accepted actions atomically. Partial streamed text may be retained
as explicitly unvalidated work, but cannot become an accepted draft automatically.

## 6. Recovery and external uncertainty

Attempt states distinguish `reserved`, `dispatched`, `succeeded`,
`known_failed`, `unknown`, and `abandoned_unresolved`. Commit the dispatch intent before outbound work;
a crash between that commit and observable completion is conservatively uncertain.

- A lost UI observer does not erase the job or accepted drafts.
- A runtime restart does not automatically resend dispatched attempts whose
  outcome is unknown. Restore the run as paused/interrupted and expose its state.
- Local cancellation or timeout does not prove that Sakura stopped processing.
- An unknown attempt retains its conservative budget reservation and is not
  eligible for blind replay. Only reconciliation that establishes the result
  may change it to `succeeded` or `known_failed`. The mere existence of a provider
  idempotency parameter is not evidence of a completed or failed execution.
- A known, fully received but invalid model result consumes budget. A bounded
  corrective assignment may be authorized by policy; it is not a transport retry.
- Cancellation prevents new dispatches, requests in-flight cancellation, and
  preserves accepted artifacts. Report uncertainty about in-flight provider work
  rather than returning a false zero-cost cancellation guarantee.

Failure of delivery or Note persistence does not rerun research or invalidate an
already committed publication. Retry only the idempotent delivery operation.

When provider reconciliation is unavailable, an authenticated explicit approval
may name an exact unknown attempt and acknowledge possible duplicate execution
and charges. Atomically record the approving actor and revision, mark the old
attempt `abandoned_unresolved`, keep its full conservative charge against the
budget, and reserve at most one replacement with a new attempt ID linked to it.
This neither proves the old call stopped nor refunds its budget. Account admission
must account for uncertain in-flight work; do not silently release its lease and
claim confirmed provider concurrency. The approval and replacement reservation
are idempotent and cannot extend the original run deadline or authorized budget.
Unacknowledged unknown attempts continue to block resumption.

## 7. Open WebUI integration

The target integration separates short submission/status/result requests from
the lifetime of a research job. One user action does not imply one multi-hour
HTTP request. The Open WebUI adapter MUST avoid an LLM-driven polling loop and
must deliver final Markdown without a second rewriting model pass.

Use a **managed native Open WebUI Pipe Function** as the dedicated research model.
It submits the job, polls short status requests, emits bounded phase-change status
events, retrieves the publication, persists the private Note, and yields the exact
final Markdown. This uses the existing backend Pipe/async-generator interface;
it does not require a new frontend or an LLM to select the runtime tool.

Selecting a Pipe alone is insufficient: in the pinned Open WebUI build, common
payload processing runs before Pipe dispatch. Context compaction and file-query
generation can already invoke a model, and title generation is scheduled on a
separate path. Add a small **server-resolved, model-scoped guard**:

- Identify the administratively managed research model and its Pipe type; do not
  trust a client-supplied marker to bypass processing.
- Skip compaction and model-backed retrieval/query/tool/skill enrichment for this
  model. Reject unsupported files explicitly and configure its built-in enrichment
  capabilities off. Forward only the explicit research input.
- Suppress title/tag/follow-up and other optional model-backed background tasks
  for this model before they are scheduled.
- Preserve authentication, model access control, request validation, and required
  security checks. Do not disable ordinary chat's compaction or other features.

This is the target **zero UI-side generation calls** contract; runtime inference
is metered separately. The guard is not implemented by this specification, and
must be tested with a long saved chat and a newly created chat. Existing private
middleware patches are digest/version pinned; new guards must fail closed when
their expected source shape changes.

Open WebUI already executes chat processing in backend tasks: a browser reload
is not equivalent to cancellation of the backend task. Conversely, those tasks
and in-memory streams are not a durable runtime. The job API removes the long
Open WebUI-backend-to-runtime inference request; it does not claim the current
browser holds one multi-hour HTTP request.

### 7.1 Target private runtime API

| Operation | Contract |
| --- | --- |
| `POST /research/jobs` | Authenticate, bind owner/action identity, validate the request, atomically create or return its job; a deliberate new generation has a new action ID |
| `GET /research/jobs/{id}` | Authorized structured phase/progress/counters/gaps; no raw reasoning, secrets, or private diagnostics |
| `GET /research/jobs/{id}/result` | Authorized immutable publication or explicitly incomplete package; unavailable results are not reported as completed |
| `POST /research/jobs/{id}/cancel` | Idempotently stop new dispatch and request cancellation; preserve durable artifacts |
| `POST /research/jobs/{id}/resume` | Explicit, revision-checked resumption; reject expired budgets and unacknowledged unknown attempts; optional exact-attempt replacement approval follows Section 6 |

The first runtime implementation exposes these private job endpoints and removes
the old synchronous `/research` endpoint. They are deliberately excluded from
OpenAPI tool discovery: the former generic LLM-driven adapter must not manufacture
the owner header while inheriting a service credential. The managed Pipe migration
is still required. Use an authenticated adapter identity plus a trusted owner
binding; an unpredictable job ID is not authorization. Never trust an owner ID
supplied in model-generated text.

Distinguish four identities: authenticated owner, explicit user action, research
job, and candidate attempt. Idempotency binds the owner and a stable `action_id`
to a canonical request hash. Retrying the same action returns the same job;
changed contents under the same action are a conflict. Polling, reconnecting,
and retrieving a publication do not create candidates or reset budgets.

An automatic second candidate stays within the same job/action and original
budget. A user explicitly pressing Regenerate is a new action and authorization,
even when the text and originating user message are unchanged. Do not use the
user-message ID alone as the generation key, or the user will receive the old
cached report instead of a new attempt.

The existing Open WebUI backend distinguishes user and assistant message IDs
and exposes message metadata to a Pipe. Reusing the assistant response ID as
`action_id` is the smallest option **only if integration tests show** it is fresh
for explicit Regenerate and stable for transport retries. Otherwise create/store
a dedicated opaque action ID in the adapter. Do not infer that a transient
backend `task_id` is a durable user action. Missing action identity on a managed
submission is an explicit error, not permission to invent a retry key.

An explicit new action may reuse authorized, versioned source artifacts from a
prior job after owner/access/retention checks, but never silently replay an
uncertain physical request. Source reuse is not candidate-result reuse. Cache
the selected final delivery, not a rejected first candidate that would short-circuit
the second candidate. A quality retry and an execution resume are different operations.

Submission returns `202` with a job identity and authorized status/result URLs;
an identical submission attaches even while the job is running. A status read
never resumes execution. An unavailable result returns `202`; a completed
publication and an incomplete package carry distinct explicit outcomes. Poll
with bounded intervals and a finite adapter deadline, respecting `Retry-After`.

On Pipe task cancellation, request runtime cancellation using a short, shielded,
best-effort call and then propagate cancellation. This is not proof that an
upstream inference stopped. Browser refresh does not necessarily cancel the Pipe;
do not equate loss of a progress subscription with a confirmed cancellation.
After an Open WebUI restart, explicit reattachment must find the original job;
automatic reattachment and Stop-button propagation require integration tests.
After a runtime restart, resumption is explicit and checks unknown attempts and
remaining budgets; resubmitting the original request only attaches.

### 7.2 Input and output boundaries

Submit the explicit research request and deliberately selected context, not the
entire chat transcript by default. Unsupported attachments/private retrieval
requirements must be rejected or clarified explicitly, not silently ignored.
Keep the original requested language separate from the language of this document.

Progress contains stages, accepted artifact counts, and unresolved work, not
internal conversations. The user must be able to retrieve an already saved result
after a dropped connection. Note publication, if enabled, uses an idempotent
owner/job/publication mapping. Failure to create the Note is reported as a
delivery problem, not disguised as successful persistence.

The existing direct-tool Note hook does not apply automatically to Pipe output.
The Pipe must call the persistence helper explicitly before announcing successful
delivery. Extend Note identity from an assistant-message mapping to an authorized
job/publication identity, with a uniqueness guarantee under concurrent observers.
Keep Notes private and preserve the exact publication text.

Runtime publication and an Open WebUI Note live in different databases. They
cannot share one atomic commit. Record a small `delivery_pending`/acknowledged
state with the publication, then perform an idempotent Note upsert and acknowledge
delivery. This is an outbox obligation, not a requirement for another queue
service. A failed or interrupted delivery retries only this operation and does
not regenerate manuscript content or make another model request.

## 8. Validation and security

Deterministic checks cover authorization, schema and size limits, URL/network
safety, citation IDs, source revision/locator integrity, state transitions,
budgets, optimistic revisions, and publication completeness.

Semantic review covers evidence entailment, numeric subject/unit/time alignment,
question coverage, independence and authority of evidence, contradictions,
duplication, and usefulness in the requested language. Numeric literal matching
alone is not entailment. Material claims still require support; removing an
over-restrictive check is not permission to invent numbers or omit citations.
Derived numbers require an explicit reproducible derivation, or must be excluded.

Model reviews are fallible. Keep a fixed review rubric and human evidence checks
in release evaluation. Do not create unlimited critic/repair cycles or require a
new evaluation platform before testing a small useful implementation.

All fetches, including references found within a source, pass through the existing
SSRF-safe path with DNS/redirect checks, content limits, and timeouts. No arbitrary
shell, network, file-writing, or private-system tool is exposed to model roles.
Validate model-proposed references before retrieval. Do not execute instructions
found in source text or accept them as changes to the task or budget.

Keep credentials out of arguments, prompts, artifacts, returned diagnostics, and
logs. Allowlisted diagnostics may include elapsed time, safe status categories,
physical attempt counts, token usage when supplied, and editorial validation
outcomes. Never persist raw provider responses or hidden reasoning in reports or
the research checkpoint merely to make context recovery easier.

## 9. Acceptance criteria

### 9.1 Software invariants

- No unauthorized job, source, draft, or publication access.
- No hidden retries or uncounted provider sends on the research path.
- No new dispatch after cancellation, deadline, or exhausted budget.
- No unknown attempt silently replayed or counted as a confirmed failure.
- No stale edit accepted, no source mismatch citation, and no unreviewed required
  manuscript section included in a completed publication.
- No accepted source/draft/publication lost because a later action fails.
- Repeated submission, result retrieval, and delivery are idempotent.
- No reliance on mid-turn compaction or a full-report editor context.

### 9.2 Research quality

The previously failed public CPython research case is a regression example, not
the entire evaluation set. Verify direct access to relevant official documents,
answers to all requested aspects, supported comparisons, coherent Japanese prose,
non-repetition, and accurate citations and limitations.

Use a small public set spanning factual research, comparison, conflicting claims,
multi-chapter breadth, and difficult extraction. Separate fixed-source editorial
tests from live-search tests. Compare under the same model and declared budgets.
Do not infer release readiness from one synthetic example or one successful report.

Score the delivered report after its bounded edit, retaining raw-draft scores
separately. Record first-candidate and within-two-candidate good deliveries, failed
executions, false acceptance, and unnecessary blocking. Operator-reconciled cases
are diagnostic evidence, not unattended successes. A useful pilot does not require
proof of perfect consistency or a statistically guaranteed success probability;
it does require visible failures and a small representative quality check. Do not
add another automatic judge layer solely to make every reviewer agree.

### 9.3 Failure and integration checks

Inject interruption after document persistence, after a draft commit, during an
unknown model attempt, after publication commit, and during Note delivery. Check
state and preservation directly. Exercise changed-request idempotency conflicts,
stale review/edit rejection, expired budgets, and user cancellation.

Test Open WebUI with a long preceding chat, a research duration exceeding five
minutes in aggregate, browser disconnect/reconnect, and Stop/cancel. These tests
must demonstrate bounded individual inference requests and no accumulated
research transcript in the UI model context.

## 10. Implementation sequence

1. Establish the no-retry, physically metered Sakura path and request/context
   admission. Add bounded job submission/status/result and durable attempt state.
2. Build the public-document store and the single-author research/write/review path.
   Use complete new source fixtures; old short excerpts cannot reconstruct lost
   original documents.
3. Add runtime-owned block references, revision-specific review, justified
   correction, and atomic publication. Verify this single-author vertical slice
   before increasing output/context budgets. Do not add a contributor pool.
4. Connect the chosen Open WebUI adapter, exact delivery, cancellation, and result
   retrieval. Preserve ordinary chat behavior.
5. Run the public regression and failure cases; then retire the obsolete deep
   research core and its incompatible tests/contracts. Update existing callers
   explicitly rather than leaving a hidden legacy fallback.

Do not deploy the redesign solely because the feasibility probes pass. The probe
code validates selected assumptions, not the proposed scheduler, database
migrations, or complete UI behavior.

### 10.1 Change boundaries and executable contracts

| Area | Required change | First focused check |
| --- | --- | --- |
| `deep_research_runtime.py` and its existing persistence code | Add short job endpoints, authenticated ownership, durable attempt reservations, status/result retrieval; retain safe fetch and provenance | Duplicate submit attaches; changed payload conflicts; no model call occurs in status/result handlers |
| Editorial core | Implement one author, a small candidate-local decision ledger, immutable drafts, runtime-owned block references, and materiality-based review; one edit round and at most two candidates | User metric/mode constraints survive; valid minor notes publish; source-backed dismissals are retained; candidate two does not reuse a rejected delivery |
| `sakura_kimi_model.py` / existing provider boundary | Validate supported parameters, meter every physical continuation, enforce absolute deadlines, retain native tool replay only where required | Fake streaming drip is interrupted; a tool continuation consumes another attempt; unknown completion is not replayed |
| `../sakura_proxy/sakura_retry_proxy.py` | Add authenticated, no-retry research dispatch with shared account admission and explicit attempt identity | A failed research request produces at most one upstream transmission; normal chat retains its separately declared policy |
| `../functions/` managed Pipe and `../scripts/reconcile.sh` | Provision the dedicated Pipe, trusted model marker, progress polling, stable job attachment, and cancellation/result delivery | No model-selection call; reconnect attaches to the original authorized job |
| `../patches/` and pinned `../Dockerfile` | Add model-scoped pre-dispatch/background-task guards and job/publication Note identity | Long old chat and new-chat title paths make zero UI-side generation calls for the Pipe, without affecting ordinary chat |
| Existing contract tests | Keep security/persistence invariants; replace tests that assert obsolete fallback or host-count behavior | Failure preserves evidence/drafts and never creates a fake complete report |

Do not begin with a wholesale rewrite of safe networking or a new task framework.
The current runtime's exact module decomposition can change, but these ownership
boundaries must remain testable. Use the repository's existing unittest/pytest
style and existing dependencies, not an additional testing service.

Implement the editorial state as small records beside the existing checkpoint,
not a claim graph or a new workflow framework. Commit each draft unit and review
unit separately; completed work must not be replayed when a later unit fails.
Keep valid public metadata such as explicit constraint provenance. Normalize only
documented presentation forms (one complete JSON fence or known citation brackets),
then validate types, status values, IDs, sizes, and revisions. Unknown references,
ambiguous content, and incomplete responses remain errors. Saved-response replay
tests cover these protocol cases without spending more model requests.

Review workspaces must fit the serialized request budget, not merely contain one
nominal chapter. Pack contiguous runtime-owned block ranges with the ledger and
relevant source passages; preserve coverage and carry a small scope/handoff map
across ranges. A unit can require multiple review requests within the same job
budget. Reject an individually unadmittable block explicitly rather than dropping
coverage, silently truncating sources, or increasing the model context ceiling.

Before accepting a draft, check for empty visible content, duplicated report roots,
and unframed internal generation markers. A successful HTTP response is not a
valid artifact. Suspicious mixed output remains unaccepted; do not silently pick
one of its apparent drafts or strip an internal prefix and label it approved.
Ordinary repeated terminology and legitimate quoted markup are not themselves
material defects. Preserve earlier usable candidates when a later generation
degrades, without presenting an incompletely reviewed draft as a completed result.

Test user-action identity separately from quality: same-action transport retries
and reattachment make no inference calls; explicit Regenerate creates a new action;
an automatic candidate two shares the original job limits. The final selected
publication, not the first rejected candidate, is the result returned by the Pipe.

Separate run status from editorial phase:

- Status: `queued`, `running`, `paused`, `completed`, `incomplete`, `cancelled`,
  or `failed`.
- Phase while active: `scoping`, `researching`, `writing`, `supervising`,
  `editing`, or `publishing`.
- A successful action commits its immutable output and the next eligible work
  in one transaction; it does not imply that the entire phase is complete.
- Restart or uncertain inference pauses execution. Budget/deadline exhaustion
  creates an incomplete package; integrity/authentication failure is a failure,
  not an invitation to use a weaker path.
- Explicit resume may restart eligible paused/cancelled work only with remaining
  original authorization and resolved/acknowledged attempts. An expired job
  cannot be revived by resetting its clock.

Start with one runtime worker process and a single provider-admission slot.
Durable queued work is claimed with a transaction, not by assuming an in-memory
task survived restart. Recheck cancellation and budgets immediately before each
dispatch. Maintain the existing private-volume boundary; do not place research
databases, source bodies, or credentials in the repository.

For migration, inventory the managed model manifests and reconcile-script callers
of `/research` before retiring it. Preserve only explicitly supported callers
through an explicit migration, not a silent legacy execution fallback. Refuse to
overwrite unmanaged Open WebUI functions or model registrations. Old checkpoints
that lack source blobs or editorial revisions remain readable historical results;
do not fabricate new provenance or automatically resume them under the new schema.

### 10.2 Triage and architecture decision

Resolve these questions in order:

1. **Execution:** Can bounded Sakura/Kimi calls produce usable artifacts and
   complete native continuation without timeout or unsupported-parameter assumptions?
2. **Editorial value:** Can a fresh reviewer identify real contradictions or
   omissions, and can a bounded correction fix them without
   introducing unsupported claims?
3. **Comparative value:** With the same real question and source material, does
   the magazine process provide useful quality, length, or working-set advantages
   over one author with bounded review and revision? Record actual calls and time.
4. **Production delivery:** Can the selected process be made durable and exposed
   through the managed Pipe without UI-context accumulation or duplicate work?

Do not spend this feasibility phase tuning Docker startup, building general
observability infrastructure, changing model providers, or optimizing unrelated
services. Add a test only if its outcome can change the architecture decision or
close a safety-critical implementation requirement.

Pre-register the real-task question, primary-source packet, rubric, and critical
error conditions before generating either variant. Do not put the rubric's
expected answers in author/editor prompts. Keep protocol and output constraints
comparable; report unequal call consumption instead of claiming equal cost.
Synthetic contradictions test a capability, not real-report quality. A manually
selected source packet tests editorial behavior, not autonomous web-search recall.

- **Proceed:** Execution constraints hold, material claims are grounded, review
  and revision demonstrably work, and the real-task result justifies coordination.
- **Limit:** The method works but a smaller one-chapter process is as good and
  cheaper for small questions. Keep chapter count proportional to the problem;
  do not force multiple contributors on every request.
- **Reject or redesign:** Additional calls fail to improve useful quality, bounded
  context loses essential relationships, review cannot repair material errors,
  or the provider contract prevents reliable execution. Record the evidence and
  replace the problematic structure rather than protecting this document's design.

## 11. Open decisions and release gates

- Exact provider timeout semantics, upstream cancellation, and external attempt
  reconciliation where no documented status/idempotency API exists.
- Verified tokenizer/accounting for the deployed Kimi alias, including tool
  schemas, Japanese input, reasoning replay, and generation reservation.
- Calibrated draft/output/working-set limits and demonstrated editorial quality.
- Pinned Open WebUI adapter and cancellation/Note behavior in the target build.
- Retention/storage quota values appropriate to the deployment.

An unresolved gate must remain visible. Do not substitute a silent fallback,
larger timeout, arbitrary truncation, or guessed model capability.

## 12. Feasibility evidence and operating profile

### 12.1 Documentation and source inspection (2026-09-08)

| Evidence | Observation | What it does not prove |
| --- | --- | --- |
| Sakura manual and Inference OpenAPI | The Chat Completions endpoint and bearer authentication are documented; several parameters are model-dependent | The inspected documents did not establish whether the reported five-minute limit is total, idle, or includes queueing |
| Sakura model metadata, one authenticated `GET /v1/models` | HTTP 200; the requested K2.7-Code alias was present; none of the inspected standard numeric capacity fields was returned | A confirmed serving-context or maximum-output limit; no inference request was made for this check |
| Upstream Kimi K2.7-Code documentation | 256K/262,144 advertised context; always-on preserved thinking; no `reasoning_effort` or forced `tool_choice: required`; reasoning and visible content share the generation allowance | Identical behavior of Sakura's preview alias, practical memory quality, or completion inside five minutes |
| Current proxy and Compose | General chat permits five retries and a 420-second upstream timeout; runtime SDK retry zero does not disable gateway retries | A single existing runtime invocation being one physical send |
| Open WebUI v0.11.3 pinned source | Common payload processing precedes Pipe dispatch; compaction, retrieval-query, and title paths require model-scoped exclusion; Pipe metadata/event/async-yield interfaces exist | A new managed Pipe or its guards already being implemented |
| Existing runtime/Note source | SQLite checkpointing and exact private Note delivery are available; the current endpoint is synchronous and Note identity is message-based | New job endpoints, immutable chapter/review revisions, or atomic cross-database delivery |

The five-minute boundary is an operational requirement supplied for this project,
not a newly verified provider SLA. Do not weaken the 240-second client policy
because the precise upstream timeout mechanism remains undocumented here.

### 12.2 Offline checks

The supervisor independently reran these existing checks with bytecode writes disabled:

```sh
# Run from containers/open-webui/patches:
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_apply_direct_tool_output test_deep_research_notes
# Run from containers/open-webui/functions:
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_deep_research_status
```

Results: **7/7** direct-output/Note tests and **1/1** status-filter test passed.
The investigator also checked five pinned-source conditions: single pre-dispatch
compaction call site, payload-before-dispatch ordering, Pipe dispatch, metadata
injection, and async output support. These are source-contract observations, not
an end-to-end test of the proposed Pipe.

The provider probe's offline self-check passed on the host and in the existing
container. It included an absolute watchdog interrupting a continuously dripping
stream, tool-call delta assembly, bounded send accounting, and fixed-input checks.
Its POSIX signal watchdog is a probe implementation, not a mandate to use process
signals in the asynchronous production runtime. Production must enforce the same
total-deadline contract with an appropriate cancellation-capable transport.

Selected runtime tests could not run in the investigator's host environment due
to missing dependencies; no dependencies were installed to turn that into a pass.
The old suite's earlier reported 149 passes are not new verification of this design.

### 12.3 Live Sakura contract smoke

Eight physical requests were sent once, sequentially, directly to the Sakura
endpoint using credentials only inside the existing proxy container. No retry,
service restart, image build, or deployment was performed. The requested model
was `preview/Kimi-K2.7-Code`, `max_tokens=4096`, streaming with usage requested,
and an absolute 240-second deadline per physical request.

| Request | Purpose | Elapsed | Prompt tokens | Completion tokens | Result |
| --- | --- | ---: | ---: | ---: | --- |
| 1 | Independent Japanese chapter A | 2.482 s | 122 | 210 | Passed structural/citation checks |
| 2 | Independent Japanese chapter B | 2.073 s | 122 | 158 | Passed structural/citation checks |
| 3 | Fresh supervisor: cross-chapter conflict and duplicate | 12.118 s | 600 | 778 | Expected issue references detected without answers in the output schema |
| 4 | Targeted revision | 77.510 s | 650 | 2,944 | Conflict references retained; duplicated budget claim consolidated |
| 5 | Native tool request | 12.542 s | 127 | 43 | `tool_calls`, expected tool/argument |
| 6 | Preserved-reasoning tool continuation | 0.701 s | 207 | 56 | Completed with the tool-supplied value |
| 7 | Fresh working-set recall at three document positions | 5.160 s | 10,912 | 126 | All three references recovered |
| 8 | Deliberate `tool_choice: required` negative case | Unknown | Unknown | Unknown | Stopped as `UNKNOWN`; not repeated |

All seven positive cases returned HTTP 200 and usage. The known successful elapsed
time totals 112.586 seconds. Their prompt/completion totals are 12,740/4,315 tokens.
Separate reasoning-token counts were not captured, not known to be zero. The eighth request counts
against the full eight-request allowance; its HTTP status, duration, and execution
outcome were not established by the safe diagnostics. It is neither a successful
capability test nor proof that Sakura rejected the parameter.

The local probe process ended and the original proxy remained healthy. This does
not prove upstream cancellation of an unknown request. The negative case is
abandoned unresolved, without a replacement or budget refund; subsequent approved
experiments use the successful parameter profile, not a retry of that case.

These results establish a **small synthetic capability**, not report quality:
Japanese presence and citation-reference checks do not certify fluent argument,
factual entailment, or reliable revision under arbitrary content. Recovering
three markers from 10,912 input tokens does not validate the advertised 256K
window or general long-context reasoning. The real-source comparison follows.

### 12.4 Real-source editorial comparison

The fixed case concerns production adoption of CPython 3.13 free threading, with
the same four official source excerpts and Japanese 1,800-2,600-character target
for both variants. The answer rubric and critical-error rules are frozen before
generation and withheld from the generation prompts. One author with review and
revision is compared with two contributors, supervision, targeted revision, and
an introduction/conclusion-only editor followed by mechanical assembly.

**Round 1: incomplete; no comparative winner.** Generation allowance was 8,192,
with the same 240-second deadline and packet for both methods. Six requests were
sent with no retries:

| Request | Elapsed | Prompt tokens | Completion tokens | Outcome |
| --- | ---: | ---: | ---: | --- |
| Magazine chapter A | 50.631 s | 4,242 | 5,074 | Draft saved |
| Magazine chapter B | 41.673 s | 4,237 | 5,087 | Draft saved |
| Magazine supervision | 94.257 s | 5,518 | 7,454 | Issue list saved |
| Magazine revision A | 79.798 s | 6,181 | 3,435 | Revised draft saved |
| Magazine revision B | 1.098 s | 6,357 | 16 | Complete response, invalid expected output; original content not retained |
| Single-author initial report | 76.933 s | 4,225 | 8,192 | `finish_reason=length`; no finished report |

The six requests total 344.390 seconds, 30,760 prompt tokens and 29,258 completion
tokens. Both final variants were unavailable. The author hit the generation cap,
not the time limit. The short invalid revision cannot be explained from the saved
safe diagnostics; do not invent an error cause or equate it with poor prose.

The saved chapters were substantive Japanese drafts, unlike the previous extractive
fallback output. However, direct review exposed false positives in supervision:
it alleged a missing normal-build rollback even though the original chapter
already stated it, and requested information in one chapter that was already
covered by the other. It also found a genuine omitted condition concerning
explicitly disabling the GIL. Revision A incorporated that condition but added
some cross-chapter repetition. These observations motivate advisory reviews and
source-checked corrections, not unconditional acceptance of reviewer assertions.

The false-positive review used only 5,518 reported prompt tokens. Therefore,
remaining well below a nominal context limit is **not** evidence that the model
reliably noticed every relevant passage. For a disputed finding, present the
specific current paragraph and its source passage explicitly rather than relying
on the model remembering them from a large editorial packet. Keep review size
and evidence access independently bounded; a context budget alone is not a
semantic-memory guarantee.

**Round 2 is a separately declared calibration, not a rewrite of Round 1's result.**
It retains the question, sources, scoring rubric, chapter commissions, and time
limit. Both methods receive a 16,384 generation allowance, consistent with the
upstream recommendation to reserve at least 16,000 for thinking/tool workloads.
Authors and chapter revisers return plain Markdown instead of wrapping long prose
in JSON. Reviews return only issues, and both methods receive the same generic
instructions to verify alleged omissions and reject unsupported proposed edits.
No previous generated answer or judge-only answer key is supplied to generation.

**Round 2: one completed variant; the magazine review interface still blocked.**
Six requests completed at the provider, with no retries or request timeout:

| Request | Elapsed | Prompt tokens | Completion tokens | Outcome |
| --- | ---: | ---: | ---: | --- |
| Single-author initial report | 52.825 s | 4,231 | 5,649 | Draft saved |
| Single-author review | 155.575 s | 5,886 | 14,286 | Review saved |
| Single-author revision | 26.983 s | 6,455 | 1,903 | Finished 3,217-character report; above requested length target |
| Magazine chapter A | 43.209 s | 4,240 | 2,202 | Draft saved |
| Magazine chapter B | 18.221 s | 4,233 | 1,293 | Draft saved |
| Magazine supervision | 49.697 s | 5,883 | 5,092 | `OUTPUT_INVALID:quote`; model quote did not match the targeted draft |

This established that a useful-length single-author report can finish under the
physical-request deadline with the calibrated allowance. It did not establish a
comparative quality winner: the magazine final was unavailable, and the baseline
exceeded the requested character target. The unmatched-quote failure is evidence
against model-owned verbatim-copy interfaces, not by itself proof that the
supervisor's semantic findings were wrong.

**Reference recovery: completed in three additional requests.** The stored
magazine chapters were reused, not regenerated. The supervisor selected valid
runtime-owned paragraph IDs; the code resolved their exact text and ownership.
Only chapter B required revision, followed by a short introduction/conclusion.
The resulting 3,157-character magazine report also exceeded the requested length.

| Recovery action | Elapsed | Prompt tokens | Completion tokens |
| --- | ---: | ---: | ---: |
| ID-based supervision | 112.611 s | 5,938 | 7,980 |
| Chapter B revision | 41.257 s | 6,793 | 4,187 |
| Framing editor | 7.727 s | 6,004 | 674 |

The baseline was copied byte-for-byte into a neutral report pair; it was not
provided to the recovery model. The independent Sol AI grader received only
neutral reports and the frozen rubric/sources, without variant mapping or cost.
Scores were frozen before the mapping was revealed. The supervisor separately
reviewed the actual reports and primary-source evidence.

| Observed result | Single author | Magazine with reference recovery |
| --- | ---: | ---: |
| Fixed-rubric AI score | 91/100 | 85/100 |
| Status/GIL/install | 25/25 | 25/25 |
| C-extension compatibility | 22/25 | 17/25 |
| Performance/memory | 19/20 | 19/20 |
| Production decision/validation | 21/25 | 20/25 |
| Evidence/usefulness | 4/5 | 4/5 |
| Major-error score cap applied | No | No |
| Final Unicode characters | 3,217 | 3,157 |
| Physical requests in the evaluated path | 3 | 6, including the failed Round 2 review |
| Reported prompt + completion tokens | 38,410 | 54,519 |
| Sum of measured request durations | 235.383 s | 272.722 s |

The magazine path used twice as many requests and about 42% more reported tokens.
The request-duration sum was about 16% higher. These are **not** a bill or a
measurement of uninterrupted end-to-end latency: manual recovery and development
pauses occurred, and the review interface changed. No causal or universal
superiority claim follows from this one curated-source comparison.

The score difference was substantive, not merely stylistic. The single-author
report covered C-extension internal state and borrowed-reference hazards more
fully. The magazine report concentrated on compatible wheels and declarations,
leaving important thread-safety audit work less explicit. Both omitted some
conditions and exceeded the length target. The recovery corrected unsupported
memory-comparison language but did not make the multi-author report better overall.

**Decision under the predeclared rules:** do not adopt independent contributors
as the initial default. The candidate scored lower while using more resources;
the rule selecting the cheaper single-author approach at no magazine quality gain
therefore applies. Keep the tested reference-resolution and durable-draft
mechanisms, and implement the simpler path in Section 3. Reconsider contributors
only with evidence from an appropriate larger/independent-research task.

This was AI-assisted assessment, not a human panel, and not a production
end-to-end test. The experiments did not implement automatic review invalidation,
atomic publication, autonomous search-quality evaluation, or durable job recovery.
Those remain explicit implementation/release checks. The development evidence
is enough to select a smaller implementation, not to skip those checks.

Total Sakura inference requests for the earlier design-comparison batch: **23**, no automatic
retries. One deliberate unsupported-parameter probe remains unresolved; it was
not repeated or counted as successful. All later calibration results and failed
artifacts were preserved rather than overwritten. That batch ended after reference
recovery. Its separate model-metadata GET made zero inference requests and did not
establish a serving-context limit. The subsequently authorized long-form study in
Section 12.7 has its own budget and is not included in this subtotal.

### 12.5 Operating limits and remaining calibration

The single-unit implementation uses the following **explicit development/pilot profile**.
It is bounded and is not a claim that a production-scale job has already passed
acceptance. A larger profile is a separate measured rollout.

| Limit | Initial value | Basis |
| --- | ---: | --- |
| Active provider requests | 1 | All live checks were serial; no parallel-capacity claim |
| Physical request deadline | 240 s | Operational five-minute boundary with local margin |
| Generation allowance | 16,384 tokens | Completed real-task calls; thinking shares this allowance |
| Serialized model-request body | 64 KiB | Byte guard; reconstructed Round 2 requests were 20,617–34,657 bytes; later long-form requests directly measured up to 58,479 bytes |
| Provider response bytes | 4 MiB | The live probe's enforced resource bound |
| Model attempts per pilot job | 18 | Revised for actual workflow allocation: eight research actions plus two five-call editorial candidates; all calls count |
| Job wall time | 4,500 s | Pilot ceiling, not a target duration or timeout extension; existing jobs retain their saved deadline |
| Author roles / initial draft units | 1 / 1 | Default single-draft path; sequential generation was tested, but automatic long-report publication remains gated |
| Draft-unit Markdown | Roughly 3,000–4,000 characters when no length is specified | Soft writing guidance, not a hard character-count gate; explicit user length takes precedence within admitted resource limits |
| Rendered publication | At most 256 KiB including references | Selected bounded delivery/storage cap, not a quality score |
| Individual fetched document | 1,500,000 bytes | Retain the current fetch bound |
| Search/fetch ceilings | 96 searches / 60 fetched documents | Retain existing deep-research ceilings; do not reduce research to make writing pass |
| Stored source/extraction data per pilot job | 128 MiB | Selected resource quota, to be checked with representative PDF/HTML inputs |

The byte measurement was reconstructed offline with the frozen Round 2 prompts,
saved inputs, and fake transport; it made no additional model calls. A byte cap
does not certify a token conversion or reliable semantic recall. Before enabling
larger working sets, validate token accounting and the serving profile; do not
infer either from a message count or the upstream advertised window. Pilot use
remains within explicit input bounds and the tested source scale.

Request, response, and publication byte caps remain hard limits; the per-unit
character guide is not a padding requirement or an additional rejection gate.
Do not silently cut an oversized result. Reserve framing/reference space and
remaining editorial attempts when scheduling writing; split admitted review work
by actual serialized bytes. Exhausted caps produce an explicit incomplete result,
not a shorter fake success.

Resource limits also apply to extraction: bound decoded output, page/work count,
and parser execution time/memory. A raw-download byte cap alone does not protect
against expensive or malformed PDFs. Do not assume cancelling an asynchronous
wrapper terminates a blocked parser thread. The extraction boundary needs an
interruptible, resource-limited execution path before arbitrary documents are
enabled; failed extraction remains a visible source gap, not a snippet fallback.

- **Required now:** no hidden retries; one admitted provider request at a time;
  240-second total physical-request deadline; finite job/assignment budgets;
  durable accepted artifacts; explicit incomplete/unknown states.
- **Observed only:** generation allowance 4,096 in the smoke; successful working
  set up to 10,912 reported prompt tokens on a synthetic recall task; successful
  short Japanese structured artifacts and one native tool continuation.
- **Measured limitation:** generation allowance 8,192 truncated a real-task
  single-author request after 76.933 seconds. A chapter-scale request succeeded
  within that allowance, but one short invalid revision prevented publication.
- **Observed, not a deployed default:** generation allowance 16,384 allowed a
  3,217-character single-author report and its review/revision to complete. The
  longest completed request was 155.575 seconds; the review used 14,286 completion
  tokens. These measurements support reserving thinking capacity separately from
  visible-length targets, not increasing the 240-second deadline. Shared input
  and response byte caps are not a certified conversion to model tokens.
- **Must be calibrated before enabling large jobs:** real Japanese segment
  lengths, full-context admission/accounting, per-role output reservations,
  useful source density, total job budgets, and storage/retention quotas. The
  old 10,350-second deep-job ceiling is not a target or evidence of enough
  editorial budget. Do not inherit it, the 3,600/3,300-second model timeouts,
  chapter-count-based reserve constants, or runtime/proxy retry loops as implicit
  defaults for the pilot profile.

Use one explicit, validated budget profile rather than scattered silent defaults.
Missing required limits must fail admission. Increase only the limit implicated
by a measured failure; do not make prompts, contexts, or timeouts arbitrarily
larger to hide an architectural defect.

### 12.6 Primary references

- [Sakura usage and endpoint documentation](https://manual.sakura.ad.jp/cloud/ai-engine/02-howto.html)
- [Sakura Inference OpenAPI](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)
- [Kimi model parameter reference](https://platform.kimi.ai/docs/api/models-overview.md)
- [Kimi thinking and multi-step tool calls](https://platform.kimi.ai/docs/guide/use-thinking-models.md)
- [Open WebUI v0.11.3](https://github.com/open-webui/open-webui/tree/v0.11.3), especially backend `main.py`, `functions.py`, `utils/chat.py`, `utils/middleware.py`, and `utils/context_compaction.py`
- [Python 3.13 free-threading HOWTO](https://docs.python.org/3.13/howto/free-threading-python.html)
- [Python 3.13 C API extension HOWTO](https://docs.python.org/3.13/howto/free-threading-extensions.html)
- [What's New in Python 3.13](https://docs.python.org/3.13/whatsnew/3.13.html#free-threaded-cpython)
- [PEP 703](https://peps.python.org/pep-0703/) (historical design; versioned documentation governs current 3.13 claims)
- [Python 3.13 initialization, finalization, and threads](https://docs.python.org/3.13/c-api/init.html#thread-state-and-the-global-interpreter-lock) (GIL-enabled baseline descriptions must not override the free-threaded HOWTO)
- [Python 3.13 reference counting](https://docs.python.org/3.13/c-api/refcounting.html)
- [Python 3.13 build configuration](https://docs.python.org/3.13/using/configure.html#cmdoption-disable-gil)
- [Python 3.13 multiprocessing](https://docs.python.org/3.13/library/multiprocessing.html#introduction)

### 12.7 Follow-up: long-form sequential authorship

#### Question and preregistered gates

The follow-up tested one author role writing four successive units, not independent
contributors. The expanded CPython 3.13 investigation covers execution models,
C-extension/ABI/shared-state migration, performance/memory/correctness gates, and
production rollout/rollback. Eight official sources were frozen before generation,
including versioned initialization, reference-counting, build-configuration, and
multiprocessing documentation. The GIL-enabled baseline explanation was explicitly
distinguished from the free-threaded contract.

The target was 10,000–14,000 substantive Japanese characters. The hard minimum
excluded bibliography, TOC, headings, code, and long quotations; repetition could
not be used as padding. The frozen AI rubric required at least 80/100, at least
12/16 for continuity, at least 4/6 for non-redundancy, and no material fabrication
or contradiction. Technical checkpoint/reference/correction invariants were
assessed separately; content score alone could not make the workflow pass.

The new job had an independent ceiling of 20 physical attempts, one at a time,
240 seconds per attempt, generation allowance 16,384, input 64 KiB, response
4 MiB, and an original 7,200-second job deadline including the pause. No old
experiment was rerun or used as available budget.

Frozen source-packet SHA-256:
`39f0b5231d7329b607796e28ccaec76a2ecc1f09a5f1397ac5f2ed318a18aee8`.
Frozen judge-rubric SHA-256:
`6cf6fbd10b9fe892513cab7322905550811500c926b3282ba20061c204ba8868`.
The resulting initial-candidate SHA-256 is
`7bef2344f034e7698094b42b6d49383cc749b6976ee6d082a19b265e348ee0ba`.

#### Implemented experimental mechanism

- The host persisted request intent, counters, deadline, public results, and draft
  hashes after each operation. A container child reused the previously reviewed
  transport for one inference request; credentials and private reasoning stayed
  out of the journal and manuscript.
- Before a unit, the author selected source and prior-block IDs from an index.
  The runtime supplied the actual selected passages. A unit's suggested sources
  were hints, not a prohibition on returning to other sources in the same job.
- Each invocation was fresh. The author retained one charter/outline and durable
  public state, not a growing hidden conversation. U4 selected meaningful U1/U2
  blocks as well as U3 material and reopened S3 outside its initial source hints.
- After the two-unit checkpoint, a different host process began with U3. Input,
  original deadline, consumed calls, and U1/U2 hashes were preserved. No U1/U2
  selection or writing request was repeated during continuation.
- Ordinary reviews used the preregistered pairs U1–U2, U2–U3, U3–U4, and U1–U4.
  No application inference request received the full manuscript. The independent
  AI quality assessment could read the whole candidate; it was not an application
  review call and did not feed answers back into generation.

#### Calibrations and deviations, not hidden successes

The first read-plan returned valid JSON within one Markdown fence. The shared
parser was corrected to normalize only one complete JSON fence while still
rejecting surrounding prose, unclosed fences, and invalid IDs/schema. The stored
plan was reconciled with no additional inference and no budget reset.

U2 exceeded the initial 4,000-raw/3,500-prose unit gate. One shortening request
made it longer rather than shorter. Both responses had completed inside the
physical time, input, and generation limits. The initial unit-length policy
therefore **did not pass**.

The experiment explicitly calibrated unit admission to at most 5,000 raw and
4,500 prose characters, keeping the approximate 3,000-character writing request.
The earliest complete U2 draft was reused; the unsuccessful shortening request
remained counted against the request budget. The source packet, rubric, 10,000-prose minimum, model limits,
total attempt budget, and original deadline were unchanged. The resumed process
thus demonstrates a declared reconciled checkpoint, not a seamless success of
the original 4,000-character policy. No further length relaxation was made.

#### Generated manuscript and actual bounds

| Unit | Raw Markdown characters | Runner-counted prose |
| --- | ---: | ---: |
| U1 | 3,151 | 2,902 |
| U2, earliest completed draft | 4,510 | 4,161 |
| U3 | 4,321 | 4,128 |
| U4 | 3,200 | 3,028 |

The assembled candidate contains 15,185 raw characters. The runner recorded
14,219 prose characters. An independent audit additionally removed U4's
non-Markdown title line, yielding **14,192 prose characters**; both measurements
comfortably exceed the minimum. This correction does not alter the manuscript.

The independent Sol AI assessment scored the frozen, unchanged initial candidate **90/100**:
evidence 21/22, technical coverage 22/24, validation design 16/20, continuity
14/16, production usefulness 11/12, and non-redundancy 6/6. It judged the extra
length substantively useful, not repeated filler. This was one AI assessment,
not a human panel or proof that every technical assertion was correct.

Across the main run and controlled diagnostic, **16 physical requests** were made,
with zero automatic retries. All provider responses completed with `stop`;
application-level format/length/review failures were recorded separately.

| Observed measure | Value |
| --- | ---: |
| Maximum serialized request | 58,479 bytes |
| Maximum physical-request duration | 121.707 s |
| Maximum reported prompt tokens | 10,066 |
| Maximum reported completion tokens | 14,627 |
| Reported prompt tokens, total | 106,824 |
| Reported completion tokens, total | 97,074 |
| Sum of request durations | 863.155 s |

The duration sum is not end-to-end user latency; it excludes preparation and
manual reconciliation pauses. These finite observations do not validate the
advertised full context window or arbitrary report lengths.

#### Main review outcome: incomplete

The four ordinary review calls returned five findings, producing more distinct
edit targets than the configured limit of three. The runner stopped before
patching and preserved the candidate as **INCOMPLETE**, not a completed publication.
The high independent content score did not override this workflow result.

Useful findings concerned GIL activation scope, exception conditions, and warm-up
assumptions. Other findings overemphasized citation presentation or source scope.
The candidate also retained a p95-to-p99 acceptance-condition drift and ambiguous
mode-specific startup checks. These observations show that references and a
bounded context do not by themselves ensure complete, stable semantic review.

#### Controlled fault and local correction

The separate diagnostic copied the frozen but uncertified candidate. It did not
change the main status or erase pre-existing findings. The original U1–U4 request
was reconstructed and its hash matched to the recorded normal review. Only one
rollback flag in U4 was changed from `-X gil=1` to `-X gil=0`; the same normal
review path was used without revealing the expected answer.

Three additional calls within the original job budget detected the wrong flag,
replaced only its target block, and reviewed the copy again. The corrected copy
was **byte-for-byte identical to the original candidate**. The original candidate,
state, earlier units, deadline, and input hash remained unchanged. One exclusive
fault-copy authorization prevented duplicating the remaining budget through forks.

The verification call reported three other natural findings, including a
mode-specific GIL startup-check risk, while no longer flagging the injected
target. The controlled repair succeeded; it did not certify the whole report.
Different findings on the restored original text also demonstrate why a single
empty or nonempty model review is not a deterministic quality oracle.

#### Decision and implementation consequence

**Overall verdict: PARTIAL.** Meaningful 10,000-plus-character drafting, bounded
fresh invocations, reference-based backward reading, reconciled process restart,
and one controlled local correction were demonstrated. Unattended global
consistency/correction and publication were not.

Keep one author and the source/manuscript store. Implement the sequential-draft
mechanism as the next bounded slice, while keeping automatic long-report
publication gated. Add explicit, versioned decision/gate declarations and a
source-grounded finding-triage step before spending correction calls. Test that
critical cross-unit commitments survive and that justified corrections converge
within the same budget. Do not solve this by enlarging context indefinitely,
forcing every unit to exactly 3,000 characters, spawning independent authors,
silently discarding findings, or treating the 90-point grade as production approval.

### 12.8 Follow-up: practical ledger, triage, and publication

#### Design and assessment boundary

The next study tested a small shared decision ledger, disposition of reviewer
proposals, one bounded edit per candidate, and at most two candidates per case.
The purpose was useful delivery, not perfect agreement among critics. Original
source evidence and explicit user conditions remained authoritative; an author
proposal was not promoted to a measured fact. The same eight-source packet from
Section 12.7 was reused without changes.

Case A left the workload and dependencies unknown. Case B additionally fixed the
baseline to standard CPython 3.13 under identical load, required non-worsening
p95 latency and total RSS no greater than 1.10 times baseline, and fixed modes
A = standard/GIL on, B = free-threaded/GIL on, C = free-threaded/GIL off.
Both requested four units from the same author role. Sources and case definitions
were frozen; the independent Sol AI judge's rubric and expected control actions
were withheld from generation and editing.

Unlike the earlier planned single-unit pilot's artifact cap, this experiment requested
roughly 3,000–4,000 characters per unit as a soft target; actual output was bounded
by request/generation/response limits. It did not validate the pilot's 4,000-character
hard cap. Unit-level review required up to eleven calls per complete candidate,
including ledger, four writes, four reviews, edit, and recheck. The shared 40-call
ceiling could therefore stop a worst-case four-candidate study; it was not a
guarantee that every optional stage would fit.

The practical rubric allocated 30 points each to usefulness, grounding, and
important-condition consistency, and 10 to non-redundancy. A good report required
at least 80/100 and no remaining material error. Raw and post-edit quality were
assessed separately; a good raw draft did not substitute for an unfinished review.
Scores are independent AI assessments with supervisor evidence/diff checks, not
a human panel or an estimate of general success probability.

#### Controls and completed edit

Six saved-draft controls tested conflicts, a real GIL-scope error, a citation nit,
a wrong rollback proposal, invented acceptance values, and a style preference.
Five actions were appropriate. The citation-only proposal was safely worded but
incorrectly elevated to a blocking patch. The retrospective ledger preserved a
p95/p99 conflict as unknown and retained draft provenance, but also inverted a
GIL transition condition and missed a mode-specific startup commitment. A valid
ledger schema therefore did not certify the ledger's truth.

A1 returned no usable ledger. A2 produced a complete raw draft, independently
scored **83/100 with one material error**: force-off operation conflicted with an
unconditional expectation of automatic GIL re-enablement. Ordinary review
eventually identified four edit targets, but an arbitrary three-target cap
stopped the original path before editing.

The explicit editorial calibration removed that count gate without increasing
input, time, or generation limits. All four targets fit one 41,634-byte edit
workspace. One editor call and one affected-block recheck changed exactly four
blocks, preserving the ledger, raw draft, unrelated blocks, and original failed
publication record. The separate calibrated result was `publish_with_caveats`.
Independent post-edit assessment scored **88/100, zero material errors** and found
no editor degradation. The final operating section made force-off exceptions and
unsupported-extension restrictions explicit; remaining cross-reference weaknesses
were treated as minor, not grounds for another generation.

#### Case B: content quality is not execution completion

B1 retained the requested modes, percentile, comparator, RSS ratio, and the
distinction between user requirements and a throughput proposal. Its raw draft
scored **91/100 with zero material errors**. However, its second review request
returned HTTP 200 and `finish_reason=stop` with empty visible content. Review did
not complete; no edited/delivered result was committed. That failure consumed its
request allowance and was not silently replayed.

B2 was explicitly authorized after this known execution failure, with unchanged
code, source packet, query, limits, and original deadline. It completed four raw
units but its first review required **69,933 serialized bytes**, exceeding the
65,536-byte limit. Admission stopped before any B2 review was transmitted. B2
also has no completed editorial delivery. No third candidate, larger input cap,
or further live reconciliation was attempted.

Independent B2 raw assessment scored **77/100 with two material problems**: an
almost duplicated first unit containing an internal generation marker, and wording
that could permit inferring unique ownership or synchronization from a reference
count of zero or one. The fixed charter explicitly prohibited that inference.
The duplicate contributed directly to the oversized first review. A byte-admission
split alone would not repair these content problems. The ledger retained the
user's modes and numeric conditions, but did not prevent structural duplication
or an error outside its small commitment set.

| Candidate | Independent raw quality | Post-edit quality | Execution/delivery |
| --- | --- | --- | --- |
| A1 | No report | Not available | Incomplete ledger response |
| A2 | 83/100, one material error | 88/100, zero material errors | Separate calibrated edit completed; operator intervention required |
| B1 | 91/100, zero material errors | Not available | Empty review response; raw draft retained, no editorial delivery |
| B2 | 77/100, two material problems | Not available | Review input rejected before dispatch; no editorial delivery |

Offline reconstruction confirmed the cause. Dividing that first unit into two
contiguous, non-overlapping block ranges retained every block and produced
49,074-byte and 48,834-byte requests under the same prompt and source-selection
rules. This is an input-admission check, **not** evidence that split review would
have found every defect or completed publication. The final implementation must
size review work by the actual serialized workspace rather than chapter count.

#### Deviations, accounting, and decision

Several harness corrections were explicit interventions: admitting real draft
IDs as retrospective provenance, normalizing known citation brackets, narrowing
the ledger task, splitting an incomplete two-unit review into unit reviews,
removing the fixed edit-target cap, and retaining a validated constraint `status`
field returned by B1. Stored valid responses were reused without resending them;
failures and original budget consumption were preserved. A1 and the original
A2 two-unit review were `INCOMPLETE`, but the earlier child adapter discarded
their detailed finish/usage metadata, so their exact causes are unknown. The
adapter was subsequently corrected to retain safe failure metrics.

**The study made 26 new physical requests**, separate from the prior 39. Its
ceiling was 40 requests, concurrency one, 240 seconds per request, generation
allowance 16,384, input 64 KiB, response 4 MiB, and an unchanged 10,800-second
global deadline. There were zero automatic transport retries. The audit verified
unique attempt names, serial intent/result order, counters, stored response
hashes, frozen inputs, unchanged raw drafts, and the four-block edit replay.

| Observed measure | Value |
| --- | ---: |
| Requests with safe usage/duration metadata | 24 of 26 |
| Maximum transmitted serialized request | 52,199 bytes |
| Maximum duration among recorded requests | 102.271 s |
| Reported prompt tokens, available records only | 174,125 |
| Reported completion tokens, available records only | 140,869 |
| Sum of recorded request durations | 1,224.485 s |

These partial token totals are not complete billing totals; the duration sum is
not end-to-end latency. The rejected B2 review is not an additional physical
request. Credentials, dedicated provider reasoning fields, and raw provider
envelopes were excluded from persistence. B2 nevertheless returned an internal
marker in the visible-content channel; that unaccepted output is not a clean
publication. A field allowlist alone is insufficient to establish that a returned
manuscript is free of generation artifacts.

**Decision: retain the small ledger and practical materiality-based single-author
workflow, with overall feasibility still PARTIAL.** The ledger helped preserve
explicit conditions, and one bounded edit improved A2 into a good report. Neither
case establishes an unattended within-two-candidate success rate. Do not label
manual protocol reconciliation as automatic success, or a high raw score as a
completed delivery.

Proceed to a small implementation using the existing checkpoint/SQLite and job
API boundaries: validated public metadata, byte-admitted review ranges, durable
unit results, one edit round, at most two candidates, and exact selected-result
delivery. Keep incomplete editorial executions visible as `needs_review` rather than
inventing content. Do not add a contributor pool, a claim graph, more mandatory
judge layers, or unlimited quality retries. Validate that bounded vertical slice
with saved-response regressions and a small public pilot before unattended rollout.

### 12.9 First runtime implementation and validation boundary

#### Implemented runtime slice

The branch now contains a runnable private job API and a single-worker execution
path in `deep_research_runtime.py`. It uses the existing Python dependencies,
SQLite/WAL connection, and public-URL/DNS/redirect validation. There is no new
workflow framework, contributor pool, vector database, or message broker.

- Submission requires the trusted adapter's Bearer credential, the required
  `X-Research-Owner` header, and a caller-provided `action_id`. Same-owner/action
  submission attaches; changed request contents conflict; cross-owner lookup is
  denied. Status/result reads never launch research. Resume uses an expected
  revision and checks current state inside the mutation boundary.
- Dedicated job, physical-attempt, source-blob/extraction, editorial-revision,
  review, and publication records retain public execution state. Successful model
  receipts can be reused after interruption without resending the completed call.
  Hash/manifest checks reject inconsistent saved data rather than regenerating
  over it. A raw source blob is committed before extraction starts.
- Research uses fresh JSON `search`, `fetch`, `read`, and `finish` actions with
  explicit output schemas. Writing uses a small candidate-local decision ledger,
  a saved outline, selected source passages, and bounded prior-block context.
  It does not accumulate complete prior units into each later prompt.
- Reviews pack contiguous block ranges according to the actual provider-request
  bytes. Material findings are tied to their admitted target blocks. A bounded
  editor can replace or justify dismissal; recheck covers every affected target,
  including unchanged blocks participating in a multi-block finding.
- Each candidate has at most one edit round; at most two candidates share the
  original job limits. Specific failure evidence is passed to candidate two.
  An incomplete execution retains the best available draft without calling it
  approved. Its execution error and the selected draft's quality decision remain
  separate, including `quality_outcome=null` for unfinished review.
- Publication is committed once and returned without a rewriting model pass.
  The legacy `/research`, `run_research`, and `reserve_run` entry points are
  removed, not retained as fallback routes. Old diagnostic/checkpoint helpers
  and historical records are not a supported execution path for new jobs.

The implemented profiles are `single_unit` (one unit, 18 attempts, 4,500 seconds)
and `sequential_long` (two to four units, 40 attempts, 10,800 seconds). Research
reserves at least `4 * units + 6` calls for two ledger/write/review/edit/recheck
candidates. Research allowance is derived from the job's remaining saved attempt
budget minus this reserve, not a fixed eight-action cap across both profiles.
The earlier 12-call proposal left only four research calls after an
eight-call editorial reserve, effectively enough for one search/fetch/read/finish
sequence. The revised single-unit allocation permits three-source collection
and two bounded editorial rounds without increasing any existing job's budget.
Extra review ranges still consume the shared cap; these limits are not a promise
that every pathological output will fit or that candidate two will improve it.

#### Model and gateway boundary

`sakura_kimi_model.py` provides exact-byte request preparation and a small aiohttp
completion client for the fresh-call workflow. It does not introduce an SDK
transport wrapper or use native tool loops on this path. The existing native
reasoning-replay and diagnostic adapter remain separate.

The proxy adds authenticated `POST /research/v1/chat/completions`, mapped to the
upstream completion endpoint. It requires `SAKURA_RESEARCH_API_KEY`,
`X-Sakura-Attempt-Id`, and `X-Sakura-Deadline-Unix-Ms`. The runtime supplies its
configured `llm_api_key` for this internal credential, never an upstream account
token in a prompt. An unset or mismatched gateway key rejects the request before
an upstream send; credential provisioning has not been performed in this work.

The path shares existing account admission/cooldowns but sends upstream at most
once, with no redirects, hidden retries, or effort substitution. One absolute
deadline covers queueing and streaming. Explicit connection setup and a final
expiry check prevent a slow connection from sending inference after expiry;
automatic reconnection after watchdog closure is disabled. Synchronous DNS
itself is not claimed to be immediately interruptible.

Complete `DONE`/finish framing, visible content, and safe optional usage fields
are distinguished from incomplete transport. Empty or invalid completed output
is not a report; an unfinished stream is `unknown`, not a known failed generation.
Unresolved unknown attempts block new research dispatch across jobs and survive
runtime restart. The proxy's 300-second account quarantine is only a finite,
process-local precaution, not provider reconciliation or proof of cancellation.

#### Resource-bounded extraction

`source_extraction.py` runs a fixed child program after the raw blob is saved.
It uses the existing trafilatura/PyPDF libraries, does not inherit the parent's
credentials/environment, and sets Linux CPU/address-space limits before parser
imports. The parent enforces output and wall limits and kills, drains, and waits
for the child on timeout, cancellation, oversized output, or invalid results.
The Dockerfile copies this helper explicitly, not the diagnostic/test files.

Bounds are 1,500,000 input bytes, at most 8,000,000 extracted characters,
32 MiB of child output, 10,000 PDF pages, 20 seconds wall time, 15 CPU seconds,
and 512 MiB address space. All applicable limits must fit; overflow is not
silently truncated. PDF page identities, including empty pages, are retained.
HTML decoding is delegated to the installed parser; plain UTF-8 decoding is
strict. Unsupported resource-limit platforms fail visibly rather than falling
back to an uninterruptible parser thread.

#### Verification and remaining gates

Accepted checks use explicit, non-private unittest module lists, not discovery of
manifest-dependent historical diagnostics. They cover actual SQLite state and
serialization, saved-receipt recovery, owner/action isolation, stale mutations,
tampered artifacts, bounded review/edit behavior, candidate selection, and
ordinary-chat proxy regressions. A loopback integration test connects the actual
client to the actual proxy with a fake upstream, checking success, authentication
rejection, known HTTP failure, incomplete SSE, exact request bytes, and send counts.

The final explicit runtime suite ran 116 tests on Darwin, with two Linux-only
resource cases skipped; the proxy suite passed 31 tests. Ruff checks/formatting
and Pyright for the current runtime and accepted test modules passed. Whole-workspace
Pyright still reports one reference to the removed `reserve_run` in a local,
untracked historical diagnostic test. That diagnostic was preserved, not modified
or hidden by restoring an obsolete runtime entry point.

The extractor's Linux checks ran in a disposable existing runtime image with
network disabled, a read-only filesystem, non-root user, dropped capabilities,
and CPU/memory/process limits. Only the helper and its synthetic tests were
mounted; no production volumes, configuration, or credentials were supplied.
All eleven extraction tests passed, including actual HTML/PDF child imports,
address-space exhaustion, a shortened CPU-limit test, and real-process cleanup.
Darwin correctly rejects unsupported address-space enforcement; its parser/fake
tests are not evidence of containment on that platform.

This is a tested implementation slice, **not production rollout approval**.
Remaining work includes the managed Pipe and server-scoped UI guards, trusted
owner/action propagation, Regenerate/reattachment/Stop behavior, private Note
delivery, retention/operational policy, verified token accounting, and live
research quality checks. Unknown-attempt reconciliation and account uncertainty
across proxy restarts also remain release gates. The old generic tool registration
must not be deployed unchanged against this private API. No new live-provider
quality experiment, service deployment, or credential provisioning is claimed.
