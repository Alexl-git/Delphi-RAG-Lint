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
  , System.Diagnostics { TStopwatch -- DRAGLINT_PROFILE per-rule attribution in Run }
  , System.Generics.Collections
  , System.Generics.Defaults
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Index.Glob
  , DRagLint.Diagnostics.ParseCache
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
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)
    /// Calls: ChangeFileExt, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindReferencesTo, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath (+26 more)
    /// Returns: nil; Findings.ToArray
    /// Complexity: 48 (cyclomatic, outer body), 239 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindReferencesTo"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Run(const AStore: ISymbolStore; const ARuleId: string = ''): TArray<TLintFinding>;
    /// <summary>Flags forbidden cross-layer 'uses' edges per a layer-config JSON file.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <param name="AConfigPath">Path to a layers JSON file (see remarks); missing/invalid -> no findings.</param>
    /// <returns>'layering-violation' findings; empty if none.</returns>
    /// <remarks>
    /// Config: { "layers":[{"name":"UI","match":["*.UI.*"]},...], "allow":[{"from":"UI","to":["Business"]},...] }.
    /// A unit's layer is the first whose match-globs accept its (qualified) unit name. Default-deny among
    /// DEFINED layers: a use A(layerX)->B(layerY), X&lt;&gt;Y, is a violation unless Y is in allow[X]. Units
    /// matching no layer are ignored (e.g. RTL/third-party). Never raises.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)
    /// Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Lint.ProjectRules.TProjectLintRules.CheckLayering.LayerOf, Format, LowerCase, SameText, TJSONArray, TJSONObject, TJSONString, Writeln
    /// Returns: nil; Findings.ToArray
    /// Complexity: 29 (cyclomatic, outer body), 139 lines (full implementation)
    /// Touches: file system
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
    /// <seealso cref="DRagLint.Lint.ProjectRules.TProjectLintRules.CheckLayering.LayerOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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

{ Walk the tree-sitter AST for AFile and collect every identifier that appears
  as a getter ('read') or setter ('write') accessor in a declProp node, plus
  the property's own backing-field name when it appears literally in those
  clauses.  Returns a lowercased-name set (TDictionary<string,Boolean>) that
  the caller must free.  Returns nil when the file cannot be parsed.

  Grammar reference (tree-sitter-delphi13/grammar.js, declProp rule):
    seq($.kRead,  field('getter', $._ref))
    seq($.kWrite, field('setter', $._ref))
  _ref is an identifier in the simple case; for qualified/array refs we
  extract only the base (leftmost) identifier so that 'FField.Sub' -> 'ffield'.
  This is an exact AST-based guard: nearly zero false negatives (a private
  method whose name matches a property accessor is correctly excluded). }
function BuildPropertyAccessorSet(const AFile: string): TDictionary<string, Boolean>;
var
  PF   : TParsedFile;
  Src  : TBytes     ;
  Dict : TDictionary<string, Boolean>;

  { Extract raw bytes from a TTSNode. }
  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Return the bare base identifier from a _ref node (e.g. 'FCount',
    'FList[0]' -> 'flist', 'Provider.Data' -> 'provider').
    We take the full text and strip everything from the first '.' or '['. }
  function BaseIdentOf(const ARefNode: TTSNode): string;
  var
    Raw  : string ;
    I    : Integer;
    Stop : Integer;
  begin
    Result:= '';
    Raw:= Trim(NodeStr(ARefNode));
    if Raw = '' then Exit;
    Stop:= Length(Raw) + 1;
    for I:= 1 to Length(Raw) do
      if (Raw[I] = '.') or (Raw[I] = '[') then
      begin
        Stop:= I;
        Break;
      end;
    Result:= LowerCase(Trim(Copy(Raw, 1, Stop - 1)));
  end;

  { Recursively walk AST, collecting getter/setter accessor names from
    every declProp node encountered. }
  procedure Walk(const N: TTSNode);
  var
    I      : Integer;
    GNode  : TTSNode;
    SNode  : TTSNode;
    GName  : string ;
    SName  : string ;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declProp' then
    begin
      { getter = read accessor; setter = write accessor. }
      GNode:= N.ChildByField('getter');
      if not GNode.IsNull then
      begin
        GName:= BaseIdentOf(GNode);
        if GName <> '' then Dict.AddOrSetValue(GName, True);
      end;
      SNode:= N.ChildByField('setter');
      if not SNode.IsNull then
      begin
        SName:= BaseIdentOf(SNode);
        if SName <> '' then Dict.AddOrSetValue(SName, True);
      end;
      { No need to recurse inside declProp: nested declProp is not valid
        Delphi, so we exit early to avoid false matches from the type ref. }
      Exit;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;

