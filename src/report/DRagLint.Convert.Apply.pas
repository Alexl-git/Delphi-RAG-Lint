unit DRagLint.Convert.Apply;

{
  Track 3 (component conversion), sub-project B -- the convert-apply
  orchestrator. Given a rule set, a target .pas + .dfm pair, and an optional
  --only instance filter, it locates the component instances to convert in the
  .dfm, rewrites all five surfaces (DFM re-emit, .pas decl/uses, property/event
  access sites, creator sites, TODO markers), and returns the combined edit set
  plus a human-readable report.

  Task 1 (skeleton) landed the public types plus stub bodies. Task 2 (this
  revision) implements instance LOCATION (FindConvertInstances, a scan of the
  .dfm's 'object Name: Class' headers) plus surface #1 (.pas declaration
  retype: 'Name: FromType;' -> 'Name: ToType;') and surface #2 (.pas uses-add
  for each distinct ToType, via TFindUnitRefactoring.Build). Surfaces #3-#5
  (DFM re-emit, property/event access rewrite, creator-site rewrite) are
  deferred to Tasks 3/6; TApplyReport.ReemitNotes/AccessSites/CreatorSites stay
  empty until those land.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Interfaces,
  DRagLint.Core.Model,
  DRagLint.Convert.Rules,
  DRagLint.Convert.DfmReemit,
  DRagLint.Convert.PropTree,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>One component instance selected for conversion: its DFM instance
  /// name, its current (From) class, and the class it is being converted to
  /// (To), per the matching #convert rule.</summary>
  TConvertInstance = record
    InstanceName: string;
    FromType    : string;
    ToType      : string;
  end;

  /// <summary>Human-readable summary of one convert-apply run, grouped by
  /// surface: Converted lists one line per instance actually rewritten;
  /// AccessSites and CreatorSites list the .pas property/event-access and
  /// object-creation call sites that were rewritten; Todos lists spots that
  /// need manual follow-up (e.g. an unmapped property); ReemitNotes carries
  /// the per-instance notes from the DFM re-emit engine (DRagLint.Convert.
  /// DfmReemit); Warnings lists non-fatal problems found while building the
  /// plan.</summary>
  TApplyReport = record
    Converted   : TArray<string>;
    AccessSites : TArray<string>;
    CreatorSites: TArray<string>;
    Todos       : TArray<string>;
    ReemitNotes : TArray<string>;
    Warnings    : TArray<string>;
  end;

  /// <summary>The outcome of BuildApplyPlan: the full set of text edits to
  /// apply (see DRagLint.Refactor.TextEdit.TTextEditApplier.Apply /
  /// RenderDryRun), the human-readable Report, and Ok/Error signalling
  /// whether a plan could be built at all.</summary>
  /// <remarks>Ok=False means no edits were computed (e.g. the .pas/.dfm file
  /// was not found, or no instance matched a #convert rule -- possibly because
  /// --only filtered everything out); Error then carries an ASCII diagnostic
  /// message. Ok=True does not imply every instance converted cleanly --
  /// per-instance problems are surfaced via Report.Todos / Report.Warnings
  /// even when Ok=True (e.g. a field declaration that could not be located, or
  /// a ToType whose unit could not be resolved for the uses-add).</remarks>
  TApplyResult = record
    Edits : TArray<TTextEdit>;
    Report: TApplyReport;
    Ok    : Boolean;
    Error : string;
  end;

