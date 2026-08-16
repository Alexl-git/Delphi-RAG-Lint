unit DRagLint.Refactor.EnumHelper;

{ Enum-helper generator -- RESOLVE (Task 2) + GENERATE (Task 3) + PLACE
  (Task 4) stages, assembled behind the top-level Build entry point (the
  CLI `create-enum-helper` verb and the IDE "Create helper class" menu both
  call Build only).
  RESOLVE looks up an enum by qualified name, gathers its members in
  declaration order, checks whether a helper already exists anywhere in the
  indexed codebase (via ISymbolStore.FindHelpersOfType), and detects a
  same-unit `<Enum>Descriptions` const array. GENERATE synthesizes the Byte-
  family record-helper declaration + method bodies from a TEnumHelperResolve,
  as pure string building (no store/index access). PLACE turns the resolved
  enum + generated text into TTextEdits: the decl lands immediately after the
  enum's own declaration (same `type` section); the bodies ALWAYS land in the
  `implementation` section (populating an empty one when necessary); a third
  edit adds `System.TypInfo` to the implementation `uses` when the generated
  bodies need RTTI and it is not already in scope. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Refactor.TextEdit
  ;

type
  /// <summary>One kind of helper method the generator can emit for an enum.
  /// ehmToByte/ehmToInteger convert the enum value outward; ehmFromByte/
  /// ehmFromInteger construct an enum value from an ordinal (with range
  /// checking); ehmToString/ehmFromString convert to/from a display string
  /// (see TToStringMode for the ToString strategy).</summary>
  TEnumHelperMethod = (ehmToByte, ehmFromByte, ehmToInteger, ehmFromInteger, ehmToString, ehmFromString);

  /// <summary>The set of helper methods requested for one generation run.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), declaration (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEnumHelperMethods = set of TEnumHelperMethod;

  /// <summary>Strategy for the generated ToString method: tsmRtti defers to
  /// System.TypInfo.GetEnumName (no per-member code, always in sync with the
  /// enum type but yields the raw identifier text, e.g. 'clRed'); tsmCase
  /// emits an explicit case statement over a `&lt;Enum>Descriptions`-style
  /// literal per member (readable display text, but must be kept in sync by
  /// hand if members are added).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), declaration (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TToStringMode = (tsmRtti, tsmCase);

  /// <summary>Result of resolving an enum type by qualified name ahead of
  /// generating a helper for it. Found=False means the qname did not resolve
  /// to an skEnum symbol; every other field is then undefined and callers
  /// must not act on it.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Resolve (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas)
  /// Used in units: DRagLint.Refactor.EnumHelper
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEnumHelperResolve = record
    /// <summary>True when AEnumQName resolved to exactly one skEnum symbol.</summary>
    Found: Boolean;
    /// <summary>Short (unqualified) enum type name, e.g. 'TColor'.</summary>
    EnumName: string;
    /// <summary>DB id of the file declaring the enum.</summary>
    EnumFileId: Int64;
    /// <summary>Filesystem path of the file declaring the enum.</summary>
    EnumFilePath: string;
    /// <summary>Enum member names in declaration order (e.g. ['clRed',
    /// 'clGreen', 'clBlue']). Only real named skEnumValue children.</summary>
    Members: TArray<string>;
    /// <summary>1-based line of the enum declaration's start (the `T&lt;Enum> =
    /// (` line). Together with EnumEndLine this bounds the source span
    /// HasExplicitOrdinal is detected from; not otherwise used for
    /// insertion (EnumEndLine is the placement anchor).</summary>
    EnumStartLine: Integer;
    /// <summary>1-based line of the enum declaration's end (closing ')' /
    /// ';'). Insertion anchor for the generated helper declaration.</summary>
    EnumEndLine: Integer;
    /// <summary>1-based column of the enum declaration's end.</summary>
    EnumEndCol: Integer;
    /// <summary>True when FindHelpersOfTypeSymbol(this enum's own symbol id)
    /// returned at least one edge anywhere in the indexed codebase (whole-DB,
    /// not just this unit). Task 9b (FP fix): matched by symbol identity, not
    /// bare name -- an unrelated same-named enum in another unit with its own
    /// helper does NOT set this True; only a helper edge that actually
    /// resolved its target to THIS enum symbol counts.</summary>
    HasHelper: Boolean;
    /// <summary>True when the existing helper (HasHelper=True) is declared
    /// in the same file as the enum (EnumFileId). Undefined when HasHelper
    /// is False.</summary>
    HelperSameUnit: Boolean;
    /// <summary>Filesystem path of the existing helper's declaring unit;
    /// '' when HasHelper is False.</summary>
    HelperUnitPath: string;
    /// <summary>Name of a same-unit const array named '&lt;EnumName>Descriptions'
    /// if one exists (e.g. 'TColorDescriptions'), else ''.</summary>
    DescArrayName: string;
    /// <summary>True when the enum declaration's source text (the
    /// EnumStartLine..EnumEndLine span) contains at least one member with an
    /// explicit ordinal assignment, e.g. `sp_Upper = 5` or `Elem1 = -2`.
    /// Delphi only emits automatic enum RTTI (GetEnumName/GetEnumValue) when
    /// EVERY member uses the implicit sequential-from-0 default; an enum
    /// whose resulting ordinal VALUES are non-sequential/non-0-based
    /// genuinely has no RTTI (E2134 "Type has no type info" if requested).
    /// This flag is a CONSERVATIVE over-approximation of that real
    /// condition: it is set by ANY explicit `= N` on ANY member, even one
    /// whose explicit values still happen to be 0,1,2,... (verified: such an
    /// enum's RTTI actually still compiles and works) -- re-deriving
    /// "sequential explicit values" from source text was judged not worth
    /// the complexity, so this flag can be True in a few cases where RTTI
    /// would have been fine. Build uses it to fall back from tsmRtti to
    /// tsmCase, which is always a safe (if occasionally unnecessary) choice.
    /// Detection is a text scan (ordinals are not indexed), scoped to the
    /// `(...)` member list so the type-definition `T&lt;Enum> = (` equals sign
    /// is never mistaken for a member ordinal assignment.</summary>
    HasExplicitOrdinal: Boolean;
  end;

  /// <summary>Result of the GENERATE stage: the synthesized Object Pascal
  /// text for a Byte-family record helper, ready for the PLACE stage to
  /// splice into the target unit. Pure text -- no file positions here (those
  /// live on TEnumHelperResolve).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas)
  /// Used in units: DRagLint.Refactor.EnumHelper
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEnumHelperGen = record
    /// <summary>The `T&lt;Enum>Helper = record helper for T&lt;Enum> ... end;`
    /// type declaration block (CRLF-joined, no trailing line break).</summary>
    DeclText: string;
    /// <summary>The implementation-section method bodies, preceded by the
    /// `{ T&lt;Enum>Helper }` convention comment (CRLF-joined, no trailing line
    /// break).</summary>
    BodiesText: string;
    /// <summary>True when RTTI-based ToString/FromString were emitted
    /// (System.TypInfo.GetEnumName/GetEnumValue); the PLACE stage should add
    /// System.TypInfo to the unit's uses clause if not already present. False
    /// when no ToString/FromString were requested, or tsmCase was used.</summary>
    NeedsTypInfo: Boolean;
  end;

  /// <summary>Outcome of Build. ehaBuilt: edits were produced (Result.Edits
  /// is populated). ehaExists: a helper for the enum already exists
  /// (anywhere in the indexed codebase); no edits are produced -- the
  /// generator never overwrites a hand-written helper. ehaNoImplSection: the
  /// enum's unit has no `implementation` keyword at all (malformed/fragment
  /// safety guard; a normal Delphi unit always has one); no edits.
  /// ehaNotFound: AEnumQName did not resolve to an skEnum symbol; no
  /// edits.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Refactor.EnumHelper.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEnumHelperAction = (ehaBuilt, ehaExists, ehaNoImplSection, ehaNotFound);

  /// <summary>Result of TEnumHelperRefactoring.Build: either a ready-to-apply
  /// set of text edits (Action=ehaBuilt) or a refusal with a human-readable
  /// reason and no edits.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), declaration (DRagLint.Refactor.EnumHelper.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Refactor.EnumHelper
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEnumHelperResult = record
    /// <summary>What Build decided. See TEnumHelperAction.</summary>
    Action: TEnumHelperAction;
    /// <summary>Decl edit + bodies edit, plus a uses edit when RTTI ToString/
    /// FromString were generated and System.TypInfo was not already in
    /// scope. Empty unless Action=ehaBuilt. Apply via
    /// TTextEditApplier.Apply.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Human-readable reason for ehaExists / ehaNoImplSection /
    /// ehaNotFound. '' when Action=ehaBuilt.</summary>
    Message: string;
    /// <summary>Short (unqualified) enum type name, e.g. 'TColor'. Set
    /// whenever the qname resolved (i.e. Action &lt;> ehaNotFound).</summary>
    EnumName: string;
    /// <summary>Filesystem path of the enum's declaring unit. Set whenever
    /// the qname resolved (i.e. Action &lt;> ehaNotFound).</summary>
    FilePath: string;
  end;

  /// <summary>Enum-helper generator: resolves an enum type, synthesizes a
  /// record helper implementing the requested conversion methods, and places
  /// the result via text edits. Resolve (Task 2) + Generate (Task 3) + Build
  /// / PLACE (this task) are all implemented.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEnumHelperRefactoring = class
  public
    /// <summary>Resolves AEnumQName to its declaring enum symbol, its members
    /// in declaration order, whether a helper for it already exists anywhere
    /// in AStore, and whether a same-unit '&lt;Enum>Descriptions' const array is
    /// present. Does not read or write any file.</summary>
    /// <param name="AStore">Open symbol store to query (whole-DB visibility
    /// for the existing-helper guard).</param>
    /// <param name="AEnumQName">Qualified name of the enum type, e.g.
    /// 'Simple.TColor'. A short (unqualified) name also works if it uniquely
    /// resolves via the store's qualified-name lookup.</param>
    /// <returns>A TEnumHelperResolve with Found=False when AEnumQName does
    /// not resolve to exactly one skEnum symbol.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?
    /// Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindHelpersOfTypeSymbol, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Refactor.EnumHelper.DetectExplicitOrdinal, DRagLint.Refactor.EnumHelper.ReadDeclSpan
    /// Returns: Default(TEnumHelperResolve)
    /// Complexity: 10 (cyclomatic, outer body), 83 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindHelpersOfTypeSymbol"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Resolve(const AStore: ISymbolStore; const AEnumQName: string): TEnumHelperResolve; static;

    /// <summary>Synthesizes the Byte-family record-helper declaration and
    /// method bodies for AResolve.EnumName, from AResolve.Members (real
    /// named members only, declaration order). Pure function of its inputs:
    /// no store/index/file access. `To*` methods return Ord(Self); `From*`
    /// methods use a `case Ord(member)` idiom with `else` mapping to the
    /// FIRST declared member (= low(T&lt;Enum>)). ToDescription is NOT one of
    /// AMethods -- it is emitted automatically, decl+body, whenever
    /// AResolve.DescArrayName is non-empty.</summary>
    /// <param name="AResolve">A resolved enum (Found must be True; EnumName
    /// and Members are read, DescArrayName drives the auto-included
    /// ToDescription method).</param>
    /// <param name="AMethods">Subset of the 6 convert methods to emit; an
    /// empty set emits an (almost) empty helper (still gets ToDescription if
    /// DescArrayName is set).</param>
    /// <param name="AToStringMode">tsmRtti (default) emits
    /// GetEnumName/GetEnumValue-based bodies and sets NeedsTypInfo; tsmCase
    /// emits a per-member string-literal case/if-chain with no RTTI
    /// dependency.</param>
    /// <returns>A TEnumHelperGen with DeclText/BodiesText in CRLF, 7-bit
    /// ASCII text, and NeedsTypInfo reflecting whether RTTI ToString/
    /// FromString were emitted.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build (DRagLint.Refactor.EnumHelper.pas)
    /// Calls: Default, DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate.EmitFromCase
    /// Returns: Default(TEnumHelperGen); Ord(Self); GetEnumName(TypeInfo(' + EnumName + '), Ord(Self)); ''' + M + '''; ''''; ' + EnumName + '(GetEnumValue(TypeInfo(' + EnumName + '), AValue))
    /// Complexity: 20 (cyclomatic, outer body), 164 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate.EmitFromCase"/>
    /// <seealso cref="DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Build"/>
    /// <seealso cref="DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Resolve"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Generate(const AResolve: TEnumHelperResolve;
      const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperGen; static;

    /// <summary>Top-level entry point: Resolve -> refuse checks -> Generate
    /// -> PLACE -> assembled TEnumHelperResult. The only method the CLI
    /// `create-enum-helper` verb and the IDE "Create helper class" menu
    /// call.</summary>
    /// <param name="AStore">Open symbol store (whole-DB visibility for the
    /// existing-helper guard and the uses-clause membership check).</param>
    /// <param name="AEnumQName">Qualified (or uniquely-resolving short) name
    /// of the enum type, e.g. 'Simple.TColor' or 'TColor'.</param>
    /// <param name="AMethods">Subset of the 6 convert methods to emit; see
    /// Generate.</param>
    /// <param name="AToStringMode">Requested ToString/FromString strategy;
    /// see Generate. tsmCase is always honored as-is. tsmRtti (the default)
    /// is silently downgraded to tsmCase when Resolve detects an explicit
    /// enum ordinal (Res.HasExplicitOrdinal) -- a conservative trigger that
    /// guarantees the fallback fires whenever RTTI would genuinely fail to
    /// compile (E2134), at the cost of occasionally also firing for an
    /// explicit-but-still-sequential-from-0 enum where RTTI would actually
    /// have worked (see HasExplicitOrdinal's doc comment). A fully implicit
    /// (no explicit ordinal at all) enum still gets RTTI under the default,
    /// unchanged.</param>
    /// <returns>Action=ehaNotFound when AEnumQName does not resolve;
    /// ehaExists when a helper already exists anywhere in the codebase (no
    /// edits -- never overwrites a hand-written helper); ehaNoImplSection
    /// when the enum's unit has no `implementation` keyword at all;
    /// otherwise ehaBuilt with 2 or 3 ready-to-apply TTextEdits (decl,
    /// bodies, and -- only when needed -- a System.TypInfo uses edit).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas)
    /// Calls: Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Refactor.EnumHelper.FindImplementationLine, DRagLint.Refactor.EnumHelper.IndentLines, DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate, DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Resolve, DRagLint.Refactor.EnumHelper.UsesContainsTypInfo, ExtractFileName, Format, TrimLeft
    /// Returns: Default(TEnumHelperResult)
    /// Complexity: 23 (cyclomatic, outer body), 193 lines (full implementation)
    /// Touches: file system
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
    /// <seealso cref="DRagLint.Refactor.EnumHelper.FindImplementationLine"/>
    /// <seealso cref="DRagLint.Refactor.EnumHelper.IndentLines"/>
    /// <seealso cref="DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Generate"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AStore: ISymbolStore; const AEnumQName: string;
      const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperResult; static;
  end;

implementation

{ Reads the 1-based AStartLine..AEndLine (inclusive) span of AFilePath, joined
  with a single space between lines, so a multi-line enum declaration (real
  MSCTYPES-shaped enums routinely wrap one member per line) is scanned as one
  string. '' on any error (missing file, out-of-range lines) -- same tolerant
  pattern as ReadSourceLine/ReadDeclLine (DRagLint.Refactor.DocStub.pas /
  DRagLint.Doc.Facts.pas), generalized here to a range because those helpers
  only read a single line. Source is strict ANSI/CRLF per repo convention. }
function ReadDeclSpan(const AFilePath: string; AStartLine, AEndLine: Integer): string;
var
  Lines : TArray<string>;
  I     : Integer;
  LLast : Integer;
  SB    : TStringBuilder;
begin
  Result:= '';
  if (AFilePath = '') or (AStartLine < 1) or (AEndLine < AStartLine) then Exit;
  if not TFile.Exists(AFilePath) then Exit;
  try
    Lines:= TFile.ReadAllLines(AFilePath, TEncoding.ANSI);
  except
    Exit;
  end;
  if AStartLine > Length(Lines) then Exit;
  LLast:= AEndLine;
  if LLast > Length(Lines) then LLast:= Length(Lines);
  SB:= TStringBuilder.Create;
  try
    for I:= AStartLine to LLast do
    begin
      if I > AStartLine then SB.Append(' ');
      SB.Append(Lines[I - 1]);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Detects an explicit ordinal assignment (e.g. `sp_Upper = 5`, `Elem1 = -2`)
  anywhere in an enum member list, from the enum's own DECLARATION SOURCE TEXT
  (ADeclSpan = the joined EnumStartLine..EnumEndLine span -- ordinals are not
  indexed, see the design note on HasExplicitOrdinal). The declaration reads
  `T<Enum> = (member1, member2 = N, ...);` -- the type-definition `=` sits
  BEFORE the opening '(', so it must never be mistaken for a member ordinal
  assignment. The fix: locate the FIRST '(' in ADeclSpan and scan only the
  substring AFTER it for a member-list `=`. Any '=' found there means at
  least one member has an explicit ordinal -- this is a deliberately
  conservative signal (see HasExplicitOrdinal's doc comment: the real Delphi
  RTTI cutoff is whether the resulting ordinal VALUES stay sequential-from-0,
  which this text scan does not attempt to re-derive; "any explicit `=`"
  triggers the case-mode fallback a little more often than strictly
  necessary, but never incorrectly skips it). Returns False if ADeclSpan has
  no '(' at all (malformed/unresolvable -- should not happen for a real
  resolved enum). }
