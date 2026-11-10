unit DRagLint.Lint.UsesAudit;

{ The uses-audit CORE, extracted from DRagLint.CLI.DoUsesAudit (gap-rules wave, lane G8) so the
  `uses-audit` verb and the `uses-movable-to-implementation` lint rule (and later the uses-fix
  autofixes) share ONE verdict routine instead of two copies that could disagree.

  A verdict is an index-based PROPOSAL, never a proof: tree-sitter can miss a reference, which
  is why the uses-fix rewriter compiler-verifies each candidate before applying it. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Verdict: no indexed project symbol of the unit is referenced from the file at all.</summary>
  USES_VERDICT_UNUSED = 'unused';
  /// <summary>Verdict: an INTERFACE uses entry that only the implementation section references.</summary>
  USES_VERDICT_MOVE = 'move-to-implementation';

type
  /// <summary>One uses-clause entry the audit has an opinion about.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.UsesAudit.pas) ?, DRagLint.Lint.ProjectRules.CollectUsesMovableToImplementation (DRagLint.Lint.ProjectRules.pas) ?, DRagLint.Lint.UsesAudit.TUsesAuditor.Audit (DRagLint.Lint.UsesAudit.pas)</para>
  /// <para>Used in units: DRagLint.Lint.ProjectRules, DRagLint.Lint.UsesAudit</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUsesAuditRow = record
    /// <summary>The unit name verbatim, with dots ('uB').</summary>
    UnitName : string;
    /// <summary>USES_VERDICT_UNUSED or USES_VERDICT_MOVE.</summary>
    Verdict  : string;
    /// <summary>The section the entry sits in (uusInterface / uusImplementation).</summary>
    Section  : TUnitUseSection;
    /// <summary>1-based position of the entry's unit name in the source file; for an
    /// entry written inside an include file, the include directive's line (column 1).</summary>
    StartLine: Integer;
    StartCol : Integer;
    EndLine  : Integer;
    EndCol   : Integer;
  end;

  /// <summary>Computes uses-audit verdicts for the files of one open store.</summary>
  /// <remarks>
  /// Reusable across many files of the same store: the stem-to-file map and the
  /// symbol-name-to-defining-units cache are built once and shared. Only project units that
  /// are in the index are audited (never RTL / library uses). Not thread-safe; the store must
  /// outlive the auditor, which does not own it.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas), DRagLint.Lint.ProjectRules.CollectUsesMovableToImplementation (DRagLint.Lint.ProjectRules.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.ProjectRules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUsesAuditor = class
  strict private
    FStore       : ISymbolStore;
    FIndexedUnits: TDictionary<string, Int64>;
    FNameCache   : TDictionary<string, TArray<string>>;
    /// <summary><!-- drag-lint:auto sum -->distinct indexed-unit stems that define a
    /// symbol named AName (cached)</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: Us.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.UsesAudit.TUsesAuditor.Audit (DRagLint.Lint.UsesAudit.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf</para>
    /// <para>Reads: FNameCache, FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Audit"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UnitsDefining(const AName: string): TArray<string>;
  public
    /// <summary>Builds the stem-to-file map from the store.</summary>
    /// <param name="AStore">An open store; must not be nil.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas), DRagLint.Lint.ProjectRules.CollectUsesMovableToImplementation (DRagLint.Lint.ProjectRules.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf</para>
    /// <para>constructor</para>
    /// <para>Reads: FStore, FIndexedUnits   Writes: FStore, FIndexedUnits, FNameCache</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Audit"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStore: ISymbolStore);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FNameCache, FIndexedUnits</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Audit"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Create"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.TryFindFile"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.UnitsDefining"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Lower-cased unit stem of a path: 'C:\x\UnitB.pas' gives 'unitb'.</summary>
    /// <param name="APath">Any path; '/' and '\' both separate.</param>
    /// <returns>The stem, '' for an empty path.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.UsesAudit.TUsesAuditor.Audit (DRagLint.Lint.UsesAudit.pas), DRagLint.Lint.UsesAudit.TUsesAuditor.Create (DRagLint.Lint.UsesAudit.pas), DRagLint.Lint.UsesAudit.TUsesAuditor.TryFindFile (DRagLint.Lint.UsesAudit.pas), DRagLint.Lint.UsesAudit.TUsesAuditor.UnitsDefining (DRagLint.Lint.UsesAudit.pas)</para>
    /// <para>Calls: ChangeFileExt, ExtractFileName, LowerCase, StringReplace</para>
    /// <para>Returns: LowerCase(ChangeFileExt(ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll])), ''))</para>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Audit"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Create"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Destroy"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.TryFindFile"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.UnitsDefining"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function StemOf(const APath: string): string;
    /// <summary>Resolves a path to its indexed file by unit stem.</summary>
    /// <param name="APath">The unit's path (only its stem matters).</param>
    /// <param name="AFileId">Out: files.id when found.</param>
    /// <returns>True when the stem is indexed.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf</para>
    /// <para>Returns: FIndexedUnits.TryGetValue(StemOf(APath), AFileId)</para>
    /// <para>Reads: FIndexedUnits</para>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Audit"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Create"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.Destroy"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.UnitsDefining"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TryFindFile(const APath: string; out AFileId: Int64): Boolean;
    /// <summary>The audit verdicts for one indexed file, in uses-clause order.</summary>
    /// <param name="AFileId">files.id of the unit to audit.</param>
    /// <param name="AFallbackPath">Source path to read when the stored path no longer exists.</param>
    /// <returns>One row per entry that is unused or movable; empty when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas), DRagLint.Lint.ProjectRules.CollectUsesMovableToImplementation (DRagLint.Lint.ProjectRules.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetReferencesFromFile, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf, DRagLint.Lint.UsesAudit.TUsesAuditor.UnitsDefining, FileExists, LowerCase, SameText, Trim</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 71 lines (full implementation)</para>
    /// <para>Reads: FStore, FIndexedUnits</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetReferencesFromFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.StemOf"/>
    /// <seealso cref="DRagLint.Lint.UsesAudit.TUsesAuditor.UnitsDefining"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Audit(AFileId: Int64; const AFallbackPath: string): TArray<TUsesAuditRow>;
  end;

implementation

class function TUsesAuditor.StemOf(const APath: string): string;
begin
  Result:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll])), ''));
