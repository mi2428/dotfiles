# Deep Research Runtime Specification

## 1. Product contract

One explicit user action in Open WebUI produces a useful, source-grounded research
report in the requested language. The dedicated Deep Research model is a long-form
research product, not a short-answer pilot.

A successful HTTP response, valid JSON, completed job, saved Note, citation count,
or minimum character count is not by itself a successful research report. A report
may be published only when it:

1. answers every essential part of the original request;
2. distinguishes evidence, inference, assumption, and unresolved uncertainty;
3. cites the stored passages supporting its material factual claims;
4. contains a coherent multi-section analysis rather than an excerpt summary;
5. has no known material error or misleading omission after bounded review; and
6. is delivered byte-for-byte as the immutable runtime publication.

When evidence or execution is insufficient, the product returns an explicit
incomplete result. It must never shorten, pad, or relabel a weak draft as completed.

**MUST** and **MUST NOT** are release requirements. Numerical limits are operating
defaults, not claims about model intelligence or provider capacity.

## 2. Scope and non-goals

The product supports public web pages and public PDFs. It does not provide
private connectors, arbitrary local-file access, authenticated browsing, shell
access, or unrestricted model tools.

The implementation uses:

- one managed Open WebUI Pipe;
- one runtime worker process;
- one Sakura/Kimi model profile;
- one active provider request at a time; and
- one author role writing two to four durable units.

Independent chapter contributors, a claim graph, vector database, message broker,
general workflow framework, and mandatory per-job AI judge are out of scope. Add
none of them without measured evidence that the simpler design is inadequate.

## 3. Component ownership

| Component | Owns | Does not own |
| --- | --- | --- |
| Open WebUI Pipe | Authenticated submission, progress, reattachment, cancellation request, exact result and private Note delivery | Research context or editorial judgment |
| Runtime scheduler | Identity, state transitions, budgets, deadlines, persistence, deterministic validation | Hard-coded conclusions or source truth |
| Research planner | Question checklist, search strategy, source adequacy, follow-up questions and counterevidence | Network access or budget changes |
| Author/editor | One coherent report, outline, synthesis and bounded corrections | Inventing evidence or altering immutable source data |
| Reviewer | Revision-specific, source-grounded material findings against the complete request | Unconditionally authoritative edits |
| Source store | Immutable source bytes, extraction revisions and addressable passages | Treating summaries as original evidence |
| Sakura gateway | Credential isolation, shared account admission and one outbound send per physical attempt | Hidden retry, model substitution or budget reset |

These are bounded invocations, not long-lived autonomous agents. Source text and
model output are untrusted data. Neither can grant permissions or change the task.

## 4. End-to-end workflow

```text
submit
  -> scope the original request
  -> adaptive bounded research <-> immutable source store
  -> evidence assessment and report outline
  -> one author writes 2-4 durable units
  -> source-grounded review of every unit and the complete checklist
  -> one bounded edit and affected-scope recheck when justified
  -> deterministic publication gate
  -> immutable publication
  -> exact Open WebUI response and private Note delivery
```

### 4.1 Submission and scope

The Pipe submits the dedicated `deep` profile with `max_units=4`. It MUST NOT map
requests to a one-section short-report path. A separate short-answer product, if
ever required, belongs outside this Deep Research route.

The first bounded model assignment converts the original request into a
`ResearchPlan` containing:

- requested language and time horizon;
- explicit exclusions or unavailable private inputs;
- a checklist of atomic questions with stable IDs;
- whether each checklist item is essential;
- preferred source types for each item; and
- three to six initial search queries, each with zero to two canonical direct
  primary-source URLs when the planner confidently knows them.

Direct URL candidates are untrusted hints, not evidence. They pass through the same
public-URL validation, bounded fetch, immutable storage, extraction and passage
admission path as search results. The planner leaves the list empty rather than
guessing a URL. Candidate selection does not prefer these unverified URLs over
informative search-result metadata for the same target.

The original request remains authoritative. The runtime assigns stable IDs to its
explicit clauses and list items before planning. A plan cannot remove, weaken or
silently reinterpret them. Every request-fragment ID must map to at least one
checklist item before the runtime accepts the plan.

The initial checklist is not a frozen chapter list. Preliminary evidence informs
the final outline.

### 4.2 Adaptive bounded research

Research proceeds in bounded rounds:

1. The runtime executes the accepted search queries and admits any validated direct
   source candidates into the same result set. If the search service reports only
   unavailable engines and there are no direct candidates, the job fails explicitly
   instead of treating the outage as an evidence gap.
2. The planner receives result metadata under stable IDs and selects candidate
   documents and purposes.
