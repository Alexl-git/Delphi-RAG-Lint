# v0.69 D1a -- `drag-lint rules` rule catalog command -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]` command that emits a single machine-readable catalog of EVERY lint rule (built-in + external `.scm`) with id, category, title, default severity, default-enabled, source, and parameters, plus summary counts.

**Architecture:** A new unit `DRagLint.Lint.RuleCatalog` holds (a) an in-code REGISTRY of the ~62 built-in rules (the one place that knows each built-in's category/title/default-severity/default-enabled/params) and (b) a builder that merges the registry with the on-disk `rules\*.json` sidecars (read directly with `System.JSON`; `source:"scm"`; category via an scm-id->category map, default `other`). A thin `DoRules` CLI handler renders the catalog as a grouped text table or `--json`. No analysis logic moves; this is pure metadata.

**Tech Stack:** Delphi 13 (Studio 37), `System.JSON`, Win64 `dcc64`/`msbuild`, PowerShell test harness.

## Global Constraints

- **Encoding (every `.pas`/`.dpr` you create or edit):** strict 7-bit ASCII, CRLF, no BOM. Edit/Write emit LF -- normalize touched files to CRLF and byte-verify no non-ASCII before committing. (A "LF" git-diff note can be a normalization artifact; byte-verify.) `.md` docs may keep pre-existing non-ASCII.
- **Pascal comments:** never put `}` or a nested `{` inside a `{ }` comment (real dcc64 error).
- **DocInsight (CDD):** `///` `<summary>` on every new public type/method; private helpers only when an invariant is non-obvious.
- **VERSION is NOT bumped in D1a.** `src/cli/DRagLint.CLI.pas:6` stays `0.68.0-alpha`; v0.69 publishes only after D2.
- **New unit needs BOTH** the `.dpr` `uses ... in '..\lint\DRagLint.Lint.RuleCatalog.pas'` AND a `.dproj` `<DCCReference Include="..\lint\DRagLint.Lint.RuleCatalog.pas"/>`.
- **Build = the `delphi-build` skill recipe** via `build\build_draglint_win64.bat` (rsvars -> msbuild Win64 Debug -> copies the exe to `third_party\dll-win64\drag-lint.exe`). Run it from PowerShell `Start-Process -Wait` redirected to a log; read the log (`OK: staged Win64 drag-lint.exe`, no `Error`/`E2xxx`/`F2xxx`). **Kill orphaned `drag-lint.exe`/`drag_lint_graph.exe` before building.**
- **DO NOT `git add` the built exe.** `third_party\dll-win64\drag-lint.exe` is ignored by `.gitignore` (`*.exe`); rebuild it for tests but commit SOURCE ONLY.
- **Catalog must be COMPLETE:** every built-in id and every distinct `rules\*.json` id appears exactly once (dedup by id; a built-in id that also has a `.scm` json is listed once as `source:"builtin"`).
- **Canonical category set (use these 12 verbatim):** `bug-patterns`, `resource-lifetime`, `security`, `platform`, `complexity`, `structure`, `naming`, `dead-code`, `data-flow`, `firedac`, `project-wide`, `other`.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `src/lint/DRagLint.Lint.RuleCatalog.pas` | `TRuleParam`/`TRuleInfo` types; built-in registry; `.scm` merge; `BuildCatalog`; `CatalogSummary` | Create |
| `src/cli/DRagLint.CLI.pas` | `DoRules` handler; `rules` dispatch; `--category` arg; help/usage | Modify |
| `src/cli/drag-lint.dpr` + `drag-lint.dproj` | register the new unit | Modify |
| `tests/rules-catalog/RuleCatalogTests.dpr` + `run_rulecatalog_tests.ps1` | console unit test (registry + merge) | Create |
| `tests/rules-catalog/run_rules_cli_test.ps1` | CLI end-to-end test (`rules --json`) | Create |
| `rules/README.md`, `CHANGELOG.md` | docs | Modify |

---

## Task 1: Catalog types + built-in registry

**Files:**
- Create: `src/lint/DRagLint.Lint.RuleCatalog.pas`
- Create: `tests/rules-catalog/RuleCatalogTests.dpr`, `tests/rules-catalog/run_rulecatalog_tests.ps1`

**Interfaces:**
- Produces:
  - `TRuleParam = record Name, ParamType, DefaultVal: string; end;` (`ParamType` in `'int'|'string'|'stringlist'|'bool'`)
  - `TRuleInfo = record Id, Category, Title, DefaultSeverity, Source: string; DefaultEnabled: Boolean; Params: TArray<TRuleParam>; end;`
  - `TRuleCatalog.BuiltinRegistry: TArray<TRuleInfo>` (class function) -- the ~62 built-ins.

- [ ] **Step 1: Write the failing console test**

Create `tests/rules-catalog/RuleCatalogTests.dpr`:
```pascal
program RuleCatalogTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Lint.RuleCatalog in '..\..\src\lint\DRagLint.Lint.RuleCatalog.pas';
var
  GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function Find(const A: TArray<TRuleInfo>; const AId: string; out AInfo: TRuleInfo): Boolean;
var R: TRuleInfo;
begin
  Result:= False;
  for R in A do if R.Id = AId then begin AInfo:= R; Exit(True); end;
end;
procedure TestRegistry;
var
  Reg: TArray<TRuleInfo>;
  Info: TRuleInfo;
  Ids: TDictionary<string, Boolean>;
  R: TRuleInfo;
  Dup: Boolean;
begin
  Reg:= TRuleCatalog.BuiltinRegistry;
  Check('registry has >= 55 built-ins', Length(Reg) >= 55);

  // representative: a parameterized complexity rule
  Check('too-many-parameters present', Find(Reg, 'too-many-parameters', Info));
  Check('too-many-parameters category complexity', Info.Category = 'complexity');
  Check('too-many-parameters severity info', Info.DefaultSeverity = 'info');
  Check('too-many-parameters source builtin', Info.Source = 'builtin');
  Check('too-many-parameters has threshold param',
    (Length(Info.Params) = 1) and (Info.Params[0].Name = 'threshold')
    and (Info.Params[0].ParamType = 'int') and (Info.Params[0].DefaultVal = '7'));

  // representative: a resource-lifetime warning
  Check('freeandnil-on-interface present', Find(Reg, 'freeandnil-on-interface', Info));
  Check('freeandnil-on-interface category resource-lifetime', Info.Category = 'resource-lifetime');
  Check('freeandnil-on-interface severity warning', Info.DefaultSeverity = 'warning');

  // representative: naming + default-disabled
  Check('reserved-word-casing present', Find(Reg, 'reserved-word-casing', Info));
  Check('reserved-word-casing category naming', Info.Category = 'naming');
  Check('reserved-word-casing default enabled', Info.DefaultEnabled = True);
  Check('hungarian-or-short-identifier default DISABLED', Find(Reg, 'hungarian-or-short-identifier', Info) and (Info.DefaultEnabled = False));
  Check('param-name-prefix default DISABLED', Find(Reg, 'param-name-prefix', Info) and (Info.DefaultEnabled = False));

  // representative: data-flow + dead-code + project-wide present
  Check('used-before-assignment is data-flow', Find(Reg, 'used-before-assignment', Info) and (Info.Category = 'data-flow'));
  Check('unused-parameter is dead-code', Find(Reg, 'unused-parameter', Info) and (Info.Category = 'dead-code'));
  Check('god-class is project-wide', Find(Reg, 'god-class', Info) and (Info.Category = 'project-wide'));

  // every entry has a non-empty id/category/severity and a valid category
  for R in Reg do
  begin
    if (R.Id = '') or (R.Category = '') or (R.DefaultSeverity = '') then
    begin Check('entry fully populated: ' + R.Id, False); Break; end;
  end;

  // no duplicate ids
  Ids:= TDictionary<string, Boolean>.Create;
  try
    Dup:= False;
    for R in Reg do
      if Ids.ContainsKey(R.Id) then begin Dup:= True; Break; end
      else Ids.Add(R.Id, True);
    Check('no duplicate built-in ids', not Dup);
  finally
    Ids.Free;
  end;
end;
begin
  GPass:= 0; GFail:= 0;
  try
    TestRegistry;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('rulecatalog-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/rules-catalog/run_rulecatalog_tests.ps1`:
```powershell
# Build + run the rule-catalog console unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\RuleCatalogTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\RuleCatalogTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 2: Run the test to verify it fails to build**

Run:
```powershell
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1
```
Expected: `BUILD FAILED` -- unit `DRagLint.Lint.RuleCatalog` not found.

- [ ] **Step 3: Create the unit with types + the built-in registry**

Create `src/lint/DRagLint.Lint.RuleCatalog.pas`. The registry is grouped by category for reviewability; each `B(...)` call adds one built-in. **Use these exact ids/categories/severities/params** (sourced from the live code inventory -- categories are the 12 canonical buckets; severities are each rule's emitted severity; default-enabled is True except where noted):

```pascal
unit DRagLint.Lint.RuleCatalog;

{ Single machine-readable catalog of every drag-lint rule. The BUILT-IN registry
  below is the one place that knows each built-in's category / title / default
  severity / default-enabled / parameters. External .scm rules are merged in by
  BuildCatalog (source:"scm"); their severity/message come from the sidecar json
  and their category from ScmCategory(). Pure metadata -- no analysis logic. }

interface

uses
  System.SysUtils, System.Generics.Collections, System.JSON, System.IOUtils;

type
  /// <summary>A single configurable parameter of a rule (threshold or naming knob).</summary>
  TRuleParam = record
    Name      : string;  // config key (e.g. 'threshold', 'class_prefix')
    ParamType : string;  // 'int' | 'string' | 'stringlist' | 'bool'
    DefaultVal: string;  // textual default
  end;

  /// <summary>One catalogued rule.</summary>
  TRuleInfo = record
    Id             : string;
    Category       : string;  // one of the 12 canonical buckets
    Title          : string;
    DefaultSeverity: string;  // 'hint' | 'info' | 'warning' | 'error'
    Source         : string;  // 'builtin' | 'scm'
    DefaultEnabled : Boolean;
    Params         : TArray<TRuleParam>;
  end;

  /// <summary>Per-category and total rule counts for the catalog summary.</summary>
  TCatalogSummary = record
    Total      : Integer;
    Categories : Integer;
    PerCategory: TArray<TPair<string, Integer>>;  // (category, count), category order = first-seen
  end;

  TRuleCatalog = class
  public
    /// <summary>The in-code registry of all built-in rules (no .scm).</summary>
    class function BuiltinRegistry: TArray<TRuleInfo>; static;
    /// <summary>Full catalog: built-ins + external .scm rules from ARulesDir
    /// (default &lt;exe-dir&gt;\rules). Deduped by id (builtin wins). Sorted by
    /// (category, id). When ACategory&lt;&gt;'' only that category is returned.</summary>
    class function BuildCatalog(const ARulesDir: string = '';
      const ACategory: string = ''): TArray<TRuleInfo>; static;
    /// <summary>Totals + per-category counts over ACatalog.</summary>
    class function Summarize(const ACatalog: TArray<TRuleInfo>): TCatalogSummary; static;
    /// <summary>Category bucket for an external .scm rule id; 'other' if unmapped.</summary>
    class function ScmCategory(const AId: string): string; static;
  end;

implementation

function MkParam(const AName, AType, ADefault: string): TRuleParam;
begin
  Result.Name:= AName; Result.ParamType:= AType; Result.DefaultVal:= ADefault;
end;

class function TRuleCatalog.BuiltinRegistry: TArray<TRuleInfo>;
var
  L: TList<TRuleInfo>;
  procedure B(const AId, ACat, ASev, ATitle: string; AEnabled: Boolean = True;
    const AParams: TArray<TRuleParam> = nil);
  var R: TRuleInfo;
  begin
    R.Id:= AId; R.Category:= ACat; R.DefaultSeverity:= ASev; R.Title:= ATitle;
    R.Source:= 'builtin'; R.DefaultEnabled:= AEnabled; R.Params:= AParams;
    L.Add(R);
  end;
begin
  L:= TList<TRuleInfo>.Create;
  try
    { --- bug-patterns --- }
    B('syntax-error',                  'bug-patterns', 'error',   'Source has a syntax error');
    B('unbalanced-begin-end',          'bug-patterns', 'warning', 'Unbalanced begin/end');
    B('raise-in-finally',              'bug-patterns', 'warning', 'raise inside a finally block masks the in-flight exception');
    B('code-after-exit',               'bug-patterns', 'warning', 'Unreachable code after Exit/raise/Break/Continue/Halt');
    B('control-flow-in-finally',       'bug-patterns', 'warning', 'Exit/Break/Continue/Halt inside a finally block');
    B('missing-inherited-ctor',        'bug-patterns', 'warning', 'Constructor without an inherited call');
    B('missing-inherited-dtor',        'bug-patterns', 'warning', 'Destructor without an inherited call');
    B('float-equality-comparison',     'bug-patterns', 'warning', 'Floating-point value compared with =');
    B('length-zero-compare',           'bug-patterns', 'info',    'Length(s) compared to 0 -- use s = '''' / s <> ''''');
    B('string-equality-comparison',    'bug-patterns', 'info',    'String compared with = -- consider SameText/SameStr semantics');
    B('format-argument-count',         'bug-patterns', 'error',   'Format() argument count does not match the specifiers');
    B('format-specifier-type-mismatch','bug-patterns', 'error',   'Format() specifier type does not match the literal argument');
    B('loop-executes-at-most-once',    'bug-patterns', 'warning', 'Loop body starts with Exit/Break/raise -- runs at most once');
    B('virtual-method-in-constructor', 'bug-patterns', 'warning', 'Virtual/dynamic method called from a constructor');
    B('try-except-swallowed',          'bug-patterns', 'warning', 'try..except swallows the exception (no raise/log)');
    B('criticalsection-not-released',  'bug-patterns', 'error',   'Critical section acquired without a matching Leave/Release in finally');
    B('ui-access-in-thread',           'bug-patterns', 'warning', 'UI access inside a TThread.Execute (not thread-safe)');
    B('global-form-variable',          'bug-patterns', 'warning', 'Unit-level global variable of the form class type -- potential leak');

    { --- resource-lifetime --- }
    B('freeandnil-on-interface',       'resource-lifetime', 'warning', 'FreeAndNil on an interface reference');
    B('unprotected-object-free',       'resource-lifetime', 'warning', 'Object created + freed without try-finally');
    B('use-after-free',                'resource-lifetime', 'warning', 'Object used after X.Free');

    { --- security --- }
    B('unsafe-shellexecute',           'security', 'error',   'WinExec/ShellExecute/CreateProcess with a non-literal command');
    B('path-traversal',                'security', 'warning', 'Concatenated path passed to a file API -- path traversal risk');

    { --- platform --- }
    B('win64-pointer-cast',            'platform', 'warning', 'Pointer cast to a 32-bit integer type -- unsafe on Win64');

    { --- complexity (all parameterized) --- }
    B('too-many-parameters',  'complexity', 'info', 'Routine has too many parameters', True, [MkParam('threshold','int','7')]);
    B('too-many-locals',      'complexity', 'info', 'Routine has too many local variables', True, [MkParam('threshold','int','25')]);
    B('method-too-long',      'complexity', 'info', 'Routine body is too long', True, [MkParam('threshold','int','120')]);
    B('deep-nesting',         'complexity', 'info', 'Nesting is too deep', True, [MkParam('threshold','int','5')]);
    B('too-many-exit-points', 'complexity', 'info', 'Routine has too many Exit statements', True, [MkParam('threshold','int','5')]);
    B('cyclomatic-complexity','complexity', 'info', 'Cyclomatic complexity is too high', True, [MkParam('threshold','int','15')]);

    { --- firedac --- }
    B('firedac-open-execsql-mismatch', 'firedac', 'warning', 'Open vs ExecSQL does not match the SQL kind');
    B('dataset-open-without-close',    'firedac', 'warning', 'Dataset opened without a matching Close in finally');
    B('field-by-name-in-loop',         'firedac', 'warning', 'FieldByName called inside a loop -- cache the field');

    { --- dead-code --- }
    B('unused-local',          'dead-code', 'hint',    'Local variable is never used');
    B('unused-parameter',      'dead-code', 'warning', 'Parameter is never used');
    B('identical-then-else',   'dead-code', 'warning', 'then and else branches are identical');
    B('referenced-never-set',  'dead-code', 'warning', 'Private field is read but never assigned');

    { --- data-flow --- }
    B('used-before-assignment','data-flow', 'warning', 'Variable used before assignment');
    B('function-result-not-set','data-flow','warning', 'Function Result not assigned on every path');
    B('out-param-not-set',     'data-flow', 'warning', 'out parameter not assigned on every path');
    B('overwrite-before-read', 'data-flow', 'info',    'Value overwritten before it is read');
    B('write-only-local',      'data-flow', 'info',    'Local assigned but never read');
    B('loop-var-after-loop',   'data-flow', 'warning', 'Loop variable used after the loop');
    B('object-leak',           'data-flow', 'info',    'Created object may leak (not freed on every path)');

    { --- naming (all info; two ship disabled) --- }
    B('type-name-prefix',    'naming', 'info', 'Type name must carry the configured prefix', True,
      [MkParam('class_prefix','string','T'), MkParam('exception_prefix','string','E'),
       MkParam('interface_prefix','string','I'), MkParam('pointer_prefix','string','P')]);
    B('field-name-prefix',   'naming', 'info', 'Field name must carry the configured prefix', True,
      [MkParam('field_prefix','string','F')]);
    B('param-name-prefix',   'naming', 'info', 'Parameter name must carry the configured prefix', False,
      [MkParam('param_prefix','string','')]);
    B('method-pascalcase',   'naming', 'info', 'Method/routine name casing', True,
      [MkParam('method_case','string','PascalCase')]);
    B('const-casing',        'naming', 'info', 'Constant name casing', True,
      [MkParam('const_case','stringlist','PascalCase,UPPER_CASE')]);
    B('local-var-casing',    'naming', 'info', 'Local variable name casing', True,
      [MkParam('local_case','string','PascalCase')]);
    B('unit-name-matches-file','naming','info', 'Unit name must equal the file base name');
    B('reserved-word-casing','naming', 'info', 'Reserved words must be lowercase', True,
      [MkParam('keyword_case','string','lowercase')]);
    B('hungarian-or-short-identifier','naming','info','Short or Hungarian-prefixed identifier', False,
      [MkParam('min_identifier_len','int','3'),
       MkParam('hungarian_prefixes','stringlist','lpsz,psz,sz,lp,int,str,dw,b,p,n'),
       MkParam('short_identifier_check','bool','false')]);

    { --- structure --- }
    B('inline-comment-in-multiline-args', 'structure', 'warning', 'Inline comment inside a multi-line argument list');

    { --- project-wide --- }
    B('unit-not-in-dpr',       'project-wide', 'warning', 'Unit is referenced but not listed in the .dpr');
    B('unit-not-in-project',   'project-wide', 'warning', 'Unit is not a member of the project');
    B('unused-unit-in-uses',   'project-wide', 'warning', 'Unit in uses is never referenced');
    B('god-class',             'project-wide', 'info',    'Class has too many members/responsibilities');
    B('unused-public-symbol',  'project-wide', 'info',    'Public symbol is never referenced');
    B('unused-private-member', 'project-wide', 'warning', 'Private member is never referenced');
    B('layering-violation',    'project-wide', 'warning', 'Unit dependency crosses an architectural layer');
    B('interface-reference-cycle','project-wide','warning','Interface reference cycle (ARC leak)');

    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

class function TRuleCatalog.ScmCategory(const AId: string): string;
begin
  if MatchStr(AId, ['empty-except','empty-on-handler','empty-finally','bare-except',
    'raise-bare-exception','reraise-loses-stack','nil-comparison','not-in-precedence',
    'not-comparison-precedence','self-assignment','comparison-same-operands',
    'classname-string-compare','empty-conditional','empty-loop-body','constant-condition',
    'ifthen-both-branches','uppercase-compare','off-by-one-count','division-by-zero-literal',
    'empty-procedure-body','empty-case-branch','large-magic-number','case-magic-numbers',
    'sleep-in-vcl','parser-error']) then
    Result:= 'bug-patterns'
  else if MatchStr(AId, ['redundant-assigned-free']) then
    Result:= 'resource-lifetime'
  else if MatchStr(AId, ['hardcoded-credential','hardcoded-connection-string','sql-injection-concat',
    'hardcoded-absolute-path','hardcoded-ip-address']) then
    Result:= 'security'
  else if MatchStr(AId, ['inline-assembly','sizeof-pointer-assumption','pchar-arithmetic',
    'unsafe-string-api','locale-sensitive-conversion','gettickcount-wraparound','deprecated-rtl-function']) then
    Result:= 'platform'
  else if MatchStr(AId, ['public-field','goto-statement','with-statement','nested-with','with-multiple-items']) then
    Result:= 'structure'
  else if MatchStr(AId, ['redundant-as-tobject','redundant-not-not','boolean-result-returned-directly',
    'boolean-comparison-true']) then
    Result:= 'dead-code'
  else
    Result:= 'other';  { writeln-in-source, outputdebugstring, compiler-magic-comments, assert-call, inherited-bare, concat-in-loop }
end;

class function TRuleCatalog.BuildCatalog(const ARulesDir, ACategory: string): TArray<TRuleInfo>;
var
  Dir   : string;
  ById  : TDictionary<string, TRuleInfo>;
  Order : TList<string>;
  R     : TRuleInfo;
  F     : string;
  Files : TArray<string>;
  Raw   : string;
  Root  : TJSONValue;
  Obj   : TJSONObject;
  Sc    : TRuleInfo;
  Res   : TList<TRuleInfo>;
  Id    : string;
begin
  if ARulesDir <> '' then Dir:= ARulesDir
  else Dir:= TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules');

  ById:= TDictionary<string, TRuleInfo>.Create;
  Order:= TList<string>.Create;
  try
    { built-ins first (they win dedup) }
    for R in BuiltinRegistry do
      if not ById.ContainsKey(R.Id) then begin ById.Add(R.Id, R); Order.Add(R.Id); end;

    { external .scm sidecars }
    if TDirectory.Exists(Dir) then
    begin
      Files:= TDirectory.GetFiles(Dir, '*.json', TSearchOption.soAllDirectories);
      for F in Files do
      begin
        Raw:= '';
        try Raw:= TFile.ReadAllText(F, TEncoding.UTF8); except Continue; end;
        Root:= TJSONObject.ParseJSONValue(Raw);
        if not (Root is TJSONObject) then begin Root.Free; Continue; end;
        try
          Obj:= Root as TJSONObject;
          if Obj.GetValue('id') = nil then Continue;
          Id:= Obj.GetValue('id').Value;
          if (Id = '') or ById.ContainsKey(Id) then Continue; { builtin/dup wins }
          Sc.Id:= Id;
          Sc.Source:= 'scm';
          Sc.Category:= ScmCategory(Id);
          if Obj.GetValue('severity') <> nil then Sc.DefaultSeverity:= Obj.GetValue('severity').Value
          else Sc.DefaultSeverity:= 'warning';
          if Obj.GetValue('message') <> nil then Sc.Title:= Obj.GetValue('message').Value
          else Sc.Title:= Id;
          if (Obj.GetValue('enabled') <> nil) then
            Sc.DefaultEnabled:= not SameText(Obj.GetValue('enabled').Value, 'false')
          else Sc.DefaultEnabled:= True;
          Sc.Params:= nil;
          ById.Add(Id, Sc); Order.Add(Id);
        finally
          Root.Free;
        end;
      end;
    end;

    { emit in (category, id) order; optional single-category filter }
    Res:= TList<TRuleInfo>.Create;
    try
      for Id in Order do
      begin
        R:= ById[Id];
        if (ACategory = '') or SameText(R.Category, ACategory) then Res.Add(R);
      end;
      Res.Sort(TComparer<TRuleInfo>.Construct(
        function(const A, B: TRuleInfo): Integer
        begin
          Result:= CompareText(A.Category, B.Category);
          if Result = 0 then Result:= CompareText(A.Id, B.Id);
        end));
      Result:= Res.ToArray;
    finally
      Res.Free;
    end;
  finally
    Order.Free;
    ById.Free;
  end;
end;

class function TRuleCatalog.Summarize(const ACatalog: TArray<TRuleInfo>): TCatalogSummary;
var
  Counts: TDictionary<string, Integer>;
  Order : TList<string>;
  R     : TRuleInfo;
  C     : string;
  N     : Integer;
begin
  Counts:= TDictionary<string, Integer>.Create;
  Order:= TList<string>.Create;
  try
    Result.Total:= Length(ACatalog);
    Result.PerCategory:= nil;
    for R in ACatalog do
    begin
      if Counts.TryGetValue(R.Category, N) then Counts[R.Category]:= N + 1
      else begin Counts.Add(R.Category, 1); Order.Add(R.Category); end;
    end;
    Result.Categories:= Order.Count;
    for C in Order do
      Result.PerCategory:= Result.PerCategory + [TPair<string, Integer>.Create(C, Counts[C])];
  finally
    Order.Free;
    Counts.Free;
  end;
end;

end.
```

- [ ] **Step 4: Run the console test to verify it passes**

Run:
```powershell
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1
```
Expected: all PASS, `rulecatalog-tests: N pass / 0 fail / N total`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/lint/DRagLint.Lint.RuleCatalog.pas tests/rules-catalog/RuleCatalogTests.dpr tests/rules-catalog/run_rulecatalog_tests.ps1
git commit -m "feat(catalog): TRuleInfo + built-in rule registry (v0.69 D1a)"
```

---

## Task 2: Merge `.scm` sidecars + summary (extend the console test)

**Files:**
- Modify: `tests/rules-catalog/RuleCatalogTests.dpr` (add a `TestMerge` block)

**Interfaces:**
- Consumes: `TRuleCatalog.BuildCatalog`, `TRuleCatalog.Summarize` (Task 1).

(The `.scm` merge + summary are already implemented in Task 1's unit; this task verifies them against the real `rules\` dir and locks the behavior.)

- [ ] **Step 1: Add the failing merge test**

In `tests/rules-catalog/RuleCatalogTests.dpr`, add this procedure and call it from the main block after `TestRegistry`:
```pascal
procedure TestMerge;
var
  Cat: TArray<TRuleInfo>;
  Info: TRuleInfo;
  Sum: TCatalogSummary;
  P: TPair<string, Integer>;
  NamingCount: Integer;
begin
  // point at the repo rules/ dir (two levels up from tests\rules-catalog)
  Cat:= TRuleCatalog.BuildCatalog('..\..\rules', '');
  Check('catalog has >= 100 rules', Length(Cat) >= 100);

  // a known .scm rule is present, source scm, sensible category
  Check('goto-statement present', Find(Cat, 'goto-statement', Info));
  Check('goto-statement source scm', Info.Source = 'scm');
  Check('goto-statement category structure', Info.Category = 'structure');

  // a known security .scm rule
  Check('sql-injection-concat present + scm + security',
    Find(Cat, 'sql-injection-concat', Info) and (Info.Source = 'scm') and (Info.Category = 'security'));

  // built-in still wins dedup + keeps builtin source
  Check('too-many-parameters still builtin after merge',
    Find(Cat, 'too-many-parameters', Info) and (Info.Source = 'builtin'));

  // summary: non-zero total + category count, naming bucket present
  Sum:= TRuleCatalog.Summarize(Cat);
  Check('summary total matches length', Sum.Total = Length(Cat));
  Check('summary categories >= 8', Sum.Categories >= 8);
  NamingCount:= 0;
  for P in Sum.PerCategory do if P.Key = 'naming' then NamingCount:= P.Value;
  Check('summary naming count = 9', NamingCount = 9);

  // category filter returns only that category
  Cat:= TRuleCatalog.BuildCatalog('..\..\rules', 'naming');
  Check('category filter naming -> 9 rules', Length(Cat) = 9);
  for Info in Cat do
    if Info.Category <> 'naming' then begin Check('filtered all naming', False); Break; end;
end;
```
And add `TestMerge;` after `TestRegistry;` in the main `begin ... end.` block.

- [ ] **Step 2: Run -- verify pass**

Run:
```powershell
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1
```
Expected: all PASS (registry + merge), exit 0. If `goto-statement`/`sql-injection-concat` category assertions fail, the `ScmCategory` map in the unit is wrong for that id -- fix the map, not the test.

- [ ] **Step 3: Commit**

```bash
git add tests/rules-catalog/RuleCatalogTests.dpr
git commit -m "test(catalog): verify .scm merge, dedup, summary, category filter (v0.69 D1a)"
```

---

## Task 3: `DoRules` CLI command + wiring + CLI test

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (new `DoRules`; dispatch; `--category` arg parse; help/usage)
- Modify: `src/cli/drag-lint.dpr`, `src/cli/drag-lint.dproj` (register the unit)
- Create: `tests/rules-catalog/run_rules_cli_test.ps1`

**Interfaces:**
- Consumes: `DRagLint.Lint.RuleCatalog` (Tasks 1-2).
- Produces: the `rules` command; `--category` populates a new `TArgs.RuleCategory` field.

- [ ] **Step 1: Write the failing CLI test**

Create `tests/rules-catalog/run_rules_cli_test.ps1`:
```powershell
# End-to-end test of `drag-lint rules` (text + --json) against the repo rules/.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

# --json
$json = & $exe rules --json --rules-dir rules 2>$null | ConvertFrom-Json
Assert "json has rules array" ($null -ne $json.rules)
Assert "json rule count >= 100" ($json.rules.Count -ge 100)
$tmp = $json.rules | Where-Object { $_.id -eq 'too-many-parameters' }
Assert "too-many-parameters present" ($null -ne $tmp)
Assert "too-many-parameters category complexity" ($tmp.category -eq 'complexity')
Assert "too-many-parameters source builtin" ($tmp.source -eq 'builtin')
Assert "too-many-parameters has threshold=7" ($tmp.params.Count -eq 1 -and $tmp.params[0].name -eq 'threshold' -and "$($tmp.params[0].default)" -eq '7')
$goto = $json.rules | Where-Object { $_.id -eq 'goto-statement' }
Assert "goto-statement present + scm" ($null -ne $goto -and $goto.source -eq 'scm')
Assert "summary total > 0" ($json.summary.total -ge 100)
Assert "summary has per-category" ($json.summary.per_category.Count -ge 8)

# text mode: header line with counts + category filter
$txt = & $exe rules --rules-dir rules 2>$null
Assert "text mode has a counts header" (($txt -join "`n") -match 'rules across \d+ categories')
$ntxt = & $exe rules --category naming --rules-dir rules 2>$null
Assert "category filter naming mentions reserved-word-casing" (($ntxt -join "`n") -match 'reserved-word-casing')

Write-Host ""
if ($fail -gt 0) { Write-Host "rules-cli: $fail FAIL"; exit 1 } else { Write-Host "rules-cli: all pass"; exit 0 }
```

- [ ] **Step 2: Run -- verify it fails (command not implemented)**

Run:
```powershell
pwsh -File tests\rules-catalog\run_rules_cli_test.ps1
```
Expected: FAIL -- `drag-lint rules` is unknown so output is empty / not JSON.

- [ ] **Step 3: Add the `--category` arg + `TArgs.RuleCategory` field**

In `src/cli/DRagLint.CLI.pas`, in the `TArgs` record (near `RulesDir : string;` ~line 96) add:
```pascal
    RuleCategory    : string        ; // --category <name>: filter `rules` output
```
In the argument-parse loop, after the `--rules-dir` handling (~line 474-478) add:
```pascal
    else if (A = '--category') and (i < ParamCount) then
    begin
      Inc(i);
      Result.RuleCategory:= ParamStr(i);
    end
```

- [ ] **Step 4: Add the `DoRules` handler**

In `src/cli/DRagLint.CLI.pas`, add `DRagLint.Lint.RuleCatalog` to the `uses` clause (near the other `DRagLint.Lint.*` units, e.g. after `DRagLint.Lint.Config`). Then add this function before the main dispatch (e.g. just before `DoLint` or near the other `Do*` handlers):
```pascal
/// <summary>`drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]` --
/// emit the full rule catalog (built-ins + external .scm). Default = grouped text
/// table; --json = the structured catalog + summary.</summary>
function DoRules(const AArgs: TArgs): Integer;
var
  Cat : TArray<TRuleInfo>;
  Sum : TCatalogSummary;
  R   : TRuleInfo;
  P   : TRuleParam;
  Pr  : TPair<string, Integer>;
  Sb  : TStringBuilder;
  CurCat: string;
  PJson : TJSONArray;
  procedure AddParamsJson(AObj: TJSONObject; const AParams: TArray<TRuleParam>);
  var PA: TJSONArray; Q: TRuleParam; PO: TJSONObject;
  begin
    PA:= TJSONArray.Create;
    for Q in AParams do
    begin
      PO:= TJSONObject.Create;
      PO.AddPair('name', Q.Name);
      PO.AddPair('type', Q.ParamType);
      PO.AddPair('default', Q.DefaultVal);
      PA.AddElement(PO);
    end;
    AObj.AddPair('params', PA);
  end;
begin
  Cat:= TRuleCatalog.BuildCatalog(AArgs.RulesDir, AArgs.RuleCategory);
  Sum:= TRuleCatalog.Summarize(Cat);

  if AArgs.AsJson then
  begin
    var Root: TJSONObject:= TJSONObject.Create;
    try
      var Arr: TJSONArray:= TJSONArray.Create;
      for R in Cat do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('id', R.Id);
        O.AddPair('category', R.Category);
        O.AddPair('title', R.Title);
        O.AddPair('default_severity', R.DefaultSeverity);
        O.AddPair('default_enabled', TJSONBool.Create(R.DefaultEnabled));
        O.AddPair('source', R.Source);
        AddParamsJson(O, R.Params);
        Arr.AddElement(O);
      end;
      Root.AddPair('rules', Arr);
      var SumO: TJSONObject:= TJSONObject.Create;
      SumO.AddPair('total', TJSONNumber.Create(Sum.Total));
      SumO.AddPair('categories', TJSONNumber.Create(Sum.Categories));
      var PcA: TJSONArray:= TJSONArray.Create;
      for Pr in Sum.PerCategory do
      begin
        var PcO: TJSONObject:= TJSONObject.Create;
        PcO.AddPair('category', Pr.Key);
        PcO.AddPair('count', TJSONNumber.Create(Pr.Value));
        PcA.AddElement(PcO);
      end;
      SumO.AddPair('per_category', PcA);
      Root.AddPair('summary', SumO);
      Writeln(Root.ToJSON);
    finally
      Root.Free;
    end;
    Exit(0);
  end;

  { text mode: header + grouped table }
  Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine(Format('%d rules across %d categories', [Sum.Total, Sum.Categories]));
    CurCat:= #1; { sentinel so the first real category prints a header }
    for R in Cat do
    begin
      if R.Category <> CurCat then
      begin
        CurCat:= R.Category;
        Sb.AppendLine('');
        Sb.AppendLine('[' + CurCat + ']');
      end;
      var Flags: string:= R.DefaultSeverity;
      if not R.DefaultEnabled then Flags:= Flags + ', off';
      if Length(R.Params) > 0 then
      begin
        var Names: string:= '';
        for P in R.Params do
        begin
          if Names <> '' then Names:= Names + ',';
          Names:= Names + P.Name + '=' + P.DefaultVal;
        end;
        Flags:= Flags + '; ' + Names;
      end;
      Sb.AppendLine(Format('  %-34s %-8s (%s)', [R.Id, R.Source, Flags]));
    end;
    Writeln(Sb.ToString);
  finally
    Sb.Free;
  end;
  Result:= 0;
end;
```
(If `System.JSON` / `System.Generics.Collections` are not already in the CLI `uses`, add them. The CLI already uses `System.JSON` elsewhere.)

- [ ] **Step 5: Dispatch the command + help**

In the command dispatch chain (`else if Args.Command = ...`, ~line 9096), add after the `lint` line:
```pascal
    else if Args.Command = 'rules'             then Result:= DoRules           (AArgs)
```
(Match the surrounding arg name -- the chain uses `Args`; if so write `(Args)`.)

In the usage/help text (the `PrintUsage`/help block that lists commands, e.g. near the other `Writeln('  drag-lint ...')` lines ~line 220-285), add:
```pascal
  Writeln('  drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]   - list every lint rule (catalog)');
```

- [ ] **Step 6: Register the unit in the project files**

In `src/cli/drag-lint.dpr`, in the `uses` clause, add a line next to the other `DRagLint.Lint.*` entries:
```pascal
  DRagLint.Lint.RuleCatalog in '..\lint\DRagLint.Lint.RuleCatalog.pas',
```
In `src/cli/drag-lint.dproj`, next to the other `<DCCReference Include="..\lint\DRagLint.Lint.*.pas"/>` lines, add:
```xml
        <DCCReference Include="..\lint\DRagLint.Lint.RuleCatalog.pas"/>
```

- [ ] **Step 7: Build the Win64 CLI**

```powershell
Get-Process drag-lint,drag_lint_graph -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d1a-build.log" -RedirectStandardError "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d1a-build.err"
Get-Content "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d1a-build.log" -Tail 5
```
Expected: `OK: staged Win64 drag-lint.exe`, no `Error`/`E2xxx`/`F2xxx`.

- [ ] **Step 8: Run the CLI test**

```powershell
pwsh -File tests\rules-catalog\run_rules_cli_test.ps1
```
Expected: `rules-cli: all pass`, exit 0.

- [ ] **Step 9: Confirm no regression of the existing lint harness**

The new command and unit do not touch the lint path, but the CLI was rebuilt:
```powershell
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
```
Expected: `lint-tests: 117 pass / 0 fail / 117 total`.

- [ ] **Step 10: Commit (source only -- NOT the exe)**

```bash
git add src/cli/DRagLint.CLI.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj tests/rules-catalog/run_rules_cli_test.ps1
git commit -m "feat(catalog): drag-lint rules command (text + --json) + CLI test (v0.69 D1a)"
```

---

## Task 4: Documentation

**Files:**
- Modify: `rules/README.md` (note the catalog command as the canonical rule source)
- Modify: `CHANGELOG.md` (add to the v0.69 in-progress section)

- [ ] **Step 1: README -- document the catalog command**

In `rules/README.md`, near the top under `## Rule files` (after the intro), add a subsection:
```markdown
## The rule catalog (`drag-lint rules`)

`drag-lint rules` is the single machine-readable source of truth for every rule --
built-in and external `.scm`:

```
drag-lint rules                       # grouped text table + a "N rules across M categories" header
drag-lint rules --json                # structured catalog: [{id,category,title,default_severity,default_enabled,source,params}] + summary
drag-lint rules --category naming      # only one category
drag-lint rules --rules-dir <dir>      # point at a specific rules folder (default <exe-dir>\rules)
```

Built-in rules carry their category/severity/params from an in-code registry
(`DRagLint.Lint.RuleCatalog`); external `.scm` rules contribute id/severity/message
from their sidecar `.json`. This command replaces the hand-maintained rule table
below as the canonical inventory.
```

- [ ] **Step 2: CHANGELOG -- add to the v0.69 in-progress section**

In `CHANGELOG.md`, under the existing `## v0.69.0-alpha (in progress)` heading, add a new subsection after the D3 "Added (naming ...)" block:
```markdown
### Added (rule catalog -- D1a)

- **`drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]`** -- a single
  machine-readable catalog of every rule (built-in + external `.scm`) with id,
  category, title, default severity, default-enabled, source, and parameters, plus
  per-category and total counts. New unit `DRagLint.Lint.RuleCatalog` holds the
  built-in registry; `.scm` rules are merged from their sidecar `.json`.
```

- [ ] **Step 3: Commit**

```bash
git add rules/README.md CHANGELOG.md
git commit -m "docs(catalog): document drag-lint rules as the canonical rule inventory (v0.69 D1a)"
```

---

## Task 5: Encoding normalize + final verification

- [ ] **Step 1: Normalize encoding on the new/edited source + test files**

```powershell
Set-Location "C:\Projects\Delphi-RAG-lint"
$files = @(
  'src\lint\DRagLint.Lint.RuleCatalog.pas',
  'src\cli\DRagLint.CLI.pas',
  'src\cli\drag-lint.dpr',
  'tests\rules-catalog\RuleCatalogTests.dpr',
  'tests\rules-catalog\run_rulecatalog_tests.ps1',
  'tests\rules-catalog\run_rules_cli_test.ps1'
)
foreach ($f in $files) {
  $t = [IO.File]::ReadAllText($f)
  $t = $t -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
  $bytes = [IO.File]::ReadAllBytes($f)
  if ($bytes | Where-Object { $_ -gt 127 }) { Write-Host "NON-ASCII in $f" -ForegroundColor Red }
}
Write-Host "encoding normalized"
```
Expected: `encoding normalized`, no `NON-ASCII`. (`.dproj` is XML -- leave its existing line endings; if you normalized it, that's fine too.)

- [ ] **Step 2: Full regression (all three relevant harnesses)**

```powershell
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1 | Select-Object -Last 1
pwsh -File tests\rules-catalog\run_rules_cli_test.ps1 | Select-Object -Last 1
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1 | Select-Object -Last 1
```
Expected: rulecatalog all pass; rules-cli all pass; `lint-tests: 117 ... 0 fail`; `lintconfig-tests: 30 ... 0 fail`.

- [ ] **Step 3: ORM3 real-code sanity (the catalog is static, but confirm counts are sane)**

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
& $exe rules --rules-dir rules | Select-Object -First 1   # the counts header
(& $exe rules --json --rules-dir rules | ConvertFrom-Json).summary.per_category | Format-Table
```
Expected: a header like `116 rules across 12 categories` (exact numbers may differ); per-category counts sane (naming=9, complexity=6, etc.).

- [ ] **Step 4: Commit any normalization-only changes + report**

```bash
git add -A
git commit -m "chore(catalog): CRLF/ASCII normalize v0.69 D1a files" || echo "nothing to normalize"
git status --porcelain
git log --oneline -6
```
Report D1a done: `drag-lint rules` (text + `--json`) emits the full catalog with category/params/counts; console + CLI tests green; lint harness unaffected. **Next: D1b (the IDE "Lint Options" tab) consumes `drag-lint rules --json`.**

---

## Self-Review (completed by plan author)

**Spec coverage (v0.69 spec section 1a):**
- `drag-lint rules [--json] [--category] [--rules-dir]` -> Task 3. ✓
- Per-rule record (id/category/title/default_severity/default_enabled/source/params) -> Task 1 `TRuleInfo` + Task 3 JSON. ✓
- Built from two sources merged: in-code registry + `.scm` sidecar jsons; builtin wins dedup -> Task 1 (`BuildCatalog`). ✓
- Parameterized built-ins map to ThresholdFor names + naming knobs -> Task 1 registry params. ✓
- Categories = the 12 canonical buckets; scm default `other` -> Global Constraints + `ScmCategory`. ✓
- Counts: total + per-category (`--json` summary; text header `N rules across M categories`) -> Task 1 `Summarize` + Task 3. ✓
- CLI test asserting a known built-in (too-many-parameters + threshold), a known scm (goto-statement, source scm), category bucketing, non-zero summary -> Task 3 CLI test (+ Task 1-2 console tests). ✓
- README notes the catalog as canonical -> Task 4. ✓

**Placeholder scan:** no TBD/"handle edge cases"; the registry is fully enumerated; the `<...>` in scratchpad log paths are concrete absolute paths.

**Type/name consistency:** `TRuleParam`(Name/ParamType/DefaultVal), `TRuleInfo`(Id/Category/Title/DefaultSeverity/Source/DefaultEnabled/Params), `TCatalogSummary`(Total/Categories/PerCategory), `TRuleCatalog.BuiltinRegistry/BuildCatalog/Summarize/ScmCategory`, `TArgs.RuleCategory`, JSON keys (`id/category/title/default_severity/default_enabled/source/params`, `summary.total/categories/per_category[].category/count`, `params[].name/type/default`) -- all used identically across the unit, the handler, and the two tests.

**Known risk flagged:** the built-in registry's per-rule severity/category is hand-encoded from the live-code inventory and can drift if a rule's emitted severity later changes. The console test pins representatives + a >=55 count + no-dup + fully-populated guard; broaden the pinned set if a drift bug appears. The `>= 100`/`>= 116` total in tests is a floor (rule set only grows), not an exact equality, so adding rules won't break the tests.
