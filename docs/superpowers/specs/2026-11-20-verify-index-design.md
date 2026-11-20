# verify-index: measure drag-lint's resolution against DelphiLSP (LSP1-VERIFY, slice 1.53.0)

Status: spec (lane SPEC-LSP1, v1523 run, 2026-11-20). Owner away; gates self-approved by the
lane, reviewed by the run controller. Binding scope: v1523 OWNER-QUESTIONS Q5 default a --
"verify-index status:internal, sample 200 refs per project, mismatch rate + list, no fixes".
Slices (SLICES-OWNER-APPROVED): 1.52.3 this spec -> 1.53.0 internal verb (lane LSP1-VERB) ->
1.53.1 full. Origin: docs\INBOX-delphilsp-verification-and-refactoring.md item 1 ("a
self-checking index").

## Problem

The `wrong` gap class (the index answers, but incorrectly) is found only when someone happens to
notice. drag-lint resolves names with its own resolver; DelphiLSP runs the real compiler front
end. Asking DelphiLSP "where is the declaration of the name at this position" for a sample of
positions drag-lint already resolved turns `wrong` into a measured number: a mismatch rate plus
the list of mismatching references, each one a candidate resolver bug.

## Scope of slice 1.53.0

In:
* A new CLI verb `verify-index`, registry status `internal` (accepted, not in `--help`).
* One project index DB per run; a deterministic sample of resolved references.
* One headless DelphiLSP child per run, configured from the project's `.delphilsp.json`.
* Outcome per sampled reference, counts, mismatch rate, list of non-matching rows; text or JSON.
* Read-only: the DB is opened read-only, no source file is written, no gap log is written.

Out (1.53.1 "full" or later, recorded so the plan does not drift into them):
* Stratified sampling of drag-lint's doubtful cases (overloads, same name in several units,
  `with`, class helpers, generics); a `--kind` / `--stratum` filter.
* Automatic logging of mismatches to `stats\draglint-gaps.log` or an INBOX.
* Library DBs, multi-DB runs, `--all` over the manifest.
* References (`textDocument/references`) and hover comparison; DFM bindings.
* An IDE / VS Code / MCP surface.
* Any fix to the resolver.

## Definitions

* **Candidate reference**: a row of `refs` in the DB whose target is resolved, where the target is
  `call_edges.target_symbol_id` when that ref has a call edge with confidence `certain`, else
  `refs.symbol_id`; `refs.inc_variant = 0`; `refs.kind` is one of `call`, `read`, `write`,
  `write-through`, `type_use`, `member-access`, `property-spec`, `record-field`; and the target
  symbol's kind is NOT `local_var` or `param`.
  Why locals and params are out: they are 256k of the 435k resolved refs on drag-lint's own DB
  (measured 2026-11-20) and are resolved inside one routine; sampling them would make the rate
  look better without testing the cross-scope resolution the verb exists to check.
