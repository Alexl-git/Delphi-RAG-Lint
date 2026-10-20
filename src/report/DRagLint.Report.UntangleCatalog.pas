unit DRagLint.Report.UntangleCatalog;

// ---------------------------------------------------------------------------
// E18 T4b: the leaf-unit catalog of `cycles --plan`.
//
// Declarations moved out of a unit of a circular group go into a LEAF unit
// named `<Source>.Untangle`. When such a unit already exists in the project
// and still uses no unit of the group, the plan EXTENDS it instead of
// creating a second one; when it exists but uses a unit of the group (it is
// no leaf for this cycle) the plan numbers a new one, `<Source>.Untangle2`,
// `3`, ... and says why.
//
// Index facts only: files.path (the unit stem, as DoCycles.UnitNameOfFile
// derives it), unit_uses (both sections) and symbols.section / end_line. No
// new table, no extractor change. This unit must not use
// DRagLint.Report.CyclePlan in its interface (CyclePlan uses it).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.Core.Interfaces;

const
  /// <summary>Suffix of every leaf unit `cycles --plan` creates or extends:
  /// declarations moved out of unit `X` go into `X.Untangle`.</summary>
  CUntangleSuffix = '.Untangle';

type
  /// <summary>What the plan does with the leaf unit it names.</summary>
  TUntangleDecision = (
    /// <summary>Create a new unit at TUntangleLeaf.Path.</summary>
    udCreate,
    /// <summary>Insert into the existing, indexed unit at TUntangleLeaf.Path.</summary>
    udExtend);

  /// <summary>The leaf unit that receives the declarations moved out of one
  /// source unit of a circular group, as ResolveUntangleLeaf found it.</summary>
  TUntangleLeaf = record
    /// <summary>Unit name, e.g. 'DemoConfig.Untangle' (or '...Untangle2').</summary>
    UnitName: string;
    /// <summary>Its file: the existing one (udExtend) or the one to create
    /// next to the source unit (udCreate).</summary>
    Path: string;
    /// <summary>Lower-case stem of the source unit, e.g. 'democonfig'.</summary>
    SourceStem: string;
    /// <summary>Create a new unit or extend the existing one.</summary>
    Decision: TUntangleDecision;
    /// <summary>udExtend: the existing unit's file id; 0 for udCreate.</summary>
    Fid: Int64;
    /// <summary>udExtend: last line of the last interface-section symbol --
    /// new declarations go after it. 0 when the unit has no interface symbol
    /// (the caller then anchors on the `interface` keyword / uses clause).</summary>
    InsertAfterLine: Integer;
    /// <summary>udExtend: the unit names of the existing interface uses clause,
    /// as written, in source order.</summary>
    ExistingUses: TArray<string>;
    /// <summary>Why a `<Source>.Untangle` that exists was passed over, one
    /// sentence per skipped unit joined by '; ', ending in what is done
    /// instead, e.g. 'existing DemoConfig.Untangle uses DemoLogger, a unit of
    /// this cycle -- creating DemoConfig.Untangle2'. Empty when none was.</summary>
    Reason: string;
  end;

/// <summary>Names (and, when one exists, finds) the leaf unit that receives
/// declarations moved out of pSourceStem for the SCC pScc. Index facts only.</summary>
/// <param name="pStore">Open index of the project; read only.</param>
/// <param name="pSourceStem">Lower-case stem of the unit the declarations
/// move out of (the declaring unit, or for R2 the class unit).</param>
/// <param name="pScc">The circular group, as lower-case unit stems.</param>
/// <param name="pProjectDir">Directory of the project file; a candidate must
/// lie under it or in the source unit's own directory. Empty = any indexed
/// path qualifies.</param>
/// <returns>udExtend with the existing unit's facts when an indexed `.pas`
/// whose stem is `&lt;source&gt;.untangle` (then `...untangle2`, `3`, ...)
/// lies under the project's roots and names no member of pScc in either uses
/// clause; otherwise udCreate with the path
/// `&lt;dir of source&gt;\&lt;Source&gt;.Untangle&lt;N&gt;.pas` of the first number
/// that is neither indexed nor an existing file.</returns>
/// <remarks>A candidate that uses a member, lies outside the roots, or exists
/// on disk but is not indexed is skipped, and Reason says so. Reads every file
/// path of the index once per call; holds no state.</remarks>
function ResolveUntangleLeaf(const pStore: ISymbolStore; const pSourceStem: string;
  const pScc: TArray<string>; const pProjectDir: string): TUntangleLeaf;

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils, System.Generics.Collections,
  DRagLint.Core.Model;