3. The runtime validates each public URL, fetches it through the SSRF-safe path,
   stores the immutable bytes, and extracts bounded text.
4. The planner receives an index and selected verbatim passages, then returns an
   `EvidenceAssessment` for every checklist item.
5. The assessment may request three to six follow-up queries, identify
   counterevidence, or stop with explicit gaps.

An evidence assessment labels each checklist item `covered`, `qualified`, or
`unresolved` and references only admitted passage IDs. It also records evidence
origin and authority: multiple hosts repeating one report are one origin, while
different useful pages on the same official site remain valid separate documents.
Passage-to-checklist relevance tags are retrieval hints, not admission boundaries;
any prompt-visible passage may support any checklist item when its text entails it.
When a selected result is collected, the runtime extracts passages for both the
selector's hints and every checklist item targeted by the query that produced it.
Within a long extracted paragraph, the bounded passage window favors the densest
query-term occurrence rather than blindly taking the first table-of-contents hit.

The runtime deduplicates exact URLs and content identities. It MUST NOT discard a
document merely because another accepted document shares its host. It MUST NOT use
host count as a proxy for semantic coverage.

The planner prefers primary and authoritative sources for company identity,
official specifications, laws, filings, statistics and numeric claims. Secondary
sources may provide context or leads but must be labelled when primary evidence is
unavailable. Research actively checks conflicting dates, definitions and adverse
evidence instead of collecting only confirming snippets.

Research stops when:

- every essential checklist item is covered or honestly qualified;
- another round is unlikely to change the answer and the reason is recorded; or
- a hard budget or deadline prevents further work.

The scheduler reserves editorial capacity before every research-model call. It
does not spend the calls needed to write and review a usable report.

### 4.3 Evidence and outline

After preliminary research, one accepted outline supplies a localized report title
and maps every checklist item and selected passage to two to four ordered content
units. Each unit has:

- a unique user-facing heading;
- a clear analytical purpose;
- checklist IDs it answers;
- relevant passage IDs;
- prior units it may reopen for continuity; and
- a short handoff describing the conclusion it must carry forward.

Every essential checklist item MUST appear in at least one unit. Every unit MUST
have relevant evidence or be explicitly designated as assumptions/limitations
analysis. The outline may group related checklist items; it must not create empty
sections merely to meet a count.

Keep a small candidate-local decision ledger for important cross-section facts,
definitions, metrics, units, comparison bases, assumptions and conflicts. The
ledger aids consistency but is not a truth database. The original request and
source passages remain authoritative.

### 4.4 Sequential single-author drafting

One author role writes the units in order. Each invocation receives the original
request, accepted outline, relevant source passages, decision ledger, small prior
handoffs and only the earlier blocks needed for continuity. It does not receive an
ever-growing private conversation or repeatedly summarized summaries.

Each accepted unit:

- starts with its exact level-two outline heading;
- contains substantive analysis, not copied excerpts or a citation list;
- addresses all assigned checklist items;
- cites admitted passages for material factual claims;
- preserves conditions and uncertainty from the ledger;
- avoids repeating earlier sections; and
- commits atomically before the next unit begins.

Unless the user requests another length, target roughly 2,000-4,000 substantive
characters per unit. A unit below 1,200 substantive characters is incomplete unless
the original request explicitly asks for a shorter report. Length is an
anti-truncation signal, not a quality score; repetition and filler do not count.

Later units may reopen exact earlier blocks and neighboring source passages by ID.
A restart reuses committed units without generating them again.

### 4.5 Review and correction

A fresh reviewer checks every accepted unit against the complete original
checklist, outline, decision ledger and actual source passages. It checks:

- essential-question coverage and usefulness;
- factual entailment and source authority;
- numeric subject, unit, period, comparator and derivation;
- conflicting evidence and unsupported certainty;
- consistency across units;
- duplicated or missing analysis;
- citation/source alignment; and
- language and presentation defects that materially impede the answer.

Review inputs are packed as contiguous runtime-owned block ranges under the actual
serialized-request byte cap. Every block is reviewed exactly once in the initial
review coverage, with a small whole-report heading/checklist map attached to each
range. No block is silently dropped to make a request fit.

Findings are classified by justified action:

- **Material:** changes the answer, violates an explicit request, invents or
  misstates evidence, breaks a comparison, or leaves essential scope misleading.
- **Benign:** style, optional detail, honest noncritical uncertainty, or redundant
  citation presentation.
- **Unsupported:** a reviewer proposal not established by admitted evidence.

