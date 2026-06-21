unit DRagLint.Lint.ProjectRules;

{ Index-wide ("project") lint rules that need the whole symbol/refs graph rather
  than a single file's AST -- the cross-file complement to the per-file `lint`
  command and the external .scm rules. Run via `drag-lint lint-project --db`.

  These deliberately do NOT duplicate the existing find-deadcode / cycles /
  uses-audit commands; they add structure + cross-unit-API checks. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Index.Glob
  ;

type
  /// <summary>Index-wide lint rules (oversized classes; unused exported routines).</summary>
  /// <remarks>Stateless; reads the supplied open store. Never raises.</remarks>
  TProjectLintRules = class
  public
    /// <summary>Runs the project rules over AStore and returns all findings.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <param name="ARuleId">If non-empty, only that rule id is evaluated.</param>
    /// <returns>Findings across the whole index (file paths + lines); empty if none.</returns>
    class function Run(const AStore: ISymbolStore; const ARuleId: string = ''): TArray<TLintFinding>;
    /// <summary>Flags forbidden cross-layer 'uses' edges per a layer-config JSON file.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <param name="AConfigPath">Path to a layers JSON file (see remarks); missing/invalid -> no findings.</param>
    /// <returns>'layering-violation' findings; empty if none.</returns>
    /// <remarks>Config: { "layers":[{"name":"UI","match":["*.UI.*"]},...], "allow":[{"from":"UI","to":["Business"]},...] }.
    /// A unit's layer is the first whose match-globs accept its (qualified) unit name. Default-deny among
    /// DEFINED layers: a use A(layerX)->B(layerY), X&lt;&gt;Y, is a violation unless Y is in allow[X]. Units
    /// matching no layer are ignored (e.g. RTL/third-party). Never raises.</remarks>
    class function CheckLayering(const AStore: ISymbolStore; const AConfigPath: string): TArray<TLintFinding>;
  end;

implementation

class function TProjectLintRules.Run(const AStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  FileIds : TArray<Int64>      ;
  Fid     : Int64             ;
  Path    : string            ;
  Syms    : TArray<TSymbol>    ;
  Sym     : TSymbol           ;
  Children: TArray<TSymbol>    ;
  Ch      : TSymbol           ;
  NMethods: Integer           ;
  NFields : Integer           ;
  Parent  : TSymbol           ;

  function WantRule(const AId: string): Boolean;
  begin
    Result:= (ARuleId = '') or (ARuleId = AId);
  end;

  procedure Add(const AId, ASeverity, AMsg: string; const ASym: TSymbol);
  var
    F: TLintFinding;
  begin
    F:= Default(TLintFinding);
    F.RuleId  := AId;
    F.Severity:= ASeverity;
    F.Message := AMsg;
    F.FilePath:= Path;
    F.StartLine:= ASym.StartLine;
    F.StartCol := ASym.StartCol;
    F.EndLine:= ASym.StartLine;
    F.EndCol := ASym.StartCol + Length(ASym.Name);
    Findings.Add(F);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    FileIds:= AStore.GetAllFileIds;
    for Fid in FileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      Syms:= AStore.FindSymbolsByFile(Path);
      for Sym in Syms do
      begin
        { god-class: a class with both many methods and many fields. }
        if WantRule('god-class') and (Sym.Kind = skClass) then
        begin
          Children:= AStore.FindAllChildSymbols(Sym.Id);
          NMethods:= 0;
          NFields := 0;
          for Ch in Children do
            case Ch.Kind of
              skMethod, skFunction, skProcedure, skConstructor, skDestructor: Inc(NMethods);
              skField: Inc(NFields);
            end;
          if (NMethods > 20) and (NFields > 15) then
            Add('god-class', 'info', Format('God class: %s has %d methods and %d fields -- consider splitting responsibilities', [Sym.Name, NMethods, NFields]), Sym);
        end;

        { unused-public-symbol: an exported (interface-section) free routine that
          nothing in the index references or calls -- likely dead public API.
          Restricted to unit-level routines (not class methods) so DFM-wired
          event handlers and virtual/override methods are not false positives. }
        if WantRule('unused-public-symbol') and (Sym.Section = 'interface') and (Sym.Kind in [skFunction, skProcedure]) and (Sym.ParentId > 0) and
          (Pos('override', LowerCase(Sym.Modifiers)) = 0) and not SameText(Sym.Name, 'Register') then
        begin
          Parent:= AStore.GetSymbolById(Sym.ParentId);
          if (Parent.Id = Sym.ParentId) and (Parent.Kind = skUnit) then
            if (Length(AStore.FindReferencesTo(Sym.Id)) = 0) and (Length(AStore.FindCallersByName(Sym.Name)) = 0) then
              Add('unused-public-symbol', 'info', Format('Exported routine %s has no references in the index -- possible dead public API', [Sym.Name]), Sym);
        end;
      end; // for Sym
    end; // for Fid
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

class function TProjectLintRules.CheckLayering(const AStore: ISymbolStore; const AConfigPath: string): TArray<TLintFinding>;
var
  Findings  : TList<TLintFinding>             ;
  Root      : TJSONValue                      ;
  Obj       : TJSONObject                     ;
  LayerNames: TStringList                     ;
  LayerPats : TDictionary<string, TStringList>;
  Allow     : TDictionary<string, TStringList>;
  FileIds   : TArray<Int64>                   ;
  Fid       : Int64                          ;
  Path      : string                         ;
  Syms      : TArray<TSymbol>                 ;
  Sym       : TSymbol                        ;
  UsingUnit : string                         ;
  UsingLayer: string                         ;
  UsesList  : TArray<TUnitUse>                ;
  U         : TUnitUse                       ;
  TgtLayer  : string                         ;
  AllowSet  : TStringList                     ;
  F         : TLintFinding                    ;

  function LayerOf(const AUnit: string): string;
  var
    I   : Integer    ;
    Pats: TStringList;
  begin
    Result:= '';
    for I:= 0 to LayerNames.Count - 1 do
      if LayerPats.TryGetValue(LayerNames[I], Pats) and TGlob.MatchesAny(AUnit, Pats.ToStringArray) then Exit(LayerNames[I]);
  end;

begin
  Result:= nil;
  if (AStore = nil) or (AConfigPath = '') or (not TFile.Exists(AConfigPath)) then Exit;
  Root:= nil;
  try
    Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(AConfigPath));
  except
    Root:= nil;
  end;
  if not (Root is TJSONObject) then begin Root.Free; Exit; end;
  Obj:= TJSONObject(Root);

  Findings  := TList<TLintFinding>.Create;
  LayerNames:= TStringList.Create;
  LayerPats := TDictionary<string, TStringList>.Create;
  Allow     := TDictionary<string, TStringList>.Create;
  try
    var LayersArr:= Obj.GetValue('layers');
    if LayersArr is TJSONArray then
      for var I:= 0 to TJSONArray(LayersArr).Count - 1 do
      begin
        var Le:= TJSONArray(LayersArr).Items[I];
        if not (Le is TJSONObject) then Continue;
        var Nm:= TJSONObject(Le).GetValue('name');
        if not (Nm is TJSONString) then Continue;
        var LName:= TJSONString(Nm).Value;
        var Pats:= TStringList.Create;
        var Mt:= TJSONObject(Le).GetValue('match');
        if Mt is TJSONArray then
          for var J:= 0 to TJSONArray(Mt).Count - 1 do
            if TJSONArray(Mt).Items[J] is TJSONString then Pats.Add(TJSONString(TJSONArray(Mt).Items[J]).Value);
        LayerNames.Add(LName);
        LayerPats.AddOrSetValue(LName, Pats);
      end;

    var AllowArr:= Obj.GetValue('allow');
    if AllowArr is TJSONArray then
      for var I:= 0 to TJSONArray(AllowArr).Count - 1 do
      begin
        var Ae:= TJSONArray(AllowArr).Items[I];
        if not (Ae is TJSONObject) then Continue;
        var Fr:= TJSONObject(Ae).GetValue('from');
        if not (Fr is TJSONString) then Continue;
        var FrLow:= LowerCase(TJSONString(Fr).Value);
        var Lst: TStringList;
        if not Allow.TryGetValue(FrLow, Lst) then begin Lst:= TStringList.Create; Allow.Add(FrLow, Lst); end;
        var ToV:= TJSONObject(Ae).GetValue('to');
        if ToV is TJSONArray then
          for var J:= 0 to TJSONArray(ToV).Count - 1 do
            if TJSONArray(ToV).Items[J] is TJSONString then Lst.Add(LowerCase(TJSONString(TJSONArray(ToV).Items[J]).Value));
      end;

    FileIds:= AStore.GetAllFileIds;
    for Fid in FileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      UsingUnit:= '';
      Syms:= AStore.FindSymbolsByFile(Path);
      for Sym in Syms do
        if Sym.Kind = skUnit then
        begin
          UsingUnit:= Sym.QualifiedName;
          if UsingUnit = '' then UsingUnit:= Sym.Name;
          Break;
        end;
      if UsingUnit = '' then Continue;
      UsingLayer:= LayerOf(UsingUnit);
      if UsingLayer = '' then Continue;
      UsesList:= AStore.GetUnitUsesForFile(Fid);
      for U in UsesList do
      begin
        TgtLayer:= LayerOf(U.UnitName);
        if (TgtLayer = '') or SameText(TgtLayer, UsingLayer) then Continue;
        var Ok:= False;
        if Allow.TryGetValue(LowerCase(UsingLayer), AllowSet) then Ok:= AllowSet.IndexOf(LowerCase(TgtLayer)) >= 0;
        if not Ok then
        begin
          F:= Default(TLintFinding);
          F.RuleId  := 'layering-violation';
          F.Severity:= 'warning';
          F.Message := Format('Layering violation: %s (layer %s) must not use %s (layer %s)', [UsingUnit, UsingLayer, U.UnitName, TgtLayer]);
          F.FilePath:= Path;
          F.StartLine:= U.StartLine;
          F.StartCol := U.StartCol;
          F.EndLine:= U.StartLine;
          F.EndCol := U.StartCol + Length(U.UnitName);
          Findings.Add(F);
          if Findings.Count >= 500 then Break;
        end;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    for var Pats in LayerPats.Values do Pats.Free;
    for var Lst in Allow.Values do Lst.Free;
    LayerPats.Free;
    Allow.Free;
    LayerNames.Free;
    Findings.Free;
    Root.Free;
  end;
end; // function

end.
