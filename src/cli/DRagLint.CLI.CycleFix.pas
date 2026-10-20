unit DRagLint.CLI.CycleFix;

// ---------------------------------------------------------------------------
// `drag-lint cycles --fix` -- the dry run (E18 Task 8): pick ONE circular group,
// take the planner's plan for it (DRagLint.Report.CyclePlan.VisitCyclePlans),
// add the mechanisability gate (stale-file, outside-roots, manual-edit) and
// print the verdict as the playbook text or as `cycle-fix/1` JSON
// (docs\superpowers\plans\2026-10-10-auto-cycle-fix.md, contract 4.4).
// Writes nothing to the project. Since Task 9 a mechanical verdict also stages the plan's result
// in a SHADOW TREE (anchored TTextEdits applied in memory, new units, project files); the
// shadow is what the dry run proves would be written. Applying (--apply) arrives with Tasks 10-12.
// ---------------------------------------------------------------------------

interface

uses
  System.Generics.Collections,
  DRagLint.Core.Interfaces, DRagLint.Project.OwnRoots, DRagLint.Report.CyclePlan, DRagLint.Refactor.TextEdit;

type
  /// <summary>The `cycles --fix` flags, as DoCycles parsed them.</summary>
  TCycleFixOptions = record
    /// <summary>--project: the .dproj (or .dpr) whose own roots bound the edit.</summary>
    Project: string;
    /// <summary>--db: the index of that project.</summary>
    Db: string;
    /// <summary>--platform, '' = win64; only echoed in the JSON.</summary>
    Platform: string;
    /// <summary>--apply (Tasks 9-12; refused with exit 2 today).</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-reindex (apply only).</summary>
    NoReindex: Boolean;
    /// <summary>--no-compile: skip the baseline build (the dry run has none yet).</summary>
    NoCompile: Boolean;
    /// <summary>--cycle: the value given (checked: must be 1 or more).</summary>
    CycleIndex: Integer;
    /// <summary>True when --cycle was on the command line.</summary>
    CycleGiven: Boolean;
    /// <summary>--unit: select the group holding this unit stem; '' = not given.</summary>
    UnitStem: string;
    /// <summary>--part: 'a', 'b', 'all' or '' (the group's default).</summary>
    Part: string;
    /// <summary>--format json.</summary>
    Json: Boolean;
    /// <summary>--shadow-out (debug): the directory the shadow tree is staged in; '' = DefaultShadowDir.</summary>
    ShadowOut: string;
  end;

/// <summary>The refusals the front end adds to the planner's own: outside-roots.</summary>
/// <param name="pView">The plan of one group.</param>
/// <param name="pOwn">The project's own roots (TOwnRoots.Load of the project folder).</param>
/// <returns>One refusal per touched file that is empty or outside every root.</returns>
/// <remarks>Pure: reads no file. stale-file needs the index and is added by RunCycleFix.
/// manual-edit is NOT added here: the planner's own refusals already name every manual
/// edit (TCyclePlanner.CaptureRefusals walks every touched file and the .dproj), so a gate
/// copy could never fire. TOwnRoots.IsOurs lets an empty path through, so an empty touched
/// path is refused explicitly.</remarks>
function MechanisabilityGate(const pView: TCyclePlanView; const pOwn: TOwnRoots): TArray<TRefusal>;

/// <summary>The default shadow directory: C:\TEMP\draglint_cyclefix_&lt;pid&gt;\.</summary>
/// <returns>The directory name with a trailing path delimiter; nothing is created.</returns>
function DefaultShadowDir: string;

/// <summary>Turns the edits of a plan into anchored TTextEdits.</summary>
/// <param name="pView">The plan of one group.</param>
/// <returns>Per edit of an existing file: a replace or delete becomes delete-lines (First..Last)
/// plus, for a replace, insert-lines after First-1; an insert-after becomes insert-lines after the
/// anchor line. Each carries ExpectLine/ExpectText (the first line of the plan's "Current text", or
/// the anchor line's text) as the applier's stale guard. A line that is blank or starts a comment
/// cannot be guarded by the applier (it never accepts a comment line as an anchor) and is left
/// unguarded; StageShadow checks every line exactly instead. Manual edits are skipped.</returns>
/// <remarks>Pure. Per file the edits are in top-to-bottom order of the playbook's list reversed, so
/// edits that tie on a line land in the file in the order a follower of the playbook produces.</remarks>
function ToTextEdits(const pView: TCyclePlanView): TArray<TTextEdit>;