function DetectExplicitOrdinal(const ADeclSpan: string): Boolean;
var
  ParenPos    : Integer;
  MemberList  : string;
begin
  Result:= False;
  ParenPos:= Pos('(', ADeclSpan);
  if ParenPos = 0 then Exit;
  MemberList:= Copy(ADeclSpan, ParenPos + 1, MaxInt);
  Result:= Pos('=', MemberList) > 0;
end;

class function TEnumHelperRefactoring.Resolve(const AStore: ISymbolStore; const AEnumQName: string): TEnumHelperResolve;
var
  Syms       : TArray<TSymbol>;
  EnumSym    : TSymbol        ;
  Children   : TArray<TSymbol>;
  Child      : TSymbol        ;
  MemberList : TArray<string> ;
  MemberCount: Integer        ;
  Edges      : TArray<THelperEdge>;
  HelperSym  : TSymbol        ;
  DescCands  : TArray<TSymbol>;
  DescSym    : TSymbol        ;
  DescName   : string         ;
begin
  Result:= Default(TEnumHelperResolve);

  Syms:= AStore.FindSymbolsByQualifiedName(AEnumQName);
  if Length(Syms) = 0 then
  begin
    { Fall back to an exact short-name lookup (whole-DB) when AEnumQName is
      not a stored qualified_name -- e.g. a bare 'TColor' where the index
      stores 'Simple.TColor'. Only skEnum candidates are considered. }
    for EnumSym in AStore.FindSymbolsByExactName(AEnumQName) do
      if EnumSym.Kind = skEnum then begin Syms:= [EnumSym]; Break; end;
    if Length(Syms) = 0 then Exit;
  end;
  EnumSym:= Syms[0];
  if EnumSym.Kind <> skEnum then Exit;

  Result.Found       := True;
  Result.EnumName    := EnumSym.Name;
  Result.EnumFileId  := EnumSym.FileId;
  Result.EnumFilePath:= AStore.GetFilePath(EnumSym.FileId);
  Result.EnumStartLine:= EnumSym.StartLine;
  Result.EnumEndLine := EnumSym.EndLine;
  Result.EnumEndCol  := EnumSym.EndCol;

  { Explicit-ordinal detection: read the enum's own decl source text
    (multi-line span) and scan it -- see DetectExplicitOrdinal's doc comment
    for the type-def-'=' vs member-ordinal-'=' distinction. }
  Result.HasExplicitOrdinal:= DetectExplicitOrdinal(
    ReadDeclSpan(Result.EnumFilePath, Result.EnumStartLine, Result.EnumEndLine));

  { Members in declaration order: FindAllChildSymbols orders by start_line,
    so a simple named-skEnumValue filter preserves that order. }
  Children:= AStore.FindAllChildSymbols(EnumSym.Id);
  MemberCount:= 0;
  SetLength(MemberList, Length(Children));
  for Child in Children do
  begin
    if Child.Kind <> skEnumValue then Continue;
    if Child.Name = '' then Continue;
    MemberList[MemberCount]:= Child.Name;
    Inc(MemberCount);
  end;
  SetLength(MemberList, MemberCount);
  Result.Members:= MemberList;

  { Existing-helper guard: whole-DB, via the first-class type_helpers edge.
    Task 9b (FP fix): matched by THIS enum's own symbol id, not its bare
    name -- an unrelated same-named enum elsewhere with its own helper must
    not make this guard report HasHelper=True for EnumSym. }
  Edges:= AStore.FindHelpersOfTypeSymbol(EnumSym.Id);
  if Length(Edges) > 0 then
  begin
    Result.HasHelper:= True;
    HelperSym:= AStore.GetSymbolById(Edges[0].HelperSymbolId);
    Result.HelperSameUnit:= HelperSym.FileId = Result.EnumFileId;
    Result.HelperUnitPath:= AStore.GetFilePath(HelperSym.FileId);
  end;

  { Same-unit '<Enum>Descriptions' const array detection: name-match filtered
    to the enum's own file. Any const kind is accepted -- this is a
    convention-based hint, not a type check. }
  DescName:= Result.EnumName + 'Descriptions';
  DescCands:= AStore.FindSymbolsByExactName(DescName);
  for DescSym in DescCands do
  begin
    if DescSym.FileId <> Result.EnumFileId then Continue;
    if DescSym.Kind <> skConstDecl then Continue;
    Result.DescArrayName:= DescSym.Name;
    Break;
  end;