Material findings reference exact draft block, checklist/ledger and source IDs and
state the consequence of leaving the text unchanged. An editor may replace the
smallest affected blocks or dismiss an unsupported finding with admitted evidence.
One bounded edit pass is allowed per candidate. Recheck covers every replacement
and evidence-backed dismissal; unchanged accepted blocks remain byte-identical.

If material problems remain, the runtime may generate one fresh second candidate
from the same original request and evidence, with specific failure feedback. It
must not silently change the request, reset budgets or repeat a rejected ledger.

## 5. Source and citation contract

Store source bytes before extraction. Each extraction is an immutable revision
with normalized text, a content hash and page/span map where available.
Re-extraction creates a new revision; it never changes evidence behind an accepted
citation.

Citation locators identify an exact extraction revision and contiguous text span.
The runtime validates offsets, hashes and verbatim equality before admission.
Generated quotes are never treated as source truth.

Material claims require citations. Derived estimates additionally state:

- the input values and their sources;
- the formula or reasoning that combines them;
- assumptions and plausible sensitivity range; and
- which requested conclusion remains uncertain.

An unsupported precise number must be removed or converted to a clearly labelled
scenario. Numeric literal overlap alone is not evidence entailment.

Fetches, redirects and references discovered in documents all pass through DNS,
public-address, redirect, media-type, byte and timeout checks. Stored HTML is not
rendered as active content.

## 6. User-facing report contract

The immutable Markdown publication has this structure:

1. exactly one level-one report title;
2. two to four substantive level-two content sections in outline order;
3. optional level-three subsections;
4. one localized limitations section; and
5. one localized sources section.

The opening content section states the answer or key findings. The final content
section synthesizes the conclusion, confidence and decision-relevant uncertainty.
Headings and runtime-generated prose use the requested language. Proper names and
source titles may remain in their original language.

The author MUST NOT generate the title, limitations or bibliography as hidden
duplicates. The runtime assembles those elements deterministically from accepted
state. For Japanese output, the appendix headings are `## 限界` and `## 情報源`.

Each source is a separate Markdown list item, for example:

```markdown
- [S1] [Document title](https://example.com/document) — Publisher, retrieved YYYY-MM-DD
```

Single newlines between plain source records are forbidden because CommonMark may
collapse them into one paragraph. The rendered Open WebUI result MUST be visually
checked for distinct headings, lists and paragraphs before release.

The publication is at most 256 KiB. Oversized output is incomplete; it is not
silently truncated. Internal action envelopes, generation markers, hidden
reasoning, credentials and private diagnostics never appear in the report.

## 7. Publication quality gate

### 7.1 Deterministic checks

Before semantic approval, the runtime verifies:

- the original request and accepted plan hashes;
- all required units and unique headings are present in order;
- each unit passes the substantive-content and anti-truncation checks;
- every essential checklist item maps to report blocks;
- every cited passage exists and belongs to the job;
- every material authored estimate or projection records sources and assumptions;
- deterministic source comparisons are not treated as projections solely because
  they show signed anomalies or arithmetic; estimate controls remain mandatory
  when the request or the prose identifies an authored estimate, scenario, forecast,
  or projection;
- all blocks were covered by the accepted review revision;
- all material edits and dismissals were rechecked;
- no unresolved material finding remains;
- title, localized limitations and Markdown source list are well formed; and
- publication, bibliography and limitation records hash to the assembled output.

A deterministic check proves structure and provenance, not semantic truth.

### 7.2 Semantic outcome

The runtime derives one of three outcomes from the accepted review and validated
editorial state:

- `publish`: useful, essential scope covered, major claims traceable, and no
  substantiated material blocker remains.
- `publish_with_caveats`: the same useful report, with explicit benign uncertainty
  or evidence limitations that do not make its conclusions misleading.
- `retryable_quality_failure`: material error, missing essential scope, shallow
  synthesis or unusable presentation requires another candidate or human review.

The presence of a limitation does not automatically mean
`publish_with_caveats`. That outcome requires the same usefulness and essential
coverage as `publish`.

Only the first two outcomes may produce `status=completed` and automatic Note
delivery. After two unsuccessful candidates, preserve the best draft as
`status=incomplete`, `delivery_status=needs_review`, with
`quality_outcome=retryable_quality_failure`. If semantic review never completed,
the quality outcome is `null`.

Execution, authorization and artifact-integrity failures remain separate from
content quality. A high score cannot override a failed review or corrupt artifact.

## 8. Budgets and provider boundary

