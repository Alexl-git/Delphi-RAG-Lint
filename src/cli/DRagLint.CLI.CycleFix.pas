unit DRagLint.CLI.CycleFix;

// ---------------------------------------------------------------------------
// `drag-lint cycles --fix` -- the dry run (E18 Task 8): pick ONE circular group,
// take the planner's plan for it (DRagLint.Report.CyclePlan.VisitCyclePlans),
// add the mechanisability gate (stale-file, outside-roots, manual-edit) and
// print the verdict as the playbook text or as `cycle-fix/1` JSON
// (docs\superpowers\plans\2026-10-10-auto-cycle-fix.md, contract 4.4).
// Writes nothing to the project. Since Task 9 a mechanical verdict also stages the plan's result
// in a SHADOW TREE (anchored TTextEdits applied in memory, new units, project files); the
// shadow is what the dry run proves would be written. Since Task 10 the COMPILE GATE builds the untouched
// project first (RunMsBuild; refusal dirty-baseline) and provides the after gate with its bounded repairs R4
// (CompileAfter / TryRepair) for the apply. Applying (--apply) arrives with Tasks 11-12.
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
    /// <summary>--no-compile: skip the baseline build; accepted by the dry run only, refused with --apply.</summary>
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

  /// <summary>The outcome of one msbuild run of a whole project (RunMsBuild).</summary>
  TBuildOutcome = record
    /// <summary>True when msbuild exited 0 and printed no `error E`/`fatal F` line.</summary>
    Ok: Boolean;
    /// <summary>The distinct dcc error lines, trimmed, in log order (empty when Ok).</summary>
    Errors: TArray<string>;
    /// <summary>Wall-clock seconds of the build.</summary>
    Seconds: Double;
  end;

  /// <summary>One bounded repair (R4) the compile gate made; an item of `repairs[]` in cycle-fix/1.</summary>
  TRepair = record
    /// <summary>The dcc code repaired: E2003, E2015 or E2010.</summary>
    Code: string;
    /// <summary>The file the dcc line names, as found in the build tree.</summary>
    FilePath: string;
    /// <summary>The line the dcc line names.</summary>
    Line: Integer;
    /// <summary>What was changed, in words.</summary>
    Action: string;
  end;

  /// <summary>The result of the after-gate (CompileAfter).</summary>
  TCompileAfterResult = record
    /// <summary>True when the last build was clean.</summary>
    Ok: Boolean;
    /// <summary>The dcc error lines of the last build.</summary>
    Errors: TArray<string>;
    /// <summary>The repairs made between the first and the second build; empty = no retry.</summary>
    Repairs: TArray<TRepair>;
    /// <summary>1, or 2 when a repair was retried.</summary>
    Builds: Integer;
    /// <summary>Seconds of every build together.</summary>
    Seconds: Double;
  end;

/// <summary>Builds a whole project with msbuild, the recipe of tools\score-cycle-playbook.ps1
/// Invoke-Build: a generated `.bat` calls rsvars.bat, changes to the project folder and runs
/// `msbuild /t:Build /p:Config=Debug /p:Platform=&lt;p&gt; /v:minimal`, output to pLogPath.</summary>
/// <param name="pProject">The .dproj to build.</param>
/// <param name="pPlatform">win32 / win64 (any case); '' = Win64.</param>
/// <param name="pLogPath">The build log; the `.bat` is written next to it (same name, .bat).
/// Its folder is created; neither file is in the project.</param>
/// <returns>Ok, the distinct `error E`/`fatal F` lines and the seconds taken. A missing rsvars.bat
/// gives Ok = False with one line saying so (CompilerAvailable tells beforehand).</returns>
/// <remarks>The build writes what any build of the project writes (dcu, exe) into the project's
/// own output folders; it writes no source file.</remarks>
function RunMsBuild(const pProject, pPlatform, pLogPath: string): TBuildOutcome;

/// <summary>True when the RAD Studio rsvars.bat RunMsBuild calls exists.</summary>
/// <returns>False on a machine without RAD Studio 37.0.</returns>
function CompilerAvailable: Boolean;

/// <summary>The baseline gate: builds the UNTOUCHED project before anything is staged.</summary>
/// <param name="pOpts">The flags (Project, Platform).</param>
/// <param name="pLogDir">Folder for the build's .bat and log (BuildScratchDir).</param>
/// <returns>The build outcome; not Ok means the refusal `dirty-baseline`.</returns>
function BaselineCompile(const pOpts: TCycleFixOptions; const pLogDir: string): TBuildOutcome;

/// <summary>The bounded repairs R4: one pass over the dcc lines of a failed after-build.</summary>
/// <param name="pView">The plan that was written.</param>
/// <param name="pErrors">The dcc lines of the failed build (RunMsBuild.Errors).</param>
/// <param name="pProjectDir">The project folder the plan's paths live in.</param>
/// <param name="pTreeDir">The folder that was built: pProjectDir itself (apply, in place) or a
/// copy laid out like it (the files are found by the shadow mapping, ShadowPathOf).</param>
/// <returns>The repairs made, one per repaired dcc line; empty = nothing repairable (no retry).</returns>
/// <remarks>Only files the plan edits or creates are changed, in their own encoding (DecodeSource /
/// EncodeSource). The rules, each on a line the plan wrote: `E2003 Undeclared identifier: 'X'` where X
/// is a moved symbol (its leaf) or the interface / pointer type / pointer variable (InversionUnit) -&gt;
/// that unit is added to the uses clause of the section holding the line (first entry; a section
/// without uses gets one); `E2015` on a line with `&lt;expr&gt; as &lt;IfaceName&gt;` -&gt; the expression is
/// cast through CastAncestor; `E2010 ... 'Procedure'` on the `PtrVar :=` assignment -&gt; the
/// declaration of PtrType is re-emitted as PtrTypeDecl (the routine's signature verbatim). Any other
/// code, and an R4 code whose condition does not hold, is left alone. Lines dcc prints as a CASCADE of
/// a repaired one (E2003 on a member inside a broken `with`, E2066, F2063) do not block the retry:
/// the second build decides.</remarks>
function TryRepair(const pView: TCyclePlanView; const pErrors: TArray<string>;
  const pProjectDir, pTreeDir: string): TArray<TRepair>;