/// <summary>Stages the result of a plan in a shadow directory without touching the project.</summary>
/// <param name="pView">The plan of one group.</param>
/// <param name="pProjectDir">The project folder; the shadow mirrors paths relative to it.
/// A file outside it is staged under `_outside\&lt;drive&gt;\...`.</param>
/// <param name="pShadowDir">Receives the staged files; existing files of the same name are overwritten.</param>
/// <returns>The refusals (kind anchor-mismatch) or an empty array when the shadow was written.</returns>
/// <remarks>Everything is computed in memory first; nothing is written when any refusal arises.
/// Refuses when a file is missing or a line of it differs from the plan's "Current text" / anchor
/// (compared exactly, as the follow-cycle-plan oracle does), when TTextEditApplier.RefusalOf finds
/// the edit set unappliable, when the applier drops an edit (line count check), or when a new unit's
/// file already exists. Edited files are written ANSI with the applier's CRLF; new units ASCII,
/// CRLF, one trailing CRLF.</remarks>
function StageShadow(const pView: TCyclePlanView; const pProjectDir, pShadowDir: string;
  pTamperAllowed: Boolean = False): TArray<TRefusal>;

/// <summary>True when the DRAGLINT_CYCLEFIX_TEST_TAMPER test seam may act: on a dry run only.</summary>
/// <param name="pOpts">The flags.</param>
/// <returns>False whenever --apply is set, whatever the environment says.</returns>
/// <remarks>The seam alters staged text without any anchor guard seeing it, so no write path may honour it.
/// Task 11: the apply writes from the shadow; every StageShadow call that feeds a write must pass
/// pTamperAllowed = False (the default).</remarks>
function TamperAllowed(const pOpts: TCycleFixOptions): Boolean;

/// <summary>Runs `cycles --fix` as a dry run and prints the result to stdout.</summary>
/// <param name="pOpts">The flags.</param>
/// <param name="pStore">Open index of the project; read only.</param>
/// <param name="pSccs">The circular groups, lower-case stems.</param>
/// <param name="pGraph">The uses graph the groups come from.</param>
/// <param name="pLibStore">Platform library index (read only) or nil.</param>
/// <returns>0 mechanical, 1 refused, 2 error (bad flags, no such group).</returns>
/// <remarks>Writes no file. The first mechanical group is chosen when neither --cycle nor --unit is given.</remarks>
function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  const pLibStore: ISymbolStore = nil): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.DateUtils, System.Hash,
  System.StrUtils;

const
  CExitMechanical = 0;
  CExitRefused    = 1;
  CExitError      = 2;
  CDefaultPlatform = 'win64';
  CSchema          = 'cycle-fix/1';
  CNeedsProject    = 'cycles --fix needs --project <X.dproj>';
  CVerdictOk       = 'Verdict: mechanical (dry run; add --apply to write)';
  CVerdictRefused  = 'Verdict: refused';
  CShadowLine      = 'Shadow tree: ';
  CMaxAsciiOrd     = 127;  // the last ASCII code point
  CTamperParts     = 3;    // File.pas|from|to

function MakeRefusal(const pKind, pSymbol, pFile, pReason: string; pLine: Integer): TRefusal;
begin
  Result.Kind    := pKind;
  Result.Symbol  := pSymbol;
  Result.FilePath:= pFile;
  Result.Reason  := pReason;
  Result.Line    := pLine;
end;

function MechanisabilityGate(const pView: TCyclePlanView; const pOwn: TOwnRoots): TArray<TRefusal>;
var
  L: TList<TRefusal>;
begin
  L:= TList<TRefusal>.Create;
  try
    for var P in pView.TouchedPaths do
      if (P = '') or not pOwn.IsOurs(P) then
        L.Add(MakeRefusal('outside-roots', '', P, 'the plan edits a file outside the project''s own roots', 0));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// True when APath's on-disk (mtime, sha) is what the index recorded; the same basis as
