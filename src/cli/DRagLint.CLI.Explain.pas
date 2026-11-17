unit DRagLint.CLI.Explain;

{ drag-lint 1.52 -- verb `explain <rule-id>`: what a rule means, why it matters,
  bad / good example, default, fixable, how to suppress.
  Scaffold created by lane FRAME: DRagLint.CLI.pas parses the flags and calls
  RunExplain in ONE dispatch line; everything else lives here. Lane EXPLAIN
  owns this unit (its signature is the FRAME contract).

  Sources, in this order, per section:
    Meaning        rule sidecar "message" (rules\<id>.json), else the catalog title
    Why it matters sidecar "why", else the wiki table row (`| `id` | ... | text |`
                   in docs\wiki\*.md, found by walking up from the rules folder),
                   else a per-category sentence
    Bad / Good     sidecar "example_bad" / "example_good" (strings); a rule without
                   them prints a one-line "no example recorded" note
    Default, Fixable, Params, Standards   the rule catalog (TRuleCatalog.BuildCatalog)
    Suppress       fixed text: the dl:ok line marker, `allow`, `lint --disable` }

interface

/// <summary>Runs `drag-lint explain &lt;rule-id&gt; [--json] [--rules-dir D]`.</summary>
/// <param name="pRuleId">The rule id (first positional after `explain`, or --rule), '' when absent.</param>
/// <param name="pRulesDir">--rules-dir value, '' = the engine's default rules folder.</param>
/// <param name="pJson">--json (or --format json).</param>
/// <returns>Process exit code: 0 known id, 2 unknown id or usage error.</returns>
/// <remarks>Read-only; needs no index. Text mode prints the sections Rule, Meaning,
/// Why it matters, Bad, Good, Default, Fixable, Suppress on stdout; `--json` prints
/// ONE object with the same facts. An unknown id prints the nearest ids (stderr in
/// text mode; `error` + `nearest` in the JSON object) and returns 2, as does an
/// empty id.</remarks>
function RunExplain(const pRuleId, pRulesDir: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils
, System.IOUtils
, System.JSON
, System.Math
, System.Generics.Collections
, System.Generics.Defaults
, DRagLint.Lint.RuleCatalog
, DRagLint.Lint.Autofix
  ;

const
  NEAREST_MAX    = 5;
  WIKI_WALK_UP   = 8;
  EXIT_UNKNOWN   = 2;
  WIKI_ROW_MIN_CELLS = 4;

type
  /// <summary>Everything the verb prints about one rule.</summary>
  TExplainFacts = record
    Info       : TRuleInfo;
    Message    : string;
    Why        : string;
    WikiPage   : string;
    ExampleBad : string;
    ExampleGood: string;
    Fixable    : Boolean;
    ManualOnly : Boolean;
  end;

{ One sentence per catalog category: the reason a rule of that bucket exists. }
function CategoryWhy(const pCategory: string): string;
const
  GENERIC_WHY = 'See the Meaning line; the rule reports code matching that description.';
  CATEGORY_WHY: array[0..16] of array[0..1] of string = (
    ('bug-patterns', 'The construct is a known source of wrong behaviour at run time.'),
    ('complexity', 'Code this tangled is hard to read, test and change safely.'),
    ('data-flow', 'A value is used, lost or overwritten in a way the code probably did not intend.'),
    ('dead-code', 'Code that can never matter still costs reading time and hides real changes.'),
    ('documentation', 'Doc comments are the contract other code and tools rely on; drift misleads.'),
    ('firedac', 'Misused FireDAC calls leak cursors or transactions and corrupt data access.'),
    ('metrics', 'A size or coupling figure past its threshold predicts defects and slow change.'),
    ('modernize', 'A newer language or RTL feature does the same job with less code and fewer mistakes.'),
    ('naming', 'Consistent names let a reader tell a field, parameter and type apart at a glance.'),
    ('platform', 'The code behaves differently, or breaks, on another platform or compiler target.'),
    ('policy', 'A project-level convention the team chose to enforce.'),
    ('project-wide', 'The problem only shows when the whole project is looked at, not one unit.'),
    ('refactoring', 'The shape of the code points to a cleaner structure that is cheap to reach now.'),
    ('resource-lifetime', 'An object, handle or lock is created without a guaranteed release, so it leaks or dangles.'),
    ('review-markers', 'A dl:ok review marker must stay truthful, or the suppression hides real findings.'),
    ('security', 'The pattern can expose data or let an attacker run or reach something unintended.'),
    ('structure', 'Module layout and dependencies decide how far a change ripples.'));
var
  I: Integer;
begin
  Result:= GENERIC_WHY;
  for I:= Low(CATEGORY_WHY) to High(CATEGORY_WHY) do
    if CATEGORY_WHY[I][0] = pCategory then Exit(CATEGORY_WHY[I][1]);
end; // function

{ Classic two-row Levenshtein distance. }
function EditDistance(const pA, pB: string): Integer;
var
  Prev, Cur: TArray<Integer>;
  I, J, Cost: Integer;
begin
  SetLength(Prev, Length(pB) + 1);
  SetLength(Cur, Length(pB) + 1);
  for J:= 0 to Length(pB) do Prev[J]:= J;
  for I:= 1 to Length(pA) do
  begin
    Cur[0]:= I;
    for J:= 1 to Length(pB) do
    begin
      Cost:= Ord(pA[I] <> pB[J]);
      Cur[J]:= Min(Min(Prev[J] + 1, Cur[J - 1] + 1), Prev[J - 1] + Cost);
    end; // for J
    Prev:= Copy(Cur);
  end; // for I
  Result:= Prev[Length(pB)];
end; // function

{ The ids nearest to pId: ids containing it (or contained in it) first, then by edit distance. }
function NearestIds(const pCatalog: TArray<TRuleInfo>; const pId: string): TArray<string>;
var
  Rows: TList<TPair<Integer, string>>;
  R   : TRuleInfo;
  Key : string;
  Lo  : string;
  I   : Integer;
  Res : TList<string>;
begin
  Lo:= LowerCase(pId);
  Rows:= TList<TPair<Integer, string>>.Create;
  Res := TList<string>.Create;
  try
    for R in pCatalog do
    begin
      Key:= LowerCase(R.Id);
      if Key.Contains(Lo) or Lo.Contains(Key) then
        Rows.Add(TPair<Integer, string>.Create(0, R.Id))
      else
        Rows.Add(TPair<Integer, string>.Create(1 + EditDistance(Lo, Key), R.Id));
    end; // for
    Rows.Sort(TComparer<TPair<Integer, string>>.Construct(
      function(const A, B: TPair<Integer, string>): Integer
      begin
        Result:= A.Key - B.Key;
        if Result = 0 then Result:= CompareStr(A.Value, B.Value);
      end));
    for I:= 0 to Min(NEAREST_MAX, Rows.Count) - 1 do Res.Add(Rows[I].Value);
    Result:= Res.ToArray;
  finally
    Res.Free;
    Rows.Free;
  end; // try
end; // function

{ The rules folder the catalog reads: --rules-dir, else <exe-dir>\rules. }
function EffectiveRulesDir(const pRulesDir: string): string;
begin
  Result:= if pRulesDir <> '' then pRulesDir else TPath.Combine(ExtractFilePath(ParamStr(0)), 'rules');
end;

{ String value of a top-level key of the rule's sidecar, '' when absent. }
function SidecarString(const pRulesDir, pId, pKey: string): string;
var
  Path: string;
  Root: TJSONValue;
  V   : TJSONValue;
begin
  Result:= '';
  Path:= TPath.Combine(EffectiveRulesDir(pRulesDir), pId + '.json');
  if not TFile.Exists(Path) then Exit;
  Root:= nil;
  try
    Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));  // dl:ok taint-path-traversal@cffe -- REVIEWED 2026-11-17 v152 EXPLAIN: the path is the operator's own --rules-dir (or <exe-dir>\rules) joined with a catalog rule id; a local CLI reading its own rules folder, no remote caller
    if Root is TJSONObject then
    begin
      V:= TJSONObject(Root).GetValue(pKey);
      if V is TJSONString then Result:= V.Value;
    end;
  except  // dl:ok bare-except@86a2 -- contract: an unreadable or malformed sidecar just means "no extra text"; the catalog row still answers
    Result:= '';
  end; // try
  Root.Free;
