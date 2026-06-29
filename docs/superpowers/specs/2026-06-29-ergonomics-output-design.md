# Ergonomics / output layer (#12) -- design

> Status: approved 2026-06-29 (brainstorming). Closes the `#12 Ergonomics / output -- gap`
> bucket in `docs/lint/MISSING-FEATURES.md` for the **v0.66.0-alpha** bundle (after M1 + M2).
> **Autofix / quick-fixes are explicitly OUT of scope** (a milestone of their own -- mutating
> source for ~14 fix types; deferred to a later alpha). This spec decomposes into a `writing-plans`
> implementation plan; the user wants: design -> plan -> handoff/clear -> (fresh session) code ->
> publish 0.66.

---

## 1. Goal

Make drag-lint's findings **consumable in CI and configurable per project** without changing any
analysis. Four bounded features, all post-processing/output:

1. **SARIF output** (`--format sarif`) -- GitHub code-scanning / CI ingestion.
2. **CI exit-code policy** (`--fail-on <level>`) -- gate builds by severity.
3. **Baseline / suppression file** (`--baseline` / `--write-baseline`) -- report only NEW findings on
   legacy codebases.
4. **Config + severity overrides + rule on/off profiles** (`drag-lint-lint.json`) -- per-project
   tuning.

## 2. Architecture: a post-processing pipeline

A single ordered pipeline sits between "raw findings produced by the checks" and "output", shared by
the three finding-producing commands (`lint`, `lint-all`, `check-ast`):

```
raw findings (TArray<TLintFinding>)
  -> Config:   severity remap + enable/disable filter        (DRagLint.Lint.Config)
  -> Baseline: drop findings already recorded (new-only)      (DRagLint.Lint.Baseline)
  -> Format:   text | json | sarif                            (DRagLint.Output.Sarif for sarif)
  -> Exit code: nonzero iff any SURVIVING finding's level >= --fail-on threshold
```

**Order rationale:** config runs first (it can re-level or drop findings); baseline filters what
remains; the formatter and the exit-code both see the FINAL surviving set. Thresholds (config) feed
the metric checks *before* they run (they change which findings are produced), so threshold
application is a check-input, not a post-filter (see 6).

**Non-breaking guarantee:** with no `drag-lint-lint.json`, no `--baseline`, and no `--fail-on`, every
command behaves exactly as today (same findings, same `--format json`/text output, same exit code).

## 3. Component: SARIF output (`DRagLint.Output.Sarif`)

- **Responsibility:** serialize `TArray<TLintFinding>` to SARIF 2.1.0 JSON. Pure function, no I/O.
- **Interface:** `class function TSarifWriter.ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string;`
- **Shape:** `{ "version":"2.1.0", "$schema":"https://json.schemastore.org/sarif-2.1.0.json",
  "runs":[ { "tool":{"driver":{"name":"drag-lint","version":<AToolVersion>,"rules":[ {"id":<ruleId>} ... ]}},
  "results":[ {"ruleId","level","message":{"text"},"locations":[{"physicalLocation":{
  "artifactLocation":{"uri":<file>}, "region":{"startLine","startColumn","endLine","endColumn"}}}]} ... ] } ] }`.
- **Level mapping:** `error -> "error"`, `warning -> "warning"`, `info`/`hint` -> `"note"`.
- **rules[]:** the DISTINCT rule ids present in the findings (deduped); `id` only is required-valid SARIF.
  (A future enhancement may add `shortDescription` from a rule-meta table; not required now.)
- **uri:** the finding's `FilePath` as-is (absolute path is valid SARIF; relativization is a later nicety).
- **Wiring:** the `--format` dispatch in each command gains a `sarif` branch calling `TSarifWriter.ToJson`.

## 4. Component: CI exit-code policy (`--fail-on <level>`)

- **Arg:** `--fail-on error|warning|info|none` (parsed into `TArgs.FailOn`). Absent => current behavior.
- **Severity order:** `error > warning > info > hint`. `--fail-on warning` => exit nonzero if ANY surviving
  finding is `error` or `warning`.
- **`none`** => always exit 0 (report-only).
- **Default (flag absent):** preserve the command's existing exit code exactly (today `lint`/`lint-all`/
  `check-ast` exit nonzero when findings exist; that stays). `--fail-on` OVERRIDES that policy when given.
- **Scope:** a small helper `function ExitCodeFor(const AFindings; const AFailOn: string; ADefaultCode: Integer): Integer;`
  applied after the pipeline, in each command.

## 5. Component: baseline / suppression (`DRagLint.Lint.Baseline`)

- **Responsibility:** fingerprint findings; write a baseline; filter a finding set against a baseline.
- **Fingerprint (line-number-independent):** `SHA-or-cheap-hash( lower(ruleId) + '|' + NormPath(FilePath) +
  '|' + hash(TrimmedSourceLineText) )`. The source-line text is the trimmed content of the finding's
  `StartLine` in its file (read once per file, cached). Using line CONTENT (not the line number) means
  inserting/removing unrelated lines does not invalidate baselined findings. When two findings on
  identical-text lines collide, disambiguate with an occurrence ordinal within `(rule,file,linetext)`.
- **Interfaces:**
  - `class function TBaseline.Fingerprint(const AFinding: TLintFinding): string;`
  - `class procedure TBaseline.Write(const APath: string; const AFindings: TArray<TLintFinding>);`
  - `class function TBaseline.Filter(const APath: string; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>;` (returns only findings whose fingerprint is NOT in the baseline)