/// <summary>The after gate: builds the written project, repairs once (TryRepair) and builds again.</summary>
/// <param name="pView">The plan that was written.</param>
/// <param name="pProjectDir">The project folder the plan's paths live in.</param>
/// <param name="pBuildProject">The .dproj to build: the project itself (apply) or the same project in a copy.</param>
/// <param name="pPlatform">As RunMsBuild.</param>
/// <param name="pLogDir">Folder for the .bat and logs (after-1.log, after-2.log).</param>
/// <returns>Ok, the last build's errors, the repairs and the build count and time.</returns>
/// <remarks>Rolls nothing back: on not Ok the caller (Task 11's apply) restores its backups, which
/// cover every file TryRepair may touch.</remarks>
function CompileAfter(const pView: TCyclePlanView; const pProjectDir, pBuildProject, pPlatform,
  pLogDir: string): TCompileAfterResult;

/// <summary>The DRAGLINT_CYCLEFIX_BREAK test seam: 1 or 2 when set AND the project file lies under
/// %TEMP% or C:\TEMP, else 0.</summary>
/// <param name="pOpts">The flags.</param>
/// <returns>The break mode to apply to the plan before staging (ApplyTestBreak), or 0.</returns>
/// <remarks>Honoured on the dry run and the apply alike (Task 11 proves the after gate with it); the
/// caller prints `TEST BREAK active` to stderr when it is not 0.</remarks>
function BreakSeam(const pOpts: TCycleFixOptions): Integer;

/// <summary>Spoils a plan the way a planner bug would, so the after gate has something to repair.</summary>
/// <param name="pView">The plan.</param>
/// <param name="pMode">1: a `&lt;Anc&gt;(expr) as I...` line loses its cast (dcc E2015); 2: the pointer
/// type is emitted as `reference to function(...)` without its `const` -- TFunc's own definition,
/// spelled inline because TFunc itself needs System.SysUtils (measured: E2003 'TFunc&lt;,&gt;') -- (dcc
/// E2010 '...' and 'Procedure' on the pointer assignment). Any other value: unchanged.</param>
/// <returns>A copy; pView's arrays are not modified.</returns>
function ApplyTestBreak(const pView: TCyclePlanView; pMode: Integer): TCyclePlanView;

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
/// <remarks>Writes no source file of the project; unless --no-compile, the baseline build writes what any build
/// of the project writes (dcu, exe) and refuses the run (dirty-baseline, exit 1) when it fails. The first mechanical group is chosen when neither --cycle nor --unit is given.</remarks>
function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  const pLibStore: ISymbolStore = nil): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.DateUtils, System.Hash,
  System.StrUtils, System.RegularExpressions, System.Diagnostics, System.Math,
  DRagLint.Diagnostics.CompileCheck;

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
  CRsvars          = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'; // dl:ok hardcoded-absolute-path@ef69 -- the RAD Studio 37.0 install the E18 design builds with (the playbook scorer's recipe)
  CBreakCast       = 1;    // DRAGLINT_CYCLEFIX_BREAK=1: drop the cast before `as I...`
  CBreakPointer    = 2;    // DRAGLINT_CYCLEFIX_BREAK=2: the pointer type as a reference type
  CSecondBuild     = 2;    // CompileAfter builds at most twice
  CJsonDecimals    = -2;   // seconds in the JSON, to 1/100
  CProbeWithLines  = 2;    // DRAGLINT_CYCLEFIX_REPAIR_PROBE=<tree>|<errors file>

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

{ ---- the compile gate (E18 Task 10) ---------------------------------------------------------- }

type
  // One dcc error line, parsed.
  TDccLine = record
    FileName: string;
    Line    : Integer;
    Code    : string;
    Message : string;
  end;

  // One file TryRepair edits: its lines in its own encoding, and whether it ended in a line break.
  TRepairFile = class
  strict private
    FPath    : string;
    FLines   : TStringList;
    FEnc     : TEncoding;
    FTrailing: Boolean;
    FDirty   : Boolean;
  public
    constructor Create(const pPath: string);
    destructor Destroy; override;
    procedure Save;
    property Path : string read FPath;
    property Lines: TStringList read FLines;
    property Dirty: Boolean read FDirty write FDirty;
  end;

  // What the gate measured, for the JSON and the timing line.
  TGateReport = record
    Baseline      : TBuildOutcome;
    BaselineStatus: string;  // ok | error | unavailable | skipped
    After         : TCompileAfterResult;
    AfterStatus   : string;  // ok | error | skipped
    AfterFiles    : Integer;
  end;

