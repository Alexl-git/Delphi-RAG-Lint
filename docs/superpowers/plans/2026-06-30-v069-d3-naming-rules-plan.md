# v0.69 D3 -- close MISSING-FEATURES #1: two naming rules -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two remaining naming rules -- `reserved-word-casing` (ON by default) and `hungarian-or-short-identifier` (OFF by default) -- to `DRagLint.Diagnostics.NamingChecks`, closing MISSING-FEATURES #1.

**Architecture:** Both rules are pure-AST checks inside the existing single-pass `TNamingChecker.Check` walker, driven by four new `TNamingConfig` fields parsed from the `naming` block of `drag-lint-lint.json`. `reserved-word-casing` inspects keyword (`kXxx`) token nodes for non-lowercase spelling; `hungarian-or-short-identifier` inspects parameter and local-variable *declaration* names for over-short or Hungarian-prefixed identifiers. No new engine, no store dependency, no new unit.

**Tech Stack:** Delphi 13 (Studio 37), tree-sitter-delphi13 grammar, Win64 `dcc64`/`msbuild`, PowerShell test harnesses.

## Global Constraints

- **Encoding (every `.pas`/`.dfm`/`.expected`/`.json` you create or edit):** strict 7-bit ASCII, CRLF line endings, no BOM. The Edit/Write tools emit LF -- normalize to CRLF before committing (Task 6 has the command). Never introduce a Unicode char.
- **Pascal comment rule:** never put `}` or a nested `{` inside a `{ }` comment (real dcc64 error). Prefer `{ ... }` single-level only.
- **DocInsight (CDD):** every new public method/type gets a `///` `<summary>` spec-comment; private helpers only when an invariant is non-obvious. Comment and test must agree.
- **Naming defaults are FP-sensitive:** `reserved-word-casing` ships **ON** (`keyword_case:"lowercase"`); `hungarian-or-short-identifier` ships **OFF** (`short_identifier_check:false`). A default `lint` run on real code must not newly fire `hungarian-or-short-identifier`.
- **VERSION is NOT bumped in D3.** `src/cli/DRagLint.CLI.pas:6` stays `0.68.0-alpha`; the bump to `0.69.0-alpha` happens at the v0.69 release after D1+D2. CHANGELOG gets an in-progress section only.
- **Build = the `delphi-build` skill recipe.** Build the CLI via `build\build_draglint_win64.bat` (it does `rsvars` -> msbuild Win64 Debug -> copies the exe to `third_party\dll-win64\drag-lint.exe`, the harness target). Run it from PowerShell `Start-Process -Wait` with output redirected to a log, then read the log (no `Error`/`E2xxx`/`F2xxx`). **Before building, kill any orphaned `drag-lint.exe`/`drag_lint_graph.exe`** (they lock the staged exe -> "used by another process").
- **drag-lint code search FIRST:** for any further symbol lookup use the drag-lint index, Grep second (see `c:\Projects\CLAUDE.md`).

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `src/lint/DRagLint.Lint.Config.pas` | `TNamingConfig` record + `TLintConfig.Load` JSON parse | Add 4 fields + defaults + parse |
| `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas` | The single-pass naming walker | Add 2 rules + helpers |
| `src/cli/DRagLint.CLI.pas` | `lint` rule allow-list, help string, `DoLint` dispatch | Add 2 rule ids (3 sites) |
| `tests/lintconfig/LintConfigTests.dpr` | Config-parse unit tests | Add field-parse asserts |
| `tests/lint/run_lint_tests.ps1` | Behavioral fixture harness | Per-fixture `.config.json` support |
| `tests/lint/*.pas` + `*.config.json` + `*.expected` | New TDD fixtures | Create |
| `rules/README.md`, `docs/lint/MISSING-FEATURES.md`, `CHANGELOG.md` | Docs | Update |

**Sequencing rationale:** Task 1 (config fields) is the dependency for everything. Task 2 (harness `.config.json` support) is the dependency for the config-driven fixtures in Tasks 3-4, and is proven first against an existing rule (`param-name-prefix`), closing a pre-existing test gap. Tasks 3 and 4 are the two rules, each independently reviewable. Task 5 wires nothing new (already done in Task 3) -- it is docs only.

---

## Task 1: Config fields for both rules

**Files:**
- Modify: `src/lint/DRagLint.Lint.Config.pas` (record `TNamingConfig` ~13-19; `TNamingConfig.Default` ~62-73; `TLintConfig.Load` naming block ~145-166)
- Test: `tests/lintconfig/LintConfigTests.dpr` (`TestNaming` ~29-53)

**Interfaces:**
- Produces: `TNamingConfig.KeywordCase: string` (default `'lowercase'`), `TNamingConfig.MinIdentifierLen: Integer` (default `3`), `TNamingConfig.HungarianPrefixes: TArray<string>` (default `['lpsz','psz','sz','lp','int','str','dw','b','p','n']`), `TNamingConfig.ShortIdentifierCheck: Boolean` (default `False`). Tasks 3-4 consume these.

- [ ] **Step 1: Write the failing config-parse test**

In `tests/lintconfig/LintConfigTests.dpr`, inside `procedure TestNaming`, after the existing block-2 `finally ... end;` (line ~52, before `end;` of `TestNaming`) add a third block:

```pascal
  // 3. New v0.69 D3 fields: defaults + overrides.
  Cfg:= TLintConfig.Load('', '');
  Check('naming default keyword_case lowercase', Cfg.Naming.KeywordCase = 'lowercase');
  Check('naming default min_identifier_len 3', Cfg.Naming.MinIdentifierLen = 3);
  Check('naming default short_identifier_check off', Cfg.Naming.ShortIdentifierCheck = False);
  Check('naming default hungarian_prefixes nonempty', Length(Cfg.Naming.HungarianPrefixes) > 0);

  Path:= TPath.Combine(TPath.GetTempPath, 'dl-naming-d3.json');
  TFile.WriteAllText(Path,
    '{ "naming": { "keyword_case": "", "min_identifier_len": 5, ' +
    '"short_identifier_check": true, "hungarian_prefixes": ["foo","bar"] } }',
    TEncoding.UTF8);
  try
    Cfg:= TLintConfig.Load(Path, '');
    Check('naming keyword_case overridden empty', Cfg.Naming.KeywordCase = '');
    Check('naming min_identifier_len overridden 5', Cfg.Naming.MinIdentifierLen = 5);
    Check('naming short_identifier_check overridden true', Cfg.Naming.ShortIdentifierCheck = True);
    Check('naming hungarian_prefixes overridden len 2', Length(Cfg.Naming.HungarianPrefixes) = 2);
    Check('naming hungarian_prefixes first foo',
      (Length(Cfg.Naming.HungarianPrefixes) = 2) and (Cfg.Naming.HungarianPrefixes[0] = 'foo'));
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
```