end; // function

{ Last non-empty cell of the markdown table row that starts with `| `id` |`, '' when absent. }
function WikiRowText(const pFile, pId: string): string;
var
  Line, Cell: string;
  Cells: TArray<string>;
  Lead : string;
begin
  Result:= '';
  Lead:= '| `' + pId + '` |';
  for Line in TFile.ReadAllLines(pFile) do
    if Line.StartsWith(Lead) then
    begin
      Cells:= Line.Split(['|']);
      if Length(Cells) >= WIKI_ROW_MIN_CELLS then
        for Cell in Cells do
          if Trim(Cell) <> '' then Result:= Trim(Cell);
      Exit;
    end; // if
end; // function

{ Finds docs\wiki above the rules folder and returns the page + row text for the id. }
procedure FindWikiRow(const pRulesDir, pId: string; out pPage, pText: string);
var
  Dir, WikiDir, F: string;
  Up: Integer;
begin
  pPage:= '';
  pText:= '';
  Dir:= ExcludeTrailingPathDelimiter(ExpandFileName(EffectiveRulesDir(pRulesDir)));
  for Up:= 1 to WIKI_WALK_UP do
  begin
    Dir:= ExtractFileDir(Dir);
    if Dir = '' then Exit;
    WikiDir:= TPath.Combine(TPath.Combine(Dir, 'docs'), 'wiki');
    if TDirectory.Exists(WikiDir) then
    begin
      for F in TDirectory.GetFiles(WikiDir, '*.md') do  // dl:ok taint-path-traversal@fd50 -- REVIEWED 2026-11-17 v152 EXPLAIN: WikiDir is docs\wiki found by walking up from the operator's own rules folder; read-only listing for a local CLI
      begin
        pText:= WikiRowText(F, pId);
        if pText <> '' then
        begin
          pPage:= ExtractFileName(F);
          Exit;
        end;
      end; // for
      Exit;
    end;
  end; // for Up
