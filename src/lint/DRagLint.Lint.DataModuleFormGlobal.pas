unit DRagLint.Lint.DataModuleFormGlobal;

{ The `datamodule-form-global` project rule (1.42 lane ruleset): a unit that declares a TDataModule
  descendant reads or writes another unit's global form variable. The data layer now needs that form
  to exist and to have been created -- the "FormGlobal coupling in data modules" of the old ROADMAP
  candidate list. OFF by default.

  A store rule because only the index knows both ends: which classes descend from TDataModule and
  which unit-level vars are typed by a TForm descendant, across units.

  Name-keyed on purpose (refs of kind read / write carry no symbol id), so three checks keep a
  homonym out: the name is bare (no receiver), the declaring file names no symbol of that spelling
  of its own (a field or local of the same name wins in scope), and the data module's unit lists
  the unit that declares the form variable in its uses clause. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  DATAMODULE_FORM_GLOBAL_RULE = 'datamodule-form-global';

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'datamodule-form-global' warning per (data module unit, form variable), anchored at
/// the first reference; the message counts the references.</returns>
/// <param name="ALibraryStore">The platform library index, or nil. It answers which library classes
/// are forms, so a form descending from TdxRibbonForm counts (measured: the only form of Loader2025).
/// Without it such a form is unknown and stays silent.</param>
/// <remarks>Not thread-safe. A form variable named only inside an inactive {$IFDEF} branch has no
/// ref and is not reported.</remarks>
function CollectDataModuleFormGlobal(const AStore: ISymbolStore; const ALibraryStore: ISymbolStore = nil): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  ;

const
  KIND_CLASS = 'class';
  KIND_VAR   = 'var';
  KIND_UNIT  = 'unit';
  REF_READ   = 'read';
  REF_WRITE  = 'write';
  ANCESTOR_DATA_MODULE = 'TDataModule';
  ANCESTORS_FORM: array[0..1] of string = ('TForm', 'TCustomForm');

function CollectDataModuleFormGlobal(const AStore, ALibraryStore: ISymbolStore): TArray<TLintFinding>;
var
  ModuleFiles: TDictionary<Int64, string>;  { file id -> name of the data module class it declares }
  FormTypes  : TDictionary<string, Boolean>;
  FormVars   : TDictionary<string, TArray<TSymbol>>; { lower var name -> the form-typed vars so named }
  UnitNames  : TDictionary<Int64, string>;  { unit symbol id -> lower-case unit name }
  Findings   : TList<TLintFinding>;

  procedure LoadModules;
  begin
    var Names: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for var N in AStore.FindDescendantNames(ANCESTOR_DATA_MODULE) do Names.AddOrSetValue(LowerCase(N), True);
      if Names.Count = 0 then Exit;
      for var C in AStore.FindSymbolsByKind(KIND_CLASS, False, MaxInt) do
        if Names.ContainsKey(LowerCase(C.Name)) then ModuleFiles.AddOrSetValue(C.FileId, C.Name);
    finally
      Names.Free;
    end;
  end;

  { AType is a known form name, or a project class with one in its ancestor closure: that closure names
    an ancestor the project index cannot resolve (TdxRibbonForm) and the library set can. }
  function IsFormType(const AType: string): Boolean;
  begin
    if FormTypes.ContainsKey(LowerCase(AType)) then Exit(True);
    Result:= False;
    for var C in AStore.FindSymbolsByExactName(AType) do
      for var A in AStore.GetTransitiveAncestors(C.Id) do
        if FormTypes.ContainsKey(LowerCase(A.Name)) then Exit(True);
  end;

  procedure LoadFormVars;
  begin
    for var A in ANCESTORS_FORM do
    begin
      FormTypes.AddOrSetValue(LowerCase(A), True);
      for var N in AStore.FindDescendantNames(A) do FormTypes.AddOrSetValue(LowerCase(N), True);
      if ALibraryStore <> nil then
        for var N in ALibraryStore.FindDescendantNames(A) do FormTypes.AddOrSetValue(LowerCase(N), True);
    end;
    for var U in AStore.FindSymbolsByKind(KIND_UNIT, False, MaxInt) do UnitNames.AddOrSetValue(U.Id, LowerCase(U.Name));
    for var V in AStore.FindSymbolsByKind(KIND_VAR, False, MaxInt) do
    begin
      if not IsFormType(Trim(V.Signature)) then Continue;
      if not UnitNames.ContainsKey(V.ParentId) then Continue; { a unit-level var, not a local or a field }
      var Key: string:= LowerCase(V.Name);
      var List: TArray<TSymbol>;
      if not FormVars.TryGetValue(Key, List) then List:= nil;
      FormVars.AddOrSetValue(Key, List + [V]);
    end;
  end;

  { The form var this name resolves to through AFileId's uses clause; False when none does. }
  function VarVisibleFrom(AFileId: Int64; const AVars: TArray<TSymbol>; out AVar: TSymbol): Boolean;
  begin
    Result:= False;
    AVar:= Default(TSymbol);
    var Uses_: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for var U in AStore.GetUnitUsesForFile(AFileId) do Uses_.AddOrSetValue(LowerCase(U.UnitName), True);
      for var V in AVars do
      begin
        if Uses_.ContainsKey(UnitNames[V.ParentId]) then
        begin
          AVar:= V;
          Exit(True);
        end;
      end;
    finally
      Uses_.Free;
    end;
  end;

  procedure ScanModule(AFileId: Int64; const AModule: string);
  begin
    var Path: string:= AStore.GetFilePath(AFileId);
    var Own: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    var First: TDictionary<string, TReference>:= TDictionary<string, TReference>.Create;
    var Count: TDictionary<string, Integer>:= TDictionary<string, Integer>.Create;
    try
      for var S in AStore.FindSymbolsByFile(Path) do Own.AddOrSetValue(LowerCase(S.Name), True);
      for var R in AStore.GetReferencesFromFile(AFileId) do
      begin
        if ((R.Kind <> REF_READ) and (R.Kind <> REF_WRITE)) or (R.ReceiverText <> '') then Continue;
        var Key: string:= LowerCase(R.NameText);
        if Own.ContainsKey(Key) or not FormVars.ContainsKey(Key) then Continue;
        var Hits: Integer;
        if not Count.TryGetValue(Key, Hits) then
        begin
          Hits:= 0;
          First.Add(Key, R);
        end;
        Count.AddOrSetValue(Key, Hits + 1);
      end;
      for var Pair in First do
      begin
        var V: TSymbol;
        if not VarVisibleFrom(AFileId, FormVars[Pair.Key], V) then Continue;
        var F: TLintFinding:= Default(TLintFinding);
        F.RuleId   := DATAMODULE_FORM_GLOBAL_RULE;
        F.Severity := 'warning';
        F.FilePath := Path;
        F.StartLine:= Pair.Value.StartLine;
        F.StartCol := Pair.Value.StartCol;
        F.EndLine  := Pair.Value.EndLine;
        F.EndCol   := Pair.Value.EndCol;
        F.Message  := Format('Data module %s reaches the global form variable %s (%s, %s) %d time(s) -- '
          + 'the data layer now needs that form to exist. Pass what it needs in, or raise an event the form handles.',
          [AModule, V.Name, Trim(V.Signature), TPath.GetFileName(AStore.GetFilePath(V.FileId)), Count[Pair.Key]]);
        Findings.Add(F);
      end;
    finally
      Count.Free;
      First.Free;
      Own.Free;
    end;
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  ModuleFiles:= TDictionary<Int64, string>.Create;
  FormTypes  := TDictionary<string, Boolean>.Create;
  FormVars   := TDictionary<string, TArray<TSymbol>>.Create;
  UnitNames  := TDictionary<Int64, string>.Create;
  Findings   := TList<TLintFinding>.Create;
  try
    LoadModules;
    if ModuleFiles.Count = 0 then Exit;
    LoadFormVars;
    if FormVars.Count = 0 then Exit;
    for var Pair in ModuleFiles do ScanModule(Pair.Key, Pair.Value);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    UnitNames.Free;
    FormVars.Free;
    FormTypes.Free;
    ModuleFiles.Free;
  end;
end;

end.