- [ ] **Step 2: Run the test to verify it fails to compile**

Run (PowerShell, from repo root):
```powershell
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1
```
Expected: `BUILD FAILED` -- `E2003`/undeclared identifier `KeywordCase` (field does not exist yet).

- [ ] **Step 3: Add the four fields to the record**

In `src/lint/DRagLint.Lint.Config.pas`, the record currently reads:

```pascal
  TNamingConfig = record
    ClassPrefix, ExceptionPrefix, InterfacePrefix, PointerPrefix: string;
    FieldPrefix, ParamPrefix: string;
    MethodCase, LocalCase   : string;        // 'PascalCase' | 'UPPER_CASE' | 'camelCase'
    ConstCase               : TArray<string>;
    class function Default: TNamingConfig; static;
  end;
```

Replace with (adds four fields + updates the DocInsight summary):

```pascal
  /// <summary>Configurable naming conventions read from the drag-lint-lint.json
  /// "naming" block. Empty-string prefixes disable that prefix check; empty
  /// ConstCase disables const casing. KeywordCase='' disables reserved-word-casing;
  /// ShortIdentifierCheck=False (default) disables hungarian-or-short-identifier.
  /// Defaults match the project conventions (TMyClass / EMyException / IMyIntf /
  /// PMyType / FMyField / pMyParam, PascalCase, lowercase keywords).</summary>
  TNamingConfig = record
    ClassPrefix, ExceptionPrefix, InterfacePrefix, PointerPrefix: string;
    FieldPrefix, ParamPrefix: string;
    MethodCase, LocalCase   : string;        // 'PascalCase' | 'UPPER_CASE' | 'camelCase'
    ConstCase               : TArray<string>;
    KeywordCase             : string;        // 'lowercase' (default) | '' disables reserved-word-casing
    MinIdentifierLen        : Integer;       // shortest allowed identifier (hungarian-or-short rule)
    HungarianPrefixes       : TArray<string>;// type-prefix denylist for the hungarian rule
    ShortIdentifierCheck    : Boolean;       // master on/off for hungarian-or-short-identifier (default False)
    class function Default: TNamingConfig; static;
  end;
```

(Delete the old un-DocInsighted `TNamingConfig = record` summary lines 9-12 that precede it, since the new summary above replaces them.)

- [ ] **Step 4: Add the defaults**

In `TNamingConfig.Default`, after `Result.ConstCase := ['PascalCase', 'UPPER_CASE'];` add:

```pascal
  Result.KeywordCase         := 'lowercase';  { reserved-word-casing ON by default }
  Result.MinIdentifierLen    := 3;
  Result.HungarianPrefixes   := ['lpsz', 'psz', 'sz', 'lp', 'int', 'str', 'dw', 'b', 'p', 'n'];
  Result.ShortIdentifierCheck:= False;        { hungarian-or-short-identifier OFF by default }
```

- [ ] **Step 5: Parse the four fields in `TLintConfig.Load`**

In `TLintConfig.Load`, inside the `if Root.GetValue('naming') is TJSONObject then begin ... end;` block, after the existing `const_case` array handling (the closing `end;` of the `if NJ.GetValue('const_case') is TJSONArray` block, ~line 165) add:

```pascal
      if NJ.GetValue('keyword_case') <> nil then
        Result.Naming.KeywordCase:= NJ.GetValue('keyword_case').Value;
      if NJ.GetValue('min_identifier_len') <> nil then
        Result.Naming.MinIdentifierLen:= StrToIntDef(NJ.GetValue('min_identifier_len').Value, 3);
      if NJ.GetValue('short_identifier_check') <> nil then
        Result.Naming.ShortIdentifierCheck:= SameText(NJ.GetValue('short_identifier_check').Value, 'true');
      if NJ.GetValue('hungarian_prefixes') is TJSONArray then
      begin
        Result.Naming.HungarianPrefixes:= nil;
        for var HV in (NJ.GetValue('hungarian_prefixes') as TJSONArray) do
          Result.Naming.HungarianPrefixes:= Result.Naming.HungarianPrefixes + [HV.Value];
      end;
```

Note: `TJSONBool.Value` returns the string `'true'`/`'false'`, so `SameText(...,'true')` is the correct bool parse (mirrors how the codebase reads JSON scalars by `.Value`).

- [ ] **Step 6: Run the test to verify it passes**

Run:
```powershell
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1
```
Expected: all PASS, final line `lintconfig-tests: N pass / 0 fail / N total` (N = previous total + 9), exit 0.

- [ ] **Step 7: Commit**

```bash
git add src/lint/DRagLint.Lint.Config.pas tests/lintconfig/LintConfigTests.dpr
git commit -m "feat(naming): TNamingConfig fields for reserved-word + hungarian-or-short rules (v0.69 D3)"
```

---

## Task 2: Per-fixture `.config.json` support in the lint harness

**Files:**
- Modify: `tests/lint/run_lint_tests.ps1` (the CLI invocation, line ~56)
- Create: `tests/lint/pnp-on.pas`, `tests/lint/pnp-on.config.json`, `tests/lint/pnp-on.pas.expected`

**Interfaces:**
- Produces: harness convention -- if `<fixture>.config.json` exists beside `<fixture>.pas`, the harness runs `drag-lint lint <fixture> --config <fixture>.config.json --json`; otherwise `--config` is omitted. Tasks 3-4 rely on this to test config-driven behavior.
- Consumes: the existing, already-built `param-name-prefix` rule in `third_party\dll-win64\drag-lint.exe` (no Delphi rebuild in this task).