const
  CPasExt = '.pas';

function NormPath(const pPath: string): string;
begin
  Result:= StringReplace(pPath, '/', '\', [rfReplaceAll]);
end;

function StemOf(const pPath: string): string;
begin
  Result:= LowerCase(ChangeFileExt(ExtractFileName(NormPath(pPath)), ''));
end;

function IsUnder(const pPath, pDir: string): Boolean;
begin
  Result:= (pDir <> '') and StartsText(IncludeTrailingPathDelimiter(NormPath(pDir)), NormPath(pPath));
end;

{ The first entry of either uses clause that names a member of pScc, or ''. }
function UsedMember(const pUses: TArray<TUnitUse>; const pScc: TArray<string>): string;
begin
  for var U in pUses do
    if MatchText(U.UnitName, pScc) then Exit(U.UnitName);
  Result:= '';
end;

{ Last line of the last interface-section declaration of pPath, or 0. }
function LastInterfaceLine(const pStore: ISymbolStore; const pPath: string): Integer;
begin
  Result:= 0;
  for var S in pStore.FindSymbolsByFile(pPath) do
    if SameText(S.Section, 'interface') and not (S.Kind in [skUnit, skProgram, skPackage]) and (S.EndLine > Result) then
      Result:= S.EndLine;
end;

function InterfaceUses(const pUses: TArray<TUnitUse>): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var U in pUses do
      if U.Section = uusInterface then L.Add(U.UnitName);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function ResolveUntangleLeaf(const pStore: ISymbolStore; const pSourceStem: string;
  const pScc: TArray<string>; const pProjectDir: string): TUntangleLeaf;
var
  Paths  : TDictionary<string, Int64>;   // stem -> fid, for the source and its .untangle* stems
  Why    : TList<string>;
  SrcPath: string;
  SrcFid : Int64;
  Fid    : Int64;
  Name   : string;
  N      : Integer;
begin
  Result:= Default(TUntangleLeaf);
  Result.SourceStem:= pSourceStem;
  Paths:= TDictionary<string, Int64>.Create;
  Why  := TList<string>.Create;
  try
    for var F in pStore.GetAllFileIds do
    begin
      var P:= pStore.GetFilePath(F);
      if not SameText(ExtractFileExt(P), CPasExt) then Continue;
      var S:= StemOf(P);
      if (S = pSourceStem) or StartsStr(pSourceStem + LowerCase(CUntangleSuffix), S) then Paths.AddOrSetValue(S, F);
    end;
    SrcPath:= '';
    if Paths.TryGetValue(pSourceStem, SrcFid) then SrcPath:= NormPath(pStore.GetFilePath(SrcFid));
    var SrcName:= if SrcPath <> '' then ChangeFileExt(ExtractFileName(SrcPath), '') else pSourceStem;
    var SrcDir := ExtractFilePath(SrcPath);
    N:= 1;
    while True do
    begin
      Name:= SrcName + CUntangleSuffix + (if N > 1 then IntToStr(N) else '');
      Inc(N);
      if Paths.TryGetValue(LowerCase(Name), Fid) then
      begin
        var P:= NormPath(pStore.GetFilePath(Fid));
        if (pProjectDir <> '') and not (IsUnder(P, pProjectDir) or SameText(ExtractFilePath(P), SrcDir)) then
        begin
          Why.Add(Format('existing %s lies outside the project''s roots (%s)', [Name, P]));
          Continue;
        end;
        var UnitUses:= pStore.GetUnitUsesForFile(Fid);
        var Member:= UsedMember(UnitUses, pScc);
        if Member <> '' then
        begin
          Why.Add(Format('existing %s uses %s, a unit of this cycle', [Name, Member]));
          Continue;
        end;
        Result.Decision       := udExtend;
        Result.Fid            := Fid;
        Result.Path           := P;
        Result.InsertAfterLine:= LastInterfaceLine(pStore, P);
        Result.ExistingUses   := InterfaceUses(UnitUses);
        Break;
      end;
      if TFile.Exists(SrcDir + Name + CPasExt) then
      begin
        Why.Add(Format('a file %s%s exists but is not indexed', [Name, CPasExt]));
        Continue;
      end;
      Result.Decision:= udCreate;
      Result.Path    := SrcDir + Name + CPasExt;
      Break;
    end;
    Result.UnitName:= Name;
    if Why.Count > 0 then
      Result.Reason:= string.Join('; ', Why.ToArray) +
        (if Result.Decision = udExtend then ' -- extending ' else ' -- creating ') + Name;
  finally
    Why.Free;
    Paths.Free;
  end;
end;

end.
