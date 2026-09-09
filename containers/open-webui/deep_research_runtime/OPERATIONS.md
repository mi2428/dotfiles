# Deep Research Operations
This runbook is for the single `sakura-proxy` / single `deep-research-runtime`
deployment. Both services must mount the same private volume at
`/data/deep-research.sqlite3`. Do not scale either service horizontally.
## Required environment
From the repository root, `bash scripts/open-webui.sh "$PWD" compose <arguments>`
runs Compose with the encrypted environment and persistent local service settings.
Use this wrapper for the Compose commands below unless that environment is already
loaded. It initializes missing internal keys in the owner-only local state file
`$XDG_STATE_HOME/open-webui/deep-research-runtime.env` (defaulting to
`~/.local/state`), retaining existing keys. Initial account labels follow the
configured token order and persist; later count/order changes require deliberate
account-ID configuration, not automatic reassignment. The default operator label
is `local-operator`. No credential values are stored in Compose or Git.

Provide values through the operator environment or a protected env file; never
put credentials in command arguments, shell history, logs, or `docker compose config` output.
- `SAKURA_AI_ACCOUNT_TOKENS`: secrets, held only in proxy memory.
- `SAKURA_AI_ACCOUNT_IDS`: stable public IDs, one-to-one and in the same order
  as tokens. Never rename/remove an ID while its durable state is unresolved.
- `SAKURA_RESEARCH_API_KEY`, `DEEP_RESEARCH_RUNTIME_API_KEY`.
- `DEEP_RESEARCH_OPERATOR_API_KEY`: separate from the owner/runtime key.
- `DEEP_RESEARCH_OPERATOR_ID`: the accountable human/operator identity.
- `DEEP_RESEARCH_DB_PATH=/data/deep-research.sqlite3` in both services.
- `DEEP_RESEARCH_RETENTION_DAYS=30` and
  `DEEP_RESEARCH_GLOBAL_LOGICAL_BYTES=536870912` unless intentionally changed.