begin
  Result:= nil;
  if AFile = '' then Exit;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src := PF.Src;
  Dict:= TDictionary<string, Boolean>.Create;
  Walk(PF.Tree.RootNode);
  Result:= Dict;
end;

{ v0.76 circular-uses (#11): report each strongly-connected component of the unit
  uses-graph (a set of units that transitively use each other). A pure interface-
  section cycle does not compile, so a real cycle in a building project runs through
  an implementation-section 'uses' -- still a coupling smell worth surfacing.
  Distinct from interface-reference-cycle (which is about interface-section symbol
  references). Uses Tarjan's SCC over file ids; one finding per component. }
function CollectCircularUses(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Findings  : TList<TLintFinding>          ;
  UnitName  : TDictionary<Int64, string>   ; { fid -> display unit name }
  FileOfUnit: TDictionary<string, Int64>   ; { lower full unit name -> fid }
  FileOfStem: TDictionary<string, Int64>   ; { lower last-segment stem -> fid }
  UnitLine  : TDictionary<Int64, Integer>  ; { fid -> unit decl line }
  Adj       : TDictionary<Int64, TList<Int64>>;
  { Tarjan state }
  Index     : TDictionary<Int64, Integer>  ;
  LowLink   : TDictionary<Int64, Integer>  ;
  OnStack   : TDictionary<Int64, Boolean>  ;
  Stack     : TList<Int64>                 ;
  Counter   : Integer                      ;

  procedure StrongConnect(V: Int64);
  var
    W  : Int64;
    Lst: TList<Int64>;
    Idx: Integer;
  begin
    Index.AddOrSetValue(V, Counter);
    LowLink.AddOrSetValue(V, Counter);
    Inc(Counter);
    Stack.Add(V);
    OnStack.AddOrSetValue(V, True);
    if Adj.TryGetValue(V, Lst) then
      for W in Lst do
      begin
        if not Index.ContainsKey(W) then
        begin
          StrongConnect(W);
          if LowLink[W] < LowLink[V] then LowLink[V]:= LowLink[W];
        end
        else if OnStack.ContainsKey(W) and OnStack[W] then
        begin
          if Index[W] < LowLink[V] then LowLink[V]:= Index[W];
        end;
      end;
    { Root of an SCC -> pop it off the stack. }
    if LowLink[V] = Index[V] then
    begin
      var Comp: TList<Int64>:= TList<Int64>.Create;
      try
        repeat
          W:= Stack[Stack.Count - 1];
          Stack.Delete(Stack.Count - 1);
          OnStack[W]:= False;
          Comp.Add(W);
        until W = V;
        if Comp.Count >= 2 then
        begin
          { Deterministic output regardless of traversal order: sort member names
            alphabetically; anchor the finding at the alphabetically-first unit. }
          var Sorted: TStringList:= TStringList.Create;
          try
            Sorted.CaseSensitive:= False;
            Sorted.Duplicates:= dupIgnore;
            Sorted.Sorted:= True;
            for Idx:= 0 to Comp.Count - 1 do
            begin
              var Nm0: string;
              if UnitName.TryGetValue(Comp[Idx], Nm0) then Sorted.Add(Nm0);
            end;
            var Names: string:= '';
            for Idx:= 0 to Sorted.Count - 1 do
            begin
              if Names <> '' then Names:= Names + ' -> ';
              Names:= Names + Sorted[Idx];
            end;
          { Anchor at the alphabetically-first unit's fid. }
          var Anchor: Int64:= Comp[Comp.Count - 1];
          if Sorted.Count > 0 then
          begin
            var FirstName: string:= Sorted[0];
            var Af: Int64;
            if FileOfUnit.TryGetValue(LowerCase(FirstName), Af) then Anchor:= Af;
          end;
          var F: TLintFinding:= Default(TLintFinding);
          F.RuleId  := 'circular-uses';
          F.Severity:= 'warning';
          F.Message := Format('Circular unit dependency among %d units: %s -- break the cycle (extract shared code or move a use to the implementation section)', [Comp.Count, Names]);
          F.FilePath:= AStore.GetFilePath(Anchor);
          var Ln: Integer:= 1;
          UnitLine.TryGetValue(Anchor, Ln);
          F.StartLine:= Ln; F.StartCol:= 1; F.EndLine:= Ln; F.EndCol:= 1;
          Findings.Add(F);
          finally
            Sorted.Free;
          end;
        end;
      finally
        Comp.Free;
      end;
    end;
  end;

var
  Fid : Int64          ;
  Sym : TSymbol        ;
  U   : TUnitUse       ;
  Path: string         ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings  := TList<TLintFinding>.Create;
  UnitName  := TDictionary<Int64, string>.Create;
  FileOfUnit:= TDictionary<string, Int64>.Create;
  FileOfStem:= TDictionary<string, Int64>.Create;
  UnitLine  := TDictionary<Int64, Integer>.Create;
  Adj       := TDictionary<Int64, TList<Int64>>.Create;
  Index     := TDictionary<Int64, Integer>.Create;
  LowLink   := TDictionary<Int64, Integer>.Create;
  OnStack   := TDictionary<Int64, Boolean>.Create;
  Stack     := TList<Int64>.Create;
  try
    { 1) map every indexed unit's fid <-> name (full + stem). }
    for Fid in AStore.GetAllFileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      for Sym in AStore.FindSymbolsByFile(Path) do
        if Sym.Kind = skUnit then
        begin
          var Nm: string:= Sym.QualifiedName;
          if Nm = '' then Nm:= Sym.Name;
          if Nm = '' then Break;
          UnitName.AddOrSetValue(Fid, Nm);
          UnitLine.AddOrSetValue(Fid, Sym.StartLine);
          FileOfUnit.AddOrSetValue(LowerCase(Nm), Fid);
          var Stem: string:= LowerCase(Nm);
          var Dp: Integer:= LastDelimiter('.', Stem);
          if Dp > 0 then Stem:= Copy(Stem, Dp + 1, MaxInt);
          FileOfStem.AddOrSetValue(Stem, Fid);
          Break;
        end;
    end;
    { 2) build the directed uses-graph among indexed units only. }
    for Fid in UnitName.Keys do
    begin
      var Lst: TList<Int64>:= TList<Int64>.Create;
      Adj.Add(Fid, Lst);
      for U in AStore.GetUnitUsesForFile(Fid) do
      begin
        var Tgt: Int64:= 0;
        if not FileOfUnit.TryGetValue(LowerCase(U.UnitName), Tgt) then
        begin
          var S: string:= LowerCase(U.UnitName);
          var Dp: Integer:= LastDelimiter('.', S);
          if Dp > 0 then S:= Copy(S, Dp + 1, MaxInt);
          FileOfStem.TryGetValue(S, Tgt);
        end;
        if (Tgt > 0) and (Tgt <> Fid) and (not Lst.Contains(Tgt)) then Lst.Add(Tgt);
      end;
    end;
    { 3) Tarjan SCC over all nodes. }
    Counter:= 0;
    for Fid in UnitName.Keys do
      if not Index.ContainsKey(Fid) then StrongConnect(Fid);
    Result:= Findings.ToArray;
  finally
    for var L in Adj.Values do L.Free;
    Adj.Free;
    Stack.Free; OnStack.Free; LowLink.Free; Index.Free;
    UnitLine.Free; FileOfStem.Free; FileOfUnit.Free; UnitName.Free;
    Findings.Free;
  end;
end; // function

/// <summary>Deliverable C (enum-helper-generator milestone): flags an enum `TX` whose
/// `record helper for TX` / `class helper for TX` (via the first-class type_helpers
/// edge, v15) is declared in a DIFFERENT unit than TX itself -- a co-location
/// advisory. Whole-DB pass: for every indexed `skEnum` symbol, queries
/// AStore.FindHelpersOfTypeSymbol(enum's own symbol id) and compares each edge's
/// helper-owning file to the enum's own file.</summary>
/// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
/// <returns>'enum-helper-separate-units' findings, one per enum with a cross-unit
/// helper (same-unit helpers and enums with no helper produce nothing); empty if
/// none. Deterministic: enums are visited in (file path, start line) order.</returns>
/// <remarks>ON by default (explicit user decision, 2026-07-07) -- diverges from the
/// OFF-by-default convention for most advisory rules in this codebase. Never raises.
/// Task 9b (FP fix, 2026-07-07): matches by the enum's own SYMBOL ID
/// (FindHelpersOfTypeSymbol), not its bare name (FindHelpersOfType) -- two
/// unrelated same-named enums in different units (e.g. two distinct
/// `TSymbolKind` types) were previously cross-linked by any helper edge
/// sharing that name, producing false positives (5 of 6 findings on this
/// repo's own self-index). A helper edge only counts as targeting THIS enum
/// when type_helpers.target_symbol_id resolved to this exact symbol; an
/// unresolved edge (NULL target_symbol_id) never matches, since it cannot be
/// proven to target this enum rather than some other same-named one.</remarks>
function CollectEnumHelperSeparateUnits(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  FileIds : TArray<Int64>      ;
  Fid     : Int64              ;
  Path    : string             ;
  Syms    : TArray<TSymbol>    ;
  Sym     : TSymbol            ;
  Edges   : TArray<THelperEdge>;
  Edge    : THelperEdge        ;
  HelperSym: TSymbol           ;
  F       : TLintFinding       ;
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
        if Sym.Kind <> skEnum then Continue;
        if Sym.Name = '' then Continue;
        Edges:= AStore.FindHelpersOfTypeSymbol(Sym.Id);
        for Edge in Edges do
        begin
          HelperSym:= AStore.GetSymbolById(Edge.HelperSymbolId);
          if HelperSym.FileId = Sym.FileId then Continue; { co-located -- no finding }
          F:= Default(TLintFinding);
          F.RuleId  := 'enum-helper-separate-units';
          F.Severity:= 'warning';
          F.Message := Format('helper %s (unit %s) is separate from enum %s (unit %s); consider co-locating.',
            [HelperSym.Name, AStore.GetFilePath(HelperSym.FileId), Sym.Name, Path]);
          F.FilePath:= Path;
          F.StartLine:= Sym.StartLine;
          F.StartCol := Sym.StartCol;
          F.EndLine  := Sym.StartLine;
          F.EndCol   := Sym.StartCol + Length(Sym.Name);
          Findings.Add(F);
        end;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

type
  { One recorded 'case' occurrence whose selector text is shared across methods. }
  TSwitchSite = record
    MethodKey: string ;  { Path + ':' + row of the enclosing defProc -- method identity }
    FilePath : string ;
    Line     : Integer;  { 1-based case.StartPoint.Row }
    Col      : Integer;  { 1-based case.StartPoint.Column }
    Original : string ;  { original-cased selector text (for the message) }
  end;

/// <summary>v0.80 repeated-type-switch (#14 refactoring): flags the SAME case-selector
/// text appearing across three or more DISTINCT methods -- a 'Replace Conditional with
/// Polymorphism' candidate. Pure AST grouping over every indexed .pas: it walks each tree
/// carrying the enclosing method identity, extracts each case node's selector text (the
/// exhaustive-enum-case idiom), normalises it (trim + collapse whitespace + lowercase) as
/// the group key, and when a normalised selector spans &gt;= MIN_DISTINCT_METHODS distinct
/// methods emits one 'info' finding at every recorded occurrence site.</summary>
/// <param name="AStore">An open, migrated symbol store; nil yields no findings. Used only to
/// enumerate files/paths -- the match itself is AST-based, not store-ref-based.</param>
/// <returns>'repeated-type-switch' findings; empty if none. Deterministic: sites are emitted
/// in (file, line) order over selector keys visited in sorted order.</returns>
/// <remarks>Known name-based FP: identically-named selectors in unrelated classes (e.g. a
/// field named FKind in two different hierarchies) group together, and legitimately-repeated
/// dispatches (message-map 'case Msg.Msg of' handlers) are flagged. Ships OFF by default.
/// Never raises.</remarks>
function CollectRepeatedTypeSwitch(const AStore: ISymbolStore): TArray<TLintFinding>;
const
  MIN_DISTINCT_METHODS = 3;
var
  Findings : TList<TLintFinding>              ;
  Groups   : TDictionary<string, TList<TSwitchSite>>; { normalised selector key -> sites }
  KeyOrder : TStringList                      ; { sorted, dedup group keys for stable output }
  Fid      : Int64                            ;
  Path     : string                           ;
  PF       : TParsedFile                      ;
  Src      : TBytes                           ;

  { Extract raw source bytes spanned by a node as a string. }
  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Trim, collapse internal whitespace runs to single spaces, lowercase. }
  function NormalizeSelector(const AText: string): string;
  var
    I  : Integer;
    C  : Char   ;
    Sb : TStringBuilder;
    Ws : Boolean;
  begin
    Sb:= TStringBuilder.Create;
    try
      Ws:= False;
      for I:= 1 to Length(AText) do
      begin
        C:= AText[I];
        if (C = ' ') or (C = #9) or (C = #10) or (C = #13) then
          Ws:= True
        else
        begin
          if Ws and (Sb.Length > 0) then Sb.Append(' ');
          Ws:= False;
          Sb.Append(C);
        end;
      end;
      Result:= LowerCase(Trim(Sb.ToString));
    finally
      Sb.Free;
    end;
  end;

  { Record one shared-selector case occurrence under its normalised key. }
  procedure RecordSite(const AKey, AOriginal: string; const ACaseNode: TTSNode;
    const AMethodKey: string);
  var
    Lst : TList<TSwitchSite>;
    Site: TSwitchSite       ;
    P   : TTSPoint          ;
  begin
    if not Groups.TryGetValue(AKey, Lst) then
    begin
      Lst:= TList<TSwitchSite>.Create;
      Groups.Add(AKey, Lst);
      KeyOrder.Add(AKey);
    end;
    P:= ACaseNode.StartPoint;
    Site.MethodKey:= AMethodKey;
    Site.FilePath := Path;
    Site.Line     := Integer(P.Row) + 1;
    Site.Col      := Integer(P.Column) + 1;
    Site.Original := AOriginal;
    Lst.Add(Site);
  end;

  { Recursively walk N carrying the enclosing-method key. On entering a defProc/
    defFunc, the new current method = Path + ':' + row; nested procs replace it for
    their own subtree. At each 'case' node extract + record the selector text. }
  procedure Walk(const N: TTSNode; const AMethodKey: string);
  var
    I       : Integer;
    Cur     : string ;
    Selector: TTSNode;
    St      : string ;
    RawSel  : string ;
    Key     : string ;
  begin
    if N.IsNull then Exit;
    Cur:= AMethodKey;
    St := N.NodeType;
    if (St = 'defProc') or (St = 'defFunc') then
      Cur:= Path + ':' + IntToStr(Integer(N.StartPoint.Row));

    if St = 'case' then
    begin
      { Selector = the 'selector' field when present, else the first named child that
        is not a caseCase arm / statement body and is not a keyword token (k...). }
      Selector:= N.ChildByField('selector');
      if Selector.IsNull then
        for I:= 0 to N.NamedChildCount - 1 do
        begin
          var Sc: TTSNode:= N.NamedChild(I);
          if Sc.IsNull then Continue;
          var Sct: string:= Sc.NodeType;
          if (Sct <> 'caseCase') and (Sct <> 'statement') and (Sct <> 'statements')
             and ((Length(Sct) = 0) or (Sct[1] <> 'k')) then
          begin Selector:= Sc; Break; end;
        end;
      if (not Selector.IsNull) and (Cur <> '') then
      begin
        RawSel:= Trim(NodeStr(Selector));
        Key   := NormalizeSelector(RawSel);
        if Key <> '' then RecordSite(Key, RawSel, N, Cur);
      end;
    end;

    for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I), Cur);
  end;

  function CountDistinctMethods(const ASites: TList<TSwitchSite>): Integer;
  var
    Seen: TDictionary<string, Boolean>;
    S   : TSwitchSite                 ;
  begin
    Seen:= TDictionary<string, Boolean>.Create;
    try
      for S in ASites do Seen.AddOrSetValue(S.MethodKey, True);
      Result:= Seen.Count;
    finally
      Seen.Free;
    end;
  end;

var
  Idx   : Integer         ;
  Sites : TList<TSwitchSite>;
  Sorted: TList<TSwitchSite>;
  S     : TSwitchSite      ;
  NDistinct: Integer       ;
  F     : TLintFinding     ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  Groups  := TDictionary<string, TList<TSwitchSite>>.Create;
  KeyOrder:= TStringList.Create;
  try
    KeyOrder.CaseSensitive:= True;
    KeyOrder.Duplicates:= dupIgnore;
    KeyOrder.Sorted:= False; { we sort explicitly after collection }

    { 1) walk every indexed .pas, grouping case-selector text by normalised key. }
    for Fid in AStore.GetAllFileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      if not SameText(ExtractFileExt(Path), '.pas') then Continue;
      PF:= TAstParseCache.Get(Path);
      if PF.Tree = nil then Continue;
      Src:= PF.Src;
      Walk(PF.Tree.RootNode, '');
    end;

    { 2) deterministic order: sort the group keys, then within each qualifying group
         sort sites by (file, line). Emit one finding per site. }
    KeyOrder.Sort;
    for Idx:= 0 to KeyOrder.Count - 1 do
    begin
      if not Groups.TryGetValue(KeyOrder[Idx], Sites) then Continue;
      NDistinct:= CountDistinctMethods(Sites);
      if NDistinct < MIN_DISTINCT_METHODS then Continue;
      Sorted:= TList<TSwitchSite>.Create;
      try
        Sorted.AddRange(Sites);
        Sorted.Sort(TComparer<TSwitchSite>.Construct(
          function(const A, B: TSwitchSite): Integer
          begin
            Result:= CompareText(A.FilePath, B.FilePath);
            if Result = 0 then Result:= A.Line - B.Line;
          end));
        for S in Sorted do
        begin
          F:= Default(TLintFinding);
          F.RuleId  := 'repeated-type-switch';
          F.Severity:= 'info';
          F.Message := Format('Type-switch on ''%s'' is repeated across %d methods -- consider replacing the conditional with polymorphism.', [S.Original, NDistinct]);
          F.FilePath:= S.FilePath;
          F.StartLine:= S.Line;
          F.StartCol := S.Col;
          F.EndLine  := S.Line;
          F.EndCol   := S.Col + 4; { length of 'case' keyword }
          Findings.Add(F);
        end;
      finally
        Sorted.Free;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    for var L in Groups.Values do L.Free;
    Groups.Free;
    KeyOrder.Free;
    Findings.Free;
  end;
