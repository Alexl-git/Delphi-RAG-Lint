unit DRagLint.V152.UNCONN;

{ Wave v152 (1.52.0-alpha) lane UNCONN -- unconnected-control and hanging-handler (ruling B2).
  Scaffold created EMPTY by lane FRAME; lane UNCONN owns this unit, its
  DRagLint.V152.UNCONN.Support helpers and DRagLint.Fix.V152.UNCONN. Called only by
  DRagLint.V151.Dispatch (the ONE provider mechanism; v152 lanes reuse the
  DRagLint.V151.Api types). How-to: C:\TEMP\claude\lanes\v152\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id: a control with a default event that nothing wires (ruling B2, D12).</summary>
  RULE_UNCONNECTED_CONTROL = 'unconnected-control';
  /// <summary>Rule id: an event-handler-shaped form method that nothing binds, assigns or calls (ruling B2).</summary>
  RULE_HANGING_HANDLER     = 'hanging-handler';

type
  /// <summary>Checker entry points of v152 lane UNCONN; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV152UNCONNRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Rule</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Rule"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V151.DFMA.Support.LoadDfm, DRagLint.V151.DFMA.Support.LoadPas, DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty, DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex, DRagLint.V152.UNCONN.CheckHanging, DRagLint.V152.UNCONN.CheckUnconnected, DRagLint.V152.UNCONN.Support.UcCountIdents, DRagLint.V152.UNCONN.UnitText</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.LoadDfm"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.LoadPas"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.UNCONN.TV152UNCONNRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.Core.Encoding, System.IOUtils
  , DRagLint.V151.Dfm.Common
  , DRagLint.V151.DFMA.Support
  , DRagLint.V152.UNCONN.Support
  ;

const
  SEV_WARNING = 'warning';

{ The lane declares two rules, both ON, severity warning (plan D7). }
class procedure TV152UNCONNRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_UNCONNECTED_CONTROL, 'dead-code', SEV_WARNING,
    'Control with a default event that has no event, no Action, no binding and no code reference'));
  ADecls.Add(V151Rule(RULE_HANGING_HANDLER, 'dead-code', SEV_WARNING,
    'Event-handler-shaped method bound in no form file and assigned or called nowhere in code'));
end;

class function TV152UNCONNRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@b081 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

/// Source text of the unit for identifier counting; ANSI decoding keeps every ASCII
/// identifier intact and never raises on a stray byte.
function UnitText(const U: TPasUnit): string;
begin
  Result:= TEncoding.ANSI.GetString(if Length(U.RawSrc) > 0 then U.RawSrc else U.Src);
end;

/// One flag per name: True when the project index references that name anywhere. All
/// False when the index cannot answer for this file (no store, or the file is not indexed):
/// the own-unit evidence the caller already applied is then the only evidence.
function UsedInIndex(const ACtx: TV151FileCtx; const ANames: TList<string>): TArray<Boolean>;
begin
  if (ACtx.Store <> nil) and (ACtx.FileId <> 0) then Result:= UcNamesReferenced(ACtx.Store, ANames.ToArray)
  else SetLength(Result, ANames.Count);
end;

/// unconnected-control: candidates are the form's own default-event controls that are
/// not wired in the .dfm; a candidate is silent when its name occurs in the unit text
/// beyond its field declaration, or (index available) is referenced anywhere by name.
function CheckUnconnected(const ACtx: TV151FileCtx; const U: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer; const ACounts: TUcIdentCounts): TArray<TLintFinding>;
var
  Lines: TArray<string>;
  Cand : TList<Integer>;
  Names: TList<string>;
