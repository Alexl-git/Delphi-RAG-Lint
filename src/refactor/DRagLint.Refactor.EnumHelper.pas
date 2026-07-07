unit DRagLint.Refactor.EnumHelper;

{ Enum-helper generator -- RESOLVE stage (Task 2). Looks up an enum by
  qualified name, gathers its members in declaration order, checks whether a
  helper already exists anywhere in the indexed codebase (via
  ISymbolStore.FindHelpersOfType), and detects a same-unit `<Enum>Descriptions`
  const array. GENERATE (method-body synthesis) and PLACE (text-edit emission)
  are added in later tasks on the same TEnumHelperRefactoring class. }

interface

uses
  System.SysUtils
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

  /// <summary>Enum-helper generator: resolves an enum type, synthesizes a
  /// record helper implementing the requested conversion methods, and places
  /// the result via text edits. This task implements Resolve only; Generate
  /// and Build (the GENERATE and PLACE stages) are added later on this same
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

end.
