unit DRagLint.V152.PROJ2.Support;

{ Wave v152 lane PROJ2 -- helpers of DRagLint.V152.PROJ2 (private to the lane).
  Scaffold created EMPTY by lane FRAME; lane PROJ2 owns it.

  Two project-wide answers, both read from the project index only:
  * unit-used-by-no-unit (ruling B9e): a unit the program file lists that no
    other unit uses and the program code never names;
  * the O05 half of unit-not-in-dpr: a closure unit OUTSIDE the walked file list
    (a shared folder outside the project roots) that the project files do not list. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id of ruling B9e.</summary>
  PROJ2_RULE_UNIT_USED_BY_NO_UNIT = 'unit-used-by-no-unit';
  /// <summary>Existing rule id this lane extends in place (O05).</summary>
  PROJ2_RULE_UNIT_NOT_IN_DPR = 'unit-not-in-dpr';

/// <summary>Reports every unit a program file (.dpr) of the index lists that nothing else reaches.</summary>
/// <param name="AStore">Project index; nil gives no finding.</param>
/// <returns>One warning per unreachable unit, anchored on its `unit` line; nil when none.</returns>
/// <remarks>
/// A candidate is a .pas the .dpr lists in its uses clause, that no other indexed file
/// uses, and none of whose symbols the program code references. Exempt: a self-registering unit
/// (an initialization section, or a container registration in the unit itself) -- but NOT a
/// form: a unit with an indexed sibling .dfm / .fmx form is exempt only when something opens it,
/// i.e. the program code names it (covered above) or another .pas names one of its classes in a
/// string literal (FindClass / GetClass('TName')). A .dpk lists package members by design and is
/// never a source of candidates. Read-only; stateless.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckProject (DRagLint.V152.PROJ2.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetReferencesFromFile, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges, DRagLint.V152.PROJ2.Support.ClassNamedElsewhere, DRagLint.V152.PROJ2.Support.IsExt, DRagLint.V152.PROJ2.Support.LoadPaths, DRagLint.V152.PROJ2.Support.MakeFinding, DRagLint.V152.PROJ2.Support.RegistersInContainer, DRagLint.V152.PROJ2.Support.SiblingFormPath, ExtractFileName</para>
/// <para>Returns: nil; Findings.ToArray</para>
/// <para>Complexity: 21 (cyclomatic, outer body), 92 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetReferencesFromFile"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges"/>
/// <seealso cref="DRagLint.V152.PROJ2.Support.ClassNamedElsewhere"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindUnitsUsedByNoUnit(const AStore: ISymbolStore): TArray<TLintFinding>;

/// <summary>unit-not-in-dpr for closure units OUTSIDE the walked file list (O05).</summary>
/// <param name="AStore">Project index; nil gives no finding.</param>
/// <param name="AProjectPath">The --project .dproj of the run; '' gives no finding (the
/// unscoped run already hands the rule every indexed file).</param>
/// <param name="AWalked">The files lint-all walked; their findings come from the host check.</param>
/// <returns>The host check's "in NEITHER project file" findings for the indexed .pas files that
/// another indexed file uses and AWalked does not contain, anchored on the project's .dpr (the
/// --project scope filter drops findings on files outside the project); nil when none, or when the
/// .dproj has no indexed sibling .dpr (a package: its members are listed by the .dpk).</returns>
/// <remarks>
/// Delegates the decision to TProjectChecks.CheckUnitsInDpr (same message, same
/// exemptions) and keeps only findings anchored on those outside files, so nothing is reported
/// twice. Reads the project files from disk.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckProject (DRagLint.V152.PROJ2.pas)</para>
/// <para>Calls: ChangeFileExt, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges, DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr, DRagLint.V152.PROJ2.Support.IsExt, DRagLint.V152.PROJ2.Support.LoadPaths, LowerCase</para>
/// <para>Returns: nil; Kept</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 53 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges"/>
/// <seealso cref="DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr"/>
/// <seealso cref="DRagLint.V152.PROJ2.Support.IsExt"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindUnlistedClosureOutsideRoots(const AStore: ISymbolStore; const AProjectPath: string;
  const AWalked: TArray<string>): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Lint.ProjectChecks
  ;

type
  TIdPaths = TDictionary<Int64, string>;

function IsExt(const APath, AExt: string): Boolean;
begin
  Result:= SameText(ExtractFileExt(APath), AExt);
end;