- [ ] **Step 1: Write the failing config fixture (param-name-prefix ON)**

Create `tests/lint/pnp-on.pas`:
```pascal
unit pnp_on;
interface
procedure Go(Value: Integer; pName: string);
implementation
procedure Go(Value: Integer; pName: string);
begin
end;
end.
```

Create `tests/lint/pnp-on.config.json`:
```json
{ "naming": { "param_prefix": "p" } }
```

Create `tests/lint/pnp-on.pas.expected`:
```
# param-name-prefix enabled via sibling .config.json (param_prefix=p).
# 'Value' lacks the 'p' prefix -> fires; 'pName' is clean.
param-name-prefix 3
param-name-prefix 5
!param-name-prefix 3 pName
```
(The third directive form `!<rule> <line> <extra>` is ignored by the harness for the absence-pair check unless `pName`'s line matched; it is documentation only. The two positive directives are the assertions.)

Simplify to the two real assertions -- final `pnp-on.pas.expected`:
```
# param-name-prefix enabled via sibling .config.json (param_prefix=p).
# 'Value' lacks the 'p' prefix and fires at its two header sites; 'pName' clean.
param-name-prefix 3
param-name-prefix 5
```

- [ ] **Step 2: Run the harness to verify the new fixture FAILS (config not yet applied)**

Run:
```powershell
pwsh -File tests\lint\run_lint_tests.ps1 -Filter pnp-on
```
Expected: `FAIL  pnp-on.pas` -- `missing expected 'param-name-prefix' at line 3` (the harness ran without `--config`, so `param_prefix` is still `''` and the rule did not fire).

- [ ] **Step 3: Add `.config.json` detection to the harness**

In `tests/lint/run_lint_tests.ps1`, replace the single invocation line:
```powershell
  $raw = & $exePath lint $pas.FullName --json 2>$null
```
with:
```powershell
  # Per-fixture config: if <fixture>.config.json exists, pass it via --config so
  # config-driven rules (param_prefix, keyword_case, short_identifier_check) can be
  # exercised. Without it the CLI uses built-in defaults.
  $cfgFile = [IO.Path]::ChangeExtension($pas.FullName, ".config.json")
  if (Test-Path $cfgFile) {
    $raw = & $exePath lint $pas.FullName --config $cfgFile --json 2>$null
  } else {
    $raw = & $exePath lint $pas.FullName --json 2>$null
  }
```

- [ ] **Step 4: Run the new fixture + the full suite to verify pass + no regression**

Run:
```powershell
pwsh -File tests\lint\run_lint_tests.ps1 -Filter pnp-on
pwsh -File tests\lint\run_lint_tests.ps1
```
Expected: `PASS  pnp-on.pas`; full run ends `lint-tests: M pass / 0 fail / M total`, exit 0 (every prior fixture still green; `.config.json` is opt-in so unaffected fixtures are unchanged).

- [ ] **Step 5: Commit**

```bash
git add tests/lint/run_lint_tests.ps1 tests/lint/pnp-on.pas tests/lint/pnp-on.config.json tests/lint/pnp-on.pas.expected
git commit -m "test(lint): per-fixture .config.json support; cover param-name-prefix ON (v0.69 D3)"
```

---

## Task 3: `reserved-word-casing` rule (ON by default)

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas` (unit-level helpers before `TNamingChecker.Check`; the `Visit` walker; the unit doc-comment block ~3-15)
- Modify: `src/cli/DRagLint.CLI.pas` (3 wiring sites; **also wire `hungarian-or-short-identifier` here** so the two ~200-char lines are edited once)
- Create: `tests/lint/reserved-word-casing.pas` (+ `.expected`); `tests/lint/rwc-off.pas` (+ `.config.json` + `.expected`)

**Interfaces:**
- Consumes: `ANaming.KeywordCase` (Task 1).
- Produces: rule id `reserved-word-casing`, severity `info`. Wires both `reserved-word-casing` and `hungarian-or-short-identifier` into the CLI allow-list / help / dispatch.

- [ ] **Step 1: Verify keyword node kinds on a real parse (de-risk before coding)**

The walker only recurses into *named* children; `reserved-word-casing` relies on Pascal keywords appearing as named `kXxx` nodes. The codebase already treats `kEnd`, `kVar`, `kConst`, `kClass`, `kAnd`, `kPrivate`, etc. as named node types, so this is expected -- but confirm against a real parse before trusting the exact spellings.

Run a one-off dump using the already-built CLI's parser is not exposed, so use the grammar's own dumper indirectly: write a throwaway fixture and lint it with `--rule reserved-word-casing` is not available yet either. Instead, inspect a known parse via the existing test corpus: grep the diagnostics source for the keyword kinds already in use to confirm the `kXxx` convention, then proceed -- the rule is written kind-spelling-agnostic (any `k`+UppercaseLetter node whose text is alphabetic), so it does not depend on enumerating the full keyword set:
```powershell
Select-String -Path src\diagnostics\*.pas,src\parser\*.pas -Pattern "'k[A-Z][A-Za-z]+'" | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
```
Expected: a list including `'kEnd'`, `'kVar'`, `'kConst'`, `'kClass'`, `'kAnd'`, `'kOr'` -- confirming keywords are named `kXxx` nodes. (If the later fixture run in Step 7 shows zero findings, re-confirm by adding a temporary `Writeln(N.NodeType)` in the keyword branch and linting the fixture.)

- [ ] **Step 2: Write the failing fixtures**

Create `tests/lint/reserved-word-casing.pas` (line numbers matter):
```pascal
unit rwc;
interface
Const
  A = 1;
implementation
procedure P;
Var
  B: Integer;
begin
  if A = 1 then B := True;
  B := A And 1;
end;
end.
```

Create `tests/lint/reserved-word-casing.pas.expected`:
```
# 'Const' (3), 'Var' (7), 'And' (11) are non-lowercase keyword tokens -> fire.
# Line 9 'begin' is lowercase (clean); line 10 'if'/'then' lowercase and 'True'
# is convention-exempt -> no finding on those lines.
reserved-word-casing 3
reserved-word-casing 7
reserved-word-casing 11
!reserved-word-casing 9
!reserved-word-casing 10
```

Create `tests/lint/rwc-off.pas`:
```pascal
unit rwcoff;
interface
implementation
procedure P;
Var
  B: Integer;
begin
  B := 1;
end;
end.
```

Create `tests/lint/rwc-off.config.json`:
```json
{ "naming": { "keyword_case": "" } }
```

Create `tests/lint/rwc-off.pas.expected`:
```
# keyword_case:"" disables the rule -> 'Var' (line 5) must NOT fire.
!reserved-word-casing
```

- [ ] **Step 3: Run the harness to verify the fixtures FAIL**

Run:
```powershell
pwsh -File tests\lint\run_lint_tests.ps1 -Filter reserved-word-casing
pwsh -File tests\lint\run_lint_tests.ps1 -Filter rwc-off
```
Expected: `reserved-word-casing.pas` FAILs (`unknown rule "reserved-word-casing"` from the CLI -> zero findings -> `missing expected`); `rwc-off.pas` may PASS vacuously (no findings) -- that is fine, it becomes meaningful after Step 6.

- [ ] **Step 4: Add the keyword helpers (unit-level, before `TNamingChecker.Check`)**

In `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas`, after `function MatchesAnyCase(...)` (ends ~line 222) and before `class function TNamingChecker.Check`, add:

```pascal
{ Returns True when AType is a tree-sitter keyword node kind: 'k' followed by an
  uppercase letter (kBegin, kEnd, kVar, kClass, kAnd, ...). Symbol-operator kinds
  (kEq, kGt, kNeq) also match the pattern but are filtered out by the alphabetic
  text guard in the caller. }
function IsKeywordKind(const AType: string): Boolean;
begin
  Result:= (Length(AType) >= 2) and (AType[1] = 'k')
    and CharInSet(AType[2], ['A'..'Z']);
end;

{ Returns True when every character of S is an ASCII letter (A..Z or a..z) and S
  is non-empty. Used to keep reserved-word-casing on word keywords (and, begin)
  and off symbol-operator keyword nodes (=, <>) whose text is not alphabetic. }
function IsWordAllAlpha(const S: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if S = '' then Exit;
  for I:= 1 to Length(S) do
    if not CharInSet(S[I], ['A'..'Z', 'a'..'z']) then Exit;
  Result:= True;
end;

{ Returns True for keyword tokens that Delphi convention does NOT write in all
  lowercase, so reserved-word-casing must not flag them: True, False, nil.
  Compared case-insensitively against the lowercased token text. }
function IsCaseExemptKeyword(const ALowerText: string): Boolean;
begin
  Result:= (ALowerText = 'true') or (ALowerText = 'false') or (ALowerText = 'nil');
end;
```

- [ ] **Step 5: Add the keyword check at the top of `Visit`**

In `TNamingChecker.Check`, inside the nested `procedure Visit(const N: TTSNode);`, immediately after `if N.IsNull then Exit;` (the first statement, ~line 369) insert:

```pascal
    { reserved-word-casing: a keyword (kXxx) token whose source text is not
      all-lowercase, when KeywordCase='lowercase'. Excludes symbol-operator
      keyword kinds (non-alphabetic text) and the convention-exempt literals
      True/False/nil. Does NOT Exit -- the walk continues so other rules and
      child nodes are still visited (keyword nodes are leaves anyway). }
    if (ANaming.KeywordCase = 'lowercase') and IsKeywordKind(N.NodeType) then
    begin
      var KwText: string:= Trim(NodeStr(N));
      if (KwText <> '') and IsWordAllAlpha(KwText)
        and (not IsCaseExemptKeyword(LowerCase(KwText)))
        and (KwText <> LowerCase(KwText)) then
        EmitAt(N, 'reserved-word-casing',
          Format('Reserved word "%s" should be written in lowercase', [KwText]));
    end;
```

Also update the unit's top doc-comment block (lines 3-15) to add the rule to the "Rules implemented here" list, e.g. add after the `unit-name-matches-file:` line:
```pascal
    reserved-word-casing  : Pascal keyword tokens must be all-lowercase
                            (begin/end/var/...); True/False/nil exempt. }
```
(Adjust the closing `}` placement so the comment stays a single `{ }` block.)

- [ ] **Step 6: Wire both new rule ids into the CLI (3 sites)**

In `src/cli/DRagLint.CLI.pas`:

(a) **Allow-list guard.** Find:
```pascal
  (AArgs.Rule <> 'method-pascalcase') and (AArgs.Rule <> 'const-casing') and (AArgs.Rule <> 'local-var-casing') and (AArgs.Rule <> 'unit-name-matches-file') and