end; // procedure

function GatherFacts(const pInfo: TRuleInfo; const pRulesDir: string): TExplainFacts;
var
  WikiText: string;
begin
  Result.Info:= pInfo;
  Result.Message:= SidecarString(pRulesDir, pInfo.Id, 'message');
  if Result.Message = '' then Result.Message:= pInfo.Title;
  FindWikiRow(pRulesDir, pInfo.Id, Result.WikiPage, WikiText);
  Result.Why:= SidecarString(pRulesDir, pInfo.Id, 'why');
  if Result.Why = '' then Result.Why:= WikiText;
  if Result.Why = '' then Result.Why:= CategoryWhy(pInfo.Category);
  Result.ExampleBad := SidecarString(pRulesDir, pInfo.Id, 'example_bad');
  Result.ExampleGood:= SidecarString(pRulesDir, pInfo.Id, 'example_good');
  Result.Fixable    := IsFixableRule(pInfo.Id);
  Result.ManualOnly := IsFixManualOnly(pInfo.Id);
end; // function

function SuppressLine(const pId: string): string;
begin
  Result:= '// dl:ok ' + pId + ' -- <why this finding is acceptable>';
end;

function ExampleText(const pText, pFallback: string): string;
begin
  Result:= if pText <> '' then pText else pFallback;
end;

procedure PrintText(const pFacts: TExplainFacts);
const
  NO_EXAMPLE = '(no example recorded for this rule; run: drag-lint lint <unit.pas> --rule %s)';
var
  P: TRuleParam;
  Sev: string;
begin
  Writeln('Rule:           ', pFacts.Info.Id, '  [', pFacts.Info.Category, ', ', pFacts.Info.Source, ']');
  Writeln('Meaning:        ', pFacts.Message);
  Writeln('Why it matters: ', pFacts.Why);
  Writeln('Bad:            ', ExampleText(pFacts.ExampleBad, Format(NO_EXAMPLE, [pFacts.Info.Id])));
  Writeln('Good:           ', ExampleText(pFacts.ExampleGood, '(see Bad)'));
  Sev:= pFacts.Info.DefaultSeverity;
  Writeln('Default:        ', if pFacts.Info.DefaultEnabled then 'ON' else 'OFF', ', severity ', Sev);
  Writeln('Fixable:        ', if not pFacts.Fixable then 'no'
    else if pFacts.ManualOnly then 'yes (manual only: --fix-rule, never batch)' else 'yes (drag-lint fix)');
  for P in pFacts.Info.Params do
    Writeln('Parameter:      ', P.Name, ' (', P.ParamType, ') default ', P.DefaultVal);
  if pFacts.WikiPage <> '' then Writeln('Wiki page:      ', pFacts.WikiPage);
  Writeln('Suppress:       one finding   ', SuppressLine(pFacts.Info.Id));
  Writeln('                or recorded   drag-lint allow <unit.pas> --fix-line <L> --fix-rule ', pFacts.Info.Id, ' --apply');
  Writeln('                whole run     drag-lint lint <path> --disable ', pFacts.Info.Id);
