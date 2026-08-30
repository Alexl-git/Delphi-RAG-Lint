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
  , System.StrUtils { StartsText / PosEx -- the .dfm text scan in global-only-uses-edge }
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
  , DRagLint.Lint.SharedUnit { ProjectsOf -- unused-public-symbol must not call a
                               shared unit's API dead on one project's index }
  ;

type
  /// <summary>Opens (or returns an already-open) read-only store for a SIBLING
  /// PROJECT named by a shared unit's own `dl:shared` header.</summary>
  /// <param name="AProjectName">The project name exactly as the header spells
  /// it -- 'YADFOT', 'YADFSetup'. Matched case-insensitively against the index
  /// manifest's section names.</param>
  /// <returns>An open store, or nil when the name resolves to no configured
  /// index or the index cannot be opened.</returns>
  /// <remarks>
  /// LAZY on purpose. A run over a project with no shared units must
  /// not open anything, and a box with ~30 configured indexes must not open
  /// them all to answer a question about one routine. The rule calls this only
  /// once it already has a finding whose unit declares siblings.
  /// nil is a legitimate answer and must be read as "could not check", never as
  /// "not referenced there" -- those lead to opposite conclusions and only one
  /// of them is safe.
  /// The caller owns the returned store's lifetime for the whole run.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), declaration (DRagLint.Lint.ProjectRules.pas), DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSiblingStoreResolver = reference to function(const AProjectName: string): ISymbolStore;

  /// <summary>Index-wide lint rules (oversized classes; unused exported routines).</summary>
  /// <remarks>Stateless; reads the supplied open store. Never raises.</remarks>
  TProjectLintRules = class
  public
    /// <summary>Runs the project rules over AStore and returns all findings.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <param name="ARuleId">If non-empty, only that rule id is evaluated.</param>
    /// <param name="ASiblingStore">Optional. When supplied, `unused-public-symbol`
    /// CONSULTS the sibling projects a shared unit's own `dl:shared` header names
    /// and suppresses the finding when the routine is referenced in one of them.
    /// nil (the default) keeps the historic behaviour: report, and tell the
    /// reader to check the siblings by hand.</param>
    /// <param name="ALibraryStore">The platform LIBRARY index, or nil. Needed by
    /// unused-unit-in-uses: a project store cannot see System.IniFiles, so
    /// without this the rule's own "is the unit indexed?" gate answered False
    /// for every RTL/VCL import and the rule reported ZERO, everywhere.</param>
    /// <returns>Findings across the whole index (file paths + lines); empty if none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)</para>
    /// <para>Calls: ASiblingStore, ChangeFileExt, CollectFrom, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetReferencedNamesLower (+27 more)</para>
    /// <para>Returns: TDictionary&lt;string, Boolean&gt;.Create; nil; Findings.ToArray</para>
    /// <para>Complexity: 50 (cyclomatic, outer body), 554 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetReferencedNamesLower"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Run(const AStore: ISymbolStore; const ARuleId: string = '';
                       const ASiblingStore: TSiblingStoreResolver = nil;
                       const ALibraryStore: ISymbolStore = nil;
                       const AOptInRules: TArray<string> = nil): TArray<TLintFinding>;
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
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Lint.ProjectRules.TProjectLintRules.CheckLayering.LayerOf, Format, LowerCase, SameText, TJSONArray, TJSONObject, TJSONString, Writeln</para>
    /// <para>Returns: nil; Findings.ToArray</para>
    /// <para>Complexity: 29 (cyclomatic, outer body), 139 lines (full implementation)</para>
    /// <para>Touches: file system</para>
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

{ REGISTRATION FAMILIES, matched by PREFIX rather than by name.

  A unit whose whole purpose is its initialization section exports nothing you
  would ever reference, so "no symbols from it are referenced" is TRUE of it and
  says nothing. Removing it is what breaks the program.

  Measured on DataCopy 2026-08-26, when unused-unit-in-uses first produced
  findings at all: 7 of 79 were exactly this -- dxSkinWXI (a DevExpress skin,
  which registers a painter), ExceptionLog7 and EExceptionManager (EurekaLog's
  injected block, which installs the exception hook). All three are correct to
  list and wrong to report.

  A prefix list, not an exact list: dxSkin* alone is dozens of units and every
  DevExpress release adds more, so enumerating them is a losing game. }
  KSideEffectPrefixes: array[0..6] of string = (
    'dxskin',        { DevExpress skins -- register a painter, export nothing }
    'vectorskin',    { the same, vector family }
    'exceptionlog',  { EurekaLog: installs the hook in initialization }
    'ememleaks', 'eresleaks', 'eappvcl', 'eexceptionmanager'
  );

function IsSideEffectUnit(const AUnitName: string): Boolean;
var
  Low: string;
  S  : string;
begin
  Low:= LowerCase(AUnitName);
  for S in KSideEffectUnits do
    if Low = S then Exit(True);
  for S in KSideEffectPrefixes do
    if Low.StartsWith(S) then Exit(True);
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
  { Per-edge section provenance, keyed 'fromFid|toFid'. An edge counts as
    implementation-only when it appears in an implementation uses and NOT in an
    interface one -- a unit listed in both still couples through its interface. }
  EdgeHasImpl: TDictionary<string, Boolean>;
  EdgeHasIntf: TDictionary<string, Boolean>;
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
          { THE ADVICE MUST MATCH WHAT THE CYCLE ACTUALLY IS.
            A pure interface-section cycle does not compile, so a cycle in a
            building project ALREADY routes through an implementation-section
            uses. Telling its author to "move a use to the implementation
            section" is telling them to do the thing they have already done --
            `DRagLint.Doc.Harvest` did exactly that, with a comment explaining
            why, and was then advised to do it again. Only the extraction remedy
            is left in that case.

            The other branch is kept rather than assumed unreachable: a cycle can
            be reported over a set of units that is not currently compiling, or
            where the implementation edge is outside the component. }
          var HasImplEdge: Boolean:= False;
          for var Ai: Integer:= 0 to Comp.Count - 1 do
            for var Bi: Integer:= 0 to Comp.Count - 1 do
              if Ai <> Bi then
              begin
                var K: string:= IntToStr(Comp[Ai]) + '|' + IntToStr(Comp[Bi]);
                if EdgeHasImpl.ContainsKey(K) then HasImplEdge:= True;
              end;
          if HasImplEdge then
            F.Message := Format('Circular unit dependency among %d units: %s -- it already routes through an implementation-section uses, so it compiles; this is a coupling smell, not a build error. Extract the shared code into a new unit (moving another use to the implementation section will NOT break this cycle)', [Comp.Count, Names])
          else
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
  EdgeHasImpl:= TDictionary<string, Boolean>.Create;
  EdgeHasIntf:= TDictionary<string, Boolean>.Create;
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
        { Remember WHICH SECTION each edge came from, so the finding can tell the
          reader something they can act on. An edge is recorded as
          implementation-only when the unit appears in the implementation uses and
          NOT in the interface uses -- a unit listed in both still couples through
          its interface, so it is not evidence that the cycle has already been
          relaxed. }
        if Tgt > 0 then
        begin
          var EKey: string:= IntToStr(Fid) + '|' + IntToStr(Tgt);
          if U.Section = uusImplementation then
          begin
            if not EdgeHasIntf.ContainsKey(EKey) then EdgeHasImpl.AddOrSetValue(EKey, True);
          end
          else if U.Section = uusInterface then
          begin
            EdgeHasIntf.AddOrSetValue(EKey, True);
            EdgeHasImpl.Remove(EKey);
          end;
        end;
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
    EdgeHasImpl.Free;
    EdgeHasIntf.Free;
    Stack.Free; OnStack.Free; LowLink.Free; Index.Free;
    UnitLine.Free; FileOfStem.Free; FileOfUnit.Free; UnitName.Free;
    Findings.Free;
  end;
