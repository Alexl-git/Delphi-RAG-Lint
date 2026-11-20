# Plan: verify-index (lane LSP1-VERB, 1.53.0, status internal)

Spec: `docs\superpowers\specs\2026-11-20-verify-index-design.md` (read it first; AC numbers below
refer to it). Written for a sonnet implementer: every file, signature and test is named. Lane rules:
`C:\TEMP\claude\lanes\v1522\COMMON-BRIEF.md` + `C:\TEMP\claude\lanes\v1523\PLAN.md` section 1
(worktree, private engine copy, hub commit <= 30 lines in `DRagLint.CLI.pas`, no version bump, no
`featuregen build --all`, failing test first, ASCII + CRLF, DocInsight on public surface).

## File fence

| file | change |
|---|---|
| `src\lsp\DRagLint.LSP.VerifyClient.pas` | NEW |
| `src\cli\DRagLint.CLI.VerifyIndex.pas` | NEW |
| `tests\VerifyIndexTests.dpr` | NEW (pure test program) |
| `tests\autotest\run_verify_index_tests.ps1` | NEW (builds + runs VerifyIndexTests.dpr) |
| `tests\autotest\run_verify_index_guard.ps1` | NEW (fake-server guard) |
| `tests\autotest\fixtures\verifyindex\VerifyMain.pas`, `VerifyLib.pas` | NEW fixture units |
| `tests\autotest\fixtures\lspproxy\LspStubServer.dpr` | additive: position-keyed script lines |
| `tests\autotest\run_docs_sync_guard.ps1` | one `$UndocumentedOnPurpose` line |
| `features\entries\verify-index.json` | NEW registry entry (status internal) |
| `docs\wiki\verify-index.md` | NEW wiki page |
| HUB COMMIT: `src\cli\DRagLint.CLI.pas`, `src\cli\drag-lint.dpr`, `src\cli\drag-lint.dproj` | flags, dispatch, unit entries |

Note for the controller: `drag-lint.dpr` / `.dproj` are outside the PLAN.md row's list but every
new engine unit needs them; they belong in the hub commit.

## Task 1 -- stub server: position-keyed script lines (test infrastructure first)

`LspStubServer.dpr`, `AnswerFrame`: before the existing loop over `AScript`, build
`PosKey := Method + '@' + <uri basename> + ':' + <line> + ':' + <character>` from
`params.textDocument.uri` (text after the last `/`, URL-decoded with `TNetEncoding.URL.Decode`,
add `System.NetEncoding` to uses) and `params.position.line` / `.character`, only when all three
exist. Look up an entry whose `Method = PosKey` first; if none, fall back to the existing
`Entry.Method = Method` match. Update the SCRIPTED MODE comment block: one line documenting the
`<method>@<file>:<line0>:<char0>` key form.
Check: `pwsh -File tests\autotest\run_lsp_proxy_stub_modes_guard.ps1 -Exe <lane exe>` still green.

## Task 2 -- `DRagLint.LSP.VerifyClient` (process + framing)

Interface (DocInsight `///` on each; wording below is the contract):

