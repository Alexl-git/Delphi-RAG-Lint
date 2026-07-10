unit DRagLint.Convert.Apply;

{
  Track 3 (component conversion), sub-project B -- the convert-apply
  orchestrator. Given a rule set, a target .pas + .dfm pair, and an optional
  --only instance filter, it locates the component instances to convert in the
  .dfm, rewrites all five surfaces (DFM re-emit, .pas decl/uses, property/event
  access sites, creator sites, TODO markers), and returns the combined edit set
  plus a human-readable report.

  Task 1 (skeleton) landed the public types plus stub bodies. Task 2 implements
  instance LOCATION (FindConvertInstances, a scan of the .dfm's 'object Name:
  Class' headers) plus surface #1 (.pas declaration retype: 'Name: FromType;'
  -> 'Name: ToType;') and surface #2 (.pas uses-add for each distinct ToType,
  via TFindUnitRefactoring.Build). Task 3 (this revision) adds surface #3: the
  .dfm object-block RE-EMIT. For each located instance, its object block is
  sliced out of the .dfm by LINE RANGE (the instance's skComponent/skForm
  symbol in the index -- the same DFM tree-sitter parse the indexer already
  ran, so StartLine/EndLine already span the whole 'object Name: Class ...
  end' block, nesting and all; no separate text-based bracket-matching is
  needed), re-emitted via the 2a-i engine (DRagLint.Convert.DfmReemit.
  ReemitComponent) driven by the F/T property trees (BuildPropTree, same
  Depth=6/ToPersistent=True convention as convert-validate/convert-reemit),
  and replaces the original lines via a tekDeleteLines + tekInsertLines pair
  that preserves the block's original indentation. A ReemitComponent failure
  (Ok=False) skips the WHOLE instance -- no .pas retype/uses edits either --
  so a component is never left half-converted; see BuildApplyPlan's remarks.
  Surfaces #4-#5 (property/event access rewrite, creator-site rewrite) are
  deferred to Task 6; TApplyReport.AccessSites/CreatorSites stay empty until
  then.
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
/// Task 3 implements surface #3 (.dfm object-block re-emit): each located
/// instance's .dfm object block is replaced (tekDeleteLines + tekInsertLines,
/// same original indentation) with the T block from ReemitComponent, driven by
/// the F/T property trees (BuildPropTree, Depth=6/ToPersistent=True). A
/// ReemitComponent Ok=False (hard re-emit failure) SKIPS THE WHOLE INSTANCE --
/// its .pas retype/uses edits (surfaces #1/#2) are also withheld, and
/// Report.Warnings gets an entry -- rather than leave a component converted in
/// its .pas declaration but not in its .dfm block (or vice versa). Surfaces
/// #4-#5 (property/event access rewrite, creator-site rewrite -- Task 6)
/// contribute no edits yet. Ok=False only on a hard failure (missing .pas/
/// .dfm, or zero instances matched); Ok=True with per-instance problems noted
/// in Report.Warnings otherwise (including every instance skipped by a
/// re-emit failure).</returns>
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

// Resolves a bare class name (as it appears in a #convert rule / .dfm object
// header, e.g. 'TOldEdit') to its fully-qualified name (e.g. 'OldEditUnit.
// TOldEdit') for BuildPropTree, which resolves AClassQName via an EXACT
// qualified_name match. Filters FindSymbolsByExactName to skClass so an
// unrelated same-named property/field never wins. '' when unresolved.
function ResolveClassQName(const AStore: ISymbolStore; const AClassName: string): string;
var
  Cands: TArray<TSymbol>;
  S    : TSymbol;
begin
  Result:= '';
  Cands:= AStore.FindSymbolsByExactName(AClassName);
  for S in Cands do
    if S.Kind = skClass then Exit(S.QualifiedName);
end;

// Locates AInstanceName's DFM object-block symbol (skForm for the DFM's root
// object, skComponent for every nested one -- see DRagLint.Parser.DFM.
// WalkObject) among ADfmFileSyms, matching both Name and Signature (the DFM
// class, e.g. 'TOldEdit') so a name collision with a differently-typed
// instance is not mismatched. StartLine/EndLine on the returned symbol are the
// tree-sitter 'object' node's full span (header through its matching 'end',
// nesting already resolved by the grammar) -- exactly the line range to slice
// out of the .dfm text. Id=0 when not found.
function FindDfmInstanceSymbol(const ADfmFileSyms: TArray<TSymbol>;
  const AInstanceName, AFromType: string): TSymbol;
