# repo gen-param-array -- design (1.52, lane GENPA)

Status: DESIGN, not implemented. Owner ruling R2: design in 1.52. Closes the design half of TTPA
handover H1 ("wire `repo gen-param-array`, gate = compile the candidate"). TT migration step M9.

Inputs read: `C:\TEMP\claude\lanes\v152\TTPA\REPORT.md`, `...\TTE\REPORT.md`,
`...\TTGEN\HANDOVER-cli-repo.patch`, `docs\wiki\field-repository.md`,
`src\sql\DRagLint.FieldRepo.ParamArray.pas` (TTPA engine, 45 unit tests green),
`src\refactor\DRagLint.Refactor.CompileGate.pas` (ApplyGated), and the real corpus
`C:\Projects\Loader2019` (see 5).

## 1. What exists, and the four facts that shape the design

The engine layer is done (TTPA): `PADiscoverFromDfm` -> `PABuildBlock` -> `PABuildPlan` (diff) ->
`PAApplyPlan(source, block, gate)` and `PARunProject(units, opts, gate)`, where
`TPAGate = reference to function(const pUnitText: string): Boolean` is called once per unit.
`repo gen-param-array` answers "not available in this build" (TTE, `DRagLint.CLI.Repo.pas`).

F1. **The block is a fragment, not code.** It is `const` sections + loop statements and, whenever a
column does not match, marker lines (`##### TYPE MISMATCH #####`, `// MISSING PARAMS`,
`#### MISSING FIELDS ####`) that dcc rejects. The IDE assistant pasted it at the cursor for a human
to finish; it was never meant to compile as emitted.

F2. **PAApplyPlan inserts it as a braced comment before the final `end.`.** A compile gate on that
candidate proves almost nothing: a comment compiles unless the block contains `}`. The gate is
still required (repo rule: every write passes the compile gate) but its value in 1.52 is "the unit
still builds", not "the loop is right".

F3. **TPAGate is per unit; ApplyGated is per project.** ApplyGated = baseline build + all-or-nothing
write under `.BCK<n>` + after build + rollback. Calling it once per unit costs 2 builds per unit:
Loader2019 has ~95 eligible units -> ~190 builds, over an hour. One gated write per RUN is needed.

F4. **The repository is not an input.** Discovery reads the DFM (fields + params with types); the
`.dlrepo` is not consulted. The verb therefore must not require `--repo` (same as `gen-memtable`,
which dispatches before `ResolveRepoPath`). `--project` keeps its repo meaning: the project file.

## 2. CLI shape

```
drag-lint repo gen-param-array --in <unit.pas> [--dfm <file>] [--query <Name>] [--table <Name>]
                               [--step-size <n>] [--progress-form <Form>]
                               [--plan | --apply --project <X.dproj>] [--json]
                               [--no-backup] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>]
drag-lint repo gen-param-array --project <X.dproj> --all
                               [same emission / mode / gate flags; --only <unit,...>]
```

* **Single** (`--in`): the "Single" assistant. DFM = `--dfm`, else `<unit>.dfm` beside the unit.
* **Project** (`--project ... --all`): the "Project" assistant over the `.dproj` members
  (`ReadDCCReferences`, `DRagLint.Lint.ProjectChecks.Parse`) filtered by `PAProjectEligible`
  (name starts with `u`, exclusion list). `--only` narrows it.
* **Mode** (one of): none = print the block(s) to stdout (what the IDE assistant put on the
  clipboard); `--plan` = print the unified diff per unit, write nothing; `--apply` = write through the
  compile gate (needs `--project`, like `rename` / `unwith`). `--plan --apply` is exit 2.
* **Emission**: `--step-size` (default 20000), `--progress-form` (default '' = no loader-form lines;
  Loader2019 callers pass `frmLoader2019_Main`). `--query` / `--table` pick the components by name
  instead of "the LAST table / LAST parameterised query" (needed: `uFOLDERS.dfm` declares
  `qryFOLDERSZZ` while the code's loop uses `qryFOLDERS`; the heuristic would silently pick the
  wrong one in a multi-query DFM). A named component that is absent = exit 1, never a fallback.