end; // function

type
  { How a datamodule member is classified for the global-only-uses-edge DFM
    demotion (owner ruling 2026-08-30). Decided by ANCESTRY, never by a list of
    member names -- the owner's words: "Objects like TFDQuery should be traced
    down to TDataSet or TDataSource, etc to verify what they are. Sometimes
    there might be non-obvious classes."

    mcUnresolved is treated exactly like mcBehavioural everywhere, and that is
    the whole point of keeping it a separate value: the demotion is a BLESSING
    ("this design-time link is legitimate"), and a blessing needs positive
    evidence. Softening advice on a type we could not even find would be
    manufacturing confidence out of absence. The two failure directions are not
    symmetric -- wrongly NOT demoting leaves a true finding whose note is merely
    missing, while wrongly demoting tells the reader a data coupling is fine. It
    also makes a degraded run safe: no library store, or a stale one, yields
    FEWER demotions rather than wrong ones. }
  TMemberClass = (mcResource, mcBehavioural, mcUnresolved);

  { Everything the demotion needs to know about ONE declaring unit's .dfm,
    computed once per declaring unit because the measured shape is many readers
    of one declarer (24 of 37 pairs, twelve of them uStyles). }
  TDeclDfm = record
    Root       : string ; // root object name  -- 'dmStyles'
    RootClass  : string ; // root class name   -- 'TdmStyles'
    RootClassId: Int64  ; // 0 when that class is not declared in the .pas
    ModuleOK   : Boolean; // the root class declares NO non-resource FIELD
    BadFields  : string ; // up to 5 offending 'name (Type)', for the message
  end;

