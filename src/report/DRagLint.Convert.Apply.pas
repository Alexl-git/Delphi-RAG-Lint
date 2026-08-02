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
  Task 5 adds surface #5: RUNTIME-CREATION sites. Every explicit 'FromType.
  Xxx(...)' construction (e.g. 'Edit1 := TOldEdit.Create(Self);') found in the
  .pas via FindConstructionSites gets its type token rewritten to ToType PLUS
  an unconditional TODO end-of-line comment marker -- ToType's constructor/
  init may take a different shape, and this applier never attempts to fix up
  constructor ARGUMENTS; the marker is the safety net. TApplyReport.
  CreatorSites/Todos are populated from this surface. Task 6 (this revision)
  adds surface #4: instance-scoped property/event ACCESS rewrite. For each
  renaming '#link ToMember <- FromMember' rule (ToMember <> FromMember,
  single-segment paths only), FindMemberAccessSites queries the .pas file's
  own refs for ref-gap G's 'member-access' kind (NameText=FromMember, at the
  member token's own span) and resolves each hit's RECEIVER by reading the
  source line text immediately before the member token (ResolveMemberAccess
  Receiver) -- the exprDot parser guarantees a plain identifier sits there.
  A site is only rewritten (FromMember -> ToMember, a tekReplaceInLine on the
  member token) when its receiver names one of THIS unit's converted
  instances (tracked via ConvertedInstNames, populated only for instances
  that survived the surface #3 re-emit checkpoint) -- an access on a
  different, unconverted receiver (e.g. 'Other.Caption' when Other is not a
  converted instance) is left untouched. TApplyReport.AccessSites is
  populated from this surface.
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

  /// <summary>Outcome of CheckFreshness: whether the F and T types' indexed
  /// source is safe to trust for this convert-apply run.</summary>
  /// <remarks>Fresh=True only when BOTH the From and To types are indexed
  /// (ResolveClassQName resolves a qualified name) AND their declaring
  /// source files are up to date on disk (ISymbolStore.FileIsUpToDate,
  /// comparing the CURRENT on-disk mtime+sha256 against what was indexed).
  /// Fresh=False covers two distinct causes, both surfaced as human-readable
  /// entries in Reasons: (a) "stale" -- the type IS indexed but its source
  /// file has changed on disk since the last index run, so BuildPropTree
  /// would be working from an outdated property tree; (b) "not indexed" --
  /// ResolveClassQName returned '' for the type, so BuildPropTree would
  /// silently get an EMPTY tree (no properties, no events) rather than an
  /// error. Both are guard failures for the same reason: the conversion plan
  /// would be built from a property tree that does not reflect the type's
  /// real current shape.</remarks>
  TFreshnessResult = record
    Fresh  : Boolean;
    Reasons: TArray<string>;
  end;

/// <summary>Verifies the F and T component types named by ARules' first
/// #convert rule are both indexed and current before BuildApplyPlan trusts
/// their property trees.</summary>
/// <param name="AStores">The symbol indexes to check against, in the order
/// given (one per --db); the first store that resolves a given type wins
/// (see CheckTypeFreshness's remarks) -- the From and To types, and the
/// form's own instances, may live in DIFFERENT --db files.</param>
/// <param name="ARules">The conversion rule set; the FromType/ToType of its
/// first rkConvert rule are the two types checked.</param>
/// <returns>A TFreshnessResult. Fresh=True when both types resolve to an
/// indexed class in SOME store AND their declaring files are up to date on
/// disk. Fresh=False with one or more human-readable Reasons entries
/// otherwise (see TFreshnessResult's remarks for the two distinct failure
/// causes).</returns>
/// <remarks>Pure read-only: computes the on-disk mtime (unix seconds) and
/// sha256 of each type's declaring source file (mirroring DRagLint.Core.
/// Indexer's own incremental-skip basis: raw bytes, ANSI-decoded for the
/// sha) and asks the store whether that exact (mtime, sha) pair is what is
/// indexed. A type with no #convert rule in ARules at all is treated as
/// vacuously fresh (nothing to check) -- callers should have already
/// validated ARules has at least one #convert rule before reaching here.</remarks>
function CheckFreshness(const AStores: TArray<ISymbolStore>; const ARules: TConversionRuleSet): TFreshnessResult;

/// <summary>Builds the full convert-apply plan for one unit: locates the
/// component instances to convert in ADfmPath (via FindConvertInstances),
/// rewrites all five surfaces per ARules, and returns the combined edit set
/// plus report.</summary>
/// <param name="AStores">The symbol indexes to resolve against, in the order
/// given (one per --db). TYPE resolution (From/To property trees, ctor-name
/// lookups) tries every store in order, first-that-resolves-wins -- the
/// From/To types may live in a DIFFERENT --db than the unit/instance being
/// converted (Bug 2). Unit-scoped lookups (the .pas/.dfm's own symbols and
/// refs) use whichever store actually has AUnitPas/ADfmPath indexed.</param>
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
/// its .pas declaration but not in its .dfm block (or vice versa). Task 5
/// implements surface #5 (runtime-creator retype + TODO marker). Task 6
/// implements surface #4 (property/event access-site rewrite): for each
/// renaming '#link ToMember &lt;- FromMember' rule, every 'member-access' ref
/// (ref-gap G) in the unit whose receiver names a converted instance (one
/// that survived the surface #3 re-emit checkpoint) contributes a
/// tekReplaceInLine edit swapping FromMember for ToMember at that access
/// site; Report.AccessSites lists each rewrite. An access on a receiver that
/// is NOT a converted instance is left untouched -- see FindMemberAccessSites.
/// Ok=False only on a hard failure (missing .pas/.dfm, or zero instances
/// matched); Ok=True with per-instance problems noted in Report.Warnings
/// otherwise (including every instance skipped by a re-emit failure).</returns>
function BuildApplyPlan(const AStores: TArray<ISymbolStore>; const AUnitPas, ADfmPath: string;
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
  System.Classes,
  System.Hash,
  System.DateUtils;

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

// Strips a leading 'Unit.' qualifier from a type name, returning only the
// bare tail (e.g. 'LibA.TSrcBtn' -> 'TSrcBtn'; 'TSrcBtn' unchanged). A #convert
// rule's FromType/ToType header may name a type either bare ('TSrcBtn') or
// fully qualified ('LibA.TSrcBtn') -- convert-scaffold and the rule editor
// emit both forms -- but a .dfm object header is ALWAYS bare ('object btn1:
// TSrcBtn', never 'object btn1: LibA.TSrcBtn') and FindSymbolsByExactName /
// the .pas field-decl type token match against the bare name column too (see
// ResolveClassQName's own remarks). Bug 1 fix: without this, a qualified
// FromType header matched zero .dfm instances ("no convertible instances
// found").
function BareTypeTail(const AQName: string): string;
var
  DotAt: Integer;
begin
  DotAt:= LastDelimiter('.', AQName);
  if DotAt > 0 then Result:= Copy(AQName, DotAt + 1, MaxInt)
  else Result:= AQName;
end;

// Looks up the #convert rule whose FromType matches AClassName (SameText,
// compared by BARE TAIL -- see BareTypeTail -- so a qualified rule header
// still matches the .dfm's always-bare object-header class). Returns True +
// the rule's ToType (also reduced to its bare tail, so every downstream
// lookup that expects a bare class name -- ResolveClassQName, the field-decl
// retype text, GetConstructorNames/ToTypeHasGenericCreate -- keeps working
// whether the rule's header was bare or qualified) when found.
function FindConvertRuleFor(const ARules: TConversionRuleSet; const AClassName: string;
  out AToType: string): Boolean;
var
  R: TConversionRule;
begin
  AToType:= '';
  for R in ARules.Rules do
    if (R.Kind = rkConvert) and SameText(BareTypeTail(R.FromType), AClassName) then
    begin AToType:= BareTypeTail(R.ToType); Exit(True); end;
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

// One construction site: 'AFromType.<ctor>(' found as a whole-word AFromType
// token immediately followed (ignoring intervening whitespace) by '.' and a
// constructor-name identifier. Line/Col/EndCol locate the AFromType token
// itself (1-based, EndCol exclusive) for a tekReplaceInLine edit -- mirrors
// TReference.StartLine/StartCol/EndCol, the same span the indexer already
// recorded for this ref (kind='read', name_text=AFromType).
type
  TCreatorSite = record
    Line, Col, EndCol: Integer;
    CtorName: string; // the identifier after '.', e.g. 'Create' -- always one of AKnownCtorNames on a match
  end;

// Enumerates AClassName's own constructor names (skConstructor children, via
// FindAllChildSymbols -- same lookup/filter ToTypeHasGenericCreate uses for
// its Create-shape probe) for the surface #5 construction-shape check below.
// Inherited constructors are NOT walked (no cheap "walk the base-class chain"
// available here without a second symbol resolve per ancestor; the class's
// OWN constructors plus the fallback below cover the near-totality of real
// component/class construction sites this applier will see). When AClassName
// resolves to an indexed skClass with zero indexed skConstructor children (or
// does not resolve to a class at all), FALLS BACK to ['Create'] -- the
// near-universal VCL/RTL constructor name -- rather than accepting an
// unbounded set of identifiers; this is deliberately conservative (a real but
// unusually-named sole constructor on an unindexed/under-indexed type would be
// missed) because the alternative (matching '.' + ANY identifier) is exactly
// the false-positive bug this function exists to prevent (I-1: 'TOldEdit.
// ClassName' / 'TOldEdit.InheritsFrom(x)' misdetected as constructions).
// Bug 2: AClassName may live in a DIFFERENT --db than the unit being
// converted, so every candidate store in AStores is tried in order --
// first store that resolves AClassName to an indexed skClass wins -- and
// FindAllChildSymbols(ClassSym.Id) runs against that SAME store (an id is
// only meaningful within the store that produced it), mirroring TreeFor's
// own cross-db convention.
function GetConstructorNames(const AStores: TArray<ISymbolStore>; const AClassName: string): TArray<string>;
var
  Cands   : TArray<TSymbol>;
  ClassSym: TSymbol;
  Found   : Boolean;
  Kids    : TArray<TSymbol>;
  K       : TSymbol;
  List    : TList<string>;
  St      : ISymbolStore;
  ResolvedStore: ISymbolStore;
begin
  Found:= False;
  ClassSym:= Default(TSymbol);
  ResolvedStore:= nil;
  for St in AStores do
  begin
    Cands:= St.FindSymbolsByExactName(AClassName);
    for var S in Cands do
      if S.Kind = skClass then begin ClassSym:= S; Found:= True; ResolvedStore:= St; Break; end;
    if Found then Break;
  end;

  Result:= ['Create']; { fallback: applies whenever the loop below adds nothing }
  if not Found then Exit;

  Kids:= ResolvedStore.FindAllChildSymbols(ClassSym.Id);
  List:= TList<string>.Create;
  try
    for K in Kids do
      if K.Kind = skConstructor then List.Add(K.Name);
    if List.Count > 0 then Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// Given the whole-word span ending at AEndCol of AFromType on 1-based line
// ALine of APasLines, checks whether it is immediately (modulo whitespace)
// followed by '.' + an identifier that NAMES ONE OF AKnownCtorNames
// (case-insensitively) -- i.e. a real construction 'AFromType.Create(' rather
// than a plain type reference OR a class-static reference like 'AFromType.
// ClassName' / 'AFromType.InheritsFrom(x)' (I-1 fix: matching '.' + ANY
// identifier misdetected those class-static reads as constructions). Returns
// True + the constructor identifier on a match.
function TryMatchConstructionShape(const APasLines: TStringList; ALine, AEndCol: Integer;
  const AKnownCtorNames: TArray<string>; out ACtorName: string): Boolean;
var
  S: string;
  P: Integer;
  NameStart: Integer;
  Name: string;
  IsKnownCtor: Boolean;
begin
  ACtorName:= '';
  if (ALine < 1) or (ALine > APasLines.Count) then Exit(False);
  S:= APasLines[ALine - 1];
  P:= AEndCol;
  while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
  if (P > Length(S)) or (S[P] <> '.') then Exit(False);
  Inc(P);
  while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
  NameStart:= P;
  while (P <= Length(S)) and CharInSet(S[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(P);
  if P = NameStart then Exit(False); { '.' not followed by an identifier }
  Name:= Copy(S, NameStart, P - NameStart);

  IsKnownCtor:= False;
  for var Ctor in AKnownCtorNames do
    if SameText(Name, Ctor) then begin IsKnownCtor:= True; Break; end;
  if not IsKnownCtor then Exit(False); { e.g. '.ClassName' / '.InheritsFrom' -- not a constructor }

  ACtorName:= Name;
  Result:= True;
end;

// Finds every runtime-construction site of AFromType ('AFromType.Xxx(...)',
// e.g. 'TOldEdit.Create(Self)') in AUnitPas, via the store's own reference
// index rather than a fresh text scan: a construction site is recorded by the
// indexer as a 'read' ref whose NameText is the bare class name, at the
// type-name token position (see docs/superpowers/specs/2026-07-09-refgap-e-
// type-references-design.md: "construction sites (TMyclass.Create) ->
// kind='read'"). GetReferencesFromFile gives StartLine/StartCol/EndCol for
// each candidate 'read' ref directly -- no separate token-column search is
// needed (contrast LocateFieldTypeToken, which DOES need one because the field
// symbol's span covers the whole declaration line, not just the type token).
// A 'read' ref is confirmed as a CONSTRUCTION (vs. a plain type reference,
// e.g. a type-test 'X is TOldEdit', or a class-static reference like 'X is
// TOldEdit.ClassName') by TryMatchConstructionShape: the token immediately
// after AFromType (modulo whitespace) must be '.' + an identifier that names
// one of AFromType's own indexed constructors (or 'Create', if AFromType has
// none indexed) -- see GetConstructorNames.
// AStores (Bug 2, cross-db): resolves AFromType's own constructor names, which
// may live in a different --db than AUnitStore. AUnitStore (single, unit-
// scoped): the store that actually has AFileId indexed -- GetReferencesFromFile
// is an id-scoped lookup, so it must go to the SAME store that produced AFileId.
function FindConstructionSites(const AStores: TArray<ISymbolStore>; const AUnitStore: ISymbolStore;
  AFileId: Int64; const APasLines: TStringList; const AFromType: string): TArray<TCreatorSite>;
var
  Refs: TArray<TReference>;
  R   : TReference;
  List: TList<TCreatorSite>;
  Site: TCreatorSite;
  Ctor: string;
  KnownCtorNames: TArray<string>;
begin
  Result:= nil;
  if AFileId <= 0 then Exit;
  KnownCtorNames:= GetConstructorNames(AStores, AFromType);
  Refs:= AUnitStore.GetReferencesFromFile(AFileId);
  List:= TList<TCreatorSite>.Create;
  try
    for R in Refs do
    begin
      if not SameText(R.Kind, 'read') then Continue;
      if not SameText(R.NameText, AFromType) then Continue;
      if not TryMatchConstructionShape(APasLines, R.StartLine, R.EndCol, KnownCtorNames, Ctor) then Continue;
      Site:= Default(TCreatorSite);
      Site.Line    := R.StartLine;
      Site.Col     := R.StartCol;
      Site.EndCol  := R.EndCol;
      Site.CtorName:= Ctor;
      List.Add(Site);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// True when AToType has at least one indexed skConstructor child whose
// Signature looks like the generic VCL component shape 'Create(AOwner:
// TComponent)' (parameter-list text loosely matched -- 'TComponent' anywhere
// in the signature is enough; exact formatting varies). Used only to enrich
// the TODO marker/ReemitNotes with a hint of whether a same-shape constructor
// exists; per the brief, the rewrite + TODO marker happen regardless of this
// result -- args are NEVER auto-fixed, so a False here does not block anything.
// Bug 2: AToType may live in a DIFFERENT --db than the unit being converted,
// so every candidate store in AStores is tried in order (first-resolve-wins),
// same convention as GetConstructorNames/TreeFor.
function ToTypeHasGenericCreate(const AStores: TArray<ISymbolStore>; const AToType: string): Boolean;
var
  Cands   : TArray<TSymbol>;
  ClassSym: TSymbol;
  Found   : Boolean;
  Kids    : TArray<TSymbol>;
  K       : TSymbol;
  St      : ISymbolStore;
  ResolvedStore: ISymbolStore;
begin
  Result:= False;
  Found:= False;
  ClassSym:= Default(TSymbol);
  ResolvedStore:= nil;
  for St in AStores do
  begin
    Cands:= St.FindSymbolsByExactName(AToType);
    for var S in Cands do
      if S.Kind = skClass then begin ClassSym:= S; Found:= True; ResolvedStore:= St; Break; end;
    if Found then Break;
  end;
  if not Found then Exit;

  Kids:= ResolvedStore.FindAllChildSymbols(ClassSym.Id);
  for K in Kids do
    if (K.Kind = skConstructor) and SameText(K.Name, 'Create') and
       (Pos('TComponent', K.Signature) > 0) then Exit(True);
end;

// Checks one class name's freshness across every candidate store, in order --
// FIRST STORE THAT RESOLVES AClassName TO AN INDEXED skClass WINS, mirroring
// the cross-db convention DoConvertApply's own TreeFor/BuildApplyPlan's TreeFor
// already use (Bug 2 fix: the From/To type may live in a DIFFERENT --db than
// the form's own instances, so a single store can't always resolve both).
// Once a store resolves the class (via FindSymbolsByExactName, same lookup
// ResolveClassQName uses), ALL of the remaining freshness work -- GetFilePath,
// FileIsUpToDate -- runs against that SAME store (an id/path pair is only
// meaningful within the store that produced it); other stores are not
// consulted further for this class. Appends a human-readable reason to
// AReasons and returns False on either failure mode: unresolved in ANY store
// (not indexed at all) or resolved-but-stale in the store that resolved it.
function CheckTypeFreshness(const AStores: TArray<ISymbolStore>; const AClassName: string;
  AReasons: TList<string>): Boolean;
var
  Cands  : TArray<TSymbol>;
  S      : TSymbol;
  Found  : Boolean;
  ClassSym: TSymbol;
  FilePath: string;
  RawBytes: TBytes;
  Sha    : string;
  MtimeUnix: Int64;
  St     : ISymbolStore;
  ResolvedStore: ISymbolStore;
begin
  Found:= False;
  ClassSym:= Default(TSymbol);
  ResolvedStore:= nil;
  for St in AStores do
  begin
    Cands:= St.FindSymbolsByExactName(AClassName);
    for S in Cands do
      if S.Kind = skClass then begin ClassSym:= S; Found:= True; ResolvedStore:= St; Break; end;
    if Found then Break;
  end;

  if not Found then
  begin
    AReasons.Add(Format('%s: not indexed (no skClass symbol found) -- reindex the unit declaring this type', [AClassName]));
    Exit(False);
  end;

  FilePath:= ResolvedStore.GetFilePath(ClassSym.FileId);
  if (FilePath = '') or (not TFile.Exists(FilePath)) then
  begin
    AReasons.Add(Format('%s: indexed declaring file not found on disk (%s) -- reindex', [AClassName, FilePath]));
    Exit(False);
  end;

  RawBytes := TFile.ReadAllBytes(FilePath);
  // Sha/Mtime basis mirrors DRagLint.Core.Indexer.IndexFile exactly (raw bytes,
  // ANSI-decoded for the sha) so this check compares apples to apples against
  // what FileIsUpToDate was given when the file was last indexed.
  Sha      := THashSHA2.GetHashString(TEncoding.ANSI.GetString(RawBytes));
  MtimeUnix:= DateTimeToUnix(TFile.GetLastWriteTime(FilePath), False);

  if not ResolvedStore.FileIsUpToDate(FilePath, MtimeUnix, Sha) then
  begin
    AReasons.Add(Format('%s: index is stale for %s (file changed on disk since last index) -- reindex before converting', [AClassName, FilePath]));
    Exit(False);
  end;

  Result:= True;
end;

function CheckFreshness(const AStores: TArray<ISymbolStore>; const ARules: TConversionRuleSet): TFreshnessResult;
var
  R       : TConversionRule;
  FromType, ToType: string;
  Reasons : TList<string>;
  FromOk, ToOk: Boolean;
begin
  Result:= Default(TFreshnessResult);
  Result.Fresh:= True;

  // BareTypeTail: a rule's #convert header may name either type qualified
  // ('LibA.TSrcBtn') -- FindSymbolsByExactName (inside CheckTypeFreshness)
  // matches the bare name column only, same as every other lookup in this
  // unit (see BareTypeTail's own remarks, Bug 1).
  FromType:= ''; ToType:= '';
  for R in ARules.Rules do
    if R.Kind = rkConvert then
    begin FromType:= BareTypeTail(R.FromType); ToType:= BareTypeTail(R.ToType); Break; end;
  if (FromType = '') and (ToType = '') then Exit; { nothing to check -- vacuously fresh }

  Reasons:= TList<string>.Create;
  try
    FromOk:= (FromType = '') or CheckTypeFreshness(AStores, FromType, Reasons);
    ToOk  := (ToType   = '') or CheckTypeFreshness(AStores, ToType  , Reasons);
    Result.Fresh  := FromOk and ToOk;
    Result.Reasons:= Reasons.ToArray;
  finally
    Reasons.Free;
  end;
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

// One confirmed surface #4 access site: a 'member-access' ref (FromMember, at
// [Line, Col..EndCol) -- the MEMBER token's own span, exactly as EmitRef
// records it for the exprDot's rhs node) whose receiver (the exprDot's lhs
// identifier, immediately before the '.') names a converted instance.
type
  TAccessSite = record
    Line, Col, EndCol: Integer;
    InstanceName: string; // the receiver, e.g. 'Edit1'
  end;

// Whole-word identifier-char test shared by the receiver scan below (mirrors
// the boundary checks LocateFieldTypeToken already uses for the same purpose).
function IsIdentChar(C: Char): Boolean; inline;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// Resolves the RECEIVER of a member-access ref at (ALine, AMemberCol) --
// i.e. the base identifier immediately before the '.' that precedes the
// member token -- by reading the source line text directly rather than a
// second refs-table lookup: the member-access ref's own span gives us the
// exact column the member token starts at (AMemberCol = the ref's StartCol,
// 1-based), so walking backward from there past whitespace, the '.', more
// whitespace, and then the identifier run is a simple, robust text scan (the
// parser's exprDot handler guarantees a plain-identifier lhs is what emitted
// this ref in the first place -- see ref-gap G in DRagLint.Parser.Delphi13.
// Walk's exprDot case -- so there is always exactly one identifier token to
// find here; this is not a general expression parse). Returns '' when the
// line text does not have the expected 'ident.' shape immediately before
// AMemberCol (defensive -- should not happen for a genuine member-access ref,
// but a stale/mismatched line count must not crash the applier).
function ResolveMemberAccessReceiver(const APasLines: TStringList; ALine, AMemberCol: Integer): string;
var
  S: string;
  P: Integer;
  NameEnd, NameStart: Integer;
begin
  Result:= '';
  if (ALine < 1) or (ALine > APasLines.Count) then Exit;
  S:= APasLines[ALine - 1];
  P:= AMemberCol - 1; { last column BEFORE the member token, 1-based }
  while (P >= 1) and (S[P] = ' ') do Dec(P);
  if (P < 1) or (S[P] <> '.') then Exit; { not immediately preceded by '.': not a simple obj.Member site }
  Dec(P);
  while (P >= 1) and (S[P] = ' ') do Dec(P);
  NameEnd:= P;
  while (P >= 1) and IsIdentChar(S[P]) do Dec(P);
  NameStart:= P + 1;
  if NameStart > NameEnd then Exit; { '.' not preceded by an identifier }
  Result:= Copy(S, NameStart, NameEnd - NameStart + 1);
end;

// Finds every surface #4 access site in AUnitPas for one renaming '#link
// AToMember <- AFromMember' (AToMember and AFromMember already confirmed
// distinct by the caller): every 'member-access' ref whose NameText =
// AFromMember, whose receiver (ResolveMemberAccessReceiver, read off the
// SAME line the ref itself was recorded at) matches one of AInstanceNames
// (case-insensitively -- the .dfm/.pas instance-name spelling is preserved
// verbatim by FindConvertInstances, so an exact SameText match is correct
// here, not a substring/prefix match). A member-access whose receiver is
// NOT in AInstanceNames (e.g. 'Other.Caption' when Other is a different,
// unconverted object) is silently skipped -- this instance-scoping is the
// whole point of joining through the receiver, not just matching on member
// name alone (which would also rewrite unrelated types' same-named members).
function FindMemberAccessSites(const AStore: ISymbolStore; AFileId: Int64;
  const APasLines: TStringList; const AFromMember: string;
  const AInstanceNames: TArray<string>): TArray<TAccessSite>;
var
  Refs: TArray<TReference>;
  R   : TReference;
  List: TList<TAccessSite>;
  Site: TAccessSite;
  Receiver: string;
  IsConverted: Boolean;
  N   : string;
begin
  Result:= nil;
  if (AFileId <= 0) or (AFromMember = '') then Exit;
  Refs:= AStore.GetReferencesFromFile(AFileId);
  List:= TList<TAccessSite>.Create;
  try
    for R in Refs do
    begin
      if not SameText(R.Kind, 'member-access') then Continue;
      if not SameText(R.NameText, AFromMember) then Continue;

      Receiver:= ResolveMemberAccessReceiver(APasLines, R.StartLine, R.StartCol);
      if Receiver = '' then Continue;

      IsConverted:= False;
      for N in AInstanceNames do
        if SameText(N, Receiver) then begin IsConverted:= True; Break; end;
      if not IsConverted then Continue; { e.g. Other.Caption -- Other is not a converted instance }

      Site:= Default(TAccessSite);
      Site.Line        := R.StartLine;
      Site.Col         := R.StartCol;
      Site.EndCol      := R.EndCol;
      Site.InstanceName:= Receiver;
      List.Add(Site);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function BuildApplyPlan(const AStores: TArray<ISymbolStore>; const AUnitPas, ADfmPath: string;
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
  CreatorSites: TList<string>;
  AccessSites : TList<string>;
  Todos       : TList<string>;
  PasLines    : TStringList;
  PasFileSyms : TArray<TSymbol>;
  PasFileId   : Int64;
  PasStore    : ISymbolStore; { the store that actually has AUnitPas indexed -- see StoreForFile }
  Sym         : TSymbol;
  DoneUnits   : TDictionary<string, Boolean>; { ToType -> already handled (added or already-used) }
  ToTypesSeen : TList<string>;
  ConvertedInstNames: TList<string>; { instances that survived the .dfm re-emit -- see surface #4 remarks below }
  E           : TTextEdit;
  TreeCache   : TDictionary<string, TPropTree>; { qname -> tree, built once per distinct type }
  Opts        : TPropTreeOptions;

  // Resolves the store (from AStores, in order) that actually has APath
  // indexed (FindSymbolsByFile non-empty, trying both the given and the
  // fully-qualified path) -- the .pas/.dfm pair being converted may live in a
  // DIFFERENT --db than the From/To types (Bug 2). Falls back to AStores[0]
  // when no store has APath indexed, preserving the prior single-db error
  // paths (a subsequent Length(...)=0 still produces the existing "could not
  // locate" warnings rather than a new failure mode).
  function StoreForFile(const APath: string): ISymbolStore;
  var
    St  : ISymbolStore;
    Syms: TArray<TSymbol>;
  begin
    for St in AStores do
    begin
      Syms:= St.FindSymbolsByFile(APath);
      if Length(Syms) = 0 then Syms:= St.FindSymbolsByFile(TPath.GetFullPath(APath));
      if Length(Syms) > 0 then Exit(St);
    end;
    if Length(AStores) > 0 then Exit(AStores[0]);
    Result:= nil;
  end;

  // F/T property trees are the same for every instance sharing a (FromType,
  // ToType) rule pair -- cache by resolved qname so a form with N instances of
  // the same F type only builds each tree once. Bug 2: tries every store in
  // AStores, in order (first-that-resolves-wins) -- the From/To type may live
  // in a DIFFERENT --db than the unit/instance being converted, mirroring
  // DoConvertApply's own cross-db TreeFor (used earlier for rule validation).
  function TreeFor(const AClassName: string): TPropTree;
  var
    QName: string;
    Cand : TPropTree;
    St   : ISymbolStore;
  begin
    Result:= Default(TPropTree);
    for St in AStores do
    begin
      QName:= ResolveClassQName(St, AClassName);
      if QName = '' then Continue;
      if TreeCache.TryGetValue(QName, Cand) then Exit(Cand);
      Cand:= BuildPropTree(St, QName, Opts);
      TreeCache.Add(QName, Cand);
      Exit(Cand);
    end;
  end;

begin
  Result:= Default(TApplyResult);
  Result.Ok:= False;

  if not TFile.Exists(AUnitPas) then
  begin Result.Error:= Format('unit .pas not found: %s', [AUnitPas]); Exit; end;
  if not TFile.Exists(ADfmPath) then
  begin Result.Error:= Format('.dfm not found: %s', [ADfmPath]); Exit; end;
  if Length(AStores) = 0 then
  begin Result.Error:= 'no symbol store available (empty AStores)'; Exit; end;

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

  { PasStore: whichever --db actually has AUnitPas indexed -- every unit-scoped
    lookup below (PasFileSyms, PasFileId, and everything keyed off PasFileId)
    goes through THIS SAME store, since an id is only meaningful within the
    store that produced it. }
  PasStore:= StoreForFile(AUnitPas);
  PasFileSyms:= PasStore.FindSymbolsByFile(AUnitPas);
  if Length(PasFileSyms) = 0 then
    PasFileSyms:= PasStore.FindSymbolsByFile(TPath.GetFullPath(AUnitPas));

  { surface #5 needs the .pas file's own refs (GetReferencesFromFile is
    keyed by file id, not path) to find construction sites. }
  PasFileId:= PasStore.FindFileIdByPath(AUnitPas);
  if PasFileId <= 0 then PasFileId:= PasStore.FindFileIdByPath(TPath.GetFullPath(AUnitPas));

  var DfmStore: ISymbolStore:= StoreForFile(ADfmPath);
  DfmFileSyms:= DfmStore.FindSymbolsByFile(ADfmPath);
  if Length(DfmFileSyms) = 0 then
    DfmFileSyms:= DfmStore.FindSymbolsByFile(TPath.GetFullPath(ADfmPath));

  Opts:= Default(TPropTreeOptions);
  Opts.Depth       := 6;
  Opts.ToPersistent:= True;

  PasLines:= TStringList.Create;
  Edits    := TList<TTextEdit>.Create;
  Converted:= TList<string>.Create;
  Warnings := TList<string>.Create;
  ReemitNotes:= TList<string>.Create;
  CreatorSites:= TList<string>.Create;
  AccessSites:= TList<string>.Create;
  Todos    := TList<string>.Create;
  DoneUnits:= TDictionary<string, Boolean>.Create;
  ToTypesSeen:= TList<string>.Create;
  ConvertedInstNames:= TList<string>.Create;
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

      { Instance has cleared the re-emit checkpoint -- it WILL get its #1/#2/#5
        edits below, so it is eligible for surface #4's instance-scoping too.
        Recorded here (not after the whole loop) so a skipped instance's name
        never enters the converted-instance set an access-site rewrite is
        scoped against. }
      ConvertedInstNames.Add(Inst.InstanceName);

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
        { A multi-declarator field line (`Edit1, Edit2: TOldEdit;`) indexes only
          the FIRST declarator as a field symbol, so a later name on the shared
          line is not located here -- the .dfm/access/creator surfaces still
          convert it, but this .pas decl line stays typed as the F type. Name the
          limitation so the user fixes the shared line by hand. }
        Warnings.Add(Format('%s: could not locate field declaration "%s: %s" in %s'
          + ' (a shared multi-declarator line is not retyped -- fix the decl by hand)',
          [Inst.InstanceName, Inst.InstanceName, Inst.FromType, AUnitPas]));

      { -- surface #5: runtime-creator retype. Every explicit construction
        site 'FromType.Xxx(...)' (e.g. 'Edit1 := TOldEdit.Create(Self);') in
        this unit gets its type token rewritten to ToType, PLUS a TODO marker
        comment -- ALWAYS, unconditionally: ToType's constructor/init may take
        a different shape than FromType's (a different parameter list, extra
        required setup), and this applier never attempts to fix up
        constructor ARGUMENTS. The marker is the safety net the user checks
        by hand. A design-time (DFM-only) instance has no .Create in code, so
        it simply contributes zero sites here -- its #1/#2/#3 edits still
        apply on their own. }
      var Sites: TArray<TCreatorSite>:= FindConstructionSites(AStores, PasStore, PasFileId, PasLines, Inst.FromType);
      var HasGenericCreate: Boolean:= ToTypeHasGenericCreate(AStores, Inst.ToType);
      for var Site in Sites do
      begin
        var CtorName: string:= Site.CtorName;
        if CtorName = '' then CtorName:= 'Create';

        E:= Default(TTextEdit);
        E.FilePath:= AUnitPas;
        E.Kind    := tekReplaceInLine;
        E.Line    := Site.Line;
        E.Col     := Site.Col;
        E.EndCol  := Site.EndCol;
        E.Text    := Inst.ToType;
        Edits.Add(E);

        var TodoText: string:= Format(
          '{ TODO: drag-lint convert -- verify creator for %s (was %s.%s); %s''s ctor/init may differ }',
          [Inst.ToType, Inst.FromType, CtorName, Inst.ToType]);

        { end-of-line insert keeps line numbers stable for every OTHER edit on
          this line/file (a tekInsertLines line-above would shift every
          subsequent line number, which every other surface's edits are NOT
          computed to account for). }
        var LineLen: Integer:= 0;
        if (Site.Line >= 1) and (Site.Line <= PasLines.Count) then
          LineLen:= Length(PasLines[Site.Line - 1]);
        E:= Default(TTextEdit);
        E.FilePath:= AUnitPas;
        E.Kind    := tekInsertInLine;
        E.Line    := Site.Line;
        E.Col     := LineLen + 1;
        E.Text    := ' ' + TodoText;
        Edits.Add(E);

        CreatorSites.Add(Format('%s: %s.%s -> %s.%s', [Inst.InstanceName, Inst.FromType, CtorName, Inst.ToType, CtorName]));
        if not HasGenericCreate then
          ReemitNotes.Add(Format('%s: %s has no indexed generic Create(AOwner: TComponent) -- verify the creator manually', [Inst.InstanceName, Inst.ToType]));
        Todos.Add(TodoText);
      end;

      { -- surface #2: uses-add for each distinct ToType (once per type). }
      if not DoneUnits.ContainsKey(Inst.ToType) then
      begin
        DoneUnits.Add(Inst.ToType, True);
        ToTypesSeen.Add(Inst.ToType);
      end;
    end;

    { -- surface #4: instance-scoped property/event ACCESS rewrite, via
      ref-gap G's 'member-access' refs. Runs ONCE over the whole unit per
      renaming '#link ToMember <- FromMember' rule (not per-instance --
      GetReferencesFromFile already returns every ref in the file, and
      FindMemberAccessSites' own instance-name join is what scopes each hit
      to a specific converted receiver), rather than inside the per-instance
      loop above: a single access-rewrite pass naturally covers every
      instance sharing the same rule in one query instead of N redundant
      whole-file ref scans. Identity renames (ToPath = FromPath, e.g. a
      #link that maps a property to itself) are skipped -- there is nothing
      to rewrite. Dotted paths (ToPath/FromPath containing '.', e.g. '#link
      Name <- Inner.Shade' -- a NESTED .dfm property path) are also skipped
      here: they describe the .dfm property tree, not a single .pas
      'obj.Member' token, so they are out of surface #4's scope (no crash,
      just no rewrite -- the .dfm-side #link still applies via surface #3). }
    for var LinkRule in ARules.Rules do
    begin
      if LinkRule.Kind <> rkLink then Continue;
      if (LinkRule.ToPath = '') or (LinkRule.FromPath = '') then Continue;
      if SameText(LinkRule.ToPath, LinkRule.FromPath) then Continue; { identity rename -- nothing to rewrite }
      if (Pos('.', LinkRule.ToPath) > 0) or (Pos('.', LinkRule.FromPath) > 0) then Continue; { nested .dfm path, not a .pas access site }

      var Sites: TArray<TAccessSite>:= FindMemberAccessSites(PasStore, PasFileId, PasLines,
        LinkRule.FromPath, ConvertedInstNames.ToArray);
      for var Site in Sites do
      begin
        E:= Default(TTextEdit);
        E.FilePath:= AUnitPas;
        E.Kind    := tekReplaceInLine;
        E.Line    := Site.Line;
        E.Col     := Site.Col;
        E.EndCol  := Site.EndCol;
        E.Text    := LinkRule.ToPath;
        Edits.Add(E);

        AccessSites.Add(Format('%s.%s -> %s.%s (L%d)',
          [Site.InstanceName, LinkRule.FromPath, Site.InstanceName, LinkRule.ToPath, Site.Line]));
      end;
    end;

    for var ToType_ in ToTypesSeen do
    begin
      var ResolvedUnit: string;
      var AlreadyUsed : Boolean;
      var UseEdits: TArray<TTextEdit>;
      { Bug 2: the To type's declaring unit may live in a DIFFERENT --db than
        the unit being converted (PasStore) -- try every store as the NAME
        store, in order, keeping PasStore fixed as the UNIT store (whose uses
        clause is what actually gets edited), first store that resolves
        (AlreadyUsed or a non-empty edit set) wins. }
      for var St in AStores do
      begin
        UseEdits:= TFindUnitRefactoring.Build(St, PasStore, ToType_, AUnitPas, ResolvedUnit, AlreadyUsed);
        if AlreadyUsed or (Length(UseEdits) > 0) then Break;
      end;
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
    Result.Report.CreatorSites:= CreatorSites.ToArray;
    Result.Report.AccessSites:= AccessSites.ToArray;
    Result.Report.Todos    := Todos.ToArray;
    Result.Ok:= True;
  finally
    PasLines.Free;
    Edits.Free;
    Converted.Free;
    Warnings.Free;
    ReemitNotes.Free;
    CreatorSites.Free;
    AccessSites.Free;
    Todos.Free;
    DoneUnits.Free;
    ToTypesSeen.Free;
    ConvertedInstNames.Free;
    TreeCache.Free;
  end;
end;

end.