var
  S: TSymbol;
begin
  Result:= Default(TSymbol);
  for S in ADfmFileSyms do
    if (S.Kind in [skForm, skComponent]) and SameText(S.Name, AInstanceName) and
       SameText(S.Signature, AFromType) then Exit(S);
end;

// Leading-whitespace run of ALine, e.g. '  object Edit1: TOldEdit' -> '  '.
// Used to re-apply the original block's indentation to the re-emitted T text,
// which EmitBlock always renders starting at column 1 (AIndent=0).
function LeadingIndent(const ALine: string): string;
var
  i: Integer;
begin
  i:= 1;
  while (i <= Length(ALine)) and CharInSet(ALine[i], [' ', #9]) do Inc(i);
  Result:= Copy(ALine, 1, i - 1);
end;

// Prefixes every line of AReemittedBlock (EmitBlock's CRLF-joined, column-1
// output, trailing CRLF trimmed) with AIndent, so the replacement block lands
// at the same indentation depth as the original.
function ReindentBlock(const AReemittedBlock, AIndent: string): string;
var
  Text_: string;
  Parts: TArray<string>;
  i    : Integer;
  SB   : TStringBuilder;
begin
  Text_:= AReemittedBlock;
  while (Length(Text_) >= 2) and (Copy(Text_, Length(Text_) - 1, 2) = #13#10) do
    Text_:= Copy(Text_, 1, Length(Text_) - 2);
  Parts:= Text_.Replace(#13#10, #10).Split([#10]);
  SB:= TStringBuilder.Create;
  try
    for i:= 0 to High(Parts) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(AIndent).Append(Parts[i]);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function BuildApplyPlan(const AStore: ISymbolStore; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TApplyResult;
var
  DfmText     : string;
  DfmLines    : TArray<string>;
  DfmFileSyms : TArray<TSymbol>;
  Instances   : TArray<TConvertInstance>;
  Inst        : TConvertInstance;
  Edits       : TList<TTextEdit>;
  Converted   : TList<string>;
  Warnings    : TList<string>;
  ReemitNotes : TList<string>;
  PasLines    : TStringList;
  PasFileSyms : TArray<TSymbol>;
  Sym         : TSymbol;
  DoneUnits   : TDictionary<string, Boolean>; { ToType -> already handled (added or already-used) }
  ToTypesSeen : TList<string>;
  E           : TTextEdit;
  TreeCache   : TDictionary<string, TPropTree>; { qname -> tree, built once per distinct type }
  Opts        : TPropTreeOptions;

  // F/T property trees are the same for every instance sharing a (FromType,
  // ToType) rule pair -- cache by resolved qname so a form with N instances of
  // the same F type only builds each tree once.
  function TreeFor(const AClassName: string): TPropTree;
  var
    QName: string;
    Cand : TPropTree;
  begin
    QName:= ResolveClassQName(AStore, AClassName);
    if QName = '' then Exit(Default(TPropTree));
    if TreeCache.TryGetValue(QName, Cand) then Exit(Cand);
    Cand:= BuildPropTree(AStore, QName, Opts);
    TreeCache.Add(QName, Cand);
    Result:= Cand;
  end;

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

  { split for line-indexed slicing (surface #3); tekDeleteLines/tekInsertLines
    are 1-based against this same line count, matching TTextEditApplier.Apply's
    own TStringList.Text split. }
  DfmLines:= DfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);

  PasFileSyms:= AStore.FindSymbolsByFile(AUnitPas);
  if Length(PasFileSyms) = 0 then
    PasFileSyms:= AStore.FindSymbolsByFile(TPath.GetFullPath(AUnitPas));

  DfmFileSyms:= AStore.FindSymbolsByFile(ADfmPath);
  if Length(DfmFileSyms) = 0 then
    DfmFileSyms:= AStore.FindSymbolsByFile(TPath.GetFullPath(ADfmPath));

  Opts.Depth       := 6;
  Opts.ToPersistent:= True;

  PasLines:= TStringList.Create;
  Edits    := TList<TTextEdit>.Create;
  Converted:= TList<string>.Create;
  Warnings := TList<string>.Create;
  ReemitNotes:= TList<string>.Create;
  DoneUnits:= TDictionary<string, Boolean>.Create;
  ToTypesSeen:= TList<string>.Create;
  TreeCache:= TDictionary<string, TPropTree>.Create;
  try
    PasLines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AUnitPas));

    for Inst in Instances do
    begin
      { -- surface #3 FIRST: the .dfm object-block re-emit. A hard re-emit
        failure skips the WHOLE instance (no .pas retype/uses edits either) --
        see BuildApplyPlan's <returns> remarks: converting the .pas declaration
        while leaving the .dfm block in its OLD (From) shape (or vice versa)
        would hand back a component that neither compiles cleanly against the
        new type nor matches its own .dfm, which is worse than leaving it
        entirely unconverted + warned. }
      var DfmSym: TSymbol:= FindDfmInstanceSymbol(DfmFileSyms, Inst.InstanceName, Inst.FromType);
      if DfmSym.Id = 0 then
      begin
        Warnings.Add(Format('%s: could not locate .dfm object block for "%s: %s" in %s -- instance skipped',
          [Inst.InstanceName, Inst.InstanceName, Inst.FromType, ADfmPath]));
        Continue;
      end;

      var BlockStart: Integer:= DfmSym.StartLine;
      var BlockEnd  : Integer:= DfmSym.EndLine;
      if (BlockStart < 1) or (BlockEnd < BlockStart) or (BlockEnd > Length(DfmLines)) then
      begin
        Warnings.Add(Format('%s: .dfm object block line range [%d..%d] out of bounds in %s -- instance skipped',
          [Inst.InstanceName, BlockStart, BlockEnd, ADfmPath]));
        Continue;
      end;

      var BlockText: string:= String.Join(#13#10, DfmLines, BlockStart - 1, BlockEnd - BlockStart + 1);
      var FromTree: TPropTree:= TreeFor(Inst.FromType);
      var ToTree  : TPropTree:= TreeFor(Inst.ToType);
      var ReemitRes: TReemitResult:= ReemitComponent(BlockText, ARules, FromTree, ToTree);
      if not ReemitRes.Ok then
      begin
        Warnings.Add(Format('%s: .dfm re-emit failed (%s) -- instance skipped', [Inst.InstanceName, ReemitRes.Error]));
        Continue;
      end;

      var Indent: string:= LeadingIndent(DfmLines[BlockStart - 1]);
      E:= Default(TTextEdit);
      E.FilePath:= ADfmPath;
      E.Kind    := tekDeleteLines;
      E.Line    := BlockStart;
      E.EndLine := BlockEnd;
      Edits.Add(E);

      E:= Default(TTextEdit);
      E.FilePath:= ADfmPath;
      E.Kind    := tekInsertLines;
      E.Line    := BlockStart - 1; { insert AFTER line BlockStart-1 == at the deleted block's old position }
      E.Text    := ReindentBlock(ReemitRes.DfmText, Indent);
      Edits.Add(E);

      for var N in ReemitRes.Report.Dropped    do ReemitNotes.Add(Format('%s: dropped %s', [Inst.InstanceName, N]));
      for var N in ReemitRes.Report.Mismatched do ReemitNotes.Add(Format('%s: mismatched %s', [Inst.InstanceName, N]));
      for var N in ReemitRes.Report.OwnedParts do ReemitNotes.Add(Format('%s: owned-part %s', [Inst.InstanceName, N]));
      for var N in ReemitRes.Report.Created    do ReemitNotes.Add(Format('%s: created %s', [Inst.InstanceName, N]));
      for var N in ReemitRes.Report.Notes      do ReemitNotes.Add(Format('%s: %s', [Inst.InstanceName, N]));

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
    Result.Report.ReemitNotes:= ReemitNotes.ToArray;
    Result.Ok:= True;
  finally
    PasLines.Free;
    Edits.Free;
    Converted.Free;
    Warnings.Free;
    ReemitNotes.Free;
    DoneUnits.Free;
    ToTypesSeen.Free;
    TreeCache.Free;
  end;
end;

end.