```
Replace with:
```pascal
  (AArgs.Rule <> 'method-pascalcase') and (AArgs.Rule <> 'const-casing') and (AArgs.Rule <> 'local-var-casing') and (AArgs.Rule <> 'unit-name-matches-file') and
  (AArgs.Rule <> 'reserved-word-casing') and (AArgs.Rule <> 'hungarian-or-short-identifier') and
```

(b) **Help "known:" string.** Find the substring:
```pascal
'type-name-prefix, field-name-prefix, param-name-prefix, method-pascalcase, const-casing, local-var-casing, unit-name-matches-file, '
```
Replace with:
```pascal
'type-name-prefix, field-name-prefix, param-name-prefix, method-pascalcase, const-casing, local-var-casing, unit-name-matches-file, reserved-word-casing, hungarian-or-short-identifier, '
```

(c) **`DoLint` dispatch `if`.** Find:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'type-name-prefix') or (AArgs.Rule = 'field-name-prefix') or (AArgs.Rule = 'param-name-prefix') or
         (AArgs.Rule = 'method-pascalcase') or (AArgs.Rule = 'const-casing') or (AArgs.Rule = 'local-var-casing') or (AArgs.Rule = 'unit-name-matches-file') then
```
Replace with:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'type-name-prefix') or (AArgs.Rule = 'field-name-prefix') or (AArgs.Rule = 'param-name-prefix') or
         (AArgs.Rule = 'method-pascalcase') or (AArgs.Rule = 'const-casing') or (AArgs.Rule = 'local-var-casing') or (AArgs.Rule = 'unit-name-matches-file') or
         (AArgs.Rule = 'reserved-word-casing') or (AArgs.Rule = 'hungarian-or-short-identifier') then