function LoadPaths(const AStore: ISymbolStore): TIdPaths;
begin
  Result:= TIdPaths.Create;
  for var Id: Int64 in AStore.GetAllFileIds do
    Result.AddOrSetValue(Id, AStore.GetFilePath(Id));
end;

{ The indexed sibling form file (.dfm, else .fmx) of a unit, or ''. }
function SiblingFormPath(const AStore: ISymbolStore; const APasPath: string): string;
begin
  Result:= '';
  for var Ext: string in ['.dfm', '.fmx'] do
  begin
    var Candidate: string:= ChangeFileExt(APasPath, Ext);
    if AStore.FindFileIdByPath(Candidate) = 0 then Continue;
    for var Sym: TSymbol in AStore.FindSymbolsByFile(Candidate) do
      if Sym.Kind = skForm then Exit(Candidate);
  end;
end;

{ Another .pas names AClassName in a string literal (FindClass / GetClass by name). }
function ClassNamedElsewhere(const AStore: ISymbolStore; const AClassName, AOwnPath: string): Boolean;
const
  MAX_HITS = 50;
begin
  Result:= False;
  for var Hit: TStringLitMatch in AStore.SearchText(AClassName, 'phrase', 'pas', MAX_HITS) do
    if SameText(Hit.Text, AClassName) and not SameText(Hit.FilePath, AOwnPath) then Exit(True);
end;

{ The unit registers itself in a DI container: a di_bindings row in its own file. }
function RegistersInContainer(const AStore: ISymbolStore; const AFileId: Int64;
  const AClasses: TList<string>): Boolean;
begin
  Result:= False;
  for var ClassName: string in AClasses do
    for var Row: TDiBindingRow in AStore.FindDiBindingsForImpl(ClassName) do
      if Row.FileId = AFileId then Exit(True);
end;

function MakeFinding(const APath: string; ALine: Integer; const AUnit, AProgram: string; AIsForm: Boolean): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := PROJ2_RULE_UNIT_USED_BY_NO_UNIT;
  Result.Severity := 'warning';
  Result.FilePath := APath;
  Result.StartLine:= ALine;
  Result.StartCol := 1;
  Result.EndLine  := ALine;
  Result.EndCol   := 1;
  Result.Message:= Format(if AIsForm then
      'Form unit "%s" is listed only by %s: no other unit uses it, the program code never ' +
      'creates it and no unit opens it by class name. It is compiled in but unreachable -- ' +
      'remove it from the project, or open it from where it belongs.'
    else
      'Unit "%s" is listed only by %s: no other unit uses it, the program code never names it, ' +
      'and it does not register itself (no initialization section, no container registration). ' +
      'It is compiled in but unreachable -- remove it from the project, or wire it in.', [AUnit, AProgram]);
end;