```pascal
type
  /// <summary>Raised when the child cannot be started or the stream breaks.</summary>
  ELspClientError = class(Exception);

  /// <summary>Minimal synchronous LSP client over a child process's stdio, for batch verbs.
  /// Not thread-safe; one instance per run.</summary>
  /// <remarks>Requests are answered in order; while waiting for a response the client consumes
  /// notifications (dropped, traced) and answers server-to-client requests via OnServerRequest
  /// (default: result null). The child is assigned to the drag-lint job object.</remarks>
  TLspVerifyClient = class
  public
    /// <param name="pExe">Full path of the server executable.</param>
    /// <param name="pTraceFile">'' = no trace; else every frame appended with C>S / S>C tags.</param>
    constructor Create(const pExe, pTraceFile: string);
    destructor Destroy; override;   { Shutdown when still running, then close handles }
    /// <summary>Spawns the child with redirected stdin/stdout; stderr is inherited.</summary>
    /// <exception cref="ELspClientError">CreateProcess failed.</exception>
    procedure Start;
    /// <summary>Sends a request and waits for its response.</summary>
    /// <param name="pParams">Owned by the call (freed after sending).</param>
    /// <param name="pTimeoutMs">Wall-clock wait for the response.</param>
    /// <param name="pResult">On success the response's `result` (cloned; caller frees; may be TJSONNull).</param>
    /// <param name="pError">On failure: the error message, or 'timeout'.</param>
    /// <returns>True when a response with a `result` arrived in time.</returns>
    function Request(const pMethod: string; pParams: TJSONValue; pTimeoutMs: Integer;
      out pResult: TJSONValue; out pError: string): Boolean;
    /// <summary>Sends a notification. pParams is owned by the call.</summary>
    procedure Notify(const pMethod: string; pParams: TJSONValue);
    /// <summary>Reads and handles incoming frames for pMs milliseconds (warm-up).</summary>
    procedure Pump(pMs: Integer);
    /// <summary>shutdown (2 s) + exit, close stdin, wait 5 s, TerminateProcess if alive (AC19).</summary>
    procedure Shutdown;
    /// <summary>Answer for a server-to-client request: (method, params) -> result JSON text.
    /// nil = reply "null".</summary>
    property OnServerRequest: TFunc<string, TJSONValue, string> read FOnServerRequest write FOnServerRequest;
  end;
```

Implementation notes (exact):
* Pipes: `CreatePipe` x2 with inheritable handles, `SetHandleInformation` to make the parent ends
  non-inheritable; `STARTF_USESTDHANDLES`, `hStdError := GetStdHandle(STD_ERROR_HANDLE)`;
  `CREATE_NO_WINDOW`. After `CreateProcess`: `AssignToDragLintJob(PI.hProcess)`
  (`DRagLint.Core.JobObject`). Model: `RunLspProxy` in `src\lsp\DRagLint.LSP.Proxy.pas` lines ~756-941.
* Write: `Content-Length: <utf8 byte count>\r\n\r\n` + UTF-8 body; ids are integers from 1.
* Read with timeout: loop `PeekNamedPipe(FOutRd, nil, 0, nil, @Avail, nil)`; when Avail > 0
  `ReadFile` up to Avail into an accumulator; else `Sleep(5)` until deadline (`GetTickCount64`).
  `PeekNamedPipe` failing = child gone -> `pError := 'server exited'`, return False.
* Frame parse: header end `\r\n\r\n`; `Content-Length` case-insensitive among headers; body is
  UTF-8. Parse with `TJSONObject.ParseJSONValue`.
* Incoming message dispatch: has `id` and (`result` or `error`) and no `method` -> response;
  has `method` and `id` -> server request: reply `{"jsonrpc":"2.0","id":<id>,"result":<OnServerRequest or null>}`;
  has `method` and no `id` -> notification, ignored. A response whose id is not the awaited one
  is dropped.
* Trace: append `C>S ` / `S>C ` + body + CRLF to pTraceFile, wrapped in try/except (never fails the run).
* Do NOT reuse the private framing helpers of `DRagLint.LSP.Proxy` (implementation-only); only
  `ResolveDelphiLspPath` from its interface is used (by Task 3).

## Task 3 -- `DRagLint.CLI.VerifyIndex` (the verb)

Interface:

```pascal
const
  VERIFY_DEFAULT_SAMPLE    = 200;
  VERIFY_DEFAULT_SEED      = 1;
  VERIFY_DEFAULT_TIMEOUT   = 10000;
  VERIFY_DEFAULT_WARMUP    = 5000;

type
  /// <summary>Outcome of one sampled reference (spec "Outcomes").</summary>
  TVerifyOutcome = (voSampled, voMatch, voMismatch, voEmpty, voError, voSkipped);

  /// <summary>One location of an LSP definition answer; Line is 1-based.</summary>
  TVerifyLocation = record Path: string; Line: Integer; end;

  /// <summary>One sampled reference and drag-lint's expected target.</summary>
  TVerifyRow = record
    RefId: Int64; Kind, Name, RefPath: string; Line, Col: Integer;
    QName, SymPath: string; DeclLine, DeclEnd, ImplLine: Integer;   { ImplLine 0 = none }
    Outcome: TVerifyOutcome; Lsp: TArray<TVerifyLocation>; Detail: string;
  end;

  TVerifyCounts = record Match, Mismatch, Empty, Error, Skipped: Integer; end;

  TVerifyOptions = record
    DbPath, ProjectPath, ConfigPath, DelphiLspExe, TraceFile: string;
    DelphiLspBits, Sample, Seed, TimeoutMs, WarmupMs: Integer;
    DryRun, Json: Boolean;
  end;

/// AC3 + AC1 + AC2: the sampling SELECT (spec "Candidate reference").
function VerifySampleSql(pSample, pSeed: Integer): string;
/// AC11: Location | Location[] | LocationLink[] | null -> locations (Line 1-based). nil/[] = empty.
function ParseDefinitionLocations(const pResult: TJSONValue): TArray<TVerifyLocation>;
/// AC5-AC7: match / mismatch for a non-empty location list (paths compared via
/// ExpandFileName + SameText).
function ClassifyLocations(const pRow: TVerifyRow; const pLocs: TArray<TVerifyLocation>): TVerifyOutcome;
/// AC10: '' when the line text is usable for the row, else the skip reason
/// ('moved' | 'non-ascii'). pLineText is the 1-based line pRow.Line of the file.
function SkipReason(const pRow: TVerifyRow; const pLineText: string): string;
/// AC14.
function MismatchRate(const pCounts: TVerifyCounts): Double;
/// AC12 first line.
function SummaryLine(const pDb: string; pSample, pSeed: Integer; const pCounts: TVerifyCounts): string;
/// AC12 row line.
function RowLine(const pRow: TVerifyRow): string;
/// AC13 document (caller frees).
function ReportJson(const pOpts: TVerifyOptions; const pExe: string; const pCounts: TVerifyCounts;
  const pRows: TArray<TVerifyRow>): TJSONObject;
/// Runs the verb (AC15-AC23). Returns 0 / 1 / 2 (AC21, AC22).
function RunVerifyIndex(const pOpts: TVerifyOptions): Integer;
```

Sampling SQL (exact; `%d` = sample, seed):
```sql
SELECT r.id AS ref_id, r.kind AS kind, r.name_text AS name, f.path AS ref_path,
       r.start_line AS line, r.start_col AS col,
       s.qualified_name AS qname, sf.path AS sym_path,
       s.start_line AS decl_line, s.end_line AS decl_end, COALESCE(s.impl_start_line, 0) AS impl_line
  FROM refs r
  JOIN files f ON f.id = r.file_id
  LEFT JOIN call_edges ce ON ce.ref_id = r.id AND ce.confidence = 'certain'
  JOIN symbols s ON s.id = COALESCE(ce.target_symbol_id, r.symbol_id)
  JOIN files sf ON sf.id = s.file_id
 WHERE r.inc_variant = 0
   AND r.kind IN ('call','read','write','write-through','type_use','member-access','property-spec','record-field')
   AND s.kind NOT IN ('local_var','param')
 ORDER BY ((r.id * 2654435761) + (%d * 40503)) % 4294967296, r.id
 LIMIT %d
```
Run it with `TChartsIndex.Create(DbPath)` + `.Query(sql)` (`src\charts\DRagLint.Charts.Index.pas`,
read-only store; rows read with `.S('name')` / `.I('line')`).

`RunVerifyIndex` flow:
1. DB: `pOpts.DbPath` (the hub resolves it like `check-init` does). Missing / not a file -> AC21.
2. Sample rows (AC1-AC3). `--dry-run`: every row outcome `voSampled`, render, exit 0 (AC4) --
   before step 3, so no config is needed for a dry run.
3. Config: `ConfigPath`, else `ChangeFileExt(ProjectPath, '.delphilsp.json')`; read
   (`TFile.ReadAllText`, UTF-8, strip BOM), parse, take `settings` (TJSONObject) -> else AC21.
4. Exe: `ResolveDelphiLspPath(pOpts.DelphiLspExe, Bits)` (`DRagLint.LSP.Proxy`); '' or not
   `FileExists` -> AC21.