```

(The `lint-all` dispatch site iterates every naming finding unconditionally and needs no change. `hungarian-or-short-identifier`'s rule logic lands in Task 4; pre-wiring its id here is inert until then.)

- [ ] **Step 7: Build the Win64 CLI and run the fixtures**

Kill orphans, then build via the canonical script (delphi-build skill -- run the bat under `Start-Process -Wait`, redirect to a log, then read the log):
```powershell
Get-Process drag-lint,drag_lint_graph -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d3-t3-build.log" -RedirectStandardError "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d3-t3-build.err"
Get-Content "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d3-t3-build.log" -Tail 5
```
Expected log tail: `OK: staged Win64 drag-lint.exe`, no `Error`/`E2xxx`/`F2xxx`.

Then:
```powershell
pwsh -File tests\lint\run_lint_tests.ps1 -Filter reserved-word-casing
pwsh -File tests\lint\run_lint_tests.ps1 -Filter rwc-off
```
Expected: both `PASS`. If `reserved-word-casing.pas` shows zero findings, the keyword node assumption is wrong -- use the temporary `Writeln(N.NodeType)` probe from Step 1 to find the real keyword kinds and adjust `IsKeywordKind`.

- [ ] **Step 8: Run the full lint suite (no regression)**

```powershell
pwsh -File tests\lint\run_lint_tests.ps1
```
Expected: `lint-tests: M pass / 0 fail / M total`, exit 0. (Watch for any pre-existing fixture that contains a capitalized keyword and now newly fires `reserved-word-casing`; if one does, add a `!reserved-word-casing` guard line to that fixture's `.expected` only if the capitalization is intentional, otherwise the finding is correct and the fixture's source should be lowercased.)

- [ ] **Step 9: Commit**

```bash
git add src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas src/cli/DRagLint.CLI.pas third_party/dll-win64/drag-lint.exe tests/lint/reserved-word-casing.pas tests/lint/reserved-word-casing.pas.expected tests/lint/rwc-off.pas tests/lint/rwc-off.config.json tests/lint/rwc-off.pas.expected
git commit -m "feat(naming): reserved-word-casing rule, ON by default (v0.69 D3)"
```

---

## Task 4: `hungarian-or-short-identifier` rule (OFF by default)

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas` (helpers; `EmitShortHungarian` closure; the `declProc`/`defProc` param loops and the `declVar` loop)
- Create: `tests/lint/hungarian-short.pas` (+ `.expected`); `tests/lint/hungarian-on.pas` (+ `.config.json` + `.expected`)

**Interfaces:**
- Consumes: `ANaming.ShortIdentifierCheck`, `ANaming.MinIdentifierLen`, `ANaming.HungarianPrefixes` (Task 1). CLI id wired in Task 3.
- Produces: rule id `hungarian-or-short-identifier`, severity `info`, only emits when `ShortIdentifierCheck=True`.

- [ ] **Step 1: Write the failing fixtures**

Create `tests/lint/hungarian-short.pas` (default config -> OFF -> must NOT fire):
```pascal
unit hsi;
interface
implementation
procedure P(lpszName: PChar; intCount: Integer);
var
  i: Integer;
  x2: Integer;
begin
end;
end.
```

Create `tests/lint/hungarian-short.pas.expected`:
```
# OFF by default (short_identifier_check=false) -> rule never fires.
!hungarian-or-short-identifier
```

Create `tests/lint/hungarian-on.pas`:
```pascal
unit hon;
interface
implementation
procedure P(lpszName: PChar; Value: Integer);
var
  i: Integer;
  x2: Integer;
  strBuf: string;
begin
end;
end.
```

Create `tests/lint/hungarian-on.config.json`:
```json
{ "naming": { "short_identifier_check": true, "min_identifier_len": 3, "hungarian_prefixes": ["lpsz", "int", "str"] } }
```

Create `tests/lint/hungarian-on.pas.expected`:
```
# short_identifier_check=true with prefixes [lpsz,int,str], min_len 3:
#   lpszName (4) -> Hungarian; x2 (7) -> too short; strBuf (8) -> Hungarian.
#   Value (4) clean (no prefix, len 5); i (6) loop-counter exempt.
hungarian-or-short-identifier 4
hungarian-or-short-identifier 7
hungarian-or-short-identifier 8
!hungarian-or-short-identifier 6
```

- [ ] **Step 2: Run the harness to verify FAIL**

```powershell
pwsh -File tests\lint\run_lint_tests.ps1 -Filter hungarian-on
```
Expected: `FAIL  hungarian-on.pas` -- `missing expected 'hungarian-or-short-identifier' at line 4` (rule logic not implemented yet; the id is wired but emits nothing). `hungarian-short.pas` PASSes vacuously.

- [ ] **Step 3: Add the rule helpers (unit-level, before `TNamingChecker.Check`)**

In `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas`, after the `IsCaseExemptKeyword` helper from Task 3, add:

```pascal
{ Returns True when AName is a conventional loop-counter / coordinate identifier
  (i, j, k, n, x, y) that is exempt from the short-identifier check. Case-
  insensitive. }
function IsLoopCounterName(const AName: string): Boolean;
begin
  Result:= SameText(AName, 'i') or SameText(AName, 'j') or SameText(AName, 'k')
    or SameText(AName, 'n') or SameText(AName, 'x') or SameText(AName, 'y');
end;

{ Returns True when AName carries one of APrefixes as a Hungarian type prefix:
  it starts with the prefix (case-sensitive) AND the next character is uppercase
  (so 'intCount' = int+Count, 'lpszName' = lpsz+Name, but 'internal' = int+e..
  is NOT flagged). An empty prefix is ignored. }
function HasHungarianPrefix(const AName: string; const APrefixes: TArray<string>): Boolean;
var
  Pfx: string;
  PLen: Integer;
begin
  Result:= False;
  for Pfx in APrefixes do
  begin
    PLen:= Length(Pfx);
    if PLen = 0 then Continue;
    if Length(AName) <= PLen then Continue;
    if Copy(AName, 1, PLen) <> Pfx then Continue;
    if CharInSet(AName[PLen + 1], ['A'..'Z']) then Exit(True);
  end;
end;
```