/// <summary>Builds the full convert-apply plan for one unit: locates the
/// component instances to convert in ADfmPath (via FindConvertInstances),
/// rewrites all five surfaces per ARules, and returns the combined edit set
/// plus report.</summary>
/// <param name="AStore">The symbol index used to resolve declarations,
/// property/event access sites, and creator sites.</param>
/// <param name="AUnitPas">Path to the .pas file that declares/uses the
/// instances being converted.</param>
/// <param name="ADfmPath">Path to the .dfm file containing the instances'
/// component blocks.</param>
/// <param name="ARules">The validated conversion rule set (see
/// DRagLint.Convert.Rules) describing which From types convert to which To
/// types and how each property/event maps.</param>
/// <param name="AOnly">Optional allow-list of instance names to restrict the
/// plan to; empty means convert every instance that matches a rule.</param>
/// <returns>A TApplyResult. Task 2 implements surface #1 (.pas declaration
/// retype) and surface #2 (.pas uses-add): each located instance contributes a
/// tekReplaceInLine edit swapping its FromType token for ToType, plus (once
/// per distinct ToType) the uses-add edit(s) from TFindUnitRefactoring.Build.
/// Surfaces #3-#5 (DFM re-emit, property/event access rewrite, creator-site
/// rewrite -- Tasks 3/6) contribute no edits yet. Ok=False only on a hard
/// failure (missing .pas/.dfm, or zero instances matched); Ok=True with
/// per-instance problems noted in Report.Warnings otherwise.</returns>
function BuildApplyPlan(const AStore: ISymbolStore; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TApplyResult;

/// <summary>Scans a .dfm's component headers (top-level and nested) and
/// returns the instances that should be converted: those whose class matches
/// a '#convert FromType' rule in ARules, filtered by AOnly when given.</summary>
/// <param name="ADfmText">The full text of the .dfm (or a single form's
/// component tree) to scan.</param>
/// <param name="ARules">The validated conversion rule set; only rules'
/// FromType classes are matched against each object header's class.</param>
/// <param name="AOnly">Optional allow-list of instance names; when non-empty,
/// only instances whose name appears here are returned.</param>
/// <returns>One TConvertInstance per matching component, in the order found.</returns>
/// <remarks>Scans for lines shaped like 'object &lt;Name&gt;: &lt;Class&gt;' (any
/// indentation depth, so both top-level and nested components are found -- a
/// nested instance is as convertible as a top-level one). A line is recognised
/// as an object header when, after trimming leading whitespace, it starts with
/// the keyword 'object ' followed by an identifier, a ':', and a second
/// identifier (the class); anything else on the line (extra whitespace, a
/// trailing comment) is tolerated. Lines that don't match this shape (property
/// lines, 'end', inherited/inline headers) are skipped -- this is a location
/// scan only, not a full DFM parse (Task 3's ParseDfmBlock/ReemitComponent do
/// the real per-instance re-emit). Pure; deterministic; no I/O.</remarks>
function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TConvertInstance>;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  System.Classes;

// True when AName appears (case-insensitively) in AOnly. Empty AOnly means
// "no filter" -- everything passes.
function InOnlyList(const AName: string; const AOnly: TArray<string>): Boolean;
var
  N: string;
begin
  if Length(AOnly) = 0 then Exit(True);
  for N in AOnly do
    if SameText(N, AName) then Exit(True);
  Result:= False;
end;

// Looks up the #convert rule whose FromType matches AClassName (SameText).
// Returns True + the rule's ToType when found.
function FindConvertRuleFor(const ARules: TConversionRuleSet; const AClassName: string;
  out AToType: string): Boolean;
var
  R: TConversionRule;
begin
  AToType:= '';
  for R in ARules.Rules do
    if (R.Kind = rkConvert) and SameText(R.FromType, AClassName) then
    begin AToType:= R.ToType; Exit(True); end;
  Result:= False;
end;

// Parses one trimmed DFM line as an 'object Name: Class' header. Returns True
// + Name/ClassName_ on a match; False for any other line shape (property
// lines, 'end', 'object Name' with no class -- a nested Font/inherited-shape
// sub-object, which has no type to convert and is correctly skipped).
function TryParseObjectHeader(const ATrimmedLine: string; out AName, AClassName: string): Boolean;
const
  KW = 'object ';
var
  Rest   : string;
  ColonAt: Integer;
  NamePart, ClassPart: string;
begin
  AName:= ''; AClassName:= '';
  if not StartsText(KW, ATrimmedLine) then Exit(False);
  Rest:= Trim(Copy(ATrimmedLine, Length(KW) + 1, MaxInt));
  ColonAt:= Pos(':', Rest);
  if ColonAt = 0 then Exit(False); { 'object Name' with no class -- e.g. a Font sub-object }
  NamePart := Trim(Copy(Rest, 1, ColonAt - 1));
  ClassPart:= Trim(Copy(Rest, ColonAt + 1, MaxInt));
  { the class token may be followed by nothing else on a well-formed DFM line;
    take the leading identifier run so a stray trailing comment doesn't break it }
  var i: Integer:= 1;
  while (i <= Length(ClassPart)) and (CharInSet(ClassPart[i], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) do Inc(i);
  ClassPart:= Copy(ClassPart, 1, i - 1);
  if (NamePart = '') or (ClassPart = '') then Exit(False);
  AName:= NamePart; AClassName:= ClassPart;
  Result:= True;
end;

function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TConvertInstance>;
var
  Lines : TArray<string>;
  L     : string;
  Trimmed: string;
  Name_, ClassName_, ToType: string;
  List  : TList<TConvertInstance>;
  Inst  : TConvertInstance;
begin
  Result:= nil;
  if Trim(ADfmText) = '' then Exit;

  Lines:= ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);

  List:= TList<TConvertInstance>.Create;
  try
    for L in Lines do
    begin
      Trimmed:= Trim(L);
      if not TryParseObjectHeader(Trimmed, Name_, ClassName_) then Continue;
      if not FindConvertRuleFor(ARules, ClassName_, ToType) then Continue;
      if not InOnlyList(Name_, AOnly) then Continue;

      Inst:= Default(TConvertInstance);
      Inst.InstanceName:= Name_;
      Inst.FromType    := ClassName_;
      Inst.ToType      := ToType;
      List.Add(Inst);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// Locates the 1-based [Col, EndCol) span of the FromType token on the field
// declaration line 'AInstanceName: AFromType' within lines [AStartLine,
// AEndLine] (inclusive, 1-based, matching TSymbol.StartLine/EndLine for the
// skField symbol -- which spans the WHOLE 'Name: Type;' declaration, not just
// the type). Returns True + ALine/ACol/AEndCol on a match. A scoped text
// search rather than a full re-parse: the field symbol already told us WHICH
// line(s) to look at; this only finds the type token's exact columns for the
// tekReplaceInLine edit.
function LocateFieldTypeToken(const APasLines: TStringList; AStartLine, AEndLine: Integer;
  const AInstanceName, AFromType: string; out ALine, ACol, AEndCol: Integer): Boolean;
var
  LineNo: Integer;
  S     : string;
  NamePos, ColonPos, TypePos: Integer;
begin
  ALine:= 0; ACol:= 0; AEndCol:= 0;
  if AStartLine < 1 then AStartLine:= 1;
  if AEndLine > APasLines.Count then AEndLine:= APasLines.Count;
  for LineNo:= AStartLine to AEndLine do
  begin
    if (LineNo < 1) or (LineNo > APasLines.Count) then Continue;
    S:= APasLines[LineNo - 1]; { 0-based TStringList, 1-based LineNo }

    { find the field name as a whole word }
    NamePos:= 1;
    repeat
      NamePos:= PosEx(AInstanceName, S, NamePos);
      if NamePos = 0 then Break;
      var AfterOk: Boolean:= (NamePos + Length(AInstanceName) > Length(S)) or
        not CharInSet(S[NamePos + Length(AInstanceName)], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
      var BeforeOk: Boolean:= (NamePos = 1) or
        not CharInSet(S[NamePos - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
      if AfterOk and BeforeOk then Break;
      Inc(NamePos);
    until False;
    if NamePos = 0 then Continue;

    { the ':' after the name, then the type token }
    ColonPos:= PosEx(':', S, NamePos + Length(AInstanceName));
    if ColonPos = 0 then Continue;
    TypePos:= ColonPos + 1;
    while (TypePos <= Length(S)) and (S[TypePos] = ' ') do Inc(TypePos);
    if (TypePos + Length(AFromType) - 1 > Length(S)) or
       (not SameText(Copy(S, TypePos, Length(AFromType)), AFromType)) then Continue;
    { require a non-identifier boundary after the type token (';', ' ', end-of-line) }
    var TypeEndPos: Integer:= TypePos + Length(AFromType);
    if (TypeEndPos <= Length(S)) and CharInSet(S[TypeEndPos], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Continue;

    ALine  := LineNo;
    ACol   := TypePos;
    AEndCol:= TypeEndPos;
    Exit(True);
  end;
  Result:= False;
end;

function BuildApplyPlan(const AStore: ISymbolStore; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TApplyResult;
var
  DfmText     : string;
  Instances   : TArray<TConvertInstance>;
  Inst        : TConvertInstance;
  Edits       : TList<TTextEdit>;
  Converted   : TList<string>;
  Warnings    : TList<string>;
  PasLines    : TStringList;
  PasFileSyms : TArray<TSymbol>;
  Sym         : TSymbol;
  DoneUnits   : TDictionary<string, Boolean>; { ToType -> already handled (added or already-used) }
  ToTypesSeen : TList<string>;
  E           : TTextEdit;
begin
  Result:= Default(TApplyResult);
  Result.Ok:= False;

  if not TFile.Exists(AUnitPas) then
  begin Result.Error:= Format('unit .pas not found: %s', [AUnitPas]); Exit; end;
  if not TFile.Exists(ADfmPath) then
  begin Result.Error:= Format('.dfm not found: %s', [ADfmPath]); Exit; end;

  DfmText:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(ADfmPath));
  Instances:= FindConvertInstances(DfmText, ARules, AOnly);
  if Length(Instances) = 0 then
  begin
    Result.Error:= 'no convertible instances found (no #convert rule matched a .dfm instance, or --only filtered everything out)';
    Exit;
  end;

  PasFileSyms:= AStore.FindSymbolsByFile(AUnitPas);
  if Length(PasFileSyms) = 0 then
    PasFileSyms:= AStore.FindSymbolsByFile(TPath.GetFullPath(AUnitPas));

  PasLines:= TStringList.Create;
  Edits    := TList<TTextEdit>.Create;
  Converted:= TList<string>.Create;
  Warnings := TList<string>.Create;
  DoneUnits:= TDictionary<string, Boolean>.Create;
  ToTypesSeen:= TList<string>.Create;
  try
    PasLines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AUnitPas));

    for Inst in Instances do
    begin
      { -- surface #1: locate the published field decl 'Name: FromType;' via
        the field symbol (gives us the line range to scope the text search),
        then find the exact FromType token span for a tekReplaceInLine edit. }
      var Found: Boolean:= False;
      for Sym in PasFileSyms do
      begin
        if (Sym.Kind <> skField) or (not SameText(Sym.Name, Inst.InstanceName)) or
           (not SameText(Sym.Signature, Inst.FromType)) then Continue;

        var FLine, FCol, FEndCol: Integer;
        if LocateFieldTypeToken(PasLines, Sym.StartLine, Sym.EndLine,
             Inst.InstanceName, Inst.FromType, FLine, FCol, FEndCol) then
        begin
          E:= Default(TTextEdit);
          E.FilePath:= AUnitPas;
          E.Kind    := tekReplaceInLine;
          E.Line    := FLine;
          E.Col     := FCol;
          E.EndCol  := FEndCol;
          E.Text    := Inst.ToType;
          Edits.Add(E);
          Converted.Add(Format('%s: %s -> %s', [Inst.InstanceName, Inst.FromType, Inst.ToType]));
          Found:= True;
        end;
        Break; { one matching field symbol is enough }
      end;
      if not Found then
        Warnings.Add(Format('%s: could not locate field declaration "%s: %s" in %s',
          [Inst.InstanceName, Inst.InstanceName, Inst.FromType, AUnitPas]));

      { -- surface #2: uses-add for each distinct ToType (once per type). }
      if not DoneUnits.ContainsKey(Inst.ToType) then
      begin
        DoneUnits.Add(Inst.ToType, True);
        ToTypesSeen.Add(Inst.ToType);
      end;
    end;

    for var ToType_ in ToTypesSeen do
    begin
      var ResolvedUnit: string;
      var AlreadyUsed : Boolean;
      var UseEdits: TArray<TTextEdit>:= TFindUnitRefactoring.Build(AStore, ToType_, AUnitPas, ResolvedUnit, AlreadyUsed);
      if AlreadyUsed then Continue;
      if Length(UseEdits) = 0 then
      begin
        Warnings.Add(Format('could not resolve a unit declaring "%s" to add to uses', [ToType_]));
        Continue;
      end;
      for E in UseEdits do Edits.Add(E);
    end;

    Result.Edits          := Edits.ToArray;
    Result.Report.Converted:= Converted.ToArray;
    Result.Report.Warnings := Warnings.ToArray;
    Result.Ok:= True;
  finally
    PasLines.Free;
    Edits.Free;
    Converted.Free;
    Warnings.Free;
    DoneUnits.Free;
    ToTypesSeen.Free;
  end;
end;

end.