end;

class function TEnumHelperRefactoring.Generate(const AResolve: TEnumHelperResolve;
  const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperGen;
var
  EnumName    : string;
  HelperName  : string;
  FirstMember : string;
  WantsDesc   : Boolean;
  DeclSb      : TStringBuilder;
  BodySb      : TStringBuilder;
  M           : string;
  MemberIdx   : Integer;

  { Emits `case <ACaseExpr> of` / one `Ord(member): Result := member;` arm per
    real named member / `else Result := <FirstMember>;` / `end;` into ASb. Used
    identically by FromByte and FromInteger -- only the case expression and
    the parameter's declared type differ, both supplied by the caller. }
  procedure EmitFromCase(ASb: TStringBuilder; const ACaseExpr: string);
  var
    LM: string;
  begin
    ASb.AppendLine('  case ' + ACaseExpr + ' of');
    for LM in AResolve.Members do
      ASb.AppendLine('    Ord(' + LM + '): Result := ' + LM + ';');
    ASb.AppendLine('  else');
    ASb.AppendLine('    Result := ' + FirstMember + ';');
    ASb.AppendLine('  end;');
  end;

begin
  Result:= Default(TEnumHelperGen);
  EnumName  := AResolve.EnumName;
  HelperName:= EnumName + 'Helper';
  if Length(AResolve.Members) > 0 then FirstMember:= AResolve.Members[0] else FirstMember:= '';
  WantsDesc := AResolve.DescArrayName <> '';

  DeclSb:= TStringBuilder.Create;
  BodySb:= TStringBuilder.Create;
  try
    // --- DECL ---
    DeclSb.AppendLine(HelperName + ' = record helper for ' + EnumName);
    DeclSb.AppendLine('  public');
    if ehmToByte in AMethods then
      DeclSb.AppendLine('    function ToByte: Byte;');
    if ehmToInteger in AMethods then
      DeclSb.AppendLine('    function ToInteger: Integer;');
    if ehmToString in AMethods then
      DeclSb.AppendLine('    function ToString: string;');
    if ehmFromByte in AMethods then
      DeclSb.AppendLine('    class function FromByte(const AValue: Byte): ' + EnumName + '; static;');
    if ehmFromInteger in AMethods then
      DeclSb.AppendLine('    class function FromInteger(const AValue: Integer): ' + EnumName + '; static;');
    if ehmFromString in AMethods then
      DeclSb.AppendLine('    class function FromString(const AValue: string): ' + EnumName + '; static;');
    if WantsDesc then
      DeclSb.AppendLine('    function ToDescription: string;');
    DeclSb.Append('end;');

    // --- BODIES ---
    BodySb.AppendLine('{ ' + HelperName + ' }');
    BodySb.AppendLine('');

    if ehmToByte in AMethods then
    begin
      BodySb.AppendLine('function ' + HelperName + '.ToByte: Byte;');
      BodySb.AppendLine('begin');
      BodySb.AppendLine('  Result := Ord(Self);');
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    if ehmToInteger in AMethods then
    begin
      BodySb.AppendLine('function ' + HelperName + '.ToInteger: Integer;');
      BodySb.AppendLine('begin');
      BodySb.AppendLine('  Result := Ord(Self);');
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    if ehmFromByte in AMethods then
    begin
      BodySb.AppendLine('class function ' + HelperName + '.FromByte(const AValue: Byte): ' + EnumName + ';');
      BodySb.AppendLine('begin');
      EmitFromCase(BodySb, 'AValue');
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    if ehmFromInteger in AMethods then
    begin
      BodySb.AppendLine('class function ' + HelperName + '.FromInteger(const AValue: Integer): ' + EnumName + ';');
      BodySb.AppendLine('begin');
      EmitFromCase(BodySb, 'AValue');
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    if ehmToString in AMethods then
    begin
      BodySb.AppendLine('function ' + HelperName + '.ToString: string;');
      BodySb.AppendLine('begin');
      if AToStringMode = tsmRtti then
      begin
        BodySb.AppendLine('  Result := GetEnumName(TypeInfo(' + EnumName + '), Ord(Self));');
        Result.NeedsTypInfo:= True;
      end
      else
      begin
        BodySb.AppendLine('  case Self of');
        for M in AResolve.Members do
          BodySb.AppendLine('    ' + M + ': Result := ''' + M + ''';');
        BodySb.AppendLine('  else');
        BodySb.AppendLine('    Result := '''';');
        BodySb.AppendLine('  end;');
      end;
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    if ehmFromString in AMethods then
    begin
      BodySb.AppendLine('class function ' + HelperName + '.FromString(const AValue: string): ' + EnumName + ';');
      BodySb.AppendLine('begin');
      if AToStringMode = tsmRtti then
      begin
        BodySb.AppendLine('  Result := ' + EnumName + '(GetEnumValue(TypeInfo(' + EnumName + '), AValue));');
        Result.NeedsTypInfo:= True;
      end
      else
      begin
        { AValue is a string -- Object Pascal `case` requires an ordinal
          selector, so (unlike ToString's `case Self of`, valid because Self
          is the enum) FromString's case-mode dispatch is an if/else-if
          chain over string comparisons, not a case statement. }
        for MemberIdx:= 0 to High(AResolve.Members) do
        begin
          M:= AResolve.Members[MemberIdx];
          if MemberIdx = 0 then
            BodySb.AppendLine('  if AValue = ''' + M + ''' then Result := ' + M)
          else
            BodySb.AppendLine('  else if AValue = ''' + M + ''' then Result := ' + M);
        end;
        BodySb.AppendLine('  else');
        BodySb.AppendLine('    Result := ' + FirstMember + ';');
      end;
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    if WantsDesc then
    begin
      BodySb.AppendLine('function ' + HelperName + '.ToDescription: string;');
      BodySb.AppendLine('begin');
      BodySb.AppendLine('  Result := ' + AResolve.DescArrayName + '[Self];');
      BodySb.AppendLine('end;');
      BodySb.AppendLine('');
    end;

    Result.DeclText  := DeclSb.ToString;
    Result.BodiesText:= BodySb.ToString.TrimRight([#13, #10]);
  finally
    DeclSb.Free;
    BodySb.Free;
  end;
end;

{ Bounded scan for the file's top-level 'implementation' keyword line: a
  normal Delphi unit has exactly one, alone on its own line. This mirrors
  TFindUnitRefactoring.Build's existing keyword-locate scan (same unit,
  DRagLint.Refactor.TextEdit.pas) rather than hand-rolling a new scanner --
  both need the same "which line does the implementation/interface keyword
  start" fact and neither has access to a stored section-anchor table
  (Task 1 only shipped type_helpers; no unit-anchors table exists yet -- see
  the design spec Section 4 note). A case-insensitive, whole-trimmed-line
  match is deliberately simple: it will not misfire on the word appearing
  inside a string literal or a brace/line comment unless that text is alone
  on its own line reading exactly 'implementation' after trimming, which does
  not occur in real source (the identifier is reserved and cannot appear as a
  bare comment/string line by itself in any fixture or real unit
  encountered). Returns 0 when not found. }
function FindImplementationLine(const ALines: TStringList): Integer;
var
  I: Integer;
  T: string;
begin
  Result:= 0;
  for I:= 0 to ALines.Count - 1 do
  begin
    T:= LowerCase(Trim(ALines[I]));
    if T = 'implementation' then Exit(I + 1); { 1-based }
  end;
end;

{ Prefixes AIndent onto every line of ABlock (CRLF- or LF-joined, as produced
  by Generate's TStringBuilder text), so the spliced decl block lines up
  under `type` at the same indentation as the enum it follows. }
function IndentLines(const ABlock, AIndent: string): string;
var
  Parts: TArray<string>;
  I    : Integer;
  SB   : TStringBuilder;
begin
  Parts:= ABlock.Replace(#13#10, #10).Split([#10]);
  SB:= TStringBuilder.Create;
  try
    for I:= 0 to High(Parts) do
    begin
      if I > 0 then SB.Append(#13#10);
      if Parts[I] = '' then SB.Append('') else SB.Append(AIndent).Append(Parts[I]);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ True when System.TypInfo (or its pre-namespace short form 'TypInfo') is
  already present in AUses -- checked across whichever section(s) AUses was
  built from (the caller passes the whole-file uses list, both interface and
  implementation, per the spec's "neither interface nor implementation uses
  contains it" rule). Only ever called for this one literal unit name, so a
  fixed two-form comparison is simpler than a generic dotted-name splitter. }
function UsesContainsTypInfo(const AUses: TArray<TUnitUse>): Boolean;
var
  U: TUnitUse;
begin
  Result:= False;
  for U in AUses do
    if SameText(U.UnitName, 'System.TypInfo') or SameText(U.UnitName, 'TypInfo') then
      Exit(True);
end;

class function TEnumHelperRefactoring.Build(const AStore: ISymbolStore; const AEnumQName: string;
  const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperResult;
var
  Res        : TEnumHelperResolve;
  Gen        : TEnumHelperGen;
  RawBytes   : TBytes;
  Src        : string;
  Lines      : TStringList;
  ImplLine   : Integer;
  BodiesLine : Integer;
  EnumIndent : string;
  DeclEdit   : TTextEdit;
  BodiesEdit : TTextEdit;
  UsesEdit   : TTextEdit;
  Edits      : TArray<TTextEdit>;
  FileId     : Int64;
  Uses_      : TArray<TUnitUse>;
  UsesPrefix : string;
  LastImplUse: TUnitUse;
  HaveLastImplUse: Boolean;
  U          : TUnitUse;
  EffectiveToStringMode: TToStringMode;
begin
  Result:= Default(TEnumHelperResult);

  Res:= Resolve(AStore, AEnumQName);
  if not Res.Found then
  begin
    Result.Action := ehaNotFound;
    Result.Message:= Format('enum "%s" not found', [AEnumQName]);
    Exit;
  end;

  Result.EnumName:= Res.EnumName;
  Result.FilePath:= Res.EnumFilePath;

  if Res.HasHelper then
  begin
    Result.Action:= ehaExists;
    if Res.HelperSameUnit then
      Result.Message:= Format('helper for "%s" already exists in the same unit (%s)',
        [Res.EnumName, Res.EnumFilePath])
    else
      Result.Message:= Format('helper for "%s" already exists in unit "%s"',
        [Res.EnumName, Res.HelperUnitPath]);
    Exit;
  end;

  if (Res.EnumFilePath = '') or (not TFile.Exists(Res.EnumFilePath)) then
  begin
    Result.Action := ehaNoImplSection;
    Result.Message:= Format('declaring file not found on disk: %s', [Res.EnumFilePath]);
    Exit;
  end;

  RawBytes:= TFile.ReadAllBytes(Res.EnumFilePath);
  Src     := TEncoding.ANSI.GetString(RawBytes);

  Lines:= TStringList.Create;
  try
    Lines.Text:= Src;

    ImplLine:= FindImplementationLine(Lines);
    if ImplLine = 0 then
    begin
      Result.Action := ehaNoImplSection;
      Result.Message:= Format('unit "%s" has no implementation section', [ExtractFileName(Res.EnumFilePath)]);
      Exit;
    end;

    { Effective ToString/FromString mode: an explicit --tostring case always
      forces case mode; an explicit --tostring rtti (the default) falls back
      to case mode whenever Res.HasExplicitOrdinal (the enum decl has at
      least one member with an explicit `= N`). NOTE this is a deliberately
      CONSERVATIVE trigger, not a precise one: Delphi only actually disables
      automatic RTTI when the resulting ordinal VALUES stop being the
      implicit sequential-from-0 default (verified: an enum whose explicit
      ordinals happen to still be 0,1,2,... keeps working RTTI fine) -- but
      re-deriving "are these explicit values sequential" from source text
      is needless complexity for no real benefit, so ANY explicit ordinal
      falls back, even on the rare case where RTTI would have compiled. This
      never produces a wrong/non-compiling result, only an occasional
      unnecessary case-mode fallback. A fully implicit (no `=` at all) enum
      still gets RTTI under the default, unchanged from before this fallback
      existed. This is the ONLY place the fallback decision is made; Generate
      remains a pure function of whatever mode it is handed. }
    EffectiveToStringMode:= AToStringMode;
    if (AToStringMode = tsmRtti) and Res.HasExplicitOrdinal then
      EffectiveToStringMode:= tsmCase;

    Gen:= Generate(Res, AMethods, EffectiveToStringMode);

    { Indentation for the decl: match the enum's own declaration line (the
      standard 2-space `type` section indent in every fixture/real unit
      encountered). Falls back to 2 spaces if the anchor line is out of
      range (should not happen for a resolved enum). }
    EnumIndent:= '  ';
    if (Res.EnumEndLine >= 1) and (Res.EnumEndLine <= Lines.Count) then
    begin
      var LEnumLine: string:= Lines[Res.EnumEndLine - 1];
      var LTrimLen : Integer:= Length(LEnumLine) - Length(TrimLeft(LEnumLine));
      EnumIndent:= Copy(LEnumLine, 1, LTrimLen);
    end;

    { Decl edit: insert right after the enum's own decl line, same `type`
      section. Gen.DeclText is trimmed of trailing line breaks (Task 3) --
      add our own leading blank line then indent every line of the block to
      match the enum's indentation. }
    DeclEdit:= Default(TTextEdit);
    DeclEdit.FilePath:= Res.EnumFilePath;
    DeclEdit.Kind    := tekInsertLines;
    DeclEdit.Line    := Res.EnumEndLine;
    DeclEdit.Text    := ''#13#10 + IndentLines(Gen.DeclText, EnumIndent);
    Edits:= [DeclEdit];

    { Locate an existing implementation `uses` clause (independent of
      NeedsTypInfo): Object Pascal requires a section's `uses` clause, if
      any, to be the FIRST thing after `implementation`/`interface` -- it
      cannot follow a routine body. So the bodies insertion point can never
      be earlier than the end of an existing implementation uses clause;
      it must always land AFTER it. Only the implementation section can
      hold routine bodies, so only its uses clause (not the interface's)
      constrains BodiesLine. }
    FileId:= Res.EnumFileId;
    if FileId <= 0 then FileId:= AStore.FindFileIdByPath(Res.EnumFilePath);
    Uses_:= nil;
    if FileId > 0 then Uses_:= AStore.GetUnitUsesForFile(FileId);

    HaveLastImplUse:= False;
    LastImplUse    := Default(TUnitUse);
    for U in Uses_ do
      if U.Section = uusImplementation then
        if (not HaveLastImplUse) or (U.StartLine > LastImplUse.StartLine)
           or ((U.StartLine = LastImplUse.StartLine) and (U.StartCol > LastImplUse.StartCol)) then
        begin LastImplUse:= U; HaveLastImplUse:= True; end;

    BodiesLine:= ImplLine;
    if HaveLastImplUse and (LastImplUse.EndLine > BodiesLine) then
      BodiesLine:= LastImplUse.EndLine;

    { uses edit: only when RTTI ToString/FromString were generated AND
      System.TypInfo is not already visible (interface OR implementation
      uses -- queried via unit_uses, never string-scanned). A found
      implementation uses clause gets ', System.TypInfo' appended in place
      (independently anchored at its own line, no ordering ambiguity with
      the bodies edit below). Absent any implementation uses clause, a fresh
      'uses System.TypInfo;' is folded into the SAME bodies edit (both would
      anchor at ImplLine, so keep them as one edit rather than two competing
      for the same insertion point). }
    UsesPrefix:= '';
    if Gen.NeedsTypInfo and (not UsesContainsTypInfo(Uses_)) then
    begin
      if HaveLastImplUse then
      begin
        UsesEdit:= Default(TTextEdit);
        UsesEdit.FilePath:= Res.EnumFilePath;
        UsesEdit.Kind    := tekInsertInLine;
        UsesEdit.Line    := LastImplUse.EndLine;
        UsesEdit.Col     := LastImplUse.EndCol;
        UsesEdit.Text    := ', System.TypInfo';
        Edits:= Edits + [UsesEdit];
      end
      else
        UsesPrefix:= #13#10'uses System.TypInfo;'#13#10;
    end;

    { Bodies edit: ALWAYS in the implementation section, anchored at
      BodiesLine (computed above: right after `implementation` itself when
      the section has no uses clause of its own, else right after that
      uses clause -- both empty-implementation and existing-implementation-
      uses fixtures verified to compile). Landing at the very top of the
      section (before any pre-existing routine bodies) rather than after
      them is a deliberate simplification: locating "after the last
      existing routine" needs the same not-yet-built section-anchor table
      the design spec flags as optional/deferred, and top-of-section is
      always valid Object Pascal, unlike top-of-section-before-a-uses-clause
      (invalid -- the bug this comment block exists to avoid re-introducing).
      Gen.BodiesText is right-trimmed (Task 3) -- add our own leading blank
      line; UsesPrefix (set above) is a fresh 'uses System.TypInfo;' block
      prepended only when the unit had no implementation uses clause to
      extend instead. }
    BodiesEdit:= Default(TTextEdit);
    BodiesEdit.FilePath:= Res.EnumFilePath;
    BodiesEdit.Kind    := tekInsertLines;
    BodiesEdit.Line    := BodiesLine;
    BodiesEdit.Text    := UsesPrefix + #13#10 + Gen.BodiesText;
    Edits:= Edits + [BodiesEdit];

    Result.Edits := Edits;
    Result.Action:= ehaBuilt;
  finally
    Lines.Free;
  end;
end;

end.