end; // procedure

procedure PrintJson(const pFacts: TExplainFacts);
var
  O, Sup: TJSONObject;
  Pars  : TJSONArray;
  P     : TRuleParam;
  PO    : TJSONObject;
begin
  O:= TJSONObject.Create;
  try
    O.AddPair('id', pFacts.Info.Id);
    O.AddPair('category', pFacts.Info.Category);
    O.AddPair('source', pFacts.Info.Source);
    O.AddPair('meaning', pFacts.Message);
    O.AddPair('why', pFacts.Why);
    O.AddPair('example_bad', pFacts.ExampleBad);
    O.AddPair('example_good', pFacts.ExampleGood);
    O.AddPair('default_severity', pFacts.Info.DefaultSeverity);
    O.AddPair('default_enabled', TJSONBool.Create(pFacts.Info.DefaultEnabled));
    O.AddPair('fixable', TJSONBool.Create(pFacts.Fixable));
    O.AddPair('fix_manual_only', TJSONBool.Create(pFacts.ManualOnly));
    O.AddPair('wiki_page', pFacts.WikiPage);
    Pars:= TJSONArray.Create;
    for P in pFacts.Info.Params do
    begin
      PO:= TJSONObject.Create;
      PO.AddPair('name', P.Name);
      PO.AddPair('type', P.ParamType);
      PO.AddPair('default', P.DefaultVal);
      Pars.AddElement(PO);
    end; // for
    O.AddPair('params', Pars);
    Sup:= TJSONObject.Create;
    Sup.AddPair('line_marker', SuppressLine(pFacts.Info.Id));
    Sup.AddPair('allow', 'drag-lint allow <unit.pas> --fix-line <L> --fix-rule ' + pFacts.Info.Id + ' --apply');
    Sup.AddPair('run', 'drag-lint lint <path> --disable ' + pFacts.Info.Id);
    O.AddPair('suppress', Sup);
    Writeln(O.ToJSON);
  finally
    O.Free;
  end; // try
end; // procedure

function ReportUnknown(const pCatalog: TArray<TRuleInfo>; const pId: string; pJson: Boolean): Integer;
var
  Near: TArray<string>;
  S   : string;
  O   : TJSONObject;
  A   : TJSONArray;
begin
  Near:= NearestIds(pCatalog, pId);
  if pJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair('error', 'unknown rule id: ' + pId);
      A:= TJSONArray.Create;
      for S in Near do A.Add(S);
      O.AddPair('nearest', A);
      Writeln(O.ToJSON);
    finally
      O.Free;
    end; // try
  end
  else
  begin
    Writeln(ErrOutput, 'explain: unknown rule id "', pId, '". Nearest ids:');
    for S in Near do Writeln(ErrOutput, '  ', S);
  end;
  Result:= EXIT_UNKNOWN;
end; // function

function RunExplain(const pRuleId, pRulesDir: string; pJson: Boolean): Integer;
var
  Catalog: TArray<TRuleInfo>;
  R      : TRuleInfo;
  Facts  : TExplainFacts;
begin
  if Trim(pRuleId) = '' then
  begin
    Writeln(ErrOutput, 'explain: a rule id is required -- drag-lint explain <rule-id> [--json] [--rules-dir <dir>]  (ids: drag-lint rules)');
    Exit(EXIT_UNKNOWN);
  end;
  Catalog:= TRuleCatalog.BuildCatalog(pRulesDir);
  for R in Catalog do
    if SameText(R.Id, Trim(pRuleId)) then
    begin
      Facts:= GatherFacts(R, pRulesDir);
      if pJson then PrintJson(Facts) else PrintText(Facts);
      Exit(0);
    end;
  Result:= ReportUnknown(Catalog, Trim(pRuleId), pJson);
end; // function

end.