end; // function

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
  UsesList      : TArray<TUnitUse>            ;
  U             : TUnitUse                    ;
  UnitStem      : string                      ;
  UF            : TLintFinding                ;
  PrivModifiers : string                      ;
  IsPrivate     : Boolean                     ;
  PropAccessors : TDictionary<string, Boolean>;
  { Run-level memos for unused-unit-in-uses. See StemsFor. }
  StemsOfName   : TDictionary<string, TArray<string>>;
  PathOfFile    : TDictionary<Int64, string>        ;
  UnitIndexed   : TDictionary<string, Boolean>      ;
  { Per-rule cost attribution, printed only under DRAGLINT_PROFILE. `lint-all`'s
    phase profiler can say "project-rules cost N seconds" but not WHICH of the
    seven rules in this pass spent it, and the answer decided the fix: on YADF,
    unused-unit-in-uses was 32.2 s of a 37.4 s pass while every other rule came
    in under 1.3 s. Attributing it by running `lint-project --rule <id>` once per
    rule works but costs a full pass each time; these counters get the same
    answer from ONE run. Two QueryPerformanceCounter reads per rule per symbol,
    against SQL queries that cost orders of magnitude more. }
  Prof          : Boolean;
  TCirc, TEnum, TRts, TUuiu, TGod, TUpub, TUpriv, TAccess, TOuter: Int64;
  { "Referenced at all?" as two sets, built with one scan each instead of two
    queries per symbol. See IsReferenced. }
  RefdIds       : TDictionary<Int64 , Boolean>;
  RefdNames     : TDictionary<string, Boolean>;

  function WantRule(const AId: string): Boolean;
  begin
    Result:= (ARuleId = '') or (ARuleId = AId);
  end;

  { Not inlined: a nested routine that reads an outer-scope variable cannot be
    (E2449), and Prof is exactly that. The call overhead is irrelevant next to
    the SQL queries being measured. }
  function Tick: Int64;
  begin
    if Prof then Result:= TStopwatch.GetTimeStamp else Result:= 0;
  end;

  procedure ProfLine(const AName: string; ATicks: Int64);
  begin
    Writeln(ErrOutput, Format('    %-28s %10.2f s', [AName, ATicks / TStopwatch.Frequency]));
  end;

  { Exactly the test the two dead-code rules used to make -- "no reference to
    this symbol id AND no reference to this name" -- but as two hash lookups
    against sets built once per run.

    It replaces
      (Length(AStore.FindReferencesTo(ASym.Id)) = 0) and
      (Length(AStore.FindCallersByName(ASym.Name)) = 0)
    which cost two row-materialising queries PER SYMBOL, the second of them a
    full scan of refs (that table has no name_text index). Measured on
    ORM3-Micronite2027: 447.8 s in unused-private-member and 59.0 s in
    unused-public-symbol.

    The name set is lowercased, matching the COLLATE NOCASE the query used;
    both that collation and Delphi's LowerCase fold ASCII only, so the two
    accept the same rows. }
  function IsReferenced(const ASym: TSymbol): Boolean;
  begin
    Result:= RefdIds.ContainsKey(ASym.Id) or RefdNames.ContainsKey(LowerCase(ASym.Name));
  end;

  { The unit stems of every symbol named AName, memoised for the whole run.

    This was one FindSymbolsByExactName query per REFERENCE OCCURRENCE, plus a
    GetFilePath query per matching symbol -- so the cost was O(all refs in the
    index) queries, repeated in full for every file, and identifiers recur
    constantly (every Create, Result, Free, TStringList). MEASURED via
    `lint-project --rule`: unused-unit-in-uses was 32.2 s of the 37.4 s
    project-rules phase on YADF, a project of EIGHT FILES, while every other
    project rule came in under 1.3 s. On ORM3-Micronite2027 the same phase was
    still running after 8,705 CPU-seconds
    (docs\INBOX-lint-all-project-wide-phase-dominates-runtime.md).

    Keying on the raw NameText -- not a lowercased or normalised form -- keeps
    this exactly equivalent to calling the store: TDictionary's default string
    comparer is ordinal, so a memo hit answers the same question the query would
    have. The stems are de-duplicated because the caller only ever tests set
    membership, which also bounds the memo's size by distinct names, not refs. }
  function StemsFor(const AName: string): TArray<string>;
  var
    Cached: TArray<string>              ;
    Seen  : TDictionary<string, Boolean>;
    S     : TSymbol                     ;
    FPath : string                      ;
    Stem  : string                      ;
  begin
    if StemsOfName.TryGetValue(AName, Cached) then Exit(Cached);
    Seen:= TDictionary<string, Boolean>.Create;
    try
      for S in AStore.FindSymbolsByExactName(AName) do
      begin
        if S.FileId <= 0 then Continue;
        if not PathOfFile.TryGetValue(S.FileId, FPath) then
        begin
          FPath:= AStore.GetFilePath(S.FileId);
          PathOfFile.Add(S.FileId, FPath);
        end;
        Stem:= LowerCase(ChangeFileExt(ExtractFileName(FPath), ''));
        if (Stem <> '') and not Seen.ContainsKey(Stem) then
        begin
          Seen.Add(Stem, True);
          Result:= Result + [Stem];
        end;
      end;
    finally
      Seen.Free;
    end;
    StemsOfName.Add(AName, Result);
  end;

  { "Is AUnitName in the index as a unit?" -- memoised for the same reason:
    every file in the project uses the same handful of units, so this ran the
    identical query once per (file x used unit). }
  function UnitIsIndexed(const AUnitName: string): Boolean;
  var
    S: TSymbol;
  begin
    if UnitIndexed.TryGetValue(AUnitName, Result) then Exit;
    Result:= False;
    for S in AStore.FindSymbolsByExactName(AUnitName) do
      if S.Kind = skUnit then begin Result:= True; Break; end;
    UnitIndexed.Add(AUnitName, Result);
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
  Findings   := TList<TLintFinding>.Create;
  StemsOfName:= TDictionary<string, TArray<string>>.Create;
  PathOfFile := TDictionary<Int64, string>        .Create;
  UnitIndexed:= TDictionary<string, Boolean>      .Create;
  RefdIds    := TDictionary<Int64 , Boolean>      .Create;
  RefdNames  := TDictionary<string, Boolean>      .Create;
  Prof:= GetEnvironmentVariable('DRAGLINT_PROFILE') <> '';
  TCirc:= 0; TEnum:= 0; TRts:= 0; TUuiu:= 0; TGod:= 0; TUpub:= 0; TUpriv:= 0; TAccess:= 0; TOuter:= 0;
  try
    { Built only for the rules that need them -- on a large index these are two
      scans of the whole refs table, which is pure waste for a --rule run that
      asks neither dead-code question. }
    if WantRule('unused-public-symbol') or WantRule('unused-private-member') then
    begin
      for var RId: Int64  in AStore.GetReferencedSymbolIds  do RefdIds  .AddOrSetValue(RId, True);
      for var RNm: string in AStore.GetReferencedNamesLower do RefdNames.AddOrSetValue(RNm, True);
    end;

    { circular-uses: whole-graph SCC pass (not per-file). }
    var T0: Int64:= Tick;
    if WantRule('circular-uses') then
      for var Cf in CollectCircularUses(AStore) do Findings.Add(Cf);
    Inc(TCirc, Tick - T0); T0:= Tick;

    { enum-helper-separate-units (Task 7, enum-helper-generator milestone):
      whole-DB helper-edge pass (not per-file). ON by default -- do NOT add
      this id to DoLintAll's inline disabled array or DoLintProject's
      DefDisabled build-up (CLI.pas); this is the sole gate that keeps it
      genuinely ON at runtime in both lint paths. }
    if WantRule('enum-helper-separate-units') then
      for var Ef in CollectEnumHelperSeparateUnits(AStore) do Findings.Add(Ef);
    Inc(TEnum, Tick - T0); T0:= Tick;

    { repeated-type-switch (v0.80 #14): cross-file case-selector grouping pass. }
    if WantRule('repeated-type-switch') then
      for var Rf in CollectRepeatedTypeSwitch(AStore) do Findings.Add(Rf);
    Inc(TRts, Tick - T0);

    FileIds:= AStore.GetAllFileIds;
    for Fid in FileIds do
    begin
      var TF: Int64:= Tick;
      Path:= AStore.GetFilePath(Fid);
      Syms:= AStore.FindSymbolsByFile(Path);
      Inc(TOuter, Tick - TF);

      { unused-unit-in-uses: build the set of file IDs referenced from this file.
        Skip files with no uses entries to avoid the O(refs) cost for every file. }
      { A program/package uses clause is the project's unit-INCLUSION list, not an
        import list: a .dpr legitimately names every unit it links even when its
        main block references no symbol from any of them. Only a .pas import can
        be a dead import, so never run this rule on .dpr/.dpk. }
      var TU: Int64:= Tick;
      if WantRule('unused-unit-in-uses') and
         not (SameText(ExtractFileExt(Path), '.dpr') or SameText(ExtractFileExt(Path), '.dpk')) then
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
              for var RefStem: string in StemsFor(Ref.NameText) do
                RefdUnitStems.AddOrSetValue(RefStem, True);
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
              if not UnitIsIndexed(U.UnitName) then Continue;
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
      Inc(TUuiu, Tick - TU);

      { Build the property-accessor guard set for unused-private-member.
        ParseCache.Get re-uses an already-parsed tree when available; cost
        is near-zero on subsequent calls for the same file within a run.
        Must be freed at end of per-file scope (see finally below). }
      PropAccessors:= nil;
      var TA: Int64:= Tick;
      if WantRule('unused-private-member') then
        PropAccessors:= BuildPropertyAccessorSet(Path);
      Inc(TAccess, Tick - TA);
      try

        for Sym in Syms do
        begin
          var TS: Int64:= Tick;
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
          Inc(TGod, Tick - TS); TS:= Tick;

          { unused-public-symbol: an exported (interface-section) free routine that
            nothing in the index references or calls -- likely dead public API.
            Restricted to unit-level routines (not class methods) so DFM-wired
            event handlers and virtual/override methods are not false positives. }
          if WantRule('unused-public-symbol') and (Sym.Section = 'interface') and (Sym.Kind in [skFunction, skProcedure]) and (Sym.ParentId > 0) and
            (Pos('override', LowerCase(Sym.Modifiers)) = 0) and not SameText(Sym.Name, 'Register') then
          begin
            Parent:= AStore.GetSymbolById(Sym.ParentId);
            if (Parent.Id = Sym.ParentId) and (Parent.Kind = skUnit) then
              if not IsReferenced(Sym) then
                Add('unused-public-symbol', 'info', Format('Exported routine %s has no references in the index -- possible dead public API', [Sym.Name]), Sym);
          end;
          Inc(TUpub, Tick - TS); TS:= Tick;

          { unused-private-member: a private or strict private member (method,
            field, const, nested type) that has zero references in the index.
            Guards:
              - skip virtual/override (may be called via dispatch table);
              - skip if any reference exists (conservative);
              - skip property accessors: getter/setter methods and backing fields
                that appear in a property's 'read'/'write' clause have zero
                FindReferencesTo + FindCallersByName because the index does NOT
                record a reference from the property declaration to its accessor.
                PropAccessors (built above from the file's AST declProp nodes via
                the 'getter' and 'setter' grammar fields) covers this case exactly.
            Published members are never private so DFM-streamed components are
            not affected. }
          if WantRule('unused-private-member') then
          begin
            PrivModifiers:= LowerCase(Sym.Modifiers);
            IsPrivate:= (Pos('private', PrivModifiers) > 0);
            if IsPrivate and
              (Sym.Kind in [skMethod, skFunction, skProcedure, skConstructor, skDestructor,
                            skField, skConstDecl, skTypeAlias, skClass, skInterface, skRecord, skEnum]) and
              (Pos('override', PrivModifiers) = 0) and
              { A message handler -- `procedure WMSize(var M: TWMSize); message WM_SIZE;`
                -- is dispatched by the VCL through the message table and is NEVER
                called by name, so "no references" is its normal, correct state,
                not dead code. Same dispatch argument as the virtual/override
                guard beside it. }
              (Pos('message', PrivModifiers) = 0) and
              (not Sym.IsVirtual) then
            begin
              { Skip members whose name appears as a property accessor or backing
                storage in this file (exact AST match; case-insensitive). }
              if (PropAccessors <> nil) and PropAccessors.ContainsKey(LowerCase(Sym.Name)) then
                { property accessor or backing field -- not dead code, skip }
              else
              if not IsReferenced(Sym) then
                Add('unused-private-member', 'warning',
                  Format('Private member ''%s'' has no references in the index -- possible dead code', [Sym.Name]), Sym);
            end;
          end;
          Inc(TUpriv, Tick - TS);

        end; // for Sym

      finally
        PropAccessors.Free;
        PropAccessors:= nil;
      end;

    end; // for Fid
    if Prof then
    begin
      Writeln(ErrOutput, '  PROJECT-RULES BREAKDOWN');
      ProfLine('circular-uses'             , TCirc  );
      ProfLine('enum-helper-separate-units', TEnum  );
      ProfLine('repeated-type-switch'      , TRts   );
      ProfLine('unused-unit-in-uses'       , TUuiu  );
      ProfLine('god-class'                 , TGod   );
      ProfLine('unused-public-symbol'      , TUpub  );
      ProfLine('unused-private-member'     , TUpriv );
      ProfLine('  (accessor-set parse)'    , TAccess);
      ProfLine('  (per-file store reads)'  , TOuter );
      Flush(ErrOutput);
    end;
    Result:= Findings.ToArray;
  finally
    RefdNames  .Free;
    RefdIds    .Free;
    UnitIndexed.Free;
    PathOfFile .Free;
    StemsOfName.Free;
    Findings   .Free;
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