| Limit | Deep profile |
| --- | ---: |
| Active provider requests | 1 |
| Physical request deadline | 360 seconds |
| Model attempts per job | 40 |
| Job wall time | 10,800 seconds |
| Generation allowance per attempt | 16,384 tokens |
| Serialized model request | 64 KiB |
| Provider response | 4 MiB |
| Research rounds | 4 |
| Search queries per round | 6 |
| Checklist items and assessment passages | 12 each |
| Fetched documents per job | 24 |
| Individual fetched document | 1,500,000 bytes |
| Stored source/extraction payload per job | 128 MiB |
| Draft units | 2-4 |
| Draft unit length when unspecified | 1,200-4,000 substantive characters |
| Publication | 256 KiB |
| Candidate generations | 2 |
| Edit passes per candidate | 1 |

All limits are hard ceilings, not targets. The scheduler records every physical
attempt, including format correction and continuation. Search and fetch operations
have separate counters and do not consume provider-attempt IDs.
For an author-unit numeric-block violation, the single correction receives the
unpersisted failed draft as untrusted input and edits that draft instead of blindly
regenerating it; the same validators and attempt limits still apply.

Before research dispatch, reserve at least `4 * units + 6` provider attempts for
two complete ledger/write/review/edit/recheck candidate paths. Additional packed
review ranges consume the shared cap and are admitted from actual serialized bytes.
Each review range contains at most 8 draft blocks; long reports split at unit
boundaries before further byte-based packing.
If the remaining budget cannot complete required editorial work, stop before the
next research call.

One absolute deadline covers gateway queueing, connection, request, headers and
streaming. SDK and proxy retries are disabled within one physical attempt. Runtime
may create up to three new, charged physical attempts with new attempt IDs after a
definitive `not_sent` or `known_failed` HTTP 408, 409, 425, 429 or 5xx result. Delay
is exponential at 1, 2 and 4 seconds plus up to 250 ms jitter; every retry remains
subject to the job deadline and attempt budget. Permanent client errors are not
retried. An uncertain transmission or incomplete stream is `unknown` and is never
replayed. A complete, parseable provider SSE error event is a known failure even
without a `[DONE]` marker; a truncated error event remains `unknown`.

Model assignments use fresh ordinary completion calls with validated JSON only for
small control records. They do not depend on forced tool selection, a configurable
reasoning-effort parameter or persisted private reasoning.

Provider-reported usage is recorded when present. Missing usage is `null`, not
zero. Local token estimates or calibration receipts are not submission gates.

## 9. Durable state and recovery

SQLite/WAL in the private runtime volume stores:

| Record | Required contents |
| --- | --- |
| Job | Owner, action, canonical request hash, plan, status, phase, limits, deadline, cancellation state |
| Attempt | Assignment, reservation, dispatch state, timestamps, safe result and reported usage |
| Source | Canonical/final URL, retrieval metadata, immutable bytes and content identity |
| Extraction | Extractor revision, immutable normalized text, page/span map and hash |
| Evidence | Checklist relevance, origin, authority, exact passage locator and limitations |
| Draft revision | Candidate/unit, outline revision, Markdown, block manifest, ledger and dependencies |
| Review/edit | Exact base revision, findings, dispositions, replacements and recheck result |
| Publication | Ordered accepted revisions, final Markdown, bibliography, limitations, hash and delivery state |

Accepted actions and their next eligible state commit atomically. Optimistic
revision checks reject stale edits. Hash or manifest inconsistency fails closed;
it never triggers regeneration over corrupted state.

Job status is one of `queued`, `running`, `paused`, `completed`, `incomplete`,
`cancelled` or `failed`. Active phases are `scoping`, `researching`, `writing`,
`supervising`, `editing` and `publishing`. Delivery is separately `pending`,
`delivered` or `needs_review`; it cannot turn an incomplete job into a completed
one.

Attempt states are `reserved`, `dispatched`, `succeeded`, `known_failed`,
`unknown`, or `abandoned_unresolved`. Runtime restart does not resend unknown work.
An authenticated operator may explicitly abandon one exact unknown attempt while
acknowledging possible execution and charges; the old reservation remains and the
affected job ends incomplete. New research requires a new user action.

Cancellation stops new dispatches and preserves accepted artifacts. Closing a
socket or losing a UI observer is not proof that upstream execution stopped.

## 10. Open WebUI and private API

The managed Pipe uses short authenticated runtime calls. It does not retain one
multi-hour HTTP request or use an LLM polling loop.