- [ ] **Step 4: Add the `EmitShortHungarian` closure**

Inside `TNamingChecker.Check`, immediately after the nested `procedure EmitAt(...)` (ends ~line 280), add a sibling local procedure:

```pascal
  { Emit a hungarian-or-short-identifier finding for a declaration name when the
    rule is enabled. Short check: shorter than MinIdentifierLen and not a loop
    counter. Hungarian check: carries a configured type prefix. At most one
    finding per name (short takes precedence). }
  procedure EmitShortHungarian(const ANameNode: TTSNode; const AName: string);
  begin
    if not ANaming.ShortIdentifierCheck then Exit;
    if AName = '' then Exit;
    if IsLoopCounterName(AName) then Exit;
    if Length(AName) < ANaming.MinIdentifierLen then
      EmitAt(ANameNode, 'hungarian-or-short-identifier',
        Format('Identifier "%s" is shorter than %d characters',
          [AName, ANaming.MinIdentifierLen]))
    else if HasHungarianPrefix(AName, ANaming.HungarianPrefixes) then
      EmitAt(ANameNode, 'hungarian-or-short-identifier',
        Format('Identifier "%s" uses a Hungarian type prefix', [AName]));
  end;
```

- [ ] **Step 5: Run the short check on params (both `declProc` and `defProc`)**

In the `declProc` branch, the param loop is currently gated by `if ANaming.ParamPrefix <> '' then`. Change the guard to also run when the short check is on, and call `EmitShortHungarian` inside.

Find (in the `declProc` branch, ~line 577):
```pascal
      if ANaming.ParamPrefix <> '' then
      begin
        ArgsNode:= N.ChildByField('args');
```
Replace with:
```pascal
      if (ANaming.ParamPrefix <> '') or ANaming.ShortIdentifierCheck then
      begin
        ArgsNode:= N.ChildByField('args');
```
Then, inside that loop, find the prefix emit:
```pascal
              ArgName:= Trim(NodeStr(NameId));
              if SameText(ArgName, 'Self') then Continue;
              if not HasPrefix(ArgName, ANaming.ParamPrefix) then
                EmitAt(NameId, 'param-name-prefix',
                  Format('Parameter "%s" should start with the "%s" prefix',
                    [ArgName, ANaming.ParamPrefix]));
```
Replace with:
```pascal
              ArgName:= Trim(NodeStr(NameId));
              if SameText(ArgName, 'Self') then Continue;
              if (ANaming.ParamPrefix <> '') and (not HasPrefix(ArgName, ANaming.ParamPrefix)) then
                EmitAt(NameId, 'param-name-prefix',
                  Format('Parameter "%s" should start with the "%s" prefix',
                    [ArgName, ANaming.ParamPrefix]));
              EmitShortHungarian(NameId, ArgName);
```

Apply the **identical two edits** to the `defProc` branch (the second copy, ~line 649-672): change `if ANaming.ParamPrefix <> '' then` to `if (ANaming.ParamPrefix <> '') or ANaming.ShortIdentifierCheck then`, guard the prefix emit with `(ANaming.ParamPrefix <> '') and`, and add `EmitShortHungarian(NameId, ArgName);` after it.

- [ ] **Step 6: Run the short check on local vars (`declVar`)**

In the `declVar` branch, the loop is gated by `if InProcBody and (ANaming.LocalCase <> '') then`. It must also run when the short check is on, and the existing local-var-casing emit must stay gated on `LocalCase`.

Find (~line 711):
```pascal
    if N.NodeType = 'declVar' then
    begin
      if InProcBody and (ANaming.LocalCase <> '') then
      begin
        TypeNode:= N.ChildByField('type');
```
Replace with:
```pascal
    if N.NodeType = 'declVar' then
    begin
      if InProcBody and ((ANaming.LocalCase <> '') or ANaming.ShortIdentifierCheck) then
      begin
        TypeNode:= N.ChildByField('type');
```
Then find the existing emit block:
```pascal
          var CasingBad: Boolean:= (not MatchesCase(VarName, ANaming.LocalCase))
            and (not IsShortAllCaps(VarName));
          var HasFieldPfx: Boolean:= (ANaming.FieldPrefix <> '') and HasPrefix(VarName, ANaming.FieldPrefix);
          var HasParamPfx: Boolean:= (ANaming.ParamPrefix <> '') and HasPrefix(VarName, ANaming.ParamPrefix);
          if CasingBad or HasFieldPfx or HasParamPfx then
            EmitAt(VarNameId, 'local-var-casing',
              Format('Local variable "%s" should be %s and not carry a field/param prefix',
                [VarName, ANaming.LocalCase]));
```
Replace with (wrap the casing emit so it only runs when LocalCase is set, then always offer the var to the short/hungarian check):
```pascal
          if ANaming.LocalCase <> '' then
          begin
            var CasingBad: Boolean:= (not MatchesCase(VarName, ANaming.LocalCase))
              and (not IsShortAllCaps(VarName));
            var HasFieldPfx: Boolean:= (ANaming.FieldPrefix <> '') and HasPrefix(VarName, ANaming.FieldPrefix);
            var HasParamPfx: Boolean:= (ANaming.ParamPrefix <> '') and HasPrefix(VarName, ANaming.ParamPrefix);
            if CasingBad or HasFieldPfx or HasParamPfx then
              EmitAt(VarNameId, 'local-var-casing',
                Format('Local variable "%s" should be %s and not carry a field/param prefix',
                  [VarName, ANaming.LocalCase]));
          end;
          EmitShortHungarian(VarNameId, VarName);
```

- [ ] **Step 7: Build the Win64 CLI and run the fixtures**