* **--json**: one object `{mode, units:[{unit, status, query, table, matched, type_mismatch,
  missing_params, missing_fields, plan?, block?, error?}], gate?:{applied, refusal, detail,
  rolled_back}}`. Text mode prints one `<unit>: <status> (<n> matched, <m> mismatch, ...)` line per
  unit plus the `compile gate: ...` lines of `GateMessageReport` on stderr.
* **Status words** (TPAStatus + CLI): `applied`, `planned`, `refused-by-gate`, `no-insert-point`,
  `no-block` (no table / no parameterised query), `excluded`, `binary-dfm`, `missing-dfm`.
  A binary or missing DFM is REPORTED per unit, never skipped silently (same rule as `rename`).
* **Exit**: 0 = every processed unit planned / applied; 1 = a unit refused, no-block in single mode,
  gate rolled back; 2 = bad flags, write failure, baseline does not build.
* Extra flags are read with `CommandLineValue` / `CommandLineFlag` (the TTE / TTGEN pattern;
  `DRagLint.CLI.pas` stays FRAME's). They must still be on the verb's `--help` line and in the
  docs-sync guard's flag set.

## 3. Compile gate

Adapter in the CLI, engine unit unchanged except for 6.1:

1. Run `PARunProject` (or `PAApplyPlan` for one unit) with a **collecting gate**: it rejects a
   candidate whose block contains `}` (would end the comment early -> refused-by-gate, no build) and
   otherwise records `(unit path, candidate bytes)` and returns True.
2. One `ApplyGated` request for all collected files (`Verb = 'repo gen-param-array'`,
   `Header` = unit count, `Project`, `Platform`, `RsVars`, `NoBackup`, `LogDir` = fresh scratch).
   Baseline build first: a project that does not build before the edit refuses, nothing written.
3. After build fails -> ApplyGated has already rolled back. Take the files the dcc error lines name
   (`ParseDccLine`), mark those units `refused-by-gate`, and retry ONCE without them. A second
   failure refuses the run (exit 1). No bisection: with comment insertion a failure means a broken
   block escape, which the `}` pre-check already catches; the retry is a safety net, not a search.
4. Map the outcome back onto the per-unit statuses; `OpenGateStandDown` / `CloseGateStandDown` around
   it so `drag-lint shutdown` and the IDE Cancel roll back (verb must be added to
   `ControlChannelEnabledFor`).

Cost: 2 builds per run (4 with the retry) instead of 2 per unit.

## 4. Cut line

**1.52 (this release, implementation lane GENPA-IMPL):**
* the CLI of section 2 with comment insertion only (the TTPA behaviour);
* the collecting gate + one ApplyGated (section 3);
* `--query` / `--table` (engine 6.1), status words, `--json`;
* fixture-project runner + the Loader2019 golden (section 5) as a REPORT, not a battery gate;
* `--help`, README, AI-USAGE, `features\entries\field-repository.json` (gen-param-array line,
  reserved list shrinks), `docs\wiki\field-repository.md`;
* TTIDE's "Param Array assistant" menu item calls `--in <current unit> --plan` and shows the diff.

**1.52.1 (out of 1.52):**
* **live mode** `--into <Class.Routine>`: insert the loop as real code where a `// dl:param-array`
  marker line stands, the `const` sections hoisted into the routine's declaration part; refused
  when the block has any marker line. Here the compile gate becomes meaningful.
* the IDE-only query preparation (UpdateSQL insert text into the query, rename update object /
  schema adapter; TTPA OWNER-Q, default no);
* repository-driven types (DL_FIELDS_INFO) instead of DFM types;
* binary DFM reading.

## 5. Golden check

There is no captured output of the real IDE assistant (TTPA FOUND: its golden is a re-derivation
from the format templates). The real corpus is **Loader2019** (the Micronite / ORM3 loader that used
the assistant): ~95 live units (`C:\Projects\Loader2019\u*.pas`) still carry its output
(`Params.ArraySize:= STEPSIZE`, `parXXX` constants, `if (I >= STEPSIZE - 2)`), hand-finished
afterwards (e.g. `Set1ByteArrayDML(...)` replacing `AsBytes[I] := byte(ord(...))` in `uFOLDERS`).
Text equality is therefore the wrong measure. The check compares **assignment triples**:

* `tests\autotest\run_fieldrepo_paramarray_golden.ps1`, on a COPY of Loader2019 under
  `C:\TEMP\claude\lanes\v152\<LANE>\corpus\` (never the real tree):
  1. `repo gen-param-array --project <copy>\Loader2019.dproj --all --json --progress-form frmLoader2019_Main`;
  2. from each generated block and from the unit's existing loop, extract the set of
     `(param constant, param accessor, source field)` triples (regex over
     `Params[parX].AsY[I] := ... tblZ.AsW`), and the `par*` constant list;
  3. per unit: `same` (sets equal), `hand-edited` (the unit's set differs only in lines a human
     rewrote: the generated triple's param is present with another RHS), `diverged` (a param or
     field in one set and not the other), `not-generated` (status <> planned);
  4. print counts + a per-unit table; write `golden-report.txt` beside the copy.
* 1.52 acceptance: every `diverged` unit is explained in the report (expected causes: LAST-query
  heuristic, DFM fields edited after generation). A battery gate (e.g. `same + hand-edited >= 90 %`)
  is set only after the first measurement, by the owner (Q3).
* `run_v152_GENPA_cli.ps1` (battery, RED first): a 2-unit fixture project under
  `tests\fieldrepo\paramarray\proj\` (one eligible unit with a text DFM, one excluded): print mode =
  TTPA's golden block; `--plan` writes nothing (hash check); `--apply` writes the commented block,
  the project builds, `.BCK1` exists; `DRAGLINT_GATE_TEST_BREAK=1` -> rolled back, bytes identical
  (positive control); `--query` naming an absent component -> exit 1; a binary DFM -> `binary-dfm`
  line; `--plan --apply` -> exit 2.

## 6. Engine and file changes

6.1 `DRagLint.FieldRepo.ParamArray.pas`: `PADiscoverNamed(pDfm, pQueryName, pTableName, out pSrc,
    pDst): Boolean` (exact-name pick); `PABlockHasMarkers(pBlock): Boolean` (used by live mode in
    1.52.1, by `--json` counts now). Tests appended to `ParamArrayTests.dpr`.
6.2 New `src\cli\DRagLint.CLI.RepoParamArray.pas` (adapter + output) so the lane is file-disjoint
    from `DRagLint.CLI.Repo.pas`, which gets a 2-line dispatch (before `ResolveRepoPath`) and loses
    `gen-param-array` from the reserved list. Unit added to `drag-lint.dpr` / `.dproj`.
6.3 `ControlChannelEnabledFor`: accept `repo gen-param-array`.
6.4 Docs / registry as in 4; `DRAGLINT_EXTRACTOR_VERSION` unchanged (no extraction change).

Rough size: engine +80 lines, CLI adapter ~350 lines, tests ~250 lines PowerShell + fixture
project, docs ~40 lines. One sonnet lane, about 5 h including two builds and the golden run.

## 7. Owner questions (defaults apply when unanswered)

Q1. Comment insertion only in 1.52, live `--into` mode in 1.52.1? **Default: yes.**
Q2. Golden corpus = Loader2019 (the project that actually used the assistant), compared by
    assignment triples, not text; ORM3 COMMON stays TTGEN's corpus. **Default: yes.**
Q3. The golden is a report in 1.52, a battery threshold only after the first measurement.
    **Default: yes; threshold proposed from the measurement.**
Q4. `--progress-form` defaults to '' (no loader-form lines); Loader2019 runs pass it explicitly.
    **Default: '' (generic projects first).**
Q5. One gated write per run with one retry excluding the units dcc names, no per-unit builds.
    **Default: yes.**