const
  CStatusSkipped = 'skipped';
  CSectionStop   = '^\s*(type|const|var|threadvar|resourcestring|procedure|function|constructor|destructor|' +
                   'class|begin|initialization|finalization|exports|end\.)\b';

constructor TRepairFile.Create(const pPath: string);
begin
  inherited Create;
  FPath := pPath;
  FLines:= TStringList.Create;
  var Content:= DecodeSource(TFile.ReadAllBytes(pPath), FEnc);
  FTrailing  := EndsStr(#10, Content);
  FLines.Text:= Content;
end;

destructor TRepairFile.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TRepairFile.Save;
begin
  FLines.LineBreak:= #13#10;
  var Text:= FLines.Text;
  if not FTrailing and EndsStr(#13#10, Text) then SetLength(Text, Length(Text) - Length(#13#10));
  TFile.WriteAllBytes(FPath, EncodeSource(Text, FEnc));
end;

function CompilerAvailable: Boolean;
begin
  Result:= TFile.Exists(CRsvars);
end;

function MsBuildPlatform(const pPlatform: string): string;
begin
  if SameText(pPlatform, 'win32') then Result:= 'Win32'
  else if (pPlatform = '') or SameText(pPlatform, CDefaultPlatform) then Result:= 'Win64'
  else Result:= pPlatform;
end;

// The folder of the gate's .bat files and logs: never inside the project or the shadow tree.
function BuildScratchDir: string;
begin
  Result:= Format('C:\TEMP\draglint_cyclefix_%d_build\', [GetCurrentProcessId]); // dl:ok hardcoded-absolute-path@4b37 -- next to the fixed debug shadow location of the E18 design
end;

// The distinct `error E....` / `fatal F....` lines of a build log, trimmed, in log order.
function DccErrorLines(const pLog: string): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var M in TRegEx.Matches(pLog, '^.*\b(error|fatal) [EF]\d{4}\b.*$', [roMultiLine]) do
    begin
      var S:= Trim(M.Value);
      if not L.Contains(S) then L.Add(S);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function RunMsBuild(const pProject, pPlatform, pLogPath: string): TBuildOutcome;
begin
  Result:= Default(TBuildOutcome);
  if not CompilerAvailable then
  begin
    Result.Errors:= ['cannot build: rsvars.bat not found: ' + CRsvars];
    Exit;
  end;
  var Project:= ExpandFileName(pProject);
  if SameText(ExtractFileExt(Project), '.dpr') and TFile.Exists(ChangeFileExt(Project, '.dproj')) then
    Project:= ChangeFileExt(Project, '.dproj');
  var Log:= ExpandFileName(pLogPath);
  var Bat:= ChangeFileExt(Log, '.bat');
  ForceDirectories(ExtractFilePath(Log));
  System.SysUtils.DeleteFile(Log); // a stale log of an earlier run must not be read as this one's; absent = fine
  TFile.WriteAllText(Bat, string.Join(#13#10, [
    '@echo off',
    Format('call "%s"', [CRsvars]),
    Format('cd /d "%s"', [ExcludeTrailingPathDelimiter(ExtractFilePath(Project))]),
    Format('msbuild /t:Build /p:Config=Debug /p:Platform=%s /v:minimal "%s" > "%s" 2>&1',
      [MsBuildPlatform(pPlatform), Project, Log]),
    { redirection FIRST: `echo X=%ERRORLEVEL%>> f` expands to `X=0>> f`, a redirect of handle 0 }
    Format('>> "%s" echo BUILD_EXITCODE=%%ERRORLEVEL%%', [Log])]) + #13#10, TEncoding.ASCII);
  var Watch:= TStopwatch.StartNew;
  TCompileChecker.RunCommand('cmd.exe /c ""' + Bat + '""');
  Result.Seconds:= Watch.Elapsed.TotalSeconds;
  var Text:= if TFile.Exists(Log) then TFile.ReadAllText(Log, TEncoding.ANSI) else '';
  Result.Errors:= DccErrorLines(Text);
  Result.Ok:= ContainsStr(Text, 'BUILD_EXITCODE=0') and (Length(Result.Errors) = 0);
  if not Result.Ok and (Length(Result.Errors) = 0) then
    Result.Errors:= ['msbuild failed without a dcc error line; see ' + Log];
end;

function BaselineCompile(const pOpts: TCycleFixOptions; const pLogDir: string): TBuildOutcome;
begin
  Result:= RunMsBuild(pOpts.Project, pOpts.Platform, IncludeTrailingPathDelimiter(pLogDir) + 'baseline.log');
end;

// `File.pas(57): error E2015: Message [proj]` (msbuild) or `[dcc64 Error] File.pas(57): E2015 Message` (dcc).
function ParseDccLine(const pText: string; out pLine: TDccLine): Boolean;
const
  CPattern = '^\s*(?:\[dcc\w*\s+\w+\]\s*)?(?<file>.+?)\((?<line>\d+)(?:,\d+)?\)\s*:?\s*(?:(?:error|fatal)\s*:?\s*)?' +
             '(?<code>[EF]\d{4})\s*:?\s*(?<msg>.*?)\s*(?:\[[^\[\]]*\])?\s*$';
begin
  pLine:= Default(TDccLine);
  var M:= TRegEx.Match(pText, CPattern, [roIgnoreCase]);
  Result:= M.Success;
  if not Result then Exit;
  pLine.FileName:= Trim(M.Groups['file'].Value);
  pLine.Line    := StrToIntDef(M.Groups['line'].Value, 0);
  pLine.Code    := UpperCase(M.Groups['code'].Value);
  pLine.Message := M.Groups['msg'].Value;
end;

// Where pPath of the plan is in pTreeDir: itself when the tree IS the project folder, else its shadow path.
function TreePathOf(const pTreeDir, pProjectDir, pPath: string): string;
begin
  if SameText(IncludeTrailingPathDelimiter(ExpandFileName(pTreeDir)), IncludeTrailingPathDelimiter(ExpandFileName(pProjectDir))) then
    Result:= ExpandFileName(pPath)
  else Result:= ShadowPathOf(pTreeDir, pProjectDir, pPath);
end;

// Every file the plan edits or creates.
function PlanFiles(const pView: TCyclePlanView): TArray<string>;
begin
  Result:= Copy(pView.TouchedPaths);
  for var N in pView.NewUnits do Result:= Result + [N.Path];
end;

// The unit that declares pName after the plan, '' when the plan does not provide it.
function LeafOf(const pView: TCyclePlanView; const pName: string): string;
begin
  for var M in pView.Moves do
    if SameText(M.Symbol, pName) and (M.ToUnit <> '') then Exit(M.ToUnit);
  if (pView.InversionUnit <> '') and (pName <> '') and MatchText(pName, [pView.IfaceName, pView.PtrType, pView.PtrVar]) then
    Exit(pView.InversionUnit);
  Result:= '';
end;

function LineIndexOf(pLines: TStrings; const pPattern: string; pFrom, pTo: Integer): Integer;
begin
  for var I:= pFrom to pTo - 1 do
    if TRegEx.IsMatch(pLines[I], pPattern, [roIgnoreCase]) then Exit(I);
  Result:= -1;
end;

// interface / implementation / program: the section holding 0-based line pIdx.
function SectionNameOf(pLines: TStrings; pIdx: Integer): string;
begin
  var Impl:= LineIndexOf(pLines, '^\s*implementation\b', 0, pLines.Count);
  if (Impl >= 0) and (pIdx > Impl) then Exit('implementation');
  Result:= if LineIndexOf(pLines, '^\s*interface\b', 0, pLines.Count) >= 0 then 'interface' else 'program';
end;

// The [pLo, pHi) lines of the named section, pLo the line after its keyword.
procedure SectionRange(pLines: TStrings; const pName: string; out pLo, pHi: Integer);
begin
  var Impl:= LineIndexOf(pLines, '^\s*implementation\b', 0, pLines.Count);
  pLo:= 0;
  pHi:= pLines.Count;
  if pName = 'implementation' then pLo:= Impl + 1
  else if pName = 'interface' then
  begin
    pLo:= LineIndexOf(pLines, '^\s*interface\b', 0, pLines.Count) + 1;
    if Impl >= 0 then pHi:= Impl;
  end;
end;

// The unit names of the uses clause that starts at line pUses (comments and `in '...'` dropped).
function UsesEntries(pLines: TStrings; pUses: Integer): TArray<string>;
var
  Buf: TStringBuilder;
begin
  Result:= nil;
  Buf:= TStringBuilder.Create;
  try
    for var I:= pUses to pLines.Count - 1 do
    begin
      var S:= TRegEx.Replace(pLines[I], '//.*$', '');
      Buf.Append(S).Append(' ');
      if ContainsStr(S, ';') then Break;
    end;
    var Text:= TRegEx.Replace(Buf.ToString, '\{[^}]*\}|\(\*.*?\*\)', ' ');
    Text:= TRegEx.Replace(Text, '^\s*uses\b', '', [roIgnoreCase]);
    if Pos(';', Text) > 0 then Text:= Copy(Text, 1, Pos(';', Text) - 1);
    for var E in Text.Split([',']) do
      Result:= Result + [Trim(TRegEx.Replace(E, '\s+in\s+''[^'']*''', '', [roIgnoreCase]))];
  finally
    Buf.Free;
  end;
end;

// Adds pLeaf as the first entry of the section's uses clause (a section without one gets one).
// False when it is there already or the section has no place for it.
function AddToUses(pLines: TStrings; const pSection, pLeaf: string): Boolean;
var
  Lo, Hi: Integer;
begin
  SectionRange(pLines, pSection, Lo, Hi);
  var Stop:= LineIndexOf(pLines, CSectionStop, Lo, Hi);
  var U:= LineIndexOf(pLines, '^\s*uses\b', Lo, if Stop >= 0 then Stop else Hi);
  if U >= 0 then
  begin
    if MatchText(pLeaf, UsesEntries(pLines, U)) then Exit(False);
    var M:= TRegEx.Match(pLines[U], '^(\s*uses)\b(.*)$', [roIgnoreCase]);
    var Rest:= Trim(M.Groups[2].Value);
    if Rest = '' then pLines.Insert(U + 1, '  ' + pLeaf + ',')
    else pLines[U]:= M.Groups[1].Value + ' ' + pLeaf + ', ' + Rest;
  end
  else if pSection = 'program' then Exit(False)
  else
  begin
    pLines.Insert(Lo, '  ' + pLeaf + ';');
    pLines.Insert(Lo, 'uses');
    pLines.Insert(Lo, '');
  end;
  Result:= True;
end;

function TryRepair(const pView: TCyclePlanView; const pErrors: TArray<string>;
  const pProjectDir, pTreeDir: string): TArray<TRepair>;
type
  TUsesAdd = record
    FilePath: string;
    Section : string;
    Leaf    : string;
    Err     : TDccLine;
  end;
var
  Files  : TObjectDictionary<string, TRepairFile>;
  Adds   : TList<TUsesAdd>;
  Repairs: TList<TRepair>;
  Seen   : TList<string>;

  // The tree path of the plan file dcc names, '' when the plan has no such file in the tree.
  function Resolve(const pName: string): string;
  begin
    Result:= '';
    for var P in PlanFiles(pView) do
    begin
      var T:= TreePathOf(pTreeDir, pProjectDir, P);
      if not TFile.Exists(T) then Continue;
      if TPath.IsPathRooted(pName) and SameText(T, ExpandFileName(pName)) then Exit(T);
      if (Result = '') and SameText(ExtractFileName(T), ExtractFileName(pName)) then Result:= T;
    end;
  end;

  function FileOf(const pPath: string): TRepairFile;
  begin
    if not Files.TryGetValue(LowerCase(pPath), Result) then
    begin
      Result:= TRepairFile.Create(pPath);
      Files.Add(LowerCase(pPath), Result);
    end;
  end;

  procedure AddRepair(const pErr: TDccLine; const pPath, pAction: string);
  var
    R: TRepair;
  begin
    R.Code    := pErr.Code;
    R.FilePath:= pPath;
    R.Line    := pErr.Line;
    R.Action  := pAction;
    Repairs.Add(R);
  end;

  // E2015 on `<expr> as <IfaceName>`: cast <expr> through the plan's ancestor.
  procedure RepairCast(const pErr: TDccLine; const pPath: string; pFile: TRepairFile);
  begin
    if (pView.IfaceName = '') or (pView.CastAncestor = '') then Exit;
    var Text:= pFile.Lines[pErr.Line - 1];
    var M:= TRegEx.Match(Text, '(?<![\w.)\]^])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+as\s+' +
      TRegEx.Escape(pView.IfaceName) + '\b', [roIgnoreCase]);
    if not M.Success then Exit;
    var G:= M.Groups[1];
    var Fixed:= Copy(Text, 1, G.Index - 1) + pView.CastAncestor + '(' + G.Value + ')' + Copy(Text, G.Index + G.Length, MaxInt);
    pFile.Lines[pErr.Line - 1]:= Fixed;
    pFile.Dirty:= True;
    AddRepair(pErr, pPath, Format('cast `%s` through %s: %s', [G.Value, pView.CastAncestor, Trim(Fixed)]));
  end;

  // E2010 '...' and 'Procedure' on the `PtrVar :=` line: re-emit the pointer type from the plan.
  procedure RepairPointer(const pErr: TDccLine; const pPath: string; pFile: TRepairFile);
  begin
    if (pView.PtrType = '') or (pView.PtrTypeDecl = '') or not ContainsText(pErr.Message, 'Procedure') or
       not TRegEx.IsMatch(pFile.Lines[pErr.Line - 1], '\b' + TRegEx.Escape(pView.PtrVar) + '\s*:=', [roIgnoreCase]) then Exit;
    for var P in PlanFiles(pView) do
    begin
      var T:= TreePathOf(pTreeDir, pProjectDir, P);
      if not TFile.Exists(T) then Continue;
      var D:= FileOf(T);
      var I:= LineIndexOf(D.Lines, '^\s*' + TRegEx.Escape(pView.PtrType) + '\s*=', 0, D.Lines.Count);
      if I < 0 then Continue;
      var Line:= D.Lines[I];
      var Want:= Copy(Line, 1, Length(Line) - Length(TrimLeft(Line))) + pView.PtrTypeDecl;
      if Line = Want then Exit;
      D.Lines[I]:= Want;
      D.Dirty   := True;
      AddRepair(pErr, pPath, Format('re-emitted %s in %s line %d from the routine''s signature: %s',
        [pView.PtrType, ExtractFileName(T), I + 1, pView.PtrTypeDecl]));
      Exit;
    end;
  end;

  // E2003 on a name the plan provides: queue its unit for the uses of the section holding the line.
  procedure QueueUses(const pErr: TDccLine; const pPath: string; pFile: TRepairFile);
  var
    A: TUsesAdd;
  begin
    var M:= TRegEx.Match(pErr.Message, '''([^'']+)''');
    if not M.Success then Exit;
    var Leaf:= LeafOf(pView, M.Groups[1].Value);
    if Leaf = '' then Exit;
    A.FilePath:= pPath;
    A.Section := SectionNameOf(pFile.Lines, pErr.Line - 1);
    A.Leaf    := Leaf;
    A.Err     := pErr;
    Adds.Add(A);
  end;

begin
  Files  := TObjectDictionary<string, TRepairFile>.Create([doOwnsValues]);
  Adds   := TList<TUsesAdd>.Create;
  Repairs:= TList<TRepair>.Create;
  Seen   := TList<string>.Create;
  try
    for var S in pErrors do
    begin
      var E: TDccLine;
      if not ParseDccLine(S, E) then Continue;
      var Key:= Format('%s|%d|%s', [LowerCase(ExtractFileName(E.FileName)), E.Line, E.Code]);
      if Seen.Contains(Key) then Continue;
      Seen.Add(Key);
      var Path:= Resolve(E.FileName);
      if Path = '' then Continue;
      var F:= FileOf(Path);
      if (E.Line < 1) or (E.Line > F.Lines.Count) then Continue;
      if E.Code = 'E2015' then RepairCast(E, Path, F)
      else if E.Code = 'E2010' then RepairPointer(E, Path, F)
      else if E.Code = 'E2003' then QueueUses(E, Path, F);
    end;
    { uses additions last: they insert lines, and every line number above was read before them }
    for var A in Adds do
    begin
      var F:= FileOf(A.FilePath);
      if AddToUses(F.Lines, A.Section, A.Leaf) then
      begin
        F.Dirty:= True;
        AddRepair(A.Err, A.FilePath, Format('added %s to the %s uses', [A.Leaf, A.Section]));
      end;
    end;
    for var F in Files.Values do
      if F.Dirty then F.Save;
    Result:= Repairs.ToArray;
  finally
    Seen.Free;
    Repairs.Free;
    Adds.Free;
    Files.Free;
  end;
end;

function CompileAfter(const pView: TCyclePlanView; const pProjectDir, pBuildProject, pPlatform,
  pLogDir: string): TCompileAfterResult;
begin
  Result:= Default(TCompileAfterResult);
  var Dir:= IncludeTrailingPathDelimiter(pLogDir);
  var B:= RunMsBuild(pBuildProject, pPlatform, Dir + 'after-1.log');
  Result.Builds := 1;
  Result.Seconds:= B.Seconds;
  if not B.Ok then
  begin
    Result.Repairs:= TryRepair(pView, B.Errors, pProjectDir, ExtractFilePath(ExpandFileName(pBuildProject)));
    if Length(Result.Repairs) > 0 then
    begin
      B:= RunMsBuild(pBuildProject, pPlatform, Dir + Format('after-%d.log', [CSecondBuild]));
      Result.Builds := CSecondBuild;
      Result.Seconds:= Result.Seconds + B.Seconds;
    end;
  end;
  Result.Ok    := B.Ok;
  Result.Errors:= B.Errors;
end;

function IsUnderTemp(const pPath: string): Boolean;
begin
  var Full:= ExpandFileName(pPath);
  var Temp:= GetEnvironmentVariable('TEMP');
  Result:= StartsText('C:\TEMP\', Full) or // dl:ok hardcoded-absolute-path@485b -- the test seams' fixed scratch root (ruling T10)
    ((Temp <> '') and StartsText(IncludeTrailingPathDelimiter(ExpandFileName(Temp)), Full));
end;

function BreakSeam(const pOpts: TCycleFixOptions): Integer;
begin
  Result:= StrToIntDef(GetEnvironmentVariable('DRAGLINT_CYCLEFIX_BREAK'), 0);
  if ((Result <> CBreakCast) and (Result <> CBreakPointer)) or not IsUnderTemp(pOpts.Project) then Result:= 0;
end;

function BreakLine(const pView: TCyclePlanView; const pLine: string; pMode: Integer): string;
begin
  Result:= pLine;
  if (pMode = CBreakCast) and (pView.IfaceName <> '') and (pView.CastAncestor <> '') then
  begin
    var M:= TRegEx.Match(pLine, '\b' + TRegEx.Escape(pView.CastAncestor) + '\(([^()]*)\)(\s+as\s+' +
      TRegEx.Escape(pView.IfaceName) + '\b)', [roIgnoreCase]);
    if M.Success then
      Result:= Copy(pLine, 1, M.Index - 1) + M.Groups[1].Value + M.Groups[2].Value + Copy(pLine, M.Index + M.Length, MaxInt);
  end
  else if (pMode = CBreakPointer) and (pView.PtrTypeDecl <> '') and (Trim(pLine) = Trim(pView.PtrTypeDecl)) then
  begin
    Result:= StringReplace(pLine, '= function(', '= reference to function(', []);
    Result:= StringReplace(Result, '= procedure(', '= reference to procedure(', []);
    Result:= TRegEx.Replace(Result, '\bconst\s+', '', [roIgnoreCase]);
  end;
end;

function ApplyTestBreak(const pView: TCyclePlanView; pMode: Integer): TCyclePlanView;
begin
  Result:= pView;
  Result.Edits:= Copy(pView.Edits);
  for var I:= 0 to High(Result.Edits) do
  begin
    Result.Edits[I].NewLines:= Copy(pView.Edits[I].NewLines);
    for var K:= 0 to High(Result.Edits[I].NewLines) do
      Result.Edits[I].NewLines[K]:= BreakLine(pView, Result.Edits[I].NewLines[K], pMode);
  end;
  Result.NewUnits:= Copy(pView.NewUnits);
  for var I:= 0 to High(Result.NewUnits) do
  begin
    Result.NewUnits[I].Text:= Copy(pView.NewUnits[I].Text);
    for var K:= 0 to High(Result.NewUnits[I].Text) do
      Result.NewUnits[I].Text[K]:= BreakLine(pView, Result.NewUnits[I].Text[K], pMode);
  end;
end;

// Test seam DRAGLINT_CYCLEFIX_REPAIR_PROBE=<tree>[|<errors file>], inert with --apply and for a tree
// outside %TEMP% / C:\TEMP. <tree> holds the project with the staged plan laid over it. With an errors
// file, TryRepair runs on <tree> with those dcc lines (no build); without, CompileAfter builds <tree>.
function ProbeSpec(const pOpts: TCycleFixOptions; out pTree, pErrorsFile: string): Boolean;
begin
  pTree      := '';
  pErrorsFile:= '';
  var Spec:= GetEnvironmentVariable('DRAGLINT_CYCLEFIX_REPAIR_PROBE').Split(['|']);
  if pOpts.Apply or (Length(Spec) = 0) or (Trim(Spec[0]) = '') then Exit(False);
  pTree:= IncludeTrailingPathDelimiter(ExpandFileName(Trim(Spec[0])));
  if Length(Spec) >= CProbeWithLines then pErrorsFile:= Trim(Spec[1]);
  Result:= IsUnderTemp(pTree) and TDirectory.Exists(pTree);
end;

// `compile: baseline 9.8 s, after 10.1 s` -- the parts that ran; '' when none did.
function TimingLine(const pGate: TGateReport): string;
begin
  Result:= '';
  if (pGate.BaselineStatus = 'ok') or (pGate.BaselineStatus = 'error') then
    Result:= Format('baseline %.1f s', [pGate.Baseline.Seconds], TFormatSettings.Invariant);
  if pGate.AfterStatus <> CStatusSkipped then
    Result:= Result + IfThen(Result <> '', ', ') + Format('after %.1f s', [pGate.After.Seconds], TFormatSettings.Invariant);
  if Result <> '' then Result:= 'compile: ' + Result;
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

function Seconds(pValue: Double): TJSONNumber;
begin
  Result:= TJSONNumber.Create(SimpleRoundTo(pValue, CJsonDecimals));
end;

// compile.errors of cycle-fix/1: {file, line, code, message}; a line dcc did not shape is kept as message.
function DccErrorsToJson(const pErrors: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pErrors do
  begin
    var E: TDccLine;
    if not ParseDccLine(S, E) then
    begin
      E:= Default(TDccLine);
      E.Message:= S;
    end;
    var O:= TJSONObject.Create;
    O.AddPair('file', E.FileName);
    O.AddPair('line', TJSONNumber.Create(E.Line));
    O.AddPair('code', E.Code);
    O.AddPair('message', E.Message);
    Result.AddElement(O);
  end;
end;

function BaselineToJson(const pGate: TGateReport): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('status', pGate.BaselineStatus);
  Result.AddPair('seconds', Seconds(pGate.Baseline.Seconds));
  Result.AddPair('errors', StringsToJson(pGate.Baseline.Errors));
end;

function RefusalToJson(const pR: TRefusal): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('kind', pR.Kind);
  Result.AddPair('symbol', pR.Symbol);
  Result.AddPair('file', pR.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pR.Line));
  Result.AddPair('reason', pR.Reason);
end;

function CycleToJson(const pView: TCyclePlanView; const pRefusals: TArray<TRefusal>;
  const pGraph: TCycleGraph; const pGate: TGateReport): TJSONObject;
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
  for var R in pRefusals do Arr.AddElement(RefusalToJson(R));
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
  O.AddPair('status', pGate.AfterStatus);
  O.AddPair('files', TJSONNumber.Create(pGate.AfterFiles));
  O.AddPair('errors', DccErrorsToJson(pGate.After.Errors));
  O.AddPair('seconds', Seconds(pGate.After.Seconds));
  O.AddPair('builds', TJSONNumber.Create(pGate.After.Builds));
  Result.AddPair('compile', O);
  Result.AddPair('baseline', BaselineToJson(pGate));
  Arr:= TJSONArray.Create;
  for var R in pGate.After.Repairs do
  begin
    O:= TJSONObject.Create;
    O.AddPair('code', R.Code);
    O.AddPair('file', R.FilePath);
    O.AddPair('line', TJSONNumber.Create(R.Line));
    O.AddPair('action', R.Action);
    Arr.AddElement(O);
  end;
  Result.AddPair('repairs', Arr);
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
  else if pOpts.Apply and pOpts.NoCompile then
    Result:= 'cycles --fix --apply always builds the project (baseline and after); --no-compile is for the dry run only'
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

// A refusal of the whole run before any group is planned (dirty-baseline, no-compiler): exit 1,
// nothing staged. JSON: the top-level `refusals` and `baseline`, `cycles` empty.
procedure ReportGateRefusal(const pOpts: TCycleFixOptions; const pGate: TGateReport; const pRefusal: TRefusal);
begin
  if pOpts.Json then
  begin
    var Doc:= TJSONObject.Create;
    try
      Doc.AddPair('schema', CSchema);
      Doc.AddPair('mode', if pOpts.Apply then 'apply' else 'dry-run');
      Doc.AddPair('project', pOpts.Project);
      Doc.AddPair('db', pOpts.Db);
      Doc.AddPair('platform', if pOpts.Platform = '' then CDefaultPlatform else LowerCase(pOpts.Platform));
      Doc.AddPair('baseline', BaselineToJson(pGate));
      Doc.AddPair('refusals', TJSONArray.Create.Add(RefusalToJson(pRefusal)));
      Doc.AddPair('cycles', TJSONArray.Create);
      Doc.AddPair('ok', TJSONBool.Create(False));
      Doc.AddPair('exit_code', TJSONNumber.Create(CExitRefused));
      Writeln(Doc.ToJSON);
    finally
      Doc.Free;
    end;
  end
  else
  begin
    Writeln(CVerdictRefused);
    Writeln(RefusalLine(pRefusal));
    for var S in pGate.Baseline.Errors do Writeln('    ', S);
    var T:= TimingLine(pGate);
    if T <> '' then Writeln(T);
  end;
end;

// Prints the stderr notice of every active test seam; returns the BREAK mode (BreakSeam) and the probe (ProbeSpec).
function AnnounceSeams(const pOpts: TCycleFixOptions; out pProbe: Boolean; out pProbeTree, pProbeLines: string): Integer;
begin
  if TamperAllowed(pOpts) and (GetEnvironmentVariable('DRAGLINT_CYCLEFIX_TEST_TAMPER') <> '') then
    Writeln(ErrOutput, 'cycles --fix: TEST TAMPER active (dry run only)');
  Result:= BreakSeam(pOpts);
  if Result <> 0 then
    Writeln(ErrOutput, Format('cycles --fix: TEST BREAK active (DRAGLINT_CYCLEFIX_BREAK=%d; the project lies under TEMP)', [Result]));
  pProbe:= ProbeSpec(pOpts, pProbeTree, pProbeLines);
  if pProbe then Writeln(ErrOutput, 'cycles --fix: TEST REPAIR PROBE active (dry run only): ' + pProbeTree);
end;

// The baseline gate: the UNTOUCHED project must build before anything is planned or staged. False =
// refused (no-compiler / dirty-baseline), already reported. pGate is filled either way.
function PassBaselineGate(const pOpts: TCycleFixOptions; pAnyGroup: Boolean; out pGate: TGateReport): Boolean;
begin
  pGate:= Default(TGateReport);
  pGate.BaselineStatus:= CStatusSkipped;
  pGate.AfterStatus   := CStatusSkipped;
  Result:= True;
  if pOpts.NoCompile or not pAnyGroup then Exit;
  if not CompilerAvailable then
  begin
    pGate.BaselineStatus:= 'unavailable';
    ReportGateRefusal(pOpts, pGate, MakeRefusal('no-compiler', '', pOpts.Project,
      'rsvars.bat not found (' + CRsvars + '): the compile gate cannot run; a dry run without it needs --no-compile', 0));
    Exit(False);
  end;
  pGate.Baseline:= BaselineCompile(pOpts, BuildScratchDir);
  pGate.BaselineStatus:= if pGate.Baseline.Ok then 'ok' else 'error';
  Result:= pGate.Baseline.Ok;
  if not Result then
    ReportGateRefusal(pOpts, pGate, MakeRefusal('dirty-baseline', '', pOpts.Project,
      Format('the project does not build before any edit (%d dcc error line(s), first: %s); fix it, then retry',
        [Length(pGate.Baseline.Errors), pGate.Baseline.Errors[0]]), 0));
end;

// DRAGLINT_CYCLEFIX_REPAIR_PROBE (ProbeSpec): TryRepair on canned lines, or CompileAfter on the tree.
procedure RunRepairProbe(const pStaged: TCyclePlanView; const pOpts: TCycleFixOptions;
  const pProjectDir, pTree, pLinesFile: string; var pGate: TGateReport);
begin
  if pLinesFile <> '' then
  begin
    pGate.After.Repairs:= TryRepair(pStaged, TFile.ReadAllLines(pLinesFile), pProjectDir, pTree);
    Exit;
  end;
  pGate.After      := CompileAfter(pStaged, pProjectDir, pTree + ExtractFileName(pOpts.Project), pOpts.Platform, BuildScratchDir);
  pGate.AfterStatus:= if pGate.After.Ok then 'ok' else 'error';
  pGate.AfterFiles := Length(PlanFiles(pStaged));
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
  Gate      : TGateReport;
  Brk       : Integer;
  Probe     : Boolean;
  ProbeTree : string;
  ProbeLines: string;
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
  Brk:= AnnounceSeams(pOpts, Probe, ProbeTree, ProbeLines);
  if not PassBaselineGate(pOpts, pSccs.Count > 0, Gate) then Exit(CExitRefused);
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
              BadPart:= Format('cycles --fix: cycle %d is planned as part %s, not --part %s ' +
                '(the other part comes with --part all, E18 Task 12)', [pView.CycleIndex, LowerCase(pView.Part), Wanted]);
            Exit(Only = 0);
          end;
          { a plan the gate passes is staged in the shadow tree; an anchor mismatch refuses the group }
          { Task 11: the apply's write path must NOT pass TamperAllowed(pOpts) here -- stage with False }
          { DRAGLINT_CYCLEFIX_BREAK (test seam, project under TEMP only) spoils the plan before staging }
          var Staged:= pView;
          if Brk <> 0 then Staged:= ApplyTestBreak(pView, Brk);
          if All.Count = 0 then All.AddRange(StageShadow(Staged, ProjectDir, ShadowDir, TamperAllowed(pOpts)));
          var Verdict:= All.ToArray;
          if Length(Verdict) = 0 then ShadowUsed:= ShadowDir;
          { Task 11: the apply writes the shadow into the project, then CompileAfter(Staged, ProjectDir,
            pOpts.Project, ...) builds it in place and repairs once; not Ok -> roll back, compile-error }
          if (Length(Verdict) = 0) and Probe then RunRepairProbe(Staged, pOpts, ProjectDir, ProbeTree, ProbeLines, Gate);
          Cycles.AddElement(CycleToJson(pView, Verdict, pGraph, Gate));
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
        Doc.AddPair('baseline', BaselineToJson(Gate));
        Doc.AddPair('refusals', TJSONArray.Create);
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
      var Timing:= TimingLine(Gate);
      if Timing <> '' then Writeln(Timing);
    end;
  finally
    Summary.Free;
    Playbook.Free;
    Cycles.Free;
  end;
end;

end.