// DRagLint.Core.Indexer.IndexFile (raw bytes, ANSI-decoded for the sha).
function FileStampIsCurrent(const pStore: ISymbolStore; const pPath: string): Boolean;
begin
  if not TFile.Exists(pPath) then Exit(False);
  var Sha  := THashSHA2.GetHashString(TEncoding.ANSI.GetString(TFile.ReadAllBytes(pPath)));
  var Mtime:= DateTimeToUnix(TFile.GetLastWriteTime(pPath), False);
  Result:= pStore.FileIsUpToDate(pPath, Mtime, Sha);
end;

function StaleRefusals(const pStore: ISymbolStore; const pView: TCyclePlanView): TArray<TRefusal>;
var
  L: TList<TRefusal>;
begin
  L:= TList<TRefusal>.Create;
  try
    for var P in pView.TouchedPaths do
      if MatchText(ExtractFileExt(P), ['.pas', '.dpr']) and not FileStampIsCurrent(pStore, P) then
        L.Add(MakeRefusal('stale-file', '', P,
          'the file changed after it was indexed; reindex the project (drag-lint index --project ...) and retry', 0));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function GetCurrentProcessId: Cardinal; stdcall; external 'kernel32.dll' name 'GetCurrentProcessId';

function DefaultShadowDir: string;
begin
  Result:= Format('C:\TEMP\draglint_cyclefix_%d\', [GetCurrentProcessId]); // dl:ok hardcoded-absolute-path@6532 -- the debug shadow location is fixed by the E18 design; --shadow-out overrides it
end;

// The text the applier's stale guard can hold: '' for a blank line or one that starts a comment
// (AnchorIsValid never accepts a comment line as an anchor).
function TamperAllowed(const pOpts: TCycleFixOptions): Boolean;
begin
  Result:= not pOpts.Apply;
end;

function GuardText(const pLine: string): string;
begin
  Result:= Trim(pLine);
  if (Result <> '') and (StartsStr('//', Result) or StartsStr('{', Result) or StartsStr('(*', Result)) then
    Result:= '';
end;

function ToTextEdits(const pView: TCyclePlanView): TArray<TTextEdit>;
var
  L: TList<TTextEdit>;

  function Make(pKind: TTextEditKind; const pPath: string; pLine, pEndLine: Integer; const pText, pGuard: string;
    pGuardLine: Integer): TTextEdit;
  begin
    Result:= Default(TTextEdit);
    Result.FilePath  := pPath;
    Result.Kind      := pKind;
    Result.Line      := pLine;
    Result.EndLine   := pEndLine;
    Result.Text      := pText;
    Result.ExpectText:= pGuard;
    Result.ExpectLine:= if pGuard = '' then 0 else pGuardLine;
  end;

begin
  L:= TList<TTextEdit>.Create;
  try
    for var I:= High(pView.Edits) downto 0 do
    begin
      var E:= pView.Edits[I];
      if SameText(E.Kind, 'delete') or SameText(E.Kind, 'replace') then
      begin
        var Guard:= if Length(E.CurrentLines) > 0 then GuardText(E.CurrentLines[0]) else '';
        L.Add(Make(tekDeleteLines, E.FilePath, E.First, E.Last, '', Guard, E.First));
        if (E.Kind = 'replace') and (Length(E.NewLines) > 0) then
          L.Add(Make(tekInsertLines, E.FilePath, E.First - 1, 0, string.Join(#13#10, E.NewLines), Guard, E.First));
      end
      else if SameText(E.Kind, 'insert') and (Length(E.NewLines) > 0) then
        L.Add(Make(tekInsertLines, E.FilePath, E.First, 0, string.Join(#13#10, E.NewLines), GuardText(E.AnchorText), E.First));
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// The shadow path of pPath: relative to the project folder, else _outside\<drive>\rest.
function ShadowPathOf(const pShadowDir, pProjectDir, pPath: string): string;
begin
  var Full:= ExpandFileName(pPath);
  var Root:= IncludeTrailingPathDelimiter(ExpandFileName(pProjectDir));
  if StartsText(Root, Full) then Result:= Copy(Full, Length(Root) + 1, MaxInt)
  else Result:= '_outside\' + StringReplace(Full, ':', '', [rfReplaceAll]);
  Result:= IncludeTrailingPathDelimiter(pShadowDir) + TrimLeft(Result);
end;

function AnchorRefusal(const pFile, pReason: string; pLine: Integer): TRefusal;
begin
  Result:= MakeRefusal('anchor-mismatch', '', pFile, pReason, pLine);
end;

// Exact check of every edit of one file against the lines on disk; adds a refusal per mismatch.
procedure CheckAnchors(const pPath: string; const pView: TCyclePlanView; pLines: TStrings; pOut: TList<TRefusal>);
begin
  for var E in pView.Edits do
  begin
    if not SameText(E.FilePath, pPath) then Continue;
    if SameText(E.Kind, 'insert') then
    begin
      if (E.First < 1) or (E.First > pLines.Count) then
        pOut.Add(AnchorRefusal(pPath, Format('anchor line %d is beyond the end of the file (%d lines)', [E.First, pLines.Count]), E.First))
      else if Trim(pLines[E.First - 1]) <> Trim(E.AnchorText) then
        pOut.Add(AnchorRefusal(pPath, Format('the anchor line differs from the plan: expected [%s], found [%s]',
          [Trim(E.AnchorText), Trim(pLines[E.First - 1])]), E.First));
    end
    else if SameText(E.Kind, 'delete') or SameText(E.Kind, 'replace') then
    begin
      if Length(E.CurrentLines) <> E.Last - E.First + 1 then
        pOut.Add(AnchorRefusal(pPath, Format('the plan lists %d current line(s) for lines %d-%d',
          [Length(E.CurrentLines), E.First, E.Last]), E.First))
      else
        for var K:= 0 to High(E.CurrentLines) do
        begin
          var No:= E.First + K;
          if (No > pLines.Count) or (pLines[No - 1] <> E.CurrentLines[K]) then
          begin
            pOut.Add(AnchorRefusal(pPath, Format('line %d differs from the plan''s "Current text": expected [%s], found [%s]',
              [No, E.CurrentLines[K], if No > pLines.Count then '<end of file>' else pLines[No - 1]]), No));
            Break;
          end;
        end;
    end;
  end;
end;

// Lines the edits of pPath add minus lines they delete.
function NetLineChange(const pPath: string; const pEdits: TArray<TTextEdit>): Integer;
begin
  Result:= 0;
  for var E in pEdits do
  begin
    if not SameText(E.FilePath, pPath) then Continue;
    if E.Kind = tekDeleteLines then Dec(Result, E.EndLine - E.Line + 1)
    else Inc(Result, Length(E.Text.Replace(#13#10, #10).Split([#10])));
  end;
end;

function HasNonAscii(const pLines: TArray<string>): Boolean;
begin
  Result:= False;
  for var Ln in pLines do
    for var Ch in Ln do
      if Ord(Ch) > CMaxAsciiOrd then Exit(True);
end;

// Test seam, inert unless DRAGLINT_CYCLEFIX_TEST_TAMPER = 'File.pas|from|to' is set: replaces the first
// occurrence of `from` in that file's text as staging reads it (in memory only), so a runner can make the
// file differ from what the planner saw -- the one way to reach the anchor-mismatch refusal.
procedure ApplyTestTamper(const pPath: string; var pContent: string);
begin
  var Spec:= GetEnvironmentVariable('DRAGLINT_CYCLEFIX_TEST_TAMPER').Split(['|']);
  if (Length(Spec) = CTamperParts) and SameText(ExtractFileName(pPath), Spec[0]) then
    pContent:= StringReplace(pContent, Spec[1], Spec[2], []);
end;

// Refusals for text the file's encoding cannot carry faithfully: for an ANSI file anything non-ASCII
// that the edits insert (it may come from a file in another code page).
procedure CheckInsertedText(const pPath: string; const pView: TCyclePlanView; pEnc: TEncoding; pOut: TList<TRefusal>);
begin
  if pEnc = TEncoding.UTF8 then Exit;
  for var E in pView.Edits do
    if SameText(E.FilePath, pPath) and HasNonAscii(E.NewLines) then
    begin
      pOut.Add(MakeRefusal('non-ascii-text', '', pPath,
        'an inserted line holds a non-ASCII character and the file is ANSI; edit this file by hand', E.First));
      Exit;
    end;
end;

function StageShadow(const pView: TCyclePlanView; const pProjectDir, pShadowDir: string;
  pTamperAllowed: Boolean): TArray<TRefusal>;
type
  TStaged = record
    Path : string;
    Bytes: TBytes;
  end;
var
  Enc    : TEncoding;
  Refs   : TList<TRefusal>;
  Staged : TList<TStaged>;
  Edits  : TArray<TTextEdit>;
  Done   : TList<string>;
  Lines  : TStringList;
  Item   : TStaged;
begin
  Refs  := TList<TRefusal>.Create;
  Staged:= TList<TStaged>.Create;
  Done  := TList<string>.Create;
  Lines := TStringList.Create;
  try
    Edits:= ToTextEdits(pView);
    var Why:= TTextEditApplier.RefusalOf(Edits);
    if Why <> '' then Refs.Add(AnchorRefusal('', Why, 0));
    for var P in pView.TouchedPaths do
    begin
      if Done.Contains(LowerCase(P)) then Continue;
      Done.Add(LowerCase(P));
      if not TFile.Exists(P) then
      begin
        Refs.Add(AnchorRefusal(P, 'the file to edit does not exist', 0));
        Continue;
      end;
      var Content:= DecodeSource(TFile.ReadAllBytes(P), Enc);
      if pTamperAllowed then ApplyTestTamper(P, Content);
      Lines.Text:= Content;
      var Before:= Refs.Count;
      CheckAnchors(P, pView, Lines, Refs);
      CheckInsertedText(P, pView, Enc, Refs);
      if Refs.Count > Before then Continue;
      var Expected:= Lines.Count + NetLineChange(P, Edits);
      var Text:= TTextEditApplier.ApplyToText(P, Content, Edits);
      Lines.Text:= Text;
      if Lines.Count <> Expected then
      begin
        Refs.Add(AnchorRefusal(P, 'the edit applier dropped an edit of this file', 0));
        Continue;
      end;
      Item.Path := ShadowPathOf(pShadowDir, pProjectDir, P);
      Item.Bytes:= EncodeSource(Text, Enc);
      Staged.Add(Item);
    end;
    for var N in pView.NewUnits do
    begin
      if TFile.Exists(N.Path) then
      begin
        Refs.Add(AnchorRefusal(N.Path, 'the new unit''s file already exists', 0));
        Continue;
      end;
      if HasNonAscii(N.Text) then
      begin
        Refs.Add(MakeRefusal('non-ascii-text', '', N.Path, 'the new unit would hold a non-ASCII character copied from the sources; move it by hand', 0));
        Continue;
      end;
      Item.Path := ShadowPathOf(pShadowDir, pProjectDir, N.Path);
      Item.Bytes:= TEncoding.ASCII.GetBytes(string.Join(#13#10, N.Text) + #13#10);
      Staged.Add(Item);
    end;
    if Refs.Count = 0 then
      for Item in Staged do
      begin
        ForceDirectories(ExtractFilePath(Item.Path));
        TFile.WriteAllBytes(Item.Path, Item.Bytes);
      end;
    Result:= Refs.ToArray;
  finally
    Lines.Free;
    Done.Free;
    Staged.Free;
    Refs.Free;
  end;
end;

function IntfEdgeCount(const pUnits: TArray<string>; const pGraph: TCycleGraph; pIntfOnly: Boolean): Integer;
var
  Targets: TList<string>;
begin
  Result:= 0;
  for var A in pUnits do
    for var B in pUnits do
    begin
      if A = B then Continue;
      if pIntfOnly then
      begin
        if pGraph.IntfEdges.ContainsKey(A + '->' + B) then Inc(Result);
      end
      else if pGraph.Adj.TryGetValue(A, Targets) and Targets.Contains(B) then Inc(Result);
    end;
end;

function RefusalLine(const pR: TRefusal): string;
begin
  Result:= Format('  - %s: %s %s:%d -- %s', [pR.Kind, pR.Symbol, pR.FilePath, pR.Line, pR.Reason]);
end;

function StringsToJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do Result.Add(S);
end;

function CycleToJson(const pView: TCyclePlanView; const pRefusals: TArray<TRefusal>;
  const pGraph: TCycleGraph): TJSONObject;
var
  Arr: TJSONArray;
  O  : TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('n', TJSONNumber.Create(pView.CycleIndex));
  Result.AddPair('units', StringsToJson(pView.Units));
  Result.AddPair('interface_edges', TJSONNumber.Create(IntfEdgeCount(pView.Units, pGraph, True)));
  Result.AddPair('edges', TJSONNumber.Create(IntfEdgeCount(pView.Units, pGraph, False)));
  Result.AddPair('part', LowerCase(pView.Part));
  Result.AddPair('verdict', if Length(pRefusals) = 0 then 'mechanical' else 'refused');
  Result.AddPair('recipe', pView.Recipe);
  Result.AddPair('edge', pView.Edge);
  Arr:= TJSONArray.Create;
  for var R in pRefusals do
  begin
    O:= TJSONObject.Create;
    O.AddPair('kind', R.Kind);
    O.AddPair('symbol', R.Symbol);
    O.AddPair('file', R.FilePath);
    O.AddPair('line', TJSONNumber.Create(R.Line));
    O.AddPair('reason', R.Reason);
    Arr.AddElement(O);
  end;
  Result.AddPair('refusals', Arr);
  Arr:= TJSONArray.Create;
  for var M in pView.Moves do
  begin
    O:= TJSONObject.Create;
    O.AddPair('symbol', M.Symbol);
    O.AddPair('kind', M.Kind);
    O.AddPair('recipe', M.Recipe);
    O.AddPair('from', M.FromFile);
    O.AddPair('lines', TJSONArray.Create.Add(M.First).Add(M.Last));
    O.AddPair('to_unit', M.ToUnit);
    Arr.AddElement(O);
  end;
  Result.AddPair('moves', Arr);
  Arr:= TJSONArray.Create;
  for var U in pView.UseDecisions do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', U.FilePath);
    O.AddPair('unit', U.UnitName);
    O.AddPair('section', U.Section);
    O.AddPair('action', U.Action);
    Arr.AddElement(O);
  end;
  Result.AddPair('uses', Arr);
  Arr:= TJSONArray.Create;
  for var N in pView.NewUnits do
  begin
    O:= TJSONObject.Create;
    O.AddPair('unit', N.UnitName);
    O.AddPair('path', N.Path);
    Arr.AddElement(O);
  end;
  Result.AddPair('new_units', Arr);
  Arr:= TJSONArray.Create;
  for var E in pView.Edits do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', E.FilePath);
    O.AddPair('kind', E.Kind);
    O.AddPair('first', TJSONNumber.Create(E.First));
    O.AddPair('last', TJSONNumber.Create(E.Last));
    Arr.AddElement(O);
  end;
  Result.AddPair('edits', Arr);
  O:= TJSONObject.Create;
  O.AddPair('status', 'skipped');
  O.AddPair('files', TJSONNumber.Create(0));
  O.AddPair('errors', TJSONArray.Create);
  Result.AddPair('compile', O);
  O:= TJSONObject.Create;
  O.AddPair('status', 'skipped');
  O.AddPair('errors', TJSONArray.Create);
  Result.AddPair('baseline', O);
  Result.AddPair('repairs', TJSONArray.Create);
  Result.AddPair('written', TJSONArray.Create);
  Result.AddPair('backups', TJSONArray.Create);
  O:= TJSONObject.Create;
  O.AddPair('status', 'dry-run');
  O.AddPair('ms', TJSONNumber.Create(0));
  Result.AddPair('reindex', O);
  Result.AddPair('predicted', pView.Predicted);
  Result.AddPair('actual', '');
  Result.AddPair('verified', TJSONBool.Create(False));
end;

// The 1-based group holding pStem (with or without .pas), 0 when none does.
function GroupOfUnit(const pSccs: TList<TArray<string>>; const pStem: string): Integer;
begin
  var Stem:= LowerCase(ChangeFileExt(pStem, ''));
  for var I:= 0 to pSccs.Count - 1 do
    for var S in pSccs[I] do
      if S = Stem then Exit(I + 1);
  Result:= 0;
end;

// Checks the flags and resolves the group (0 = scan for the first mechanical one) and the
// project's own roots; returns the error text, '' when all is well.
function ResolveSelection(const pOpts: TCycleFixOptions; const pSccs: TList<TArray<string>>;
  out pOwn: TOwnRoots; out pOnly: Integer): string;
begin
  Result:= '';
  pOnly := 0;
  pOwn  := Default(TOwnRoots);
  if pOpts.Project = '' then Result:= CNeedsProject
  else if pOpts.Apply then
    Result:= 'cycles --fix --apply is not available yet (E18 Tasks 9-12); the dry run needs no --apply'
  else if not MatchText(pOpts.Part, ['', 'a', 'b', 'all']) then
    Result:= 'cycles --fix --part must be a, b or all'
  else if SameText(pOpts.Part, 'all') then
    Result:= 'cycles --fix --part all is not available yet (E18 Task 12)'
  else if pOpts.CycleGiven and (pOpts.CycleIndex < 1) then
    Result:= 'cycles --fix --cycle needs a group number of 1 or more (see `drag-lint cycles` for the groups)';
  if Result <> '' then Exit;
  if (pOpts.ShadowOut <> '') and TDirectory.Exists(ExpandFileName(pOpts.ShadowOut)) and
     (Length(TDirectory.GetFileSystemEntries(ExpandFileName(pOpts.ShadowOut))) > 0) then
    Exit('cycles --fix: shadow-out dir not empty: ' + ExpandFileName(pOpts.ShadowOut) + ' (name an empty or new directory; nothing is deleted)');
  pOwn:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
  if pOwn.Error <> '' then Exit(pOwn.Error);
  if pOpts.CycleGiven then pOnly:= pOpts.CycleIndex
  else if pOpts.UnitStem <> '' then
  begin
    pOnly:= GroupOfUnit(pSccs, pOpts.UnitStem);
    if pOnly = 0 then Exit('cycles --fix: unit ' + pOpts.UnitStem + ' is in no circular group');
  end;
  if (pOnly > pSccs.Count) then
    Result:= Format('cycles --fix: --cycle %d, but there are %d circular group(s)', [pOnly, pSccs.Count]);
end;

// Error path: a cycle-fix/1 object with "error" under --format json (as the other verbs'
// JSON reports do), else `ERROR: <message>`.
procedure ReportError(const pOpts: TCycleFixOptions; const pMessage: string);
begin
  if pOpts.Json then
  begin
    var Doc:= TJSONObject.Create;
    try
      Doc.AddPair('schema', CSchema);
      Doc.AddPair('error', pMessage);
      Doc.AddPair('ok', TJSONBool.Create(False));
      Doc.AddPair('exit_code', TJSONNumber.Create(CExitError));
      Writeln(Doc.ToJSON);
    finally
      Doc.Free;
    end;
  end
  else Writeln('ERROR: ', pMessage);
end;

function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pLibStore: ISymbolStore): Integer;
var
  Problem : string;
  Own     : TOwnRoots;
  Only    : Integer;
  Cycles  : TJSONArray;
  Playbook: TStringList;
  Summary : TStringList;
  Chosen  : Boolean;
  BadPart : string;
  ProjectDir: string;
  ShadowDir : string;
  ShadowUsed: string;
begin
  Problem:= ResolveSelection(pOpts, pSccs, Own, Only);
  if Problem <> '' then
  begin
    ReportError(pOpts, Problem);
    Exit(CExitError);
  end;

  Chosen  := False;
  BadPart := '';
  ShadowUsed:= '';
  if TamperAllowed(pOpts) and (GetEnvironmentVariable('DRAGLINT_CYCLEFIX_TEST_TAMPER') <> '') then
    Writeln(ErrOutput, 'cycles --fix: TEST TAMPER active (dry run only)');
  ProjectDir:= ExtractFilePath(ExpandFileName(pOpts.Project));
  ShadowDir := if pOpts.ShadowOut <> '' then IncludeTrailingPathDelimiter(ExpandFileName(pOpts.ShadowOut)) else DefaultShadowDir;
  Cycles  := TJSONArray.Create;
  Playbook:= TStringList.Create;
  Summary := TStringList.Create;
  try
    VisitCyclePlans(pStore, pOpts.Db, pSccs, pGraph, pLibStore,
      function(const pView: TCyclePlanView; const pRender: TFunc<TArray<string>>): Boolean
      var
        All: TList<TRefusal>;
      begin
        All:= TList<TRefusal>.Create;
        try
          All.AddRange(pView.Refusals);
          All.AddRange(MechanisabilityGate(pView, Own));
          All.AddRange(StaleRefusals(pStore, pView));
          var Wanted:= pOpts.Part;
          if (Wanted <> '') and not SameText(Wanted, string(pView.Part)) then
          begin
            { an explicit group is an error; a scan just skips the groups of the other part }
            if Only > 0 then
            begin
              BadPart:= Format('cycles --fix: cycle %d is planned as part %s, not --part %s ' +
                '(the other part comes with --part all, E18 Task 12)', [pView.CycleIndex, LowerCase(pView.Part), Wanted]);
              Exit(False);
            end;
            Exit(True);
          end;
          { a plan the gate passes is staged in the shadow tree; an anchor mismatch refuses the group }
          { Task 11: the apply's write path must NOT pass TamperAllowed(pOpts) here -- stage with False }
          if All.Count = 0 then All.AddRange(StageShadow(pView, ProjectDir, ShadowDir, TamperAllowed(pOpts)));
          var Verdict:= All.ToArray;
          if Length(Verdict) = 0 then ShadowUsed:= ShadowDir;
          Cycles.AddElement(CycleToJson(pView, Verdict, pGraph));
          Chosen:= Length(Verdict) = 0;
          if (not pOpts.Json) and ((Only > 0) or Chosen) then Playbook.AddStrings(pRender());
          if Chosen then
          begin
            if not pOpts.Json then
            begin
              Summary.Add(CVerdictOk);
              Summary.Add(CShadowLine + ShadowDir);
            end;
          end
          else if Only > 0 then
          begin
            Summary.Add(CVerdictRefused);
            for var R in Verdict do Summary.Add(RefusalLine(R));
          end
          else
          begin
            Summary.Add(Format('Cycle %d: %s', [pView.CycleIndex, string.Join(' <-> ', pView.Units)]));
            Summary.Add(RefusalLine(Verdict[0]));
          end;
          Exit(not Chosen);
        finally
          All.Free;
        end;
      end, Only);
    if BadPart <> '' then
    begin
      ReportError(pOpts, BadPart);
      Exit(CExitError);
    end;
    Result:= if Chosen or (pSccs.Count = 0) then CExitMechanical else CExitRefused;
    if pOpts.Json then
    begin
      var Doc:= TJSONObject.Create;
      try
        Doc.AddPair('schema', CSchema);
        Doc.AddPair('mode', 'dry-run');
        Doc.AddPair('project', pOpts.Project);
        Doc.AddPair('db', pOpts.Db);
        Doc.AddPair('platform', if pOpts.Platform = '' then CDefaultPlatform else LowerCase(pOpts.Platform));
        Doc.AddPair('cycles', Cycles);
        Cycles:= nil;
        if ShadowUsed <> '' then Doc.AddPair('shadow', ShadowUsed);
        Doc.AddPair('ok', TJSONBool.Create(Result = CExitMechanical));
        Doc.AddPair('exit_code', TJSONNumber.Create(Result));
        Writeln(Doc.ToJSON);
      finally
        Doc.Free;
      end;
    end
    else
    begin
      if pSccs.Count = 0 then Writeln(CCycleNone);
      for var Line in Playbook do Writeln(Line);
      for var Line in Summary do Writeln(Line);
      if (pSccs.Count > 0) and (Only = 0) and not Chosen then Writeln(CVerdictRefused);
    end;
  finally
    Summary.Free;
    Playbook.Free;
    Cycles.Free;
  end;
end;

end.
