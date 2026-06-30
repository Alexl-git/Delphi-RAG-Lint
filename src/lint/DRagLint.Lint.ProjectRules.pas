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

{ Side-effect / operator / helper units that are legitimately used without any
  named symbol reference. Stored lowercase for fast SameText comparison. }
const
  KSideEffectUnits: array[0..9] of string = (
    'vcl.themes', 'system.uitypes', 'winapi.messages',
    'winapi.windows', 'vcl.forms', 'fmx.forms',
    'system.typinfo', 'system.rtti',
    'designintf', 'designeditors'
  );

function IsSideEffectUnit(const AUnitName: string): Boolean;
var
  Low: string;
  S  : string;
begin
  Low:= LowerCase(AUnitName);
  for S in KSideEffectUnits do
    if Low = S then Exit(True);
  Result:= False;
end;

class function TProjectLintRules.Run(const AStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>;
var
  Findings      : TList<TLintFinding>         ;
  FileIds       : TArray<Int64>               ;
  Fid           : Int64                       ;
  Path          : string                      ;
  Syms          : TArray<TSymbol>             ;
  Sym           : TSymbol                     ;
  Children      : TArray<TSymbol>             ;
  Ch            : TSymbol                     ;
  NMethods      : Integer                     ;
  NFields       : Integer                     ;
  Parent        : TSymbol                     ;
  RefdUnitStems : TDictionary<string, Boolean>;
  Refs          : TArray<TReference>          ;
  Ref           : TReference                  ;
  RefSym        : TSymbol                     ;
  UsesList      : TArray<TUnitUse>            ;
  U             : TUnitUse                    ;
  NameSyms      : TArray<TSymbol>             ;
  UnitStem      : string                      ;
  UF            : TLintFinding                ;
  PrivModifiers : string                      ;
  IsPrivate     : Boolean                     ;

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

      { unused-unit-in-uses: build the set of file IDs referenced from this file.
        Skip files with no uses entries to avoid the O(refs) cost for every file. }
      if WantRule('unused-unit-in-uses') then
      begin
        UsesList:= AStore.GetUnitUsesForFile(Fid);
        if Length(UsesList) > 0 then
        begin
          { Build the set of unit stems referenced from this file.
            Mirror the uses-audit approach: map each ref's NameText via
            FindSymbolsByExactName to the stem of the file defining it.
            This correctly handles refs where SymbolId is 0 (unresolved). }
          RefdUnitStems:= TDictionary<string, Boolean>.Create;
          try
            Refs:= AStore.GetReferencesFromFile(Fid);
            for Ref in Refs do
            begin
              if Ref.NameText = '' then Continue;
              NameSyms:= AStore.FindSymbolsByExactName(Ref.NameText);
              for RefSym in NameSyms do
              begin
                if RefSym.FileId <= 0 then Continue;
                UnitStem:= LowerCase(ChangeFileExt(ExtractFileName(AStore.GetFilePath(RefSym.FileId)), ''));
                if UnitStem <> '' then RefdUnitStems.AddOrSetValue(UnitStem, True);
              end;
            end;
            { Check each used unit: flag if its stem is absent from the ref set. }
            for U in UsesList do
            begin
              { Skip self-reference. }
              if SameText(LowerCase(U.UnitName), LowerCase(ChangeFileExt(ExtractFileName(Path), ''))) then Continue;
              { Skip implicit/side-effect units. }
              if IsSideEffectUnit(U.UnitName) then Continue;
              { Skip known built-ins never in the index. }
              if SameText(U.UnitName, 'System') or SameText(U.UnitName, 'SysInit') then Continue;
              { Derive the stem -- last dotted segment, lowercase (e.g. 'System.SysUtils' -> 'sysutils'
                but also try full lowercase name so qualified names match). }
              UnitStem:= LowerCase(U.UnitName);
              { Conservative: only flag when the unit IS in the index (has a skUnit symbol). }
              NameSyms:= AStore.FindSymbolsByExactName(U.UnitName);
              var FoundInIndex: Boolean:= False;
              for RefSym in NameSyms do
                if RefSym.Kind = skUnit then begin FoundInIndex:= True; Break; end;
              if not FoundInIndex then Continue;
              { Also build the plain stem (last segment after the dot) for matching. }
              var DotPos: Integer:= LastDelimiter('.', UnitStem);
              var PlainStem: string:= UnitStem;
              if DotPos > 0 then PlainStem:= Copy(UnitStem, DotPos + 1, MaxInt);
              { Flag if neither the full name nor the plain stem appear in the ref set. }
              if (not RefdUnitStems.ContainsKey(UnitStem)) and (not RefdUnitStems.ContainsKey(PlainStem)) then
              begin
                UF:= Default(TLintFinding);
                UF.RuleId  := 'unused-unit-in-uses';
                UF.Severity:= 'warning';
                UF.Message := Format('Unit ''%s'' is listed in the uses clause but no symbols from it are referenced -- possible dead import', [U.UnitName]);
                UF.FilePath := Path;
                UF.StartLine:= U.StartLine;
                UF.StartCol := U.StartCol;
                UF.EndLine  := U.StartLine;
                UF.EndCol   := U.StartCol + Length(U.UnitName);
                Findings.Add(UF);
              end;
            end; // for U
          finally
            RefdUnitStems.Free;
          end;
        end; // if Length(UsesList) > 0
      end; // if WantRule

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

        { unused-private-member: a private or strict private member (method,
          field, const, nested type) that has zero references in the index.
          Guards: skip virtual/override (may be called via dispatch table);
          skip if any reference exists (conservative). Published members
          are never private so DFM-streamed components are not affected. }
        if WantRule('unused-private-member') then
        begin
          PrivModifiers:= LowerCase(Sym.Modifiers);
          IsPrivate:= (Pos('private', PrivModifiers) > 0);
          if IsPrivate and
            (Sym.Kind in [skMethod, skFunction, skProcedure, skConstructor, skDestructor,
                          skField, skConstDecl, skTypeAlias, skClass, skInterface, skRecord, skEnum]) and
            (Pos('override', PrivModifiers) = 0) and
            (not Sym.IsVirtual) then
          begin
            if (Length(AStore.FindReferencesTo(Sym.Id)) = 0) and
               (Length(AStore.FindCallersByName(Sym.Name)) = 0) then
              Add('unused-private-member', 'warning',
                Format('Private member ''%s'' has no references in the index -- possible dead code', [Sym.Name]), Sym);
          end;
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
  { Per the <remarks>Never raises</remarks> contract, a bad/unreadable config must
    NOT propagate -- log a single diagnostic line and return an empty result. }
  try
    Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(AConfigPath));
  except // drag-lint:ignore try-except-swallowed (log-then-return-empty: honors the Never-raises contract)
    on E: Exception do
    begin
      Writeln(ErrOutput, Format('[layering] skipping bad config %s: %s', [AConfigPath, E.Message]));
      Root.Free;
      Exit;
    end;
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