- **File format:** JSON `{ "version":1, "fingerprints":[ "<fp>", ... ] }`.
- **CLI:** `--write-baseline <file>` (produce baseline from the current run, then exit 0 without normal
  output) and `--baseline <file>` (filter the run, report only new). `--write-baseline` runs the checks +
  config pipeline but skips the baseline-filter (it's recording the current state).

## 6. Component: config + severity + profiles (`DRagLint.Lint.Config`)

- **Discovery:** `--config <path>` if given, else `drag-lint-lint.json` in the current directory if it
  exists, else no config (defaults).
- **Schema (`drag-lint-lint.json`):**
  ```json
  {
    "disabled": ["rule-id", ...],
    "enabled":  ["rule-id", ...],
    "severity": { "rule-id": "warning" | "error" | "info" | "hint" },
    "thresholds": { "too-many-parameters": 7, "too-many-locals": 25, "method-too-long": 120,
                    "deep-nesting": 5, "cyclomatic-complexity": 15, "too-many-exit-points": 5 },
    "profiles": { "ci": { "disabled": [...], "enabled": [...] } }
  }
  ```
- **Behavior:**
  - **severity:** remap a finding's `Severity` field by rule id (applied first in the pipeline).
  - **disabled/enabled:** drop findings whose rule id is disabled; `enabled` re-includes (and is the hook
    for turning ON rules that ship off-by-default, e.g. naming rules / `.scm` `"enabled":false`).
  - **thresholds:** feed the metric checks (`CheckRoutineMetrics`, cyclomatic, exit-points), which today
    take hardcoded constants. Threshold config is read BEFORE the checks run and passed in (a check input).
  - **profiles:** `--profile <name>` merges that profile's `disabled`/`enabled` over the top-level ones.
    Kept minimal -- named enable/disable sets only, no separate DSL.
- **`--enable <id1,id2>`** CLI flag mirrors the existing `--disable`; both compose with the config.
- **`.scm` `"enabled": false`:** honor an `"enabled": false` key in a rule's `.json` so a rule can ship
  off-by-default; `enabled`/`--enable` turns it on. (Today `.scm` rules always run; only `--disable` exists.)
- **Interface:** `TLintConfig` record loaded by `class function TLintConfig.Load(const APath: string): TLintConfig;`
  with helpers `ApplySeverity`, `IsEnabled(ruleId)`, `ThresholdFor(name, default)`.

## 7. Integration points

The three finding-producing commands each get the SAME post-processing tail. To avoid duplication, a
single helper `function FinalizeAndOutput(const AArgs: TArgs; AFindings: TArray<TLintFinding>;
ADefaultExit: Integer): Integer;` performs: load config -> apply severity/enable-disable -> baseline
filter (or write) -> format (text/json/sarif) -> compute exit code. Each command builds its raw
findings then calls this helper (replacing its current inline output+exit code). Threshold config is
loaded once and passed into the metric checks where they are invoked.

Sites (from the M1/M2 work): `DoLint`, `DoLintAll`, `DoCheckAst` in `src/cli/DRagLint.CLI.pas`. The
new CLI args (`--format sarif` value, `--fail-on`, `--baseline`, `--write-baseline`, `--config`,
`--enable`, `--profile`) are added to the arg parser + the help text.

## 8. Testing

- **SARIF:** a fixture finding-set -> `TSarifWriter.ToJson` -> assert it parses as JSON, has
  `runs[0].results` with the right `level` mapping and a `region`, and `runs[0].tool.driver.rules`
  lists the distinct ids. Console unit test (mirrors `tests/projectchecks`) since it is a pure function.
- **Baseline:** write a baseline from a fixture run, then re-run with `--baseline` and assert 0 new;
  add a line ABOVE the finding and assert it is STILL suppressed (line-shift stability); introduce a
  genuinely new finding and assert it reports.
- **Config:** fixtures asserting a `severity` override changes a finding's level; a `disabled` id drops
  it; a `thresholds` override flips a metric finding on/off; `--enable` turns on an off-by-default rule.
- **`--fail-on`:** assert exit codes for a file with a known error/warning/info under each `--fail-on`
  value (including `none`).
- The existing `tests/lint/run_lint_tests.ps1` stays green (default behavior unchanged).

## 9. Non-goals (this milestone)

- **Autofix / quick-fixes** (mutating source) -- deferred; tracked in `#12`.
- SARIF rule metadata (descriptions/help URIs) beyond `id` -- later nicety.
- URI relativization in SARIF -- later nicety.

## 10. Internal phasing (one milestone, staged commits)

1. `DRagLint.Output.Sarif` + `--format sarif` wiring + SARIF unit test.
2. `--fail-on` + exit-code helper + tests.
3. `DRagLint.Lint.Config` (severity/enable/disable/thresholds) + `--config`/`--enable`/`--profile` +
   `.scm` `"enabled":false` + fixtures.
4. `DRagLint.Lint.Baseline` + `--baseline`/`--write-baseline` + round-trip + line-shift tests.
5. `FinalizeAndOutput` helper -- refactor the three commands onto the shared tail.
6. Docs: `rules/README.md` (config + formats), CHANGELOG v0.66 "Ergonomics" section; real-code sanity run.

Each stage: fixture -> green harness -> Win64 build -> commit. The v0.66 bundle ships after.

## 11. Definition of done

`--format sarif`, `--fail-on`, `--baseline`/`--write-baseline`, and `drag-lint-lint.json`
(severity/enable/disable/thresholds/profiles + `--config`/`--enable`/`--profile`) all live and wired
into `lint`/`lint-all`/`check-ast` via one shared `FinalizeAndOutput` tail; default behavior unchanged
(harness green); SARIF validates; baseline is line-shift stable; CHANGELOG v0.66 gains an Ergonomics
section. Then merge the M2 branch + ergonomics to `main` and publish **v0.66.0-alpha** (M1 + M2 + #12).