end;

constructor TUsesAuditor.Create(const AStore: ISymbolStore);
var
  Fid: Int64;
  U  : string;
begin
  inherited Create;
  FStore       := AStore;
  FIndexedUnits:= TDictionary<string, Int64>.Create;
  FNameCache   := TDictionary<string, TArray<string>>.Create;
  for Fid in FStore.GetAllFileIds do
  begin
    U:= StemOf(FStore.GetFilePath(Fid));
    if U <> '' then FIndexedUnits.AddOrSetValue(U, Fid);
  end;
end;

destructor TUsesAuditor.Destroy;
begin
  FNameCache   .Free;
  FIndexedUnits.Free;
  inherited Destroy;
end;

function TUsesAuditor.TryFindFile(const APath: string; out AFileId: Int64): Boolean;
begin
  Result:= FIndexedUnits.TryGetValue(StemOf(APath), AFileId);
end;

{ distinct indexed-unit stems that define a symbol named AName (cached) }
function TUsesAuditor.UnitsDefining(const AName: string): TArray<string>;
var
  Sm: TSymbol      ;
  Us: TList<string>;
  St: string       ;
begin
  if FNameCache.TryGetValue(AName, Result) then Exit;
  Us:= TList<string>.Create;
  try
    for Sm in FStore.FindSymbolsByExactName(AName) do
    begin
      St:= StemOf(FStore.GetFilePath(Sm.FileId));
      if (St <> '') and not Us.Contains(St) then Us.Add(St);
    end;
    Result:= Us.ToArray;
  finally
    Us.Free;
  end;
  FNameCache.AddOrSetValue(AName, Result);
end;

function TUsesAuditor.Audit(AFileId: Int64; const AFallbackPath: string): TArray<TUsesAuditRow>;
var
  ThisStem: string                    ;
  ImplLine: Integer                   ;
  Lines   : TStringList               ;
  RefIntf : TDictionary<string, Boolean>;
  RefImpl : TDictionary<string, Boolean>;
  SrcPath : string                    ;
  R       : TReference                ;
  Uo      : TUnitUse                  ;
  U       : string                    ;
  UnitStem: string                    ;
  Row     : TUsesAuditRow             ;
  i       : Integer                   ;
begin
  Result:= nil;
  ThisStem:= StemOf(FStore.GetFilePath(AFileId));
  RefIntf:= TDictionary<string, Boolean>.Create;
  RefImpl:= TDictionary<string, Boolean>.Create;
  try
    { which section references each indexed unit }
    ImplLine:= MaxInt;
    SrcPath:= FStore.GetFilePath(AFileId);
    if not FileExists(SrcPath) then SrcPath:= AFallbackPath;
    if FileExists(SrcPath) then
    begin
      Lines:= TStringList.Create;
      try
        Lines.LoadFromFile(SrcPath);
        for i:= 0 to Lines.Count - 1 do
          if SameText(Trim(Lines[i]), 'implementation') then
          begin
            ImplLine:= i + 1;
            Break;
          end;
      finally
        Lines.Free;
      end;
    end;

    for R in FStore.GetReferencesFromFile(AFileId) do
      for U in UnitsDefining(R.NameText) do
      begin
        if SameText(U, ThisStem) then Continue;
        if R.StartLine < ImplLine then RefIntf.AddOrSetValue(U, True)
        else RefImpl.AddOrSetValue(U, True);
      end;

    for Uo in FStore.GetUnitUsesForFile(AFileId) do
    begin
      UnitStem:= LowerCase(Uo.UnitName);
      { audit only project units we can actually see in the index }
      if not FIndexedUnits.ContainsKey(UnitStem) then Continue;
      if SameText(UnitStem, ThisStem) then Continue;

      Row:= Default(TUsesAuditRow);
      if (not RefIntf.ContainsKey(UnitStem)) and (not RefImpl.ContainsKey(UnitStem)) then Row.Verdict:= USES_VERDICT_UNUSED
      else if (Uo.Section = uusInterface) and (not RefIntf.ContainsKey(UnitStem)) then Row.Verdict:= USES_VERDICT_MOVE
      else Continue;
      Row.UnitName := Uo.UnitName;
      Row.Section  := Uo.Section;
      // 150 CF: an entry written inside an include file has its coordinates in the .inc, not in
      // this file -- anchor at the host's include directive (as used-unit-not-resolvable does).
      Row.StartLine:= Uo.HostLine;
      Row.StartCol := Uo.HostCol;
      Row.EndLine  := if Uo.FromInclude then Uo.IncludeLine else Uo.EndLine;
      Row.EndCol   := if Uo.FromInclude then 1 else Uo.EndCol;
      Result:= Result + [Row];
    end;
  finally
    RefImpl.Free;
    RefIntf.Free;
  end;
end;

end.