```powershell
Get-Process drag-lint,drag_lint_graph -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d3-t4-build.log" -RedirectStandardError "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d3-t4-build.err"
Get-Content "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d3-t4-build.log" -Tail 5
pwsh -File tests\lint\run_lint_tests.ps1 -Filter hungarian-short
pwsh -File tests\lint\run_lint_tests.ps1 -Filter hungarian-on
```
Expected: build `OK: staged Win64 drag-lint.exe`; both fixtures `PASS`.

- [ ] **Step 8: Run the full lint suite (no regression)**

```powershell
pwsh -File tests\lint\run_lint_tests.ps1
```
Expected: `lint-tests: M pass / 0 fail / M total`, exit 0. (Default config keeps `hungarian-or-short-identifier` OFF, so no prior fixture can newly fire it.)

- [ ] **Step 9: Commit**

```bash
git add src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas third_party/dll-win64/drag-lint.exe tests/lint/hungarian-short.pas tests/lint/hungarian-short.pas.expected tests/lint/hungarian-on.pas tests/lint/hungarian-on.config.json tests/lint/hungarian-on.pas.expected
git commit -m "feat(naming): hungarian-or-short-identifier rule, OFF by default (v0.69 D3)"
```

---

## Task 5: Documentation (README + MISSING-FEATURES + CHANGELOG)

**Files:**
- Modify: `rules/README.md` (naming schema block, shipped-rules table, FP-hardening list, section heading)
- Modify: `docs/lint/MISSING-FEATURES.md` (section 1 heading + the `[ ]` line)
- Modify: `CHANGELOG.md` (new in-progress section)

- [ ] **Step 1: README -- bump the section heading and rule count**

In `rules/README.md`, change `## Naming conventions (v0.68)` to `## Naming conventions (v0.68-0.69)` and the lead-in `Seven config-driven naming rules added in v0.68.` to `Nine config-driven naming rules (seven in v0.68, two in v0.69).`. Change `### Shipped naming rules (v0.68)` to `### Shipped naming rules (v0.68-0.69)`.

- [ ] **Step 2: README -- extend the `naming` block schema**

In the schema JSON block (the one starting `"naming": {` with `"local_case": "PascalCase"`), add the four new keys before the closing `}`:
```json
  "local_case":   "PascalCase",
  "keyword_case": "lowercase",
  "min_identifier_len": 3,
  "hungarian_prefixes": ["lpsz", "psz", "sz", "lp", "int", "str", "dw", "b", "p", "n"],
  "short_identifier_check": false
```
And add four rows to the **Field descriptions** table after the `local_case` row:
```
| `keyword_case` | string | `"lowercase"` | Required casing for reserved words; `""` disables `reserved-word-casing` |
| `min_identifier_len` | int | `3` | Shortest allowed identifier for `hungarian-or-short-identifier` |
| `hungarian_prefixes` | array | `["lpsz","psz","sz","lp","int","str","dw","b","p","n"]` | Type-prefix denylist for `hungarian-or-short-identifier` |
| `short_identifier_check` | bool | `false` | Master on/off for `hungarian-or-short-identifier` (**off by default**) |
```

- [ ] **Step 3: README -- add the two rule rows**

In the **Shipped naming rules** table, after the `unit-name-matches-file` row add:
```
| `reserved-word-casing` | info | Pascal reserved words / keywords must be written in lowercase (`begin`/`end`/`var`/...). **On by default** (`keyword_case: "lowercase"`); `True`/`False`/`nil` are convention-exempt. |
| `hungarian-or-short-identifier` | info | Parameter and local-variable names must not be overly short (< `min_identifier_len`) or use a Hungarian type prefix (`lpszName`, `intCount`). **Off by default** (`short_identifier_check: false`); loop counters `i`/`j`/`k`/`n`/`x`/`y` exempt. FP-prone -- opt in per project. |
```

- [ ] **Step 4: README -- FP note**

In the **False-positive hardening (naming rules)** list add:
```
- **`reserved-word-casing`**: only keyword (`kXxx`) tokens are checked, never
  identifiers; symbol operators and the `True`/`False`/`nil` literals are exempt.
- **`hungarian-or-short-identifier`**: ships **off** (`short_identifier_check:
  false`); scoped to parameter and local-variable declarations only; loop-counter
  names `i`/`j`/`k`/`n`/`x`/`y` are exempt. Domain abbreviations and legitimate
  short names mean this rule is opt-in.
```

- [ ] **Step 5: MISSING-FEATURES -- mark #1 done**

In `docs/lint/MISSING-FEATURES.md`:
- Change the section-1 heading `## 1. Naming conventions  -- SHIPPED v0.68 (7 rules, ...)` to `## 1. Naming conventions  -- SHIPPED v0.68-0.69 (9 rules, `info`, config-driven)  **(now)**`.
- Change the `[ ]` line:
```
- [ ] Reserved-word casing (lowercase keywords); Hungarian/short-identifier flags -- PLANNED v0.69 (D3: `reserved-word-casing` ON + `hungarian-or-short-identifier` OFF) -> closes #1. See section 13.
```
to:
```
- [x] Reserved-word casing (lowercase keywords); Hungarian/short-identifier flags -- shipped v0.69 D3 as `reserved-word-casing` (ON) + `hungarian-or-short-identifier` (OFF). Closes #1.
```
- Update the closing note `> 7 config-driven rules shipped.` to `> 9 config-driven rules shipped.`

- [ ] **Step 6: CHANGELOG -- in-progress section**

In `CHANGELOG.md`, above the `## v0.68.0-alpha -- 2026-06-30` line, add:
```markdown
## v0.69.0-alpha (in progress)

### Added (naming -- D3, closes MISSING-FEATURES #1)

- **`reserved-word-casing`** (`info`, **on by default**) -- flags Pascal keyword
  tokens not written in lowercase (`Begin`/`VAR`/`And`). `True`/`False`/`nil` are
  convention-exempt; disable via `"keyword_case": ""`.
- **`hungarian-or-short-identifier`** (`info`, **off by default**) -- flags
  parameter/local names that are overly short (< `min_identifier_len`) or carry a
  Hungarian type prefix. Enable via `"short_identifier_check": true`. Loop counters
  `i`/`j`/`k`/`n`/`x`/`y` exempt.
- New `naming` config keys: `keyword_case`, `min_identifier_len`,
  `hungarian_prefixes`, `short_identifier_check`.

```

