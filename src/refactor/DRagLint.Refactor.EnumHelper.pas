unit DRagLint.Refactor.EnumHelper;

{ Enum-helper generator -- RESOLVE (Task 2) + GENERATE (Task 3) stages.
  RESOLVE looks up an enum by qualified name, gathers its members in
  declaration order, checks whether a helper already exists anywhere in the
  indexed codebase (via ISymbolStore.FindHelpersOfType), and detects a
  same-unit `<Enum>Descriptions` const array. GENERATE synthesizes the Byte-
  family record-helper declaration + method bodies from a TEnumHelperResolve,
  as pure string building (no store/index access). PLACE (text-edit emission)
  is added in a later task on the same TEnumHelperRefactoring class. }

interface

uses
  System.SysUtils
  , System.Classes
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>One kind of helper method the generator can emit for an enum.
  /// ehmToByte/ehmToInteger convert the enum value outward; ehmFromByte/
  /// ehmFromInteger construct an enum value from an ordinal (with range
  /// checking); ehmToString/ehmFromString convert to/from a display string
  /// (see TToStringMode for the ToString strategy).</summary>
  TEnumHelperMethod = (ehmToByte, ehmFromByte, ehmToInteger, ehmFromInteger, ehmToString, ehmFromString);

  /// <summary>The set of helper methods requested for one generation run.</summary>
  TEnumHelperMethods = set of TEnumHelperMethod;

  /// <summary>Strategy for the generated ToString method: tsmRtti defers to
  /// System.TypInfo.GetEnumName (no per-member code, always in sync with the
  /// enum type but yields the raw identifier text, e.g. 'clRed'); tsmCase
  /// emits an explicit case statement over a `<Enum>Descriptions`-style
  /// literal per member (readable display text, but must be kept in sync by
  /// hand if members are added).</summary>
  TToStringMode = (tsmRtti, tsmCase);

  /// <summary>Result of resolving an enum type by qualified name ahead of
  /// generating a helper for it. Found=False means the qname did not resolve
  /// to an skEnum symbol; every other field is then undefined and callers
  /// must not act on it.</summary>
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
    /// <summary>1-based line of the enum declaration's end (closing ')' /
    /// ';'). Insertion anchor for the generated helper declaration.</summary>
    EnumEndLine: Integer;
    /// <summary>1-based column of the enum declaration's end.</summary>
    EnumEndCol: Integer;
    /// <summary>True when FindHelpersOfType(EnumName) returned at least one
    /// edge anywhere in the indexed codebase (whole-DB, not just this unit).</summary>
    HasHelper: Boolean;
    /// <summary>True when the existing helper (HasHelper=True) is declared
    /// in the same file as the enum (EnumFileId). Undefined when HasHelper
    /// is False.</summary>
    HelperSameUnit: Boolean;
    /// <summary>Filesystem path of the existing helper's declaring unit;
    /// '' when HasHelper is False.</summary>
    HelperUnitPath: string;
    /// <summary>Name of a same-unit const array named '<EnumName>Descriptions'
    /// if one exists (e.g. 'TColorDescriptions'), else ''.</summary>
    DescArrayName: string;
  end;

  /// <summary>Result of the GENERATE stage: the synthesized Object Pascal
  /// text for a Byte-family record helper, ready for the PLACE stage to
  /// splice into the target unit. Pure text -- no file positions here (those
  /// live on TEnumHelperResolve).</summary>
  TEnumHelperGen = record
    /// <summary>The `T<Enum>Helper = record helper for T<Enum> ... end;`
    /// type declaration block (CRLF-joined, no trailing line break).</summary>
    DeclText: string;
    /// <summary>The implementation-section method bodies, preceded by the
    /// `{ T<Enum>Helper }` convention comment (CRLF-joined, no trailing line
    /// break).</summary>
    BodiesText: string;
    /// <summary>True when RTTI-based ToString/FromString were emitted
    /// (System.TypInfo.GetEnumName/GetEnumValue); the PLACE stage should add
    /// System.TypInfo to the unit's uses clause if not already present. False
    /// when no ToString/FromString were requested, or tsmCase was used.</summary>
    NeedsTypInfo: Boolean;
  end;

  /// <summary>Enum-helper generator: resolves an enum type, synthesizes a
  /// record helper implementing the requested conversion methods, and places
  /// the result via text edits. Resolve (Task 2) + Generate (this task) are
  /// implemented; Build (the PLACE stage) is added later on this same
  /// class.</summary>
  TEnumHelperRefactoring = class
  public
    /// <summary>Resolves AEnumQName to its declaring enum symbol, its members
    /// in declaration order, whether a helper for it already exists anywhere
    /// in AStore, and whether a same-unit '<Enum>Descriptions' const array is
    /// present. Does not read or write any file.</summary>
    /// <param name="AStore">Open symbol store to query (whole-DB visibility
    /// for the existing-helper guard).</param>
    /// <param name="AEnumQName">Qualified name of the enum type, e.g.
    /// 'Simple.TColor'. A short (unqualified) name also works if it uniquely
    /// resolves via the store's qualified-name lookup.</param>
    /// <returns>A TEnumHelperResolve with Found=False when AEnumQName does
    /// not resolve to exactly one skEnum symbol.</returns>
    class function Resolve(const AStore: ISymbolStore; const AEnumQName: string): TEnumHelperResolve; static;

    /// <summary>Synthesizes the Byte-family record-helper declaration and
    /// method bodies for AResolve.EnumName, from AResolve.Members (real
    /// named members only, declaration order). Pure function of its inputs:
    /// no store/index/file access. `To*` methods return Ord(Self); `From*`
    /// methods use a `case Ord(member)` idiom with `else` mapping to the
    /// FIRST declared member (= low(T<Enum>)). ToDescription is NOT one of
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
    class function Generate(const AResolve: TEnumHelperResolve;
      const AMethods: TEnumHelperMethods; const AToStringMode: TToStringMode): TEnumHelperGen; static;
  end;

implementation

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
  Result.EnumEndLine := EnumSym.EndLine;
  Result.EnumEndCol  := EnumSym.EndCol;

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

  { Existing-helper guard: whole-DB, via the first-class type_helpers edge. }
  Edges:= AStore.FindHelpersOfType(Result.EnumName);
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
        BodySb.AppendLine('  case AValue of');
        for M in AResolve.Members do
          BodySb.AppendLine('    ''' + M + ''': Result := ' + M + ';');
        BodySb.AppendLine('  else');
        BodySb.AppendLine('    Result := ' + FirstMember + ';');
        BodySb.AppendLine('  end;');
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

end.
