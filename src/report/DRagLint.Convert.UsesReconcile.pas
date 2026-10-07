unit DRagLint.Convert.UsesReconcile;

{
  C9 (1.27.0): convert-apply's USES RECONCILIATION.

  The editor writes unit rules atomically -- every conversion appends
  '#unuse <From unit>' + '#use <To unit>' -- and leaves "is the unit still
  needed, is it already there" to the engine. This unit answers those
  questions for ONE unit, from a RE-INDEX OF THE CONVERTED OUTPUT (owner ruling
  3, 2026-10-06): the converted .pas and .dfm text are run through the
  indexer's own extractor (IParser.Parse -- TDelphi13Parser / TDFMParser, the
  rows `index` would store) IN MEMORY. No database is written, so the dry run
  shows the same plan --apply writes, and the uses edits stay ordinary plan
  edits in convert-apply's single all-or-nothing write.

  THE VERDICTS (owner rulings 2026-10-06):
    * WATCH LIST. A unit a #unuse / #useswap names is KEPT only while a
      component the converted .dfm streams has a class declared in it. A need
      from .pas code alone does NOT keep it (ruling 1: EDBEngineError, Session,
      a 'var T: TTable' are not valid in the target application; the compile
      errors are the signal) -- the unit is removed and the references left
      dangling are reported on the remove row.
    * A watched unit no --db knows is KEPT (Q3), with a warning.
    * NEW NAMES. A bare name the converted .pas references that the original
      did not (a cast template's routine or enum value), that the unit does not
      declare and that no unit in the post-plan uses (nor System / SysInit)
      declares, gets its declaring unit added -- interface uses when it is
      referenced above 'implementation'. A name two units declare is REPORTED
      (ambiguous) and never picked.
    * Fail-safe is KEEP: a re-index that fails keeps every watched unit and
      adds nothing ('degraded').
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Interfaces,
  DRagLint.Core.Model,
  DRagLint.Convert.Rules,
  DRagLint.Convert.UnitRules;

const
  /// <summary>uses[].reason of a `kept` row whose unit a .dfm component needs.</summary>
  KEEP_REASON_DFM        = 'still needed by the .dfm';
  /// <summary>uses[].reason of a `kept` row whose unit no --db indexes (Q3).</summary>
  KEEP_REASON_UNVERIFIED = 'no --db indexes this unit';
  /// <summary>uses[].reason of a `kept` row when the re-index failed.</summary>
  KEEP_REASON_DEGRADED   = 're-index of the converted output failed';
  /// <summary>uses_unresolved[].reason: two or more units declare the name.</summary>
  UNRESOLVED_AMBIGUOUS   = 'ambiguous';
  /// <summary>uses_unresolved[].reason: no --db declares the name.</summary>
  UNRESOLVED_NOT_FOUND   = 'not-found';
  /// <summary>needed_by / TUsesNeed.Section of a .dfm component.</summary>
  NEED_SECTION_DFM       = 'dfm';
  /// <summary>How many needed_by entries a row carries at most.</summary>
  NEEDED_BY_MAX          = 5;

type
  /// <summary>One unit that declares a name, and the --db it was found in.</summary>
  TUsesCandidate = record
    UnitName: string;
    Db      : string;
  end;

  /// <summary>A name the conversion introduced whose unit was NOT added
  /// (apply/1 uses_unresolved[]).</summary>
  TUsesUnresolved = record
    Name      : string;
    Line      : Integer;
    Section   : string;
    Reason    : string;   { UNRESOLVED_AMBIGUOUS / UNRESOLVED_NOT_FOUND }
    Candidates: TArray<TUsesCandidate>;
  end;

  /// <summary>The indexed unit set of a run's --db stores, with the
  /// declaring-unit lookups the reconciler makes. One per convert-apply run,
  /// shared by every unit of a batch.</summary>
  /// <remarks>Not thread-safe. Unit names are the indexed .pas files' base
  /// names ('Bde.DBTables'). Built lazily on first use: one files-table read
  /// per store.</remarks>
  TUsesUnitIndex = class
  private
    FStores   : TArray<ISymbolStore>;
    FDbs      : TArray<string>;
    FBuilt    : Boolean;
    FStems    : TDictionary<string, string>;            { lower stem -> stem }
    FByTail   : TObjectDictionary<string, TList<string>>; { lower last segment -> stems }
    FDeclMemo : TDictionary<string, TArray<TUsesCandidate>>;
    FPathMemo : TDictionary<string, string>;
    procedure Build;
    function StemOf(AStore: Integer; AFileId: Int64): string;
  public
    /// <summary>Wraps the run's stores.</summary>
    /// <param name="AStores">The --db stores, in --db order. Not owned.</param>
    /// <param name="ADbs">Their paths, index-aligned (may be shorter: '' then).</param>
    constructor Create(const AStores: TArray<ISymbolStore>; const ADbs: TArray<string>);
    destructor Destroy; override;
    /// <summary>The indexed unit a uses spelling names, or '' when none or
    /// more than one alias matches.</summary>
    /// <param name="AName">A uses entry or rule spelling ('DBTables').</param>
    /// <returns>The indexed stem ('Bde.DBTables'), or ''.</returns>
    function Resolve(const AName: string): string;
    /// <summary>True when some --db indexes the unit AName names (exactly or
    /// as a scope alias).</summary>
    /// <param name="AName">A uses entry spelling.</param>
    /// <returns>True when known.</returns>
    function IsKnown(const AName: string): Boolean;
    /// <summary>C9 R9: two spellings name one unit -- equal, or one is
    /// '&lt;scope&gt;.&lt;other&gt;' and they are not two distinct indexed units.</summary>
    /// <param name="A">One spelling.</param>
    /// <param name="B">The other.</param>
    /// <returns>True when they are the same unit.</returns>
    function SameUnit(const A, B: string): Boolean;
    /// <summary>The distinct units that declare AName at unit level and
    /// visibly (not in an implementation section), across every store.</summary>
    /// <param name="AName">A bare identifier.</param>
    /// <param name="AClassesOnly">True: class/interface/record declarations only.</param>
    /// <returns>Candidates in store order; memoised.</returns>
    function DeclaringUnits(const AName: string; AClassesOnly: Boolean): TArray<TUsesCandidate>;
    /// <summary>The lowercase names unit AUnit exports: its interface-level
    /// declarations, unscoped enum values, and (AHelpers) its type-helper
    /// members.</summary>
    /// <param name="AUnit">An indexed stem.</param>
    /// <param name="AHelpers">True for the helper-member half only.</param>
    /// <returns>The names (a new array per call).</returns>
    function ExportNames(const AUnit: string; AHelpers: Boolean): TArray<string>;
  end;

  /// <summary>What ReconcileUses needs to know about one unit.</summary>
  TUsesReconcileInput = record
    UnitPas     : string;              { the unit's path }
    OrigPas     : string;              { its text as read from disk }
    ConvPas     : string;              { its text after every non-uses plan edit }
    ConvDfm     : string;              { the sibling .dfm after the plan; '' when none }
    Rules       : TConversionRuleSet;  { the book }
    ExtraAdds   : TArray<string>;      { units the #convert surface adds (To types) }
    HandledNames: TArray<string>;      { names the #convert surface resolves itself (To types) }
  end;

  /// <summary>ReconcileUses' answer.</summary>
  /// <remarks>Status is 'on' or 'degraded' (Detail says why). Needs goes to
  /// PlanUnitRules; Unresolved to apply/1 uses_unresolved[].</remarks>
  TUsesReconcileResult = record
    Status    : string;
    Detail    : string;
    Needs     : TUsesNeeds;
    Unresolved: TArray<TUsesUnresolved>;
  end;

/// <summary>Reconciles one unit's uses clauses against the re-indexed
/// converted output (see the unit header for the verdicts).</summary>
/// <param name="AIndex">The run's unit index. Not owned.</param>
/// <param name="AIn">The unit, its original and converted text, the book.</param>
/// <returns>The verdicts; never raises (a failure is Status 'degraded').</returns>
/// <remarks>Reads the stores only; writes nothing. Pinned by
/// tests\autotest\run_convert_apply_uses_reconcile.ps1.</remarks>
function ReconcileUses(AIndex: TUsesUnitIndex; const AIn: TUsesReconcileInput): TUsesReconcileResult;

/// <summary>Runs the indexer's extractor over text in memory -- the rows
/// `index` would store for it, written nowhere.</summary>
/// <param name="APath">The file's path; its extension picks the parser
/// (.dfm -> TDFMParser, else TDelphi13Parser with usage refs).</param>
/// <param name="AText">The text to parse.</param>
/// <returns>The parse result.</returns>
/// <exception cref="Exception">Whatever the parser raises.</exception>
function ReindexText(const APath, AText: string): TParseResult;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  System.Generics.Defaults,
  DRagLint.Parser.Delphi13,
  DRagLint.Parser.DFM;

const
  SECTION_INTF = 'interface';
  SECTION_IMPL = 'implementation';
  IMPLICIT_UNITS: array[0..1] of string = ('System', 'SysInit');

{ ---- TUsesUnitIndex ---------------------------------------------------------- }

constructor TUsesUnitIndex.Create(const AStores: TArray<ISymbolStore>; const ADbs: TArray<string>);
begin
  inherited Create;
  FStores  := AStores;
  FDbs     := ADbs;
  FStems   := TDictionary<string, string>.Create;
  FByTail  := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FDeclMemo:= TDictionary<string, TArray<TUsesCandidate>>.Create;
  FPathMemo:= TDictionary<string, string>.Create;
end;

destructor TUsesUnitIndex.Destroy;
begin
  FPathMemo.Free;
  FDeclMemo.Free;
  FByTail.Free;
  FStems.Free;
  inherited Destroy;
end;

procedure TUsesUnitIndex.Build;
var
  Stem, Tail: string;
  L         : TList<string>;
begin
  if FBuilt then Exit;
  FBuilt:= True;
  for var St: ISymbolStore in FStores do
    for var FS: TFileStamp in St.GetAllFileStamps do
    begin
      if not SameText(ExtractFileExt(FS.Path), '.pas') then Continue;
      Stem:= TPath.GetFileNameWithoutExtension(FS.Path);
      if FStems.ContainsKey(LowerCase(Stem)) then Continue;
      FStems.Add(LowerCase(Stem), Stem);
      Tail:= LowerCase(Stem);
      if Tail.Contains('.') then Tail:= Tail.Substring(Tail.LastIndexOf('.') + 1);
      if not FByTail.TryGetValue(Tail, L) then
      begin
        L:= TList<string>.Create;
        FByTail.Add(Tail, L);
      end;
      L.Add(Stem);
    end;
end;

function TUsesUnitIndex.Resolve(const AName: string): string;
var
  L   : TList<string>;
  Low : string;
begin
  Build;
  Low:= LowerCase(Trim(AName));
  if FStems.TryGetValue(Low, Result) then Exit;
  Result:= '';
  if Low.Contains('.') then
  begin
    { 'Bde.DBTables' written, 'DBTables' indexed }
    var Tail: string:= Low.Substring(Low.LastIndexOf('.') + 1);
    if FStems.TryGetValue(Tail, Result) then Exit;
    Exit('');
  end;
  if FByTail.TryGetValue(Low, L) and (L.Count = 1) then Result:= L[0];
end;

function TUsesUnitIndex.IsKnown(const AName: string): Boolean;
var
  L: TList<string>;
begin
  Result:= Resolve(AName) <> '';
  if not Result then
  begin
    Build;
    Result:= FByTail.TryGetValue(LowerCase(Trim(AName)), L) and (L.Count > 0);
  end;
end;

function TUsesUnitIndex.SameUnit(const A, B: string): Boolean;
var
  LA, LB, Short, Long: string;
begin
  LA:= LowerCase(Trim(A));
  LB:= LowerCase(Trim(B));
  if LA = LB then Exit(True);
  if EndsStr('.' + LB, LA) then begin Long:= LA; Short:= LB; end
  else if EndsStr('.' + LA, LB) then begin Long:= LB; Short:= LA; end
  else Exit(False);
  Build;
  { 'DB' and 'Data.DB' are one unit -- unless the index holds BOTH as units }
  Result:= not (FStems.ContainsKey(Short) and FStems.ContainsKey(Long));
end;

function TUsesUnitIndex.StemOf(AStore: Integer; AFileId: Int64): string;
var
  Key: string;
begin
  Key:= IntToStr(AStore) + ':' + IntToStr(AFileId);
  if FPathMemo.TryGetValue(Key, Result) then Exit;
  Result:= TPath.GetFileNameWithoutExtension(FStores[AStore].GetFilePath(AFileId));
  FPathMemo.Add(Key, Result);
end;

function TUsesUnitIndex.DeclaringUnits(const AName: string; AClassesOnly: Boolean): TArray<TUsesCandidate>;
const
  CLASS_KINDS: set of TSymbolKind = [skClass, skInterface, skRecord];
  UNIT_LEVEL : set of TSymbolKind = [skClass, skInterface, skRecord, skEnum, skEnumValue, skProcedure,
                                     skFunction, skVarDecl, skConstDecl, skTypeAlias];
var
  Key : string;
  Seen: TList<string>;
begin
  Key:= LowerCase(AName) + '|' + BoolToStr(AClassesOnly, True);
  if FDeclMemo.TryGetValue(Key, Result) then Exit;
  Result:= nil;
  Seen  := TList<string>.Create;
  try
    for var I: Integer:= 0 to High(FStores) do
      for var S: TSymbol in FStores[I].FindSymbolsByExactName(AName) do
      begin
        if (S.FileId <= 0) or SameText(S.Section, SECTION_IMPL) then Continue;
        if AClassesOnly and not (S.Kind in CLASS_KINDS) then Continue;
        if not (S.Kind in UNIT_LEVEL) then Continue;
        var Stem: string:= StemOf(I, S.FileId);
        if not SameText(ExtractFileExt(FStores[I].GetFilePath(S.FileId)), '.pas') then Continue;
        if (Stem = '') or Seen.Contains(LowerCase(Stem)) then Continue;
        Seen.Add(LowerCase(Stem));
        var C: TUsesCandidate:= Default(TUsesCandidate);
        C.UnitName:= Stem;
        C.Db      := if I <= High(FDbs) then FDbs[I] else '';
        Result:= Result + [C];
      end;
  finally
    Seen.Free;
  end;
  FDeclMemo.Add(Key, Result);
end;

function TUsesUnitIndex.ExportNames(const AUnit: string; AHelpers: Boolean): TArray<string>;
begin
  Result:= nil;
  for var St: ISymbolStore in FStores do
  begin
    for var U: TSymbol in St.FindSymbolsByExactName(AUnit) do
    begin
      if U.Kind <> skUnit then Continue;
      if AHelpers then
        Exit(St.FindHelperMemberNamesInUnit(U.Id));
      for var Ch: TSymbol in St.FindAllChildSymbols(U.Id) do
      begin
        if not SameText(Ch.Section, SECTION_INTF) or (Ch.Name = '') then Continue;
        var N: string:= Ch.Name;
        if N.Contains('<') then N:= N.Substring(0, N.IndexOf('<'));
        Result:= Result + [LowerCase(N)];
        if Ch.Kind = skEnum then
          for var V: TSymbol in St.FindAllChildSymbols(Ch.Id) do
            if V.Kind = skEnumValue then Result:= Result + [LowerCase(V.Name)];
      end;
      Exit;
    end;
  end;
end;

{ ---- the re-index ------------------------------------------------------------ }

function ReindexText(const APath, AText: string): TParseResult;
var
  Parser: IParser;
begin
  if SameText(ExtractFileExt(APath), '.dfm') then
    Parser:= TDFMParser.Create
  else
  begin
    var DP: TDelphi13Parser:= TDelphi13Parser.Create;
    DP.EmitUsageRefs:= True;  { a project index is deep: usage refs included }
    Parser:= DP;
  end;
  Result:= Parser.Parse(TEncoding.ANSI.GetBytes(AText), APath);
end;

{ ---- the reconciler ----------------------------------------------------------- }

type
  { One name a .pas references, where it first appears, and whether any
    occurrence is bare (not after a '.') / above 'implementation'. }
  TNameUse = record
    Name     : string;
    Line     : Integer;
    Bare     : Boolean;
    BareLine : Integer;
    InIntf   : Boolean;
  end;

  TReconciler = class
  private
    FIx      : TUsesUnitIndex;
    FIn      : TUsesReconcileInput;
    FRes     : TUsesReconcileResult;
    FEntries : TArray<TUsesEntryInfo>;
    FWatch   : TArray<TWatchUnit>;
    FRemoved : TList<string>;           { entries the reconciler removes }
    FPostPlan: TList<string>;           { the unit names reachable after the plan }
    FConvUses: TDictionary<string, TNameUse>;
    FOrigUses: TDictionary<string, TNameUse>;
    FOwn     : TDictionary<string, Boolean>;
    function WatchedBy(const AEntry: string): Boolean;
    procedure CollectNames(const AText: string; const AParse: TParseResult; ADict: TDictionary<string, TNameUse>);
    function ImplementationLine(const AText: string): Integer;
    procedure DecideWatch(const ADfm: TParseResult; ADfmOk: Boolean);
    procedure BuildPostPlan;
    function Reachable(const ACands: TArray<TUsesCandidate>): Boolean;
    procedure PlanNewNames;
    procedure PlanDangling;
  public
    constructor Create(AIndex: TUsesUnitIndex; const AIn: TUsesReconcileInput);
    destructor Destroy; override;
    function Run: TUsesReconcileResult;
  end;

function Need(const AName: string; ALine: Integer; const ASection: string): TUsesNeed;
begin
  Result.Name   := AName;
  Result.Line   := ALine;
  Result.Section:= ASection;
end;

constructor TReconciler.Create(AIndex: TUsesUnitIndex; const AIn: TUsesReconcileInput);
begin
  inherited Create;
  FIx      := AIndex;
  FIn      := AIn;
  FRemoved := TList<string>.Create;
  FPostPlan:= TList<string>.Create;
  FConvUses:= TDictionary<string, TNameUse>.Create;
  FOrigUses:= TDictionary<string, TNameUse>.Create;
  FOwn     := TDictionary<string, Boolean>.Create;
end;

destructor TReconciler.Destroy;
begin
  FOwn.Free;
  FOrigUses.Free;
  FConvUses.Free;
  FPostPlan.Free;
  FRemoved.Free;
  inherited Destroy;
end;

function TReconciler.WatchedBy(const AEntry: string): Boolean;
begin
  for var W: TWatchUnit in FWatch do
    if FIx.SameUnit(W.UnitName, AEntry) then Exit(True);
  Result:= False;
end;

function TReconciler.ImplementationLine(const AText: string): Integer;
var
  Lines: TArray<string>;
begin
  Lines:= AText.Replace(#13#10, #10).Split([#10]);
  for var I: Integer:= 0 to High(Lines) do
  begin
    var T: string:= LowerCase(Trim(Lines[I]));
    if (T = SECTION_IMPL) or T.StartsWith(SECTION_IMPL + ' ') then Exit(I + 1);
  end;
  Result:= MaxInt;
end;

{ Every name a ref of AParse names, with its first line, whether one
  occurrence is BARE (the character before it, blanks skipped, is not a '.')
  and whether one sits above 'implementation'. }
procedure TReconciler.CollectNames(const AText: string; const AParse: TParseResult;
  ADict: TDictionary<string, TNameUse>);
var
  Lines  : TArray<string>;
  ImplAt : Integer;
  U      : TNameUse;
begin
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  ImplAt:= ImplementationLine(AText);
  for var R: TReference in AParse.References do
  begin
    if (R.NameText = '') or (R.StartLine < 1) or (R.StartLine > Length(Lines)) then Continue;
    var S: string:= Lines[R.StartLine - 1];
    var P: Integer:= R.StartCol - 1;
    while (P >= 1) and CharInSet(S[P], [' ', #9]) do Dec(P);
    var IsBare: Boolean:= not ((P >= 1) and (S[P] = '.'));
    var Key: string:= LowerCase(R.NameText);
    if not ADict.TryGetValue(Key, U) then
    begin
      U:= Default(TNameUse);
      U.Name:= R.NameText;
      U.Line:= R.StartLine;
    end;
    if IsBare and not U.Bare then
    begin
      U.Bare    := True;
      U.BareLine:= R.StartLine;
    end;
    if IsBare and (R.StartLine < ImplAt) then U.InIntf:= True;
    ADict.AddOrSetValue(Key, U);
  end;
end;

procedure TReconciler.DecideWatch(const ADfm: TParseResult; ADfmOk: Boolean);
var
  Keeps: TList<TUsesKeep>;
begin
  Keeps:= TList<TUsesKeep>.Create;
  try
    for var E: TUsesEntryInfo in FEntries do
    begin
      if not WatchedBy(E.Name) then Continue;
      var K: TUsesKeep:= Default(TUsesKeep);
      K.UnitName:= E.Name;
      K.Action  := 'kept';
      if not ADfmOk then
        K.Reason:= KEEP_REASON_DEGRADED
      else if not FIx.IsKnown(E.Name) then
        K.Reason:= KEEP_REASON_UNVERIFIED
      else
        { ruling 2: only a .dfm component keeps a watched unit }
        for var S: TSymbol in ADfm.Symbols do
        begin
          if S.Kind <> skComponent then Continue;
          for var C: TUsesCandidate in FIx.DeclaringUnits(S.Signature, True) do
            if FIx.SameUnit(C.UnitName, E.Name) then
            begin
              K.Reason:= KEEP_REASON_DFM;
              if Length(K.NeededBy) < NEEDED_BY_MAX then
                K.NeededBy:= K.NeededBy + [Need(S.Name + ': ' + S.Signature, S.StartLine, NEED_SECTION_DFM)];
              Break;
            end;
        end;
      if K.Reason <> '' then Keeps.Add(K)
      else FRemoved.Add(E.Name);
    end;
    FRes.Needs.Keeps:= Keeps.ToArray;
  finally
    Keeps.Free;
  end;
end;

procedure TReconciler.BuildPostPlan;
begin
  for var E: TUsesEntryInfo in FEntries do
    if not FRemoved.Contains(E.Name) then FPostPlan.Add(E.Name);
  for var U: string in FIn.ExtraAdds do FPostPlan.Add(U);
  for var U: string in IMPLICIT_UNITS do FPostPlan.Add(U);
  FPostPlan.Add(TPath.GetFileNameWithoutExtension(FIn.UnitPas));
  for var R: TConversionRule in FIn.Rules.Rules do
    case R.Kind of
      rkUse: FPostPlan.Add(R.UnitName);
      rkUseSwap:
        for var E: TUsesEntryInfo in FEntries do
          if FIx.SameUnit(E.Name, R.UnitName) then
            for var N: string in R.UnitsAdd do FPostPlan.Add(N);
    end;
end;

function TReconciler.Reachable(const ACands: TArray<TUsesCandidate>): Boolean;
begin
  for var C: TUsesCandidate in ACands do
    for var U: string in FPostPlan do
      if FIx.SameUnit(C.UnitName, U) then Exit(True);
  Result:= False;
end;

{ R7 / R8: a bare name the converted .pas references and the original did not. }
procedure TReconciler.PlanNewNames;
var
  Adds: TList<TUsesReconAdd>;
  Orig: TNameUse;
begin
  Adds:= TList<TUsesReconAdd>.Create;
  try
    for var P: TPair<string, TNameUse> in FConvUses do
    begin
      var U: TNameUse:= P.Value;
      if not U.Bare or FOwn.ContainsKey(P.Key) then Continue;
      if FOrigUses.TryGetValue(P.Key, Orig) and Orig.Bare then Continue;
      if MatchText(U.Name, FIn.HandledNames) then Continue;
      var Cands: TArray<TUsesCandidate>:= nil;
      for var C: TUsesCandidate in FIx.DeclaringUnits(U.Name, False) do
        if not SameText(C.UnitName, TPath.GetFileNameWithoutExtension(FIn.UnitPas)) then Cands:= Cands + [C];
      if Reachable(Cands) then Continue;
      { a unit the book removes is never added back (ADD would win over it) }
      var Kept: TArray<TUsesCandidate>:= nil;
      for var C: TUsesCandidate in Cands do
      begin
        var Removed: Boolean:= False;
        for var R: string in FRemoved do
          if FIx.SameUnit(R, C.UnitName) then Removed:= True;
        if not Removed then Kept:= Kept + [C];
      end;
      if (Length(Cands) > 0) and (Length(Kept) = 0) then Continue;
      var Section: string:= if U.InIntf then SECTION_INTF else SECTION_IMPL;
      if Length(Kept) = 1 then
      begin
        var Merged: Boolean:= False;
        for var I: Integer:= 0 to Adds.Count - 1 do
          if SameText(Adds[I].UnitName, Kept[0].UnitName) then
          begin
            var A: TUsesReconAdd:= Adds[I];
            A.ToInterface:= A.ToInterface or U.InIntf;
            if Length(A.NeededBy) < NEEDED_BY_MAX then A.NeededBy:= A.NeededBy + [Need(U.Name, U.BareLine, Section)];
            Adds[I]:= A;
            Merged:= True;
          end;
        if not Merged then
        begin
          var A: TUsesReconAdd:= Default(TUsesReconAdd);
          A.UnitName   := Kept[0].UnitName;
          A.ToInterface:= U.InIntf;
          A.NeededBy   := [Need(U.Name, U.BareLine, Section)];
          Adds.Add(A);
        end;
        Continue;
      end;
      var Un: TUsesUnresolved:= Default(TUsesUnresolved);
      Un.Name      := U.Name;
      Un.Line      := U.BareLine;
      Un.Section   := Section;
      Un.Reason    := if Length(Kept) = 0 then UNRESOLVED_NOT_FOUND else UNRESOLVED_AMBIGUOUS;
      Un.Candidates:= Kept;
      FRes.Unresolved:= FRes.Unresolved + [Un];
    end;
    FRes.Needs.Adds:= Adds.ToArray;
  finally
    Adds.Free;
  end;
end;

{ Ruling 1: a removed unit's exports the converted .pas still references --
  reported on the remove row, never a reason to keep it. }
procedure TReconciler.PlanDangling;
var
  U: TNameUse;
begin
  for var E: string in FRemoved do
  begin
    var Stem: string:= FIx.Resolve(E);
    if Stem = '' then Continue;
    var D: TUsesKeep:= Default(TUsesKeep);
    D.UnitName:= E;
    for var Pass: Integer:= 0 to 1 do
      for var N: string in FIx.ExportNames(Stem, Pass = 1) do
      begin
        if not FConvUses.TryGetValue(N, U) then Continue;
        if (Pass = 0) and not U.Bare then Continue;
        if FOwn.ContainsKey(N) then Continue;
        { still declared by a unit that stays: not dangling }
        if (Pass = 0) and Reachable(FIx.DeclaringUnits(U.Name, False)) then Continue;
        var Line: Integer:= if Pass = 0 then U.BareLine else U.Line;
        var Dup: Boolean:= False;
        for var X: TUsesNeed in D.NeededBy do
          if SameText(X.Name, U.Name) then Dup:= True;
        if Dup or (Length(D.NeededBy) >= NEEDED_BY_MAX) then Continue;
        D.NeededBy:= D.NeededBy + [Need(U.Name, Line,
          if Line < ImplementationLine(FIn.ConvPas) then SECTION_INTF else SECTION_IMPL)];
      end;
    if Length(D.NeededBy) > 0 then
    begin
      TArray.Sort<TUsesNeed>(D.NeededBy, TComparer<TUsesNeed>.Construct(
        function(const A, B: TUsesNeed): Integer begin Result:= A.Line - B.Line; end));
      FRes.Needs.Dangling:= FRes.Needs.Dangling + [D];
    end;
  end;
end;

function TReconciler.Run: TUsesReconcileResult;
var
  ConvParse, OrigParse, DfmParse: TParseResult;
  DfmOk: Boolean;
begin
  FRes:= Default(TUsesReconcileResult);
  FRes.Status:= 'on';
  FRes.Needs.Enabled := True;
  FRes.Needs.SameUnit:= FIx.SameUnit;
  if not ReadUsesEntries(FIn.UnitPas, FIn.OrigPas, FEntries) then Exit(FRes);
  FWatch:= UnitRuleWatchList(FIn.Rules, FIn.ExtraAdds, FIx.SameUnit);
  DfmOk:= True;
  DfmParse:= Default(TParseResult);
  try
    ConvParse:= ReindexText(FIn.UnitPas, FIn.ConvPas);
    OrigParse:= ReindexText(FIn.UnitPas, FIn.OrigPas);
    if FIn.ConvDfm <> '' then
    begin
      DfmParse:= ReindexText(ChangeFileExt(FIn.UnitPas, '.dfm'), FIn.ConvDfm);
      DfmOk:= False;
      for var S: TSymbol in DfmParse.Symbols do
        if S.Kind = skForm then DfmOk:= True;
      if not DfmOk then FRes.Detail:= 'the converted .dfm yields no root object';
    end;
  except
    on Ex: Exception do
    begin
      DfmOk:= False;
      FRes.Detail:= Ex.ClassName + ': ' + Ex.Message;
    end;
  end;
  if not DfmOk then
  begin
    FRes.Status:= 'degraded';
    DecideWatch(DfmParse, False);
    Exit(FRes);
  end;
  for var S: TSymbol in ConvParse.Symbols do
    if S.Name <> '' then FOwn.AddOrSetValue(LowerCase(S.Name), True);
  CollectNames(FIn.ConvPas, ConvParse, FConvUses);
  CollectNames(FIn.OrigPas, OrigParse, FOrigUses);
  DecideWatch(DfmParse, True);
  BuildPostPlan;
  PlanNewNames;
  PlanDangling;
  Result:= FRes;
end;

function ReconcileUses(AIndex: TUsesUnitIndex; const AIn: TUsesReconcileInput): TUsesReconcileResult;
var
  R: TReconciler;
begin
  R:= TReconciler.Create(AIndex, AIn);
  try
    Result:= R.Run;
  finally
    R.Free;
  end;
end;

end.