- [ ] **Step 7: Commit**

```bash
git add rules/README.md docs/lint/MISSING-FEATURES.md CHANGELOG.md
git commit -m "docs(naming): document reserved-word-casing + hungarian-or-short-identifier; close #1 (v0.69 D3)"
```

---

## Task 6: Final verification + encoding normalization

- [ ] **Step 1: Normalize encoding (CRLF, ASCII) on all new/edited text files**

The Edit/Write tools emit LF; the repo requires CRLF + 7-bit ASCII. Normalize and verify:
```powershell
$files = @(
  'src\lint\DRagLint.Lint.Config.pas',
  'src\diagnostics\DRagLint.Diagnostics.NamingChecks.pas',
  'src\cli\DRagLint.CLI.pas',
  'tests\lintconfig\LintConfigTests.dpr',
  'tests\lint\run_lint_tests.ps1'
) + (Get-ChildItem tests\lint\pnp-on.*, tests\lint\reserved-word-casing.*, tests\lint\rwc-off.*, tests\lint\hungarian-short.*, tests\lint\hungarian-on.* | ForEach-Object FullName)
foreach ($f in $files) {
  $t = [IO.File]::ReadAllText($f)
  $t = $t -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
  $bytes = [IO.File]::ReadAllBytes($f)
  $nonAscii = $bytes | Where-Object { $_ -gt 127 }
  if ($nonAscii) { Write-Host "NON-ASCII in $f" -ForegroundColor Red }
}
Write-Host "encoding normalized"
```
Expected: `encoding normalized`, no `NON-ASCII` lines. (`.pas`/`.dpr` must stay ASCII; the `UTF8Encoding($false)` writes no BOM, and pure-ASCII content is byte-identical to ANSI.)

- [ ] **Step 2: Full regression -- both harnesses green**

```powershell
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1
pwsh -File tests\lint\run_lint_tests.ps1
```
Expected: `lintconfig-tests: ... / 0 fail / ...` exit 0; `lint-tests: M pass / 0 fail / M total` exit 0.

- [ ] **Step 3: Real-code sanity (ORM3) -- default run stays quiet on the new OFF rule**

Run the new rules against a real unit to confirm zero spurious `hungarian-or-short-identifier` under default config and that `reserved-word-casing` is quiet on well-formatted code:
```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
& $exe lint "C:\Projects\DB\ORM3\<pick-a-real-unit>.pas" --rule hungarian-or-short-identifier --json
& $exe lint "C:\Projects\DB\ORM3\<pick-a-real-unit>.pas" --rule reserved-word-casing --json
```
Expected: `hungarian-or-short-identifier` -> `[]` (off by default). `reserved-word-casing` -> `[]` or only genuine non-lowercase keywords. If `reserved-word-casing` is noisy on real code (e.g. flags a convention the team uses), capture the cases and decide whether to widen `IsCaseExemptKeyword` -- record any such follow-up in `.superpowers/sdd/progress.md` rather than silently broadening.

- [ ] **Step 4: Commit any normalization-only changes**

```bash
git add -A
git commit -m "chore(naming): CRLF/ASCII normalize v0.69 D3 files" || echo "nothing to normalize"
```

- [ ] **Step 5: Confirm clean tree + report**

```bash
git status --porcelain
git log --oneline -6
```
Expected: empty `git status`; the six D3 commits present. Report D3 done: both rules live (`reserved-word-casing` ON, `hungarian-or-short-identifier` OFF), config fields parsed, fixtures green, both harnesses green, MISSING-FEATURES #1 marked `[x]`, docs updated. **Next deliverable: D1 (rule catalog + Lint Options tab).** VERSION bump to `0.69.0-alpha` deferred to the v0.69 release after D2.

---

## Self-Review (completed by plan author)

**Spec coverage (spec section 3 + 6 + 7 "D3"):**
- `reserved-word-casing` ON, keyword list, `keyword_case` config -> Tasks 1, 3. ✓
- `hungarian-or-short-identifier` OFF, short + Hungarian, `min_identifier_len`/`hungarian_prefixes`/`short_identifier_check`, loop-counter exemptions -> Tasks 1, 4. ✓
- Config parsed by `TLintConfig.Load`, defaults when absent -> Task 1 (+ LintConfigTests). ✓
- Same 4-site CLI wiring -> Task 3 Step 6 (allow-list, help, `DoLint` dispatch; `lint-all` site needs no change as documented). ✓
- TDD fixtures: positive fires + guarded negative; `keyword_case:""` disables; hungarian OFF-by-default + ON fires on `lpszName`/`i2`-style + exempts `i`/`j` -> Tasks 3, 4 (harness extended for config in Task 2). ✓
- README FP risk documented; MISSING-FEATURES #1 marked `[x]`; CHANGELOG updated -> Task 5. ✓
- Encoding (ASCII/CRLF) -> Global Constraints + Task 6 Step 1. ✓

**Placeholder scan:** no TBD/"handle edge cases"/"similar to"; every code step shows complete code. The Task 6 Step 3 `<pick-a-real-unit>` is an intentional operator choice at run time, not a code placeholder.

**Type/name consistency:** `KeywordCase`/`MinIdentifierLen`/`HungarianPrefixes`/`ShortIdentifierCheck` used identically in Config (Task 1), the rule (Tasks 3-4), and tests. Helper names `IsKeywordKind`/`IsWordAllAlpha`/`IsCaseExemptKeyword`/`IsLoopCounterName`/`HasHungarianPrefix`/`EmitShortHungarian` are each defined once and referenced consistently. Rule ids `reserved-word-casing` / `hungarian-or-short-identifier` spelled identically across CLI wiring, fixtures, `.expected`, and docs.

**Known risk flagged in-plan:** keyword nodes being named `kXxx` is strongly evidenced but verified at run time in Task 3 Step 1/7 (probe fallback included). The `p` Hungarian prefix vs the project's `pMyParam` param convention is a deliberate, documented interaction (rule ships OFF; users tune `hungarian_prefixes`).