/// <summary>Flags a const or var NAME declared at interface unit level in two
/// or more units -- which declaration compiles depends on uses order.</summary>
/// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
/// <returns>'duplicate-global-decl' findings, one per NAME (not per site),
/// anchored at the first declaring site in (path, line) order; empty if none.</returns>
/// <remarks>
/// Requested by the owner 2026-08-30, verbatim: "Const declared in 2 different
/// units is often my mistake. I don't know why it is not a syntax error." It is
/// not an error because Delphi resolves an unqualified name through the uses
/// clause in REVERSE order, current unit first -- so adding or merely
/// REORDERING a uses entry silently changes which declaration compiles, with no
/// diagnostic at all.
///
/// REPORTED ALWAYS, NOT ONLY WHEN THE VALUES DIFFER, and that is a measurement
/// rather than a preference: all 11 real findings on ORM3 are byte-identical
/// after normalization, so a differ-only rule would ship SILENT on the exact
/// corpus that motivated the request. Two identical copies are still a hazard --
/// a uses reorder swaps which one you get, and they are identical only UNTIL
/// someone edits one of them. Differing declarations are strictly worse, so
/// they escalate the MESSAGE and not the severity.
///
/// THE COMPARISON IS NORMALIZED (lowercased, whitespace runs collapsed), and
/// that too came from the corpus: raw string comparison calls ORM3's
/// tbltdistrcount a difference on 'integer' against 'Integer'. Reporting a case
/// difference as a semantic one would teach the reader to distrust the
/// escalation, which costs more than the finding is worth.
///
/// Measured 2026-08-30: 11 findings on ORM3 server, 11 on client, 0 on this
/// repo, at 0.02 / 0.05 / 0.01 s. Symbols-only -- no refs join -- so unlike the
/// sibling global-only-uses-edge it needs no OptedIn gate and ships enabled.
///
/// KNOWN CAVEAT: the finding is anchored at ONE site, so if that file is
/// excluded by exclude_paths or ownership while its twin is owned, the finding
/// vanishes with it. Accepted for v1 -- per-site findings would report the same
/// name twice. Duplicates against the LIBRARY index (re-declaring an RTL name)
/// are a deliberate non-goal here; TProjectLintRules.Run already receives the
/// library store, so a future tier can join against it.
/// Never raises. See ISymbolStore.FindDuplicateGlobalDecls.
/// </remarks>
function CollectDuplicateGlobalDecls(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;

  { Lowercased with every whitespace run collapsed to one space. See the
    tbltdistrcount note above -- this is the difference between an escalation
    the reader believes and one they learn to ignore. }
  function NormSig(const AText: string): string;
  var
    I   : Integer;
    Gap : Boolean;
  begin
    Result:= '';
    Gap   := False;
    for I:= 1 to Length(AText) do
      if CharInSet(AText[I], [' ', #9, #13, #10]) then
        Gap:= True
      else
      begin
        if Gap and (Result <> '') then Result:= Result + ' ';
        Gap   := False;
        Result:= Result + AText[I];
      end;
    Result:= LowerCase(Result);
  end;

var
  Rows    : TArray<TDuplicateDeclSite>;
  I, J, K : Integer                   ;
  Paths   : TArray<string>            ;
  Sites   : string                    ;
  Kinds   : string                    ;
  Sigs    : string                    ;
  Differ  : Boolean                   ;
  NFiles  : Integer                   ;
  F       : TLintFinding              ;
  Seen    : TDictionary<string, Boolean>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Rows:= AStore.FindDuplicateGlobalDecls;
  if Length(Rows) = 0 then Exit;
  Findings:= TList<TLintFinding>.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  try
    I:= 0;
    while I < Length(Rows) do
    begin
      { Rows arrive ordered by lowercased name, so one group is one contiguous
        run -- no dictionary of groups, and no dependence on GROUP_CONCAT
        ordering, which SQLite does not guarantee. }
      J:= I;
      while (J < Length(Rows)) and SameText(Rows[J].Name, Rows[I].Name) do Inc(J);

      Paths := nil;
      Sites := '';
      Kinds := '';
      Sigs  := '';
      Differ:= False;
      Seen.Clear;
      for K:= I to J - 1 do
      begin
        var SitePath: string:= AStore.GetFilePath(Rows[K].FileId);
        if SitePath = '' then Continue;
        if not Seen.ContainsKey(LowerCase(SitePath)) then
        begin
          Seen.Add(LowerCase(SitePath), True);
          Paths:= Paths + [SitePath];
        end;
        if Sites <> '' then Sites:= Sites + ', ';
        Sites:= Sites + Format('%s:%d', [SitePath, Rows[K].StartLine]);
        if not ContainsText(Kinds, Rows[K].Kind) then
        begin
          if Kinds <> '' then Kinds:= Kinds + '/';
          Kinds:= Kinds + Rows[K].Kind;
        end;
        if NormSig(Rows[K].Signature) <> NormSig(Rows[I].Signature) then Differ:= True;
        if Sigs <> '' then Sigs:= Sigs + ' vs ';
        Sigs:= Sigs + Trim(Rows[K].Signature);
      end;
      NFiles:= Length(Paths);

      { Two sites in the SAME file are not the hazard this rule names -- the
        store already requires two distinct files, but a name declared twice in
        one unit would otherwise slip through the row loop above. }
      if NFiles >= 2 then
      begin
        F:= Default(TLintFinding);
        F.RuleId   := 'duplicate-global-decl';
        F.Severity := 'warning';
        F.FilePath := AStore.GetFilePath(Rows[I].FileId);
        F.StartLine:= Rows[I].StartLine;
        F.StartCol := Rows[I].StartCol;
        if F.StartCol <= 0 then F.StartCol:= 1;
        F.EndLine  := Rows[I].StartLine;
        F.EndCol   := F.StartCol + Length(Rows[I].Name);
        if Differ then
          F.Message:= Format(
            '%s is declared at interface level in %d units as %s (%s) -- THE DECLARATIONS ' +
            'DIFFER (%s), so which one compiles depends on uses order',
            [Rows[I].Name, NFiles, Kinds, Sites, Sigs])
        else
          F.Message:= Format(
            '%s is declared at interface level in %d units as %s (%s) -- the declarations ' +
            'are identical; delete one and re-point the uses',
            [Rows[I].Name, NFiles, Kinds, Sites]);
        Findings.Add(F);
      end;

      I:= J;
    end;
    Result:= Findings.ToArray;
  finally
    Seen    .Free;
    Findings.Free;
  end;
end; // function

/// <summary>Flags a unit pair whose ONLY dependency link is one or more
/// interface-section global variables -- RELOCATING them deletes the uses edge
/// (and INJECTING them, when every one is interface-typed).</summary>
/// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
/// <returns>'global-only-uses-edge' findings, one per (reader, declarer) pair,
/// ordered by how few globals carry the edge (one is the strongest); empty if none.</returns>
/// <remarks>
/// The approved di-globals shape (owner ruling 2026-08-30). The rejected shape was
/// "flag global reads", refuted on measurement at 1,987 reads on ORM3 client and 745
/// on server -- a census, not a defect report. This asks the narrower decoupling
/// question and measures 8 pairs on ORM3 server, 29 on client, 0 on this repo, with
/// 24 of the 37 carried by a SINGLE global. Specification:
/// docs\probe-di-globals-uses-edges.py.
///
/// THE DEFAULT ADVICE IS "RELOCATE", AND ONLY A TYPE BUYS THE WORD "INJECT"
/// (owner ruling 2026-08-30, tightening the earlier unconditional "inject or
/// relocate"). The strongest measured case is uStyles.SkipRefresh: twelve units
/// depend on a 1,139-line unit for one Boolean. The cure is to MOVE the
/// variable to a small unit; telling that author to wire up a container is
/// worse advice than saying nothing, because a Boolean cannot be registered and
/// resolved. When every carrying global IS interface-typed, injection genuinely
/// is a cure and the message says so -- measured 2026-08-30 on ORM3 client, 5
/// of the 21 edges (MyStation/ImcSTATIONS, MyOperator/ImcOPTRLIST,
/// CSVHelper/IMicroniteCSVFolderOperation), 2 mixed, 14 neither.
///
/// The test is ALL and not ANY: on a mixed edge, injecting the interface half
/// leaves the remaining global carrying the edge, so the edge does not go away
/// and the sentence would be false. See TGlobalOnlyEdge.AllInterfaceTyped.
///
/// Severity stays 'info' even when nothing demotes it: this is a design opinion
/// about coupling, not a defect, and the reader may have reasons the index cannot
/// see. The DFM check below is one such reason made visible -- but only when the
/// referenced member is a RESOURCE. Owner ruling 2026-08-30: a form binding to a
/// datamodule's TcxStyle or TImageList at design time is legitimate and the edge
/// is blessed; a form binding to its TFDQuery or an event handler is the finding,
/// because that coupling forces construction order and blocks testing, and its
/// cure is an interface resolved through the container rather than a deleted
/// uses line. A MIXED datamodule -- one holding both -- is the worst case and is
/// never blessed, which is the ruling taken literally: the construction-order
/// argument is about the MODULE, not about whichever member this reader sampled.
/// Never raises. The heavy lifting is one SQL statement -- see
/// ISymbolStore.FindGlobalOnlyUsesEdges.
/// </remarks>
function CollectGlobalOnlyUsesEdges(const AStore, ALibStore: ISymbolStore): TArray<TLintFinding>;
const
  { Ancestry does the work; this only names where the climb STOPS. Verified
    2026-08-30 by query against library-Win64.sqlite rather than assumed:
    TFDQuery reaches TDataSet in five hops (TFDCustomQuery -> TFDRdbmsDataSet ->
    TFDAdaptedDataSet -> TFDDataSet); TDataSource does NOT descend TDataSet and
    needs its own root; and TFDTransaction reaches NEITHER TDataSet nor
    TCustomConnection, so without TFDCustomTransaction here a
    `Transaction = dmMain.trX` binding would classify as a resource and be
    blessed. Known gap accepted for first ship: IBX's TIBTransaction descends
    only TComponent. ORM3 is FireDAC. }
  CBehaviouralRoots: array[0..3] of string =
    ('TDataSet', 'TDataSource', 'TCustomConnection', 'TFDCustomTransaction');
var
  Findings   : TList<TLintFinding>            ;
  TypeMemo   : TDictionary<string, TMemberClass>;
  RootCache  : TDictionary<string, TDeclDfm>  ;
  MemberCache: TObjectDictionary<string, TDictionary<string, TSymbol>>;

  function IsBehaviouralRoot(const AName: string): Boolean;
  begin
    for var R: string in CBehaviouralRoots do
      if SameText(R, AName) then Exit(True);
    Result:= False;
  end;

  { The ancestor-NAME closure of AName, across the project store and then the
    library store. Returns True when at least one CLASS declaration of AName was
    found anywhere -- which is how the caller tells "resolved and benign" from
    "never found" -- and sets ABehav when any name in the closure is one of the
    roots above.

    Matching on the NAME means an UNRESOLVED ancestor leaf still classifies, and
    that is deliberate: it keeps the guard fixtures library-independent (a bare
    `TFixQuery = class(TDataSet)` classifies behavioural with no library store
    attached) and it is also the cross-store hop that takes a project-declared
    `TMyQuery = class(TFDQuery)` down to TDataSet -- the project index cannot
    resolve TFDQuery, so the climb continues in the library index by name. }
  function Climb(const AName: string; ADepth: Integer; var ABehav: Boolean): Boolean;
  var
    Idx: Integer     ;
    S  : ISymbolStore;
    Sy : TSymbol     ;
    A  : TTypeAncestor;
  begin
    Result:= False;
    if (ADepth > 8) or (Trim(AName) = '') then Exit;
    if IsBehaviouralRoot(AName) then
    begin
      ABehav:= True;
      Exit(True);
    end;
    for Idx:= 0 to 1 do
    begin
      if Idx = 0 then S:= AStore else S:= ALibStore;
      if S = nil then Continue;
      for Sy in S.FindSymbolsByExactName(AName) do
      begin
        if Sy.Kind <> skClass then Continue;
        Result:= True;
        for A in S.GetTransitiveAncestors(Sy.Id) do
        begin
          if IsBehaviouralRoot(A.Name) then
          begin
            ABehav:= True;
            Exit(True);
          end;
          if (not A.Resolved) and (ALibStore <> nil) and (Idx = 0) then
            if Climb(A.Name, ADepth + 1, ABehav) then
            begin
              Result:= True;
              if ABehav then Exit(True);
            end;
        end;
      end;
    end;
  end;

  { Run-level memo. A project has a handful of distinct member types and this is
    reached only for findings whose reader .dfm actually names the declaring
    root -- zero sites on ORM3 client today. }
  function ClassifyType(const ATypeName: string): TMemberClass;
  var
    Key  : string ;
    Behav: Boolean;
  begin
    Key:= LowerCase(Trim(ATypeName));
    if Key = '' then Exit(mcUnresolved);
    if TypeMemo.TryGetValue(Key, Result) then Exit;
    Behav := False;
    if Climb(Trim(ATypeName), 0, Behav) then
      if Behav then Result:= mcBehavioural else Result:= mcResource
    else
      Result:= mcUnresolved;
    TypeMemo.AddOrSetValue(Key, Result);
  end;

  { The declaring unit's DFM ROOT OBJECT name ('dmStyles' for uStyles.dfm), or ''
    when the unit has no .dfm. Read from the FILE, not the index, and that is a
    deliberate choice rather than an oversight: measured 2026-08-30, DFM
    references in the index are event-bindings only -- 1,154 rows on ORM3 client,
    ZERO of which name dmStyles -- while the DFM TEXT carries the cross-form
    component links in 18 of that project's .dfm files. Asking the index here
    would return "no link" for every case this check exists to catch. }
  procedure DfmRootObject(const AUnitPath: string; out ARoot, ARootClass: string);
  var
    Dfm, Line: string;
    SL       : TStringList;
    I, C     : Integer;
  begin
    ARoot:= ''; ARootClass:= '';
    Dfm:= ChangeFileExt(AUnitPath, '.dfm');
    if not TFile.Exists(Dfm) then Exit;
    SL:= TStringList.Create;
    try
      try
        SL.LoadFromFile(Dfm);
      except
        { A .dfm that cannot be read demotes nothing. Silently: this runs on a
          handful of findings and a read error here is not the user's question. }
        Exit;
      end;
      for I:= 0 to SL.Count - 1 do
      begin
        Line:= Trim(SL[I]);
        if not StartsText('object ', Line) then Continue;
        Line:= Trim(Copy(Line, 8, MaxInt));
        C:= Pos(':', Line);
        if C > 1 then
        begin
          { 'object dmStyles: TdmStyles' -- the CLASS is on the same line the
            root name is parsed from, so it costs nothing extra and is what
            lets the member lookup below resolve against a real declaration. }
          ARoot     := Trim(Copy(Line, 1, C - 1));
          ARootClass:= Trim(Copy(Line, C + 1, MaxInt));
        end;
        Exit; { the ROOT object is the first one; nested objects are components }
      end;
    finally
      SL.Free;
    end;
  end;

  { A .dfm line with every single-quoted run blanked out. Without this a CAPTION
    reading 'see dmStyles.Header for details' is indistinguishable from a real
    component binding -- a latent false demotion in the substring test this
    replaces, and one that only gets worse now that the member name is extracted
    and classified. A doubled quote toggles twice and is blanked either way. }
  function StripQuoted(const ALine: string): string;
  var
    InStr: Boolean;
    I    : Integer;
  begin
    Result:= ALine;
    InStr := False;
    for I:= 1 to Length(Result) do
      if Result[I] = '''' then
      begin
        InStr    := not InStr;
        Result[I]:= ' ';
      end
      else if InStr then
        Result[I]:= ' ';
  end;

  { The DISTINCT member names the reading unit's own .dfm binds on the declaring
    unit's root object -- 'styThing' for `StyleRef = dmFix.styThing`. Empty when
    there is no design-time link at all, which is the same answer the old
    substring test gave and produces no note either way.

    Still a TEXT scan of the .dfm, and still for the reason recorded above: the
    index carries DFM references as event-bindings only, so asking it here
    returns "no link" for every case this check exists to catch. What changed is
    that the answer is now the member NAMES rather than a yes/no, because the
    ruling turns on WHICH member is bound. }
  function DfmReferencedMembers(const AReaderPath, ARoot: string): TArray<string>;
  var
    SL, Names: TStringList;
    Dfm, Line: string     ;
    Lo       : string     ;
    I, P, Q, E: Integer   ;
  begin
    Result:= nil;
    if ARoot = '' then Exit;
    Dfm:= ChangeFileExt(AReaderPath, '.dfm');
    if not TFile.Exists(Dfm) then Exit;
    SL   := TStringList.Create;
    Names:= TStringList.Create;
    try
      try
        SL.LoadFromFile(Dfm);
      except
        { A .dfm that cannot be read -- a binary TPF0 form included -- yields no
          members, exactly as it yielded no match before. }
        Exit;
      end;
      Names.CaseSensitive:= False;
      Names.Sorted       := True;
      Names.Duplicates   := dupIgnore;
      Lo:= LowerCase(ARoot) + '.';
      for I:= 0 to SL.Count - 1 do
      begin
        Line:= StripQuoted(SL[I]);
        P   := 1;
        while True do
        begin
          Q:= PosEx(Lo, LowerCase(Line), P);
          if Q = 0 then Break;
          P:= Q + Length(Lo);
          { 'FdmFix.x' is not a reference to dmFix. }
          if (Q > 1) and CharInSet(Line[Q - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
            Continue;
          E:= P;
          while (E <= Length(Line)) and
                CharInSet(Line[E], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(E);
          if E > P then Names.Add(Copy(Line, P, E - P));
        end;
      end;
      for I:= 0 to Names.Count - 1 do Result:= Result + [Names[I]];
    finally
      Names.Free;
      SL   .Free;
    end;
  end;

  { The declaring unit's root object, its class, and the MODULE-level verdict,
    computed once per declaring unit. ModuleOK is the owner's mixed-datamodule
    ruling taken literally: a module that also holds datasets forces the whole
    data machinery's construction order onto every form that binds to it, so it
    is never blessed however benign the member this reader happened to touch.

    FIELDS ONLY, and that is the answer to "does a method make a module
    behavioural". It does not: TdmStyles -- the canonical resource datamodule,
    the one the demotion exists for -- declares seven methods (DataModuleCreate,
    Timer1Timer, PrintScreenToPrinter, ...), so counting them would mean no real
    datamodule ever demotes and the whole arm would be dead code. A method
    REFERENCED from the reader's .dfm is behavioural; a method merely EXISTING
    on the module is not. }
  function DeclInfo(const ADeclPath: string): TDeclDfm;
  var
    S     : TSymbol ;
    Kids  : TDictionary<string, TSymbol>;
    Cls   : TMemberClass;
    NBad  : Integer ;
    TypeTx: string  ;
  begin
    if RootCache.TryGetValue(ADeclPath, Result) then Exit;
    Result:= Default(TDeclDfm);
    DfmRootObject(ADeclPath, Result.Root, Result.RootClass);
    Kids:= TDictionary<string, TSymbol>.Create;
    MemberCache.AddOrSetValue(ADeclPath, Kids);
    if Result.Root <> '' then
    begin
      { Prefer the class declared in the DECLARING unit itself; a same-named
        class elsewhere is not this .dfm's root. }
      for S in AStore.FindSymbolsByFile(ADeclPath) do
        if (S.Kind = skClass) and SameText(S.Name, Result.RootClass) then
        begin
          Result.RootClassId:= S.Id;
          Break;
        end;
      if Result.RootClassId <> 0 then
      begin
        NBad:= 0;
        Result.ModuleOK:= True;
        for S in AStore.FindSymbolsByFile(ADeclPath) do
        begin
          if S.ParentId <> Result.RootClassId then Continue;
          Kids.AddOrSetValue(LowerCase(S.Name), S);
          if S.Kind <> skField then Continue;
          Cls:= ClassifyType(S.Signature);
          if Cls = mcResource then Continue;
          Result.ModuleOK:= False;
          Inc(NBad);
          if NBad <= 5 then
          begin
            TypeTx:= Trim(S.Signature);
            if TypeTx = '' then TypeTx:= 'unknown type';
            if Result.BadFields <> '' then Result.BadFields:= Result.BadFields + ', ';
            Result.BadFields:= Result.BadFields + Format('%s (%s)', [S.Name, TypeTx]);
          end;
        end;
        if NBad > 5 then Result.BadFields:= Result.BadFields + Format(', +%d more', [NBad - 5]);
      end;
    end;
    RootCache.Add(ADeclPath, Result);
  end;

  { One member of the declaring unit's root class. Not found on the class ->
    mcUnresolved: inherited members from visual datamodule inheritance are rare,
    and absence is not evidence in the safe direction. }
  function ClassifyMember(const ADeclPath: string; const AInfo: TDeclDfm;
                          const AMember: string; out ATypeText: string): TMemberClass;
  var
    Kids: TDictionary<string, TSymbol>;
    S   : TSymbol;
  begin
    ATypeText:= 'unknown';
    Result   := mcUnresolved;
    if AInfo.RootClassId = 0 then Exit;
    if not MemberCache.TryGetValue(ADeclPath, Kids) then Exit;
    if not Kids.TryGetValue(LowerCase(AMember), S) then Exit;
    case S.Kind of
      skMethod, skProcedure, skFunction, skConstructor, skDestructor:
        begin
          { A cross-form .dfm reference to a METHOD is an event binding
            (`OnGetText = dmX.HandleGetText`) -- behaviour by definition. }
          ATypeText:= 'method';
          Result   := mcBehavioural;
        end;
      skField, skProperty:
        begin
          ATypeText:= Trim(S.Signature);
          if ATypeText = '' then ATypeText:= 'unknown type';
          Result   := ClassifyType(S.Signature);
        end;
    end;
  end;

  { The unit's own declared name ('uStyles'), falling back to the file stem when
    the unit symbol is missing -- a .dpr has no unit symbol and DOES appear as a
    reader (Micronite2027.dpr -> BASICS.PAS is one of the measured pairs). }
  function UnitNameOf(const APath: string): string;
  var
    S: TSymbol;
  begin
    for S in AStore.FindSymbolsByFile(APath) do
      if S.Kind = skUnit then
      begin
        Result:= S.QualifiedName;
        if Result = '' then Result:= S.Name;
        if Result <> '' then Exit;
      end;
    Result:= TPath.GetFileNameWithoutExtension(APath);
  end;

  { Anchor the finding at the `uses` entry that names the declaring unit, not at
    line 1 of the reader. The edge IS that line -- it is what the reader deletes
    when they act on the advice -- so pointing anywhere else makes the finding
    harder to act on than the grep it replaces. Falls back to 1:1. }
  procedure AnchorAtUses(const AReaderFid: Int64; const ADeclUnit: string;
                         var ALine, ACol: Integer);
  var
    U   : TUnitUse;
    Stem: string  ;
  begin
    ALine:= 1; ACol:= 1;
    Stem:= LowerCase(ADeclUnit);
    if LastDelimiter('.', Stem) > 0 then
      Stem:= Copy(Stem, LastDelimiter('.', Stem) + 1, MaxInt);
    for U in AStore.GetUnitUsesForFile(AReaderFid) do
    begin
      var N: string:= LowerCase(U.UnitName);
      if LastDelimiter('.', N) > 0 then N:= Copy(N, LastDelimiter('.', N) + 1, MaxInt);
      if N = Stem then
      begin
        ALine:= U.StartLine; ACol:= U.StartCol;
        Exit;
      end;
    end;
  end;

  { SQLite's GROUP_CONCAT gives NO ordering guarantee, so the names arrive in
    whatever order the aggregate happened to visit. Rendering that straight into
    the message makes the same finding differ between runs, which turns a report
    diff into noise and a golden file into a coin flip. }
  function SortedNames(const ACsv: string): string;
  var
    SL: TStringList;
  begin
    SL:= TStringList.Create;
    try
      SL.CaseSensitive:= False;
      SL.Delimiter    := ',';
      SL.StrictDelimiter:= True;
      SL.DelimitedText:= ACsv;
      SL.Sort;
      Result:= '';
      for var I: Integer:= 0 to SL.Count - 1 do
      begin
        if Trim(SL[I]) = '' then Continue;
        if Result <> '' then Result:= Result + ', ';
        Result:= Result + Trim(SL[I]);
      end;
    finally
      SL.Free;
    end;
  end;

var
  E             : TGlobalOnlyEdge;
  ReaderPath    : string         ;
  DeclPath      : string         ;
  DeclUnit      : string         ;
  ReaderUnit    : string         ;
  Names         : string         ;
  Info          : TDeclDfm       ;
  Members       : TArray<string> ;
  Bad           : string         ;
  NBad          : Integer        ;
  MemTx         : string         ;
  MemCls        : TMemberClass   ;
  AllResource   : Boolean        ;
  Ln, Cl        : Integer        ;
  F             : TLintFinding   ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings := TList<TLintFinding>.Create;
  { One .dfm read and one classification per DECLARING unit, not per finding:
    the measured shape is many readers of one declarer (24 of 37 pairs, and
    twelve of them uStyles). }
  RootCache  := TDictionary<string, TDeclDfm>.Create;
  TypeMemo   := TDictionary<string, TMemberClass>.Create;
  MemberCache:= TObjectDictionary<string, TDictionary<string, TSymbol>>.Create([doOwnsValues]);
  try
    for E in AStore.FindGlobalOnlyUsesEdges do
    begin
      ReaderPath:= AStore.GetFilePath(E.ReaderFileId);
      DeclPath  := AStore.GetFilePath(E.DeclFileId  );
      if (ReaderPath = '') or (DeclPath = '') then Continue;
      ReaderUnit:= UnitNameOf(ReaderPath);
      DeclUnit  := UnitNameOf(DeclPath  );
      Names     := SortedNames(E.GlobalNames);
      if Names = '' then Continue;

      Info:= DeclInfo(DeclPath);

      AnchorAtUses(E.ReaderFileId, DeclUnit, Ln, Cl);

      F:= Default(TLintFinding);
      F.RuleId  := 'global-only-uses-edge';
      F.Severity:= 'info';
      F.FilePath:= ReaderPath;
      F.StartLine:= Ln; F.StartCol:= Cl;
      F.EndLine  := Ln; F.EndCol  := Cl + Length(DeclUnit);
      { THE CURE CLAUSE IS CHOSEN BY THE CARRYING GLOBAL'S TYPE, and only an
        interface earns the word "inject" -- see the remarks above. }
      if E.GlobalCount = 1 then
        if E.AllInterfaceTyped then
          F.Message:= Format(
            '%s depends on %s for nothing but the global variable %s -- it is ' +
            'interface-typed, so injecting or relocating it deletes this uses edge',
            [ReaderUnit, DeclUnit, Names])
        else
          F.Message:= Format(
            '%s depends on %s for nothing but the global variable %s -- relocating ' +
            'it deletes this uses edge',
            [ReaderUnit, DeclUnit, Names])
      else
        if E.AllInterfaceTyped then
          F.Message:= Format(
            '%s depends on %s for nothing but %d global variables (%s) -- they are ' +
            'interface-typed, so injecting or relocating them deletes this uses edge',
            [ReaderUnit, DeclUnit, E.GlobalCount, Names])
        else
          F.Message:= Format(
            '%s depends on %s for nothing but %d global variables (%s) -- relocating ' +
            'them deletes this uses edge',
            [ReaderUnit, DeclUnit, E.GlobalCount, Names]);
      { THE DEMOTION, NOW CONDITIONAL. Without any demotion the rule tells the
        reader to break a dependency their .dfm silently puts back at design
        time, and the advice is not merely useless -- following it produces a
        unit that no longer compiles once the form is opened in the IDE. But an
        UNCONDITIONAL demotion is the opposite error: it blesses a form wired to
        a datamodule's datasets, which is exactly the coupling this rule exists
        to name. Both gates must pass before the edge is blessed. }
      Members:= DfmReferencedMembers(ReaderPath, Info.Root);
      if Length(Members) > 0 then
      begin
        AllResource:= True;
        Bad := '';
        NBad:= 0;
        for var M: string in Members do
        begin
          MemCls:= ClassifyMember(DeclPath, Info, M, MemTx);
          if MemCls = mcResource then Continue;
          AllResource:= False;
          Inc(NBad);
          if NBad <= 5 then
          begin
            if Bad <> '' then Bad:= Bad + ', ';
            Bad:= Bad + Format('%s (%s)', [M, MemTx]);
          end;
        end;
        if NBad > 5 then Bad:= Bad + Format(', +%d more', [NBad - 5]);

        if AllResource and Info.ModuleOK then
          { GATE 1 and GATE 2 both pass: every bound member is a resource and the
            module holds nothing else. This is the case the demotion was written
            for, and its wording is unchanged. }
          F.Message:= F.Message +
            Format(' (NOTE: %s references %s, so the DFM re-creates this dependency at ' +
                   'design time -- the uses edge cannot simply be deleted)',
                   [TPath.GetFileName(ChangeFileExt(ReaderPath, '.dfm')), Info.Root])
        else if not AllResource then
          { GATE 1 fails: the reader binds behaviour or something unidentifiable.
            The finding keeps full strength and says what to do instead, because
            plain silence here would hide that naively deleting the uses line
            still breaks the form in the IDE. }
          F.Message:= F.Message +
            Format(' (NOTE: %s binds %s of %s -- behavioural/data member(s); this coupling ' +
                   'forces construction order and blocks testing -- the cure is an interface ' +
                   'resolved through the container, not deleting the uses edge)',
                   [TPath.GetFileName(ChangeFileExt(ReaderPath, '.dfm')), Bad, Info.Root])
        else
          { GATE 2 fails: this reader only took a resource, but the module is
            MIXED. Worst case wins -- binding to it at all forces the whole
            module's construction order onto this form. }
          F.Message:= F.Message +
            Format(' (NOTE: %s binds %s, whose class %s also declares behavioural/data ' +
                   'field(s) (%s) -- the whole module''s construction order is forced onto ' +
                   'this form; the cure is an interface resolved through the container, not ' +
                   'deleting the uses edge)',
                   [TPath.GetFileName(ChangeFileExt(ReaderPath, '.dfm')), Info.Root,
                    Info.RootClass, Info.BadFields]);
      end;
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    MemberCache.Free;
    TypeMemo   .Free;
    RootCache  .Free;
    Findings   .Free;
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

class function TProjectLintRules.Run(const AStore: ISymbolStore; const ARuleId: string;
  const ASiblingStore: TSiblingStoreResolver; const ALibraryStore: ISymbolStore;
  const AOptInRules: TArray<string>): TArray<TLintFinding>;
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
  { unused-unit-in-uses: unit name -> lowercase set of the names it EXPORTS
    (its interface-section children). Owns its values. }
  ExportsOfUnit : TObjectDictionary<string, TDictionary<string, Boolean>>;
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
  TGlob: Int64;
  TDupD: Int64;
  { "Referenced at all?" as two sets, built with one scan each instead of two
    queries per symbol. See IsReferenced. }
  RefdIds       : TDictionary<Int64 , Boolean>;
  RefdNames     : TDictionary<string, Boolean>;

  function WantRule(const AId: string): Boolean;
  begin
    Result:= (ARuleId = '') or (ARuleId = AId);
  end;

  { Opt-in gate for a rule that is BOTH DefaultEnabled=False and expensive.
    WantRule answers "did --rule ask for it"; this answers "did the config turn
    it on". They are different questions and only the pair is safe. Without the
    second one, EVERY default lint-all runs the rule and the config filter
    downstream throws the findings away -- 0.92 s of full refs scan on ORM3
    client, permanently invisible because the printed output stays correct.
    An explicit `--rule <id>` counts as opting in: asking for a rule by name and
    getting silence would be the worse failure. }
  function OptedIn(const AId: string): Boolean;
  begin
    if ARuleId = AId then Exit(True);
    for var S: string in AOptInRules do
      if SameText(S, AId) then Exit(True);
    Result:= False;
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

  { The EXPORT SURFACE of AUnitName: the lowercase names of its interface-section
    children, from whichever store holds the unit -- project first, then library.

    This replaces a name-stem match that asked "does this file reference ANY
    symbol declared in a file whose stem matches the unit?". That question
    admits implementation-section locals, so a loop counter named I inside
    System.IniFiles made every file that uses a variable I "reference" it. Only
    what a unit EXPORTS can be imported, so only that can keep an import alive.

    parent_id is never NULL in this schema -- every symbol roots at its unit --
    so "top level" means the parent IS the unit symbol, which is what
    FindAllChildSymbols(U.Id) answers.

    An EMPTY result means "not found in either store", and the caller treats
    that as DO NOT REPORT. Silence about a unit nothing can see beats guessing. }
  function ExportNamesFor(const AUnitName: string): TDictionary<string, Boolean>;
    procedure CollectFrom(const AFrom: ISymbolStore; ATo: TDictionary<string, Boolean>);
    var
      U : TSymbol;
      Ch: TSymbol;
    begin
      if AFrom = nil then Exit;
      for U in AFrom.FindSymbolsByExactName(AUnitName) do
      begin
        if U.Kind <> skUnit then Continue;
        for Ch in AFrom.FindAllChildSymbols(U.Id) do
          if SameText(Ch.Section, 'interface') and (Ch.Name <> '') then
          begin
            { BOTH SIDES must be stripped of type parameters. A generic export is
              stored under its DECLARED name, `TComparer<T>`, while a use site
              references `TComparer` (or `TComparer<TRuleInfo>`), so a literal
              match fires on neither. Stripping only the reference side -- which
              is what I did first -- changes nothing, and the measurement said so:
              91 findings before and 91 after. }
            ATo.AddOrSetValue(LowerCase(Ch.Name), True);
            var LtPos: Integer:= Pos('<', Ch.Name);
            if LtPos > 1 then ATo.AddOrSetValue(LowerCase(Copy(Ch.Name, 1, LtPos - 1)), True);
          end;
        if ATo.Count > 0 then Break;   { first store that actually has it wins }
      end;
    end;
  var
    Cached: TDictionary<string, Boolean>;
  begin
    if ExportsOfUnit.TryGetValue(AUnitName, Cached) then Exit(Cached);
    Result:= TDictionary<string, Boolean>.Create;
    CollectFrom(AStore, Result);
    if Result.Count = 0 then CollectFrom(ALibraryStore, Result);
    ExportsOfUnit.Add(AUnitName, Result);
  end;

  { A referenced name, plus its GENERIC BASE.

    A reference to TComparer<TRuleInfo>.Construct arrives with the type
    arguments attached -- 'TComparer<TRuleInfo>' -- and the unit exports plain
    'TComparer', so a literal match never fires. Measured on drag-lint's own
    source: 15 of 91 unused-unit-in-uses findings were System.Generics.Defaults
    in files that demonstrably call TComparer<T>.Construct. Every one was a
    FALSE POSITIVE of exactly this shape.

    Both forms are recorded: the base for the export match, the full text
    because a non-generic name is its own base. }
  procedure AddRefName(ASet: TDictionary<string, Boolean>; const AName: string);
  var
    Lt: Integer;
  begin
    if AName = '' then Exit;
    ASet.AddOrSetValue(LowerCase(AName), True);
    Lt:= Pos('<', AName);
    if Lt > 1 then ASet.AddOrSetValue(LowerCase(Copy(AName, 1, Lt - 1)), True);
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
  ExportsOfUnit:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  RefdIds    := TDictionary<Int64 , Boolean>      .Create;
  RefdNames  := TDictionary<string, Boolean>      .Create;
  Prof:= GetEnvironmentVariable('DRAGLINT_PROFILE') <> '';
  TCirc:= 0; TEnum:= 0; TRts:= 0; TUuiu:= 0; TGod:= 0; TUpub:= 0; TUpriv:= 0; TAccess:= 0; TOuter:= 0;
  TGlob:= 0; TDupD:= 0;
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

    { global-only-uses-edge: whole-refs-graph pass (not per-file), and the ONE
      rule here that is gated on OptedIn as well as WantRule -- see the gate's
      own comment for why both are needed. }
    if WantRule('global-only-uses-edge') and OptedIn('global-only-uses-edge') then
      for var Gf in CollectGlobalOnlyUsesEdges(AStore, ALibraryStore) do Findings.Add(Gf);
    Inc(TGlob, Tick - T0); T0:= Tick;

    { duplicate-global-decl: whole-symbols pass (not per-file). ON by default
      and NOT OptedIn-gated -- 0.05 s on the 144 MB client index, symbols only,
      no refs join, so running it and discarding it is not the defect the
      sibling's gate exists to prevent. }
    if WantRule('duplicate-global-decl') then
      for var Df in CollectDuplicateGlobalDecls(AStore) do Findings.Add(Df);
    Inc(TDupD, Tick - T0); T0:= Tick;

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
            { NAMES referenced by this file, lowercased -- not unit stems.
              The receiver is included because `IniFile.ReadString` references
              TIniFile through the receiver's type, not through NameText. }
            Refs:= AStore.GetReferencesFromFile(Fid);
            for Ref in Refs do
            begin
              AddRefName(RefdUnitStems, Ref.NameText    );
              AddRefName(RefdUnitStems, Ref.ReceiverText);
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
              { WHAT THE UNIT EXPORTS is the only thing an import can keep alive.
                Conservative in the same way as before -- an empty export set
                means the unit is in NEITHER the project nor the library index,
                and an unseen unit is never reported. That gate is load-bearing:
                removing it yields 208 findings on DataCopy, nearly all wrong. }
              var UnitExports: TDictionary<string, Boolean>:= ExportNamesFor(U.UnitName);
              if UnitExports.Count = 0 then Continue;
              var UsesAnyExport: Boolean:= False;
              for var ExportName: string in UnitExports.Keys do
                if RefdUnitStems.ContainsKey(ExportName) then
                begin
                  UsesAnyExport:= True;
                  Break;
                end;
              if not UsesAnyExport then
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
              begin
                { A SHARED UNIT MAKES THIS RULE'S CONCLUSION UNPROVABLE, so say
                  what is actually known instead of asserting dead API.

                  IsReferenced asks ONE project's index. YADF, YADFOT and
                  YADFSetup are three projects over one source folder, so a
                  routine defined in a shared unit and called only from a sibling
                  is unreferenced HERE and very much alive. Measured 2026-08-16:
                  5 of 6 YADF findings were false this way -- SaveOptionsToIni
                  alone has 10 caller refs in sibling DBs.

                  NOT SUPPRESSED, deliberately. The one genuine finding in that
                  set (OptionsHelpText, 0 refs anywhere) lives in YADF.Options.pas,
                  which is itself shared -- skipping shared units would have
                  traded a false positive for a false negative in the same file.
                  So the finding stands and the MESSAGE carries the caveat, with
                  the sibling projects named from the unit's own dl:shared header
                  so the reader knows exactly where to look before deleting.
                  Severity drops to hint because a question this index cannot
                  answer should not block a true-zero run.
                  See docs\INBOX-unused-public-symbol-lies-on-shared-units.md. }
                var UPath  : string          := AStore.GetFilePath(Sym.FileId);
                var UProjs : TArray<string>  := nil;
                if UPath <> '' then UProjs:= DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf(UPath);
                if Length(UProjs) > 1 then
                begin
                  { NOW WE ACTUALLY GO AND LOOK. The message above has been telling
                    the reader to check the siblings by hand since the caveat was
                    added; with a resolver in hand the engine can answer it, and an
                    answerable question should not be delegated to a human.

                    THE RELATIONSHIP IS DECLARED, so consulting these DBs does not
                    violate the authoritative-set rule (library + project, nothing
                    else): the unit's OWN `dl:shared` header names exactly these
                    projects. This is not a name-match fishing trip across every
                    index on the box -- it is following a statement the source
                    makes about itself.

                    Measured on YADF 2026-08-17, and it is what validates the
                    name-keyed predicate below: of the 9 findings, the 6 false ones
                    each have >=1 caller ref in a named sibling, while the genuine
                    one (OptionsHelpText) has 0 in all three. A declaration site
                    does not count itself as a caller, which is why 0 means 0.

                    THREE OUTCOMES, and the third is the one that is easy to get
                    wrong: found alive -> suppress; checked everything and found
                    nothing -> report, and say the siblings WERE checked, because
                    the old wording ("check there before treating it as dead") is
                    now stale advice; could not check some sibling -> report with
                    the old wording, since an unopened index is not evidence of
                    absence. }
                  var LiveIn    : string  := '';
                  var CheckedAll: Boolean := Assigned(ASiblingStore);
                  if Assigned(ASiblingStore) then
                    for var PN in UProjs do
                    begin
                      var Sib: ISymbolStore := ASiblingStore(PN);
                      if Sib = nil then begin CheckedAll:= False; Continue; end;
                      if Length(Sib.FindCallersByName(Sym.Name)) > 0 then
                      begin
                        LiveIn:= PN;
                        Break;
                      end;
                    end;
                  { LiveIn <> '' means a project that compiles this same unit
                    references the routine: it is alive, and there is no finding
                    to make. }
                  if LiveIn = '' then
                    if CheckedAll then
                      Add('unused-public-symbol', 'hint',
                        Format('Exported routine %s is not referenced in this project, nor in the project(s) its unit is shared with (%s).',
                               [Sym.Name, string.Join(', ', UProjs)]), Sym)
                    else
                      Add('unused-public-symbol', 'hint',
                        Format('Exported routine %s is not referenced within this project. Its unit is shared with %s -- check there before treating it as dead.',
                               [Sym.Name, string.Join(', ', UProjs)]), Sym);
                end
                else
                  Add('unused-public-symbol', 'info',
                    Format('Exported routine %s has no references in the index -- possible dead public API', [Sym.Name]), Sym);
              end;
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
      ProfLine('global-only-uses-edge'     , TGlob  );
      ProfLine('duplicate-global-decl'     , TDupD  );
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
    ExportsOfUnit.Free;
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