5. Client: `Start`; `OnServerRequest` answers `workspace/configuration` with an array of
   `settings` clones, one per `params.items` element (AC18); `initialize` with
   `{"processId":<pid>,"rootUri":<PathToFileUri(project or db dir)>,"capabilities":{},"initializationOptions":<settings>}`
   (no response in `TimeoutMs` -> AC21); `initialized` `{}`; `workspace/didChangeConfiguration`
   `{"settings":<settings>}`; `Pump(WarmupMs)` (AC16). `PathToFileUri` is in
   `DRagLint.LSP.Completion`; `TLSPServer.FileFromUri` (class function, `DRagLint.LSP.Server`)
   converts reply URIs.
6. Per row in sample order: read the file's lines once (cache by path, `TFile.ReadAllLines`;
   unreadable -> `skipped`, detail `unreadable`); `SkipReason` (AC10); first row of a file ->
   `textDocument/didOpen` (AC17, version 1); `textDocument/definition` at (Line-1, Col-1) with
   `TimeoutMs` (AC9); error/timeout -> `voError` with the message; empty -> remember for retry;
   else `ClassifyLocations`.
7. Retry the remembered empties once, in order (AC8); still empty -> `voEmpty`.
8. `Shutdown` (AC19, in a `finally`). Render text (`SummaryLine` + `RowLine` for non-match) or
   JSON (`ReportJson`, one `Writeln`). Exit 1 when Mismatch > 0 else 0 (AC22).
All errors before the report: `Writeln(ErrOutput, 'ERROR: verify-index: ', msg)`, exit 2, nothing
on stdout (AC21). Nothing is written except stdout, stderr and the optional trace file (AC23).

Rate formatting: `FormatFloat('0.0', Rate * 100, TFormatSettings.Invariant) + '%'`; JSON `rate`
as a number with 4 decimals.

## Task 4 -- pure tests: `tests\VerifyIndexTests.dpr` + `run_verify_index_tests.ps1`

Recipe: copy `tests\autotest\run_forward_stub_pairing.ps1` (dcc64 with the engine's src folders on
`-U`, exit 2 on build failure, exit 1 on any `[FAIL]`). Write the tests FIRST against stub bodies
(`Result:= Default(...)`), watch them FAIL, then implement Task 3. Tests (one `Check` each):