function FindUnitsUsedByNoUnit(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Paths   : TIdPaths;
  Users   : TDictionary<Int64, Boolean>;  // target file -> used by a non-program file
  Programs: TObjectDictionary<Int64, TList<Int64>>;  // program file -> units it lists
  Classes : TList<string>;
  Findings: TList<TLintFinding>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Paths:= LoadPaths(AStore);
  Users:= TDictionary<Int64, Boolean>.Create;
  Programs:= TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  Classes:= TList<string>.Create;
  Findings:= TList<TLintFinding>.Create;
  try
    for var Edge: TFileScopeEdge in AStore.GetUnitScopeEdges do
    begin
      if Edge.FileId = Edge.TargetFileId then Continue;
      var FromPath: string;
      if not Paths.TryGetValue(Edge.FileId, FromPath) then Continue;
      if IsExt(FromPath, '.dpr') then
      begin
        var Listed: TList<Int64>;
        if not Programs.TryGetValue(Edge.FileId, Listed) then
        begin
          Listed:= TList<Int64>.Create;
          Programs.Add(Edge.FileId, Listed);
        end;
        Listed.Add(Edge.TargetFileId);
      end
      else
        Users.AddOrSetValue(Edge.TargetFileId, True);
    end;

    for var Prog: TPair<Int64, TList<Int64>> in Programs do
    begin
      { Every symbol the program code references, by file: CreateForm(TMainForm, ..),
        a qualified UnitX.Run, an `exports` entry. Uses-clause names carry no ref. }
      var Named:= TDictionary<Int64, Boolean>.Create;
      try
        for var Ref: TReference in AStore.GetReferencesFromFile(Prog.Key) do
          if Ref.SymbolId <> 0 then
          begin
            var Sym: TSymbol:= AStore.GetSymbolById(Ref.SymbolId);
            if (Sym.Id <> 0) and (Sym.Kind <> skUnit) then Named.AddOrSetValue(Sym.FileId, True);
          end;
        var ProgName: string:= ExtractFileName(Paths[Prog.Key]);
        for var UnitId: Int64 in Prog.Value do
        begin
          var UnitPath: string;
          if not Paths.TryGetValue(UnitId, UnitPath) or not IsExt(UnitPath, '.pas') then Continue;
          if Users.ContainsKey(UnitId) or Named.ContainsKey(UnitId) then Continue;
          var FormPath: string:= SiblingFormPath(AStore, UnitPath);
          var UnitLine: Integer:= 1;
          var HasInit: Boolean:= False;
          Classes.Clear;
          for var Sym: TSymbol in AStore.FindSymbolsByFile(UnitPath) do
            case Sym.Kind of
              skUnit          : UnitLine:= Sym.StartLine;
              skInitialization: HasInit:= True;
              skClass         : Classes.Add(Sym.Name);
            end;
          if FormPath = '' then
          begin
            if HasInit or RegistersInContainer(AStore, UnitId, Classes) then Continue;
          end
          else
          begin
            var Opened: Boolean:= False;
            for var ClassName: string in Classes do
              if ClassNamedElsewhere(AStore, ClassName, UnitPath) then
              begin
                Opened:= True;
                Break;
              end;
            if Opened then Continue;
          end;
          Findings.Add(MakeFinding(UnitPath, UnitLine, TPath.GetFileNameWithoutExtension(UnitPath), ProgName, FormPath <> ''));
        end;
      finally
        Named.Free;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Classes.Free;
    Programs.Free;
    Users.Free;
    Paths.Free;
  end;
end;

function FindUnlistedClosureOutsideRoots(const AStore: ISymbolStore; const AProjectPath: string;
  const AWalked: TArray<string>): TArray<TLintFinding>;
var
  Paths  : TIdPaths;
  Walked : TDictionary<string, Boolean>;
  Outside: TDictionary<string, string>;  // lower-cased full path -> path as indexed
begin
  Result:= nil;
  if (AStore = nil) or (AProjectPath = '') or not TFile.Exists(AProjectPath) then Exit;
  Paths:= LoadPaths(AStore);
  Walked:= TDictionary<string, Boolean>.Create;
  Outside:= TDictionary<string, string>.Create;
  try
    for var P: string in AWalked do
      Walked.AddOrSetValue(LowerCase(TPath.GetFullPath(P)), True);
    for var Edge: TFileScopeEdge in AStore.GetUnitScopeEdges do
    begin
      if Edge.FileId = Edge.TargetFileId then Continue;
      var Target: string;
      if not Paths.TryGetValue(Edge.TargetFileId, Target) or not IsExt(Target, '.pas') then Continue;
      var Key: string:= LowerCase(TPath.GetFullPath(Target));
      if not Walked.ContainsKey(Key) then Outside.AddOrSetValue(Key, Target);
    end;
    if Outside.Count = 0 then Exit;
    { Re-anchor on the program file: lint-all --project drops every finding whose file is
      not one of the project's own source files, and the unit lives outside them by
      definition (that filter, not the walk, is what hid these). The fix goes in the
      program file anyway; the message keeps the unit's real location. }
    var ProgPath: string:= ChangeFileExt(AProjectPath, '.dpr');
    var ProgLine: Integer:= 1;
    var ProgId: Int64:= AStore.FindFileIdByPath(ProgPath);
    if ProgId = 0 then Exit;
    for var Sym: TSymbol in AStore.FindSymbolsByFile(ProgPath) do
      if Sym.Kind = skProgram then ProgLine:= Sym.StartLine;
    var Kept: TArray<TLintFinding>:= nil;
    for var F: TLintFinding in TProjectChecks.CheckUnitsInDpr(AProjectPath, Outside.Values.ToArray, False) do
      if Outside.ContainsKey(LowerCase(TPath.GetFullPath(F.FilePath))) then
      begin
        var R: TLintFinding:= F;
        R.Message  := F.Message + ' Found at ' + F.FilePath + ', outside the project roots.';
        R.FilePath := Paths[ProgId];
        R.StartLine:= ProgLine;
        R.StartCol := 1;
        R.EndLine  := ProgLine;
        R.EndCol   := 1;
        Kept:= Kept + [R];
      end;
    Result:= Kept;
  finally
    Outside.Free;
    Walked.Free;
    Paths.Free;
  end;
end;

end.