| Operation | Contract |
| --- | --- |
| `POST /research/jobs` | Bind owner/action/request, create or attach to the same job |
| `GET /research/jobs/{id}` | Return authorized phase, progress, counters and safe gaps without dispatch |
| `GET /research/jobs/{id}/result` | Return immutable publication or explicit incomplete package |
| `POST /research/jobs/{id}/cancel` | Idempotently stop new work and preserve artifacts |
| `POST /research/jobs/{id}/resume` | Explicit revision-checked resume with original limits |
| `POST /research/actions/{action_id}/cancel` | Cancel the exact action without creating a job |
| `POST /research/jobs/{id}/delivery` | Acknowledge exact publication/hash/private Note identity |

Owner, action, job and candidate are distinct identities. The assistant response
ID may be the action ID only when the pinned Open WebUI contract proves it is fresh
for explicit Regenerate and stable for retries and reattachment. Same-action
resubmission attaches; changed content conflicts. Regenerate creates a new action.

The server verifies the managed Pipe and HMAC-binds owner, chat, action and query.
Client markers and model-generated owner IDs are never trusted. The private job API
is excluded from model tool discovery.

The model-scoped Open WebUI guard disables UI-side compaction, retrieval-query
generation, tool/skill enrichment, title/tag/follow-up generation and output
rewriting for this model. Authentication, authorization and ordinary chat behavior
remain unchanged.

Completed Markdown is hash-verified, returned without a rewriting model pass and
stored in one deterministic private Note keyed by owner/job/publication. Note
persistence and runtime publication cannot share a transaction, so delivery uses
an idempotent outbox acknowledgement. Delivery retry never reruns research.

## 11. Security and retention

- Credentials stay out of arguments, prompts, artifacts, diagnostics and logs.
- Raw provider envelopes and hidden reasoning are not persisted.
- Source and model text cannot execute instructions or widen permissions.
- Unauthorized job, source, draft, publication or Note access fails closed.
- Public URL checks are repeated after every redirect and DNS resolution.
- Parser children receive no parent credentials and run with CPU, memory, output,
  page and wall-time limits on the supported production platform.
- Extraction ceilings are 8,000,000 characters, 32 MiB child output, 10,000 PDF
  pages, 20 seconds wall time, 15 CPU seconds and 512 MiB address space.
- Shared admission records use stable non-secret account IDs; credential values
  and fingerprints are not persisted.
- Active, unknown and undelivered jobs are not purged.
- Terminal delivered jobs default to 30-day runtime retention under a 512 MiB
  global logical payload limit.
- Small owner/action/request tombstones survive payload purge so duplicate
  submission cannot become a new provider execution.
- Runtime retention does not delete Open WebUI Notes.

## 12. Acceptance and release gates

### 12.1 Software checks

Tests MUST establish:

- same-action attach and changed-request conflict;
- zero provider sends from status/result reads;
- no hidden retries or sends after cancellation, deadline or budget exhaustion;
- no replay of unknown attempts;
- safe URL, redirect, extraction and storage bounds;
- source locator and citation integrity;
- plan/checklist/outline coverage rejection;
- two to four substantive content sections and localized appendix rendering;
- contiguous complete review coverage and stale-edit rejection;
- correct candidate-two and `needs_review` behavior;
- restart reuse of committed sources and units without regeneration;
- exact publication/response/private Note hash equality;
- reconnect, Regenerate and Stop behavior; and
- ordinary-chat non-regression.

Tests use explicit tracked module lists. Historical or private diagnostics are not
part of accepted discovery.

### 12.2 Live quality set

Before unattended publication is enabled, run a frozen public set containing at
least five materially different cases:

1. sparse public-company research with a derived range and explicit assumptions;
2. primary-document technical research;
3. conflicting-source reconciliation;
4. multi-option comparison under common conditions; and
5. difficult HTML/PDF extraction with tables or page-specific evidence.

Freeze each request, rubric and known critical errors before generation. Score the
delivered result after bounded editing; retain raw-candidate results separately.
At least one human review must inspect factual support, usefulness and rendered
structure. An independent model review may assist but is not production truth.

Release requires:

- zero completed reports with a known material error or missing essential request;
- at least four of five cases delivered within two candidates with a frozen score
  of at least 80/100;
- every non-delivered case represented honestly as incomplete;
- rendered headings, paragraphs, citations and source lists visually verified;
- preserved attempt counts, deadlines and artifact hashes; and
- successful new-chat, existing-chat, reconnect, restart, Regenerate, Stop and
  private-Note flows on the deployed integration.

One successful E2E proves only that one path worked. It does not establish the
quality or success rate of Deep Research.

## 13. Conformance

The implementation conforms only when one durable execution path satisfies this
document. Disconnected planning/research paths and hidden short-report fallbacks
must not exist in the conforming build.

If implementation and this specification disagree, fail the release gate and
resolve the disagreement explicitly. Do not change the specification after a poor
result merely to relabel that result as acceptable.