| # | test | AC |
|---|---|---|
| T1 | `ParseDefinitionLocations(TJSONNull)` -> 0 locations | 11 |
| T2 | single `Location` object -> 1 location, Line = range.start.line + 1, path from file URI | 11 |
| T3 | `Location[]` of 2 -> 2 locations in order | 11 |
| T4 | `LocationLink[]` -> uses targetUri + targetSelectionRange; without targetSelectionRange uses targetRange | 11 |
| T5 | empty array -> 0 locations | 8 |
| T6 | Classify: same file (different case + `..\` segment) and line in decl range -> match | 5 |
| T7 | Classify: same file, line = ImplLine -> match | 6 |
| T8 | Classify: same file, line outside both -> mismatch | 7 |
| T9 | Classify: other file, same line -> mismatch | 7 |
| T10 | Classify: two locations, second matches -> match | 5 |
| T11 | SkipReason: name at column -> '' ; name moved -> 'moved'; non-ASCII char before col -> 'non-ascii'; non-ASCII AFTER the name -> '' | 10 |
| T12 | MismatchRate: 3 / (180+3); 0 when match+mismatch = 0 | 14 |
| T13 | SummaryLine exact text for a fixed counts record (`rate=1.6%`) | 12 |
| T14 | RowLine for a mismatch row: tab-separated fields as in the spec | 12 |
| T15 | ReportJson: keys verb, counts.mismatch, rate, rows[0].outcome = 'mismatch', rows[0].dl.line | 13 |
| T16 | VerifySampleSql contains `LIMIT 200`, the seed term, and `NOT IN ('local_var','param')` | 1,2,3 |

## Task 5 -- fake-server guard: `run_verify_index_guard.ps1`

Header + structure: copy `run_lsp_proxy_merge_definition_guard.ps1` (pwsh 7, `-Exe` param,
`dl:serial` comment, `Check` helper, stub built with dcc64 into the work dir, fixture indexed with
`& $Exe index $srcDir --db $db`). Fixture units (ASCII, CRLF):
* `VerifyLib.pas`: `procedure LibProc;`, `const LibConst = 3;`, `type TLibThing = class procedure Go; end;` + implementations.
* `VerifyMain.pas`: `uses VerifyLib;` and one routine that calls `LibProc`, reads `LibConst`,
  declares `var T: TLibThing;` and calls `T.Go` -- at least 3 candidate refs.
* A fake `.delphilsp.json` in the work dir: `{"settings":{"project":"file:///x"}}`.

Steps and assertions:
1. `verify-index --db $db --dry-run --json --sample 50` -> exit 0; `rows.Count -ge 3`; every row
   outcome `sampled`; no stub process started (no stub log file created) (AC4). Parse with
   `ConvertFrom-Json` and read named properties (NOT `sql --json`; see memory lesson on positional rows).
2. Determinism: the same dry run twice -> identical `refId` sequence; `--seed 2` -> a different
   order OR (when fewer rows than 2) note it (AC2).
3. Script for run A (one planted mismatch): `initialize\t0\t{"capabilities":{"definitionProvider":true}}`,
   `shutdown\t0\tnull`, and for each dry-run row
   `textDocument/definition@<basename(file)>:<line-1>:<col-1>\t0\t<Location at dl.path, dl.line-1>`,
   except row 0, whose location is `dl.line + 50` (outside the range) in the same file.
   Run `verify-index --db $db --delphi-lsp $stub --delphi-lsp-config $cfg --warmup-ms 0 --json --sample 50`
   with `DRAGLINT_STUB_SCRIPT` / `DRAGLINT_STUB_LOG` set.
   Assert: exit 1; `counts.mismatch -eq 1`; `counts.match -eq rows-1`; `rate` = 1/(n) within 1e-4;
   `rows.Count -eq 1` and `rows[0].refId` = dry-run row 0's refId and `rows[0].outcome -eq 'mismatch'`.
   Positive control: the stub log has `initialize`, `textDocument/didOpen`... (logged as
   method + `-`), `textDocument/definition` n times, `shutdown`.
4. Run B (controls): row 0 answered `null` (-> empty; the stub log has `textDocument/definition`
   n+1 times: the retry, AC8), row 1 answered as a `LocationLink[]` at the right place (-> match,
   AC11), row 2 not scripted and NO plain `textDocument/definition` fallback line (stub replies
   -32601 -> error, AC9), rows 3+ answered correctly. Assert counts (empty 1, error 1, mismatch 0)
   and rate 0 (AC14); exit 0 (no mismatch).
5. Text mode of run A (no `--json`): first line matches
   `^verify-index: db=.* sample=50 seed=1 match=\d+ mismatch=1 empty=0 error=0 skipped=0 rate=`
   and exactly one `mismatch\t` row (AC12).
6. Errors (AC21): missing config file -> exit 2, stdout empty, stderr has `ERROR: verify-index:`;
   `--delphi-lsp C:\nonexistent.exe` -> exit 2; no `--db` and no `--project` from a neutral CWD -> exit 2.
7. Read-only (AC23): DB file size + mtime + SHA256 unchanged across all runs.
Cleanup: kill only the PIDs this guard started; delete the work dir.

RED proof for the report: run the guard on the INT engine (verb unknown -> step 1 fails), then GREEN
on the lane build.

## Task 6 -- hub commit (`DRagLint.CLI.pas`, `drag-lint.dpr`, `drag-lint.dproj`; <= 30 lines in CLI.pas)

* Args record: `VerifySample, VerifySeed, VerifyWarmupMs: Integer; VerifyLspConfig: string;`
  (defaults set where the record is zeroed: sample 0 = default, seed 0 = default 1 -- or set
  the constants in `RunVerifyIndex` when 0; prefer the latter, so ParseArgs stays 4 lines).
* ParseArgs: `--sample N`, `--seed N`, `--warmup-ms N` (`StrToIntDef`, a non-number -> raise
  `Exception.CreateFmt('--sample must be a whole number, got: %s', ...)` like `--delphi-lsp-bits`),
  `--delphi-lsp-config FILE`. Reused flags already parse: `--db`, `--project`, `--delphi-lsp`,
  `--delphi-lsp-bits`, `--timeout-ms`, `--trace`, `--dry-run`, `--json`.
* Dispatch (next to `check-init`):
  `else if Args.Command = 'verify-index' then Result:= DoVerifyIndex(Args)` with a small
  `DoVerifyIndex` filling `TVerifyOptions` (DB resolved the same way `DoUnwith` /
  `NoDbResolved(AArgs.DbPath, 'verify-index')` does) and calling `RunVerifyIndex`.
* `uses`: `DRagLint.CLI.VerifyIndex { verify-index verb (1.53.0 LSP1-VERB) }`.
* `drag-lint.dpr`: `DRagLint.LSP.VerifyClient in '..\lsp\DRagLint.LSP.VerifyClient.pas',` and
  `DRagLint.CLI.VerifyIndex in 'DRagLint.CLI.VerifyIndex.pas',`; `drag-lint.dproj`: the two
  `<DCCReference Include=...>` lines (same relative paths).
* Check a flag-name clash in `features\flag-aliases.json` for `--sample` / `--seed` before committing.

## Task 7 -- docs (status internal)

* `features\entries\verify-index.json` -- shape of `features\entries\convert-reemit.json`:
  id `verify-index`, title `verify-index`, group `indexing`, owner `ENGINE`, status `internal`,
  since `1.53.0-alpha`, audience `agent`, wikiPage `verify-index`, summary "Measures drag-lint's
  resolution against DelphiLSP: samples resolved references, asks DelphiLSP for each definition,
  reports the mismatch rate and the mismatching rows", one `cli` surface with verb `verify-index`,
  the usage line from the spec and every flag of the spec's CLI block, one question
  ("How often does the index resolve a name differently from the compiler?" ->
  `drag-lint verify-index --project <x.dproj> --db <copy.sqlite>`), notes
  `internal: 1.53.0 slice of LSP1-VERIFY; read-only; needs a .delphilsp.json`. Then
  `featuregen normalise` and `featuregen verify --id verify-index --by ENGINE` (build featuregen
  with `build\_build_featuregen_local.bat` if missing). NO `featuregen build --all`.
* `tests\autotest\run_docs_sync_guard.ps1` `$UndocumentedOnPurpose`:
  `'verify-index' = '1.53.0 LSP1-VERIFY: internal measurement verb (index vs DelphiLSP); registry status internal, not advertised until 1.53.1.'`
* `docs\wiki\verify-index.md`: what it measures, outcomes table, rate definition, the command,
  the `.delphilsp.json` requirement (RAD Studio writes it when the project is opened), the risks
  section of the spec, "1.53.1 adds stratified sampling and gap logging".
* REPORT CHANGELOG line: `verify-index (internal): mismatch rate of drag-lint's resolution vs
  DelphiLSP over a deterministic sample of resolved references.`

## Task 8 -- verification

1. `build\build_draglint_win64.bat -NoStage` in the worktree -> `BUILD_EXITCODE=0`, no `[dcc] Error`.
2. `pwsh -File tests\autotest\run_verify_index_tests.ps1` -> all PASS (RED run recorded first).
3. `pwsh -File tests\autotest\run_verify_index_guard.ps1 -Exe <lane exe>` -> all PASS (RED on INT engine first).
4. `run_lsp_proxy_stub_modes_guard.ps1 -Exe <lane exe>`, `run_docs_sync_guard.ps1 -Exe <lane exe>`,
   `run_feature_registry_guard.ps1`, `run_encoding_guard.ps1` -> green.
5. Lint (private engine, lane DB copy reindexed): `lint <unit> --enable magic-literal,multiple-statements-per-line,commented-out-code`
   on both new units = 0 findings on new lines or `dl:ok` with reason; `lint-all` delta 0 for the new units.
6. Live smoke (non-blocking, owner-machine only, never in the battery): copy
   `src\cli\_D-RAG\drag-lint.sqlite` to the lane folder, run
   `verify-index --db <copy> --project src\cli\drag-lint.dproj --json --sample 200` with the
   installed DelphiLSP; put counts, rate, run time and the first 10 non-match rows in REPORT.md.
   If every answer is `empty`, report it (warm-up / config problem) -- do not tune in this lane.

## Cut-off fallback

If time runs out: Tasks 1-4 + 6 green = merge-ready without the live smoke; Task 5 is required
for MERGE-READY (it is the PLAN.md acceptance "fake-server test with one planted mismatch reports
rate + row").