begin
  Result:= nil;
  Lines:= ReadSourceFileLines(ACtx.DfmPath);  // LoadDfm just read it; a failure is logged by the dispatcher
  Cand := TList<Integer>.Create;
  Names:= TList<string>.Create;
  try
    for var I: Integer:= 1 to High(ADfm.Nodes) do
    begin
      var N: TDfmNode:= ADfm.Nodes[I];
      if (N.Kind <> dnkObject) or N.InInline or (N.Name = '') then Continue;
      if not UcIsDefaultEventClass(N.CompClass) or UcNodeWiredInDfm(ADfm, I, Lines) then Continue;
      var FieldIdx: Integer:= if ACls >= 0 then U.Classes[ACls].FieldIndex(N.Name) else -1;
      var Baseline: Integer:= if FieldIdx >= 0 then 1 else 0;
      if UcIdentCount(ACounts, N.Name) > Baseline then Continue;
      Cand.Add(I);
      Names.Add(N.Name);
    end;
    if Cand.Count = 0 then Exit;
    var Used: TArray<Boolean>:= UsedInIndex(ACtx, Names);
    for var I: Integer:= 0 to Cand.Count - 1 do
    begin
      if Used[I] then Continue;
      var N: TDfmNode:= ADfm.Nodes[Cand[I]];
      var Msg: string:= Format('%s: %s has no event handler, no Action, no data binding and no reference in code '
        + '-- the control does nothing; bind an event or an Action, or remove it', [N.Name, N.CompClass]);
      var FieldIdx: Integer:= if ACls >= 0 then U.Classes[ACls].FieldIndex(N.Name) else -1;
      Result:= Result + [if FieldIdx >= 0
        then MakeFinding(RULE_UNCONNECTED_CONTROL, ACtx.Path, U.Classes[ACls].Fields[FieldIdx].Line,
          U.Classes[ACls].Fields[FieldIdx].Col, SEV_WARNING, Msg)
        else MakeFinding(RULE_UNCONNECTED_CONTROL, ACtx.DfmPath, N.Line, N.Col, SEV_WARNING, Msg)];
    end;
  finally
    Names.Free;
    Cand.Free;
  end;
end;

/// hanging-handler: candidates are the form class's implemented methods with a
/// `Sender: TObject` parameter whose name the .dfm does not bind; a candidate is silent
/// when its name occurs in the unit text beyond its declaration and implementation
/// header (two per overload), or (index available) is referenced anywhere by name,
/// which includes the event-binding rows of every indexed form file.
function CheckHanging(const ACtx: TV151FileCtx; const U: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer; const ACounts: TUcIdentCounts): TArray<TLintFinding>;
var
  Cand : TList<Integer>;
  Names: TList<string>;
begin
  Result:= nil;
  if ACls < 0 then Exit;
  var Cls: string:= U.Classes[ACls].Name;
  var Bound: TArray<string>:= ADfm.HandlerNames;
  Cand := TList<Integer>.Create;
  Names:= TList<string>.Create;
  try
    for var I: Integer:= 0 to High(U.Routines) do
    begin
      var R: TPasRoutine:= U.Routines[I];
      if not SameText(R.OwnerClass, Cls) or not R.SenderObj or R.IsCtor or R.Body.IsNull then Continue;
      var Lower: string:= LowerCase(R.Name);
      var IsBound: Boolean:= False;
      for var B in Bound do
        if B = Lower then IsBound:= True;
      if IsBound then Continue;
      var Overloads: Integer:= 0;
      for var R2 in U.Routines do
        if SameText(R2.OwnerClass, Cls) and SameText(R2.Name, R.Name) then Inc(Overloads);
      if UcIdentCount(ACounts, R.Name) > 2 * Overloads then Continue;
      Cand.Add(I);
      Names.Add(R.Name);
    end;
    if Cand.Count = 0 then Exit;
    var Used: TArray<Boolean>:= UsedInIndex(ACtx, Names);
    for var I: Integer:= 0 to Cand.Count - 1 do
    begin
      if Used[I] then Continue;
      var R: TPasRoutine:= U.Routines[Cand[I]];
      Result:= Result + [MakeFinding(RULE_HANGING_HANDLER, ACtx.Path, R.Line, R.Col, SEV_WARNING,
        Format('%s.%s looks like an event handler (Sender: TObject) but no form file binds it and no code '
        + 'assigns, passes or calls it -- bind it to an event or remove it', [Cls, R.Name]))];
    end;
  finally
    Names.Free;
    Cand.Free;
  end;
end;

class function TV152UNCONNRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  var WantU: Boolean:= ACtx.Wants(RULE_UNCONNECTED_CONTROL);
  var WantH: Boolean:= ACtx.Wants(RULE_HANGING_HANDLER);
  if not (WantU or WantH) then Exit;
  var Dfm: TDfmDoc:= LoadDfm(ACtx.DfmPath);
  if Dfm.IsEmpty then Exit;
  var U: TPasUnit:= LoadPas(ACtx.Path);
  if not U.Ok then Exit;
  var Cls: Integer:= U.ClassIndex(Dfm.Nodes[0].CompClass);
  var Counts: TUcIdentCounts:= UcCountIdents(UnitText(U));
  try
    if WantU then Result:= Result + CheckUnconnected(ACtx, U, Dfm, Cls, Counts);
    if WantH then Result:= Result + CheckHanging(ACtx, U, Dfm, Cls, Counts);
  finally
    Counts.Free;
  end;
end;

class function TV152UNCONNRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@fbae -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152UNCONNRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@54e9 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

end.