## First startup and calibration
Calibration is live, billable work: four bounded research requests, including a
65,535-byte boundary fixture. Obtain explicit approval and budget first. The
research transport has a 240-second absolute deadline and no hidden retry.
Start only the dependencies, proxy, and runtime. `exec` works while the runtime
health JSON is `not_ready`, so WebUI dependency gating cannot deadlock calibration.
```bash
cd containers/open-webui
docker compose up -d sakura-proxy searxng
docker compose up -d --no-deps deep-research-runtime
# Expected before first calibration: status=not_ready, token_accounting.ready=false.
docker compose exec -T deep-research-runtime python -c \
  'import json,urllib.request; print(json.dumps(json.load(urllib.request.urlopen("http://127.0.0.1:8000/health")),indent=2))'
# Uses service env for DB, model, gateway, actor, and API key; timeout maximum is 240.
docker compose exec -T deep-research-runtime \
  python token_accounting.py calibrate --timeout 240
# Gate on JSON, not merely HTTP 200 or Compose's container-health label.
docker compose exec -T deep-research-runtime python -c \
  'import json,urllib.request; v=json.load(urllib.request.urlopen("http://127.0.0.1:8000/health")); print(json.dumps(v,indent=2)); raise SystemExit(0 if v["token_accounting"]["ready"] else 1)'
docker compose up -d open-webui
```
Without a matching receipt, health remains `not_ready`, new submissions return
503, and attempt dispatch fails closed. A receipt is bound to the serving model,
gateway, fixed assets, 64 KiB cases, verified input ceiling, and counter code.
Changing any binding requires a new explicitly approved calibration.
## Internal API helper
The helper reads credentials from the already-running container environment and
request JSON from stdin. Credential values therefore do not enter process args.
```bash
runtime_call() {
  local kind="$1" method="$2" path="$3"
  docker compose exec -T -e API_AUTH_KIND="$kind" -e RESEARCH_OWNER \
    deep-research-runtime python -c '
import json,os,sys,urllib.error,urllib.request
kind,method,path=os.environ["API_AUTH_KIND"],sys.argv[1],sys.argv[2]
key="DEEP_RESEARCH_OPERATOR_API_KEY" if kind=="operator" else "DEEP_RESEARCH_RUNTIME_API_KEY"
headers={"Authorization":"Bearer "+os.environ[key],"Content-Type":"application/json"}
if kind=="owner": headers["X-Research-Owner"]=os.environ["RESEARCH_OWNER"]
body=sys.stdin.buffer.read()
req=urllib.request.Request("http://127.0.0.1:8000"+path,data=body or None,headers=headers,method=method)
try:
    with urllib.request.urlopen(req) as r: print(r.status,r.read().decode())
except urllib.error.HTTPError as e:
    print(e.code,e.read().decode()); raise
' "$method" "$path"
}
```
## Obtain exact unresolved IDs (read-only)
Never invent or infer IDs. This prints metadata only, not prompts, responses, or
tokens. `lease_id == attempt_id` correlates a research/calibration send.
```bash
docker compose exec -T deep-research-runtime python -c '
import os,sqlite3
p=os.environ["DEEP_RESEARCH_DB_PATH"]
d=sqlite3.connect(f"file:{p}?mode=ro",uri=True)
queries={
 "research": "SELECT j.owner_id,j.action_id,a.job_id,a.attempt_id,a.assignment_key,a.state,j.revision,j.status FROM research_attempts a JOIN research_jobs j ON j.job_id=a.job_id WHERE a.state IN (\"unknown\",\"dispatched\")",
 "accounts": "SELECT account_id,lease_id,purpose,state,updated_at_ms FROM account_admissions WHERE state=\"unknown\"",
 "calibration": "SELECT attempt_id,run_id,case_name,state,model_alias,gateway_fingerprint,input_tokens_estimated,output_tokens_reserved,observed_prompt_tokens FROM token_calibration_attempts WHERE state IN (\"unknown\",\"dispatched\")"
}
for name,sql in queries.items(): print(name,*d.execute(sql).fetchall(),sep="\n")
' </dev/null
```
`dispatched` after a process interruption is uncertainty, not proof of success or
`not_sent`. Restart/recovery converts it to `unknown`. Do not replay it.
## Resolve UNKNOWN explicitly
Use the exact risk acknowledgement below. Generate one unique operator action ID
per approval and reuse that same ID/body if the response is lost. A new action ID
is not a retry. Approval accepts possible duplicate execution/charge; it does not
assert success, `not_sent`, or a refund. Reservations are not refunded.
```bash
export RISK_ACK='possible duplicate execution or charge; no refund; no replay'
export OPERATOR_ACTION_ID="$(uuidgen)"   # preserve for an idempotent retry
```
For a `research_attempts` row, export its exact values as `JOB_ID`, `ATTEMPT_ID`,
and `EXPECTED_REVISION`. This atomically abandons the attempt,
releases its matching unknown account lease if present, and makes the job
`incomplete`. That assignment cannot be replayed.
```bash
python3 - <<'PY' | runtime_call operator POST /internal/research/attempts/abandon
import json,os
print(json.dumps({"job_id":os.environ["JOB_ID"],"attempt_id":os.environ["ATTEMPT_ID"],
 "action_id":os.environ["OPERATOR_ACTION_ID"],"expected_revision":int(os.environ["EXPECTED_REVISION"]),
 "risk_ack":os.environ["RISK_ACK"]}))
PY
```
For an unknown account with no matching research attempt (normal chat or
calibration), export its exact `ACCOUNT_ID` and `LEASE_ID` from `account_admissions`:
```bash
python3 - <<'PY' | runtime_call operator POST /internal/research/accounts/abandon
import json,os
print(json.dumps({"account_id":os.environ["ACCOUNT_ID"],"lease_id":os.environ["LEASE_ID"],
 "action_id":os.environ["OPERATOR_ACTION_ID"],"risk_ack":os.environ["RISK_ACK"]}))
PY
```
A calibration UNKNOWN also needs its own durable attempt abandoned; use a second
unique action ID, then start a new explicitly approved calibration (not a replay):
```bash
export OPERATOR_ACTION_ID="$(uuidgen)"
docker compose exec -T deep-research-runtime python token_accounting.py abandon \
  --attempt-id "$CALIBRATION_ATTEMPT_ID" --action-id "$OPERATOR_ACTION_ID" \
  --risk-ack "$RISK_ACK"
```
An unresolved account is unavailable to both research and ordinary chat; known
normal-chat retry/cooldown behavior otherwise remains unchanged.
## Cancel by action ID
Preserve the exact original `ResearchJobRequest` JSON; do not reconstruct it.
The path `action_id`, owner, and canonical body hash must match. This boundary
performs no inference and handles Stop before or after job creation atomically.
```bash
export RESEARCH_OWNER='the-exact-owner-id'
runtime_call owner POST "/research/actions/$ACTION_ID/cancel" <"$REQUEST_JSON_FILE"
```
A pre-submit cancel returns `{"status":"cancelled","job_id":null}`. A running
job returns `cancel_requested` and observes at most the current bounded call.
Submitting that action later returns 409 `action_cancelled`. Retry the same cancel
with the same owner/path/body; changed content returns 409.
## Delivery, retention, and tombstones
Only acknowledge delivery after the exact publication is durably written to the
note. Obtain `publication_id` and `content_hash` from authenticated job result,
then POST `{publication_id,content_hash,note_id}` to
`/research/jobs/$JOB_ID/delivery`. The runtime verifies the stored Markdown/hash.
Purge is operator-only and performs no `VACUUM`:
```bash
runtime_call operator POST /internal/research/retention/purge </dev/null
```
After the TTL, purge accepts terminal jobs with no publication, or jobs whose
publication is `delivered`; any `unknown`/`dispatched` attempt is retained. It
deletes runtime payloads in FK order and leaves a small
`research_job_tombstones` row. Status/result then return 410 and the same action
cannot regenerate the job. External note content is never deleted. Quota failure
does not justify purging active/unknown or undelivered publications.