* **Expected location** (drag-lint's answer): the target symbol's file path, its declaration line
  range `start_line..end_line`, and `impl_start_line` when not null. Lines and columns in the index
  are 1-based; the end column is exclusive.
* **LSP answer**: DelphiLSP's reply to `textDocument/definition` at position
  `(line = refs.start_line - 1, character = refs.start_col - 1)` for the ref's file. The reply may
  be `null`, a `Location`, a `Location[]` or a `LocationLink[]` (use `targetUri` +
  `targetSelectionRange.start.line`, falling back to `targetRange.start.line`).
* **Outcomes** (exactly one per sampled reference):

| outcome | when | in the rate |
|---|---|---|
| `match` | some LSP location has the expected file (case-insensitive, normalised full path) AND its 1-based line is in `start_line..end_line` or equals `impl_start_line` | yes (denominator) |
| `mismatch` | the LSP answer has at least one location and none matches | yes (numerator and denominator) |
| `empty` | the LSP answer is `null` or `[]`, also after the one retry | no |
| `error` | an error response, a timeout, or an unparsable reply | no |
| `skipped` | the source text at the position no longer starts with `name_text` (case-insensitive) -- the file changed since the index -- or the line has a non-ASCII character before the ref's column (UTF-16 column risk), or the file cannot be read | no |

* **Mismatch rate** = mismatch / (match + mismatch); 0 when the denominator is 0.

## Acceptance criteria (EARS; each one is a test in the plan)

Sampling
* AC1 THE verb SHALL sample at most `--sample N` candidate references (default 200, N >= 1).
* AC2 WHEN the same DB, `--sample` and `--seed` are given THE verb SHALL select the same references
  in the same order (deterministic; default seed 1).
* AC3 THE sample SHALL contain only candidate references (kinds and target kinds as defined above).
* AC4 WHERE `--dry-run` is given THE verb SHALL print the sampled rows (outcome `sampled`) and exit
  0 WITHOUT starting DelphiLSP.

Classification
* AC5 WHEN an LSP location names the expected file and a line inside the declaration range THE
  reference SHALL be `match`.
* AC6 WHEN an LSP location names the expected file and the line `impl_start_line` THE reference
  SHALL be `match`.
* AC7 WHEN every LSP location names another file or a line outside both ranges THE reference SHALL
  be `mismatch`.
* AC8 WHEN the LSP answer is `null` or `[]` on the first request THE verb SHALL retry that reference
  once after all other references were asked, and IF it is still empty THEN classify it `empty`.
* AC9 IF DelphiLSP answers with an error or does not answer within `--timeout-ms` (default 10000)
  THEN the reference SHALL be `error` and the run SHALL continue with the next reference.
* AC10 IF the source text at the ref position does not start with `name_text`, or a non-ASCII
  character precedes the column on that line, THEN the reference SHALL be `skipped` and DelphiLSP
  SHALL NOT be asked for it.
* AC11 THE verb SHALL accept `Location`, `Location[]` and `LocationLink[]` replies.

Report
* AC12 THE text report SHALL start with one summary line naming db, sample, seed, the five counts
  and the rate as a percentage with one decimal, followed by one row per non-`match` reference.
* AC13 WHERE `--json` is given THE verb SHALL write exactly one JSON document to stdout (shape
  below) and nothing else to stdout.
* AC14 THE rate SHALL be mismatch / (match + mismatch), and 0 when that denominator is 0.

Process and protocol
* AC15 THE verb SHALL start DelphiLSP from `--delphi-lsp <exe>` when given, else from the installed
  Studio (`ResolveDelphiLspPath`, `--delphi-lsp-bits` honoured).
* AC16 THE verb SHALL send `initialize` (initializationOptions = the `.delphilsp.json` `settings`
  object), `initialized`, then `workspace/didChangeConfiguration` with `{settings: <that object>}`,
  then wait `--warmup-ms` (default 5000) before the first definition request.
* AC17 THE verb SHALL send `textDocument/didOpen` (languageId `delphi`, the file's text) once per
  sampled file before the first definition request in that file.
* AC18 WHEN DelphiLSP sends a request to the client THE verb SHALL reply: `workspace/configuration`
  with an array holding the `settings` object once per requested item; any other method with
  result `null`.
* AC19 THE verb SHALL end the session with `shutdown` + `exit`, and IF the child is still alive 5 s
  later THEN terminate it; the child SHALL be in the drag-lint job object so it never outlives the
  verb.
* AC20 THE `.delphilsp.json` SHALL come from `--delphi-lsp-config <file>` when given, else from
  `<project dir>\<project base>.delphilsp.json` for `--project <x.dproj>`.

Errors and exit codes
* AC21 IF no DB resolves, the DB does not exist, no `.delphilsp.json` is found or it has no
  `settings` object, or DelphiLSP cannot be started or does not answer `initialize` within
  `--timeout-ms` THEN the verb SHALL write one `ERROR: verify-index: ...` line to stderr, nothing to
  stdout, and exit 2.
* AC22 THE verb SHALL exit 0 when the run finished with zero `mismatch`, and 1 when it finished
  with at least one `mismatch`.
* AC23 THE verb SHALL NOT write to the DB, to any source file, or to any log under `stats\`.

Surface
* AC24 THE verb SHALL be registered with status `internal` (absent from `--help`), listed in
  `run_docs_sync_guard.ps1`'s `$UndocumentedOnPurpose` with a reason, and have a wiki page.

## CLI surface (internal)

```
drag-lint verify-index (--db <db> | --project <x.dproj>) [--delphi-lsp-config <file>]
    [--sample N] [--seed N] [--delphi-lsp <exe>] [--delphi-lsp-bits 32|64]
    [--timeout-ms N] [--warmup-ms N] [--trace <file>] [--dry-run] [--json]
```
`--trace <file>` appends every frame sent and received, tagged `C>S` / `S>C` (same meaning as
`lsp --proxy --trace`). New flags: `--sample`, `--seed`, `--delphi-lsp-config`, `--warmup-ms`.
Reused: `--db`, `--project`, `--delphi-lsp`, `--delphi-lsp-bits`, `--timeout-ms`, `--trace`,
`--dry-run`, `--json`.

## Report shapes

Text (tab-separated rows):
```
verify-index: db=<path> sample=200 seed=1 match=180 mismatch=3 empty=12 error=0 skipped=5 rate=1.6%
mismatch<TAB><file>:<line>:<col><TAB><name><TAB><ref kind><TAB>dl=<qname> @ <path>:<decl line>[/<impl line>]<TAB>lsp=<path>:<line>[;<path>:<line>...]
empty   ...                                                              lsp=-
error   ...                                                              lsp=<message>
skipped ...                                                              lsp=<reason: moved|non-ascii|unreadable>
```
JSON:
```json
{ "verb": "verify-index", "db": "...", "delphiLsp": "...", "config": "...",
  "sample": 200, "seed": 1,
  "counts": { "match": 180, "mismatch": 3, "empty": 12, "error": 0, "skipped": 5 },
  "rate": 0.0164,
  "rows": [ { "outcome": "mismatch", "refId": 123, "file": "...", "line": 10, "col": 5,
              "name": "Foo", "kind": "call",
              "dl":  { "qname": "U.Foo", "path": "...", "line": 7, "endLine": 7, "implLine": 40 },
              "lsp": [ { "path": "...", "line": 12 } ], "detail": "" } ] }
```
`rows` holds every non-`match` reference (with `--dry-run`: every sampled reference, outcome
`sampled`, `lsp` empty). Rows are in sample order.

## Units (new)

* `src\lsp\DRagLint.LSP.VerifyClient.pas` -- a minimal synchronous LSP client: spawn the child
  with three pipes, Content-Length framing, request/response by id with a timeout, notification
  send, replies to server-to-client requests, trace, shutdown. No knowledge of the index.
* `src\cli\DRagLint.CLI.VerifyIndex.pas` -- the verb: options record, sampling SQL, source checks,
  location parsing, classification, rate, text and JSON rendering, `RunVerifyIndex`. The pure
  functions are on the unit's interface so a test program can call them without a process.

Hub: `DRagLint.CLI.pas` (flags + one dispatch line), `src\cli\drag-lint.dpr` and
`src\cli\drag-lint.dproj` (two unit entries each).

## Tests

* `tests\VerifyIndexTests.dpr` (pure, no process, no DB): location parsing, classification,
  rate, skip checks, sampling SQL text.
* `tests\autotest\run_verify_index_guard.ps1` (fake server): builds the existing
  `LspStubServer.dpr` (scripted mode, extended with position-keyed script lines), indexes a
  two-unit fixture, runs `--dry-run --json` to get the sample, scripts one planted mismatch, runs
  the verb against the stub and asserts counts, rate and the planted row; plus empty/error/
  LocationLink controls, exit codes, determinism and the no-config error.
* `tests\autotest\run_lsp_proxy_stub_modes_guard.ps1` stays green (the stub change is additive).

A live run against the real DelphiLSP on a DB copy is a smoke step in the plan, not a battery
test: the battery must not need RAD Studio's language server.

## Risks

* DelphiLSP's definition target convention (declaration vs implementation, forward class
  declarations) is unmeasured; AC5/AC6 accept both declaration range and implementation line.
  Forward declarations will show as `mismatch` until 1.53.1 decides; the live smoke reports them.
* DelphiLSP may answer `null` while it still loads the project; the warm-up wait plus the one
  retry (AC8) bound this, and `empty` is kept out of the rate so it cannot fake accuracy.
* LSP columns are UTF-16 code units; the index column unit on non-ASCII lines is the subject of
  lane COLS-TAILS. AC10 skips such lines instead of guessing.
* Paths: DelphiLSP may return a differently cased or short path; comparison expands and compares
  case-insensitively, and a mismatch row prints both paths so a path-form false positive is
  visible.
