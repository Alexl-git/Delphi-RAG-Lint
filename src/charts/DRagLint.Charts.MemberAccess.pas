unit DRagLint.Charts.MemberAccess;

(* The DATA layer of who-writes and who-reads, in-process: a port of charts\src\Emit-MemberAccess.ps1
  steps 1-5 and its measurement functions (spec s11; the PS output is the reference, P3). The Q unit
  that renders the rows, the dot and the fields is DRagLint.Charts.Q.MemberAccess; this unit only
  COLLECTS the facts of one selection in one mode, so the numbers can be pinned without a bundle.

  THE THING THAT LOOKS LIKE A DEFECT AND IS NOT. member_accesses.accessor_symbol_id does NOT mean
  "who touched the member": it names the ACCESSOR that implements the access (Connected -> the
  field FConnected, VERDICT -> GetVERDICT / SetVERDICT) and is NULL for every plain field access
  by owner ruling (INBOX-property-refs-never-resolve, RETIRED). The caller list is therefore
  built on find-callers' computation, uncapped, never on that column.

  TWO QUERIES, NEVER N. Step 1 asks the shared engine routine for the routines and the totals;
  step 2 asks SQL once for the SITE anchors of the routines that survived the cap. A site is a
  line AND a column (BASICSF.pas:4072 holds three accesses to RChartSampleData.R), and a routine
  that both reads and writes appears on both sides.

  D13 / D31 in two sentences: what find-callers reports is RESOLVED; what the index holds UNBOUND
  (a ref with no symbol, named like the member) is disclosed by name and never counted in a wing
  or a total. A bare access bound to the member with no member_accesses row is anchored by the
  second arm of the site query, so the verb and the SQL still count the same population.

  Data route (M2): the PS spawns `query find-callers --name N --db D --resolved --json`. The port
  calls DRagLint.Query.Callers.ResolvedCallersForName on a read-only ISymbolStore opened BESIDE
  the TChartsIndex: that function IS the shared engine code the verb renders from, so there is no
  mirror, no JSON and no spawn. The PS exit-1-with-[] acceptance is an empty array here.

  PS traps closed: hashtable keys, -eq, -in and Group-Object are case-blind (SameText,
  TIStringComparer.Ordinal); Group-Object's group name keeps the FIRST-SEEN casing; the two
  Sort-Object calls go through TPsSort and `Sort-Object -Unique` is SortUniqueNames; the PS
  200-row refusal of the site query cannot fire (TChartsIndex.Query has no cap) and is not
  ported; `$x = if (...) { @() }` assigning $null does not exist here; Write-Host is not output. *)

interface

uses
  System.SysUtils, System.Generics.Collections, DRagLint.Core.Interfaces,
  DRagLint.Charts.Index, // dl:unit DRagLint.Charts.Index accepted -- the resolver, the SQL text escaper and CompareGroupKeys travel with TChartsIndex, so the refusal texts and the sort order cannot drift from the other questions
  DRagLint.Charts.Text;

const
  /// <summary>The writers wing only (who-writes).</summary>
  MODE_WRITE = 'write';
  /// <summary>The readers wing only (who-reads).</summary>
  MODE_READ = 'read';
  /// <summary>Both wings; reachable only by the data layer (ruling R5), never by a question id.</summary>
  MODE_BOTH = 'both';
  /// <summary>How many unbound same-file lines are listed before the rest is only counted (the PS LIMIT 12).</summary>
  UNREPORTED_LINES_MAX = 12;

type
  /// <summary>One Group-Routines row: a routine and how many access sites find-callers reported in it.</summary>
  TRoutineHits = record
    /// <summary>The caller's qualified name, in the casing first seen.</summary>
    Routine: string;
    /// <summary>The number of reported sites in that routine.</summary>
    Sites  : Integer;
  end;

  /// <summary>One access site: a file, a line AND a column.</summary>
  TSiteAnchor = record
    /// <summary>files.path of the file holding the site.</summary>
    Path: string;
    /// <summary>refs.start_line.</summary>
    Line: Integer;
    /// <summary>refs.start_col.</summary>
    Col : Integer;
  end;

  /// <summary>The refs of one kind that are named like the member but bound to no symbol (the PS Get-UnreportedAccess object).</summary>
  TUnreportedAccess = record
    /// <summary>'write' or 'read'.</summary>
    Kind     : string;
    /// <summary>How many sit in the member's own file.</summary>
    Same     : Integer;
    /// <summary>':&lt;line&gt;' per same-file ref, ascending, at most UNREPORTED_LINES_MAX.</summary>
    SameLines: TArray<string>;
    /// <summary>How many sit in other files (the PS field is called Else, a reserved word here).</summary>
    Elsewhere: Integer;
    /// <summary>Same + Elsewhere.</summary>
    Total    : Integer;
  end;

  /// <summary>One accessor that implements a property (the backing query row).</summary>
  TBackingAccessor = record
    /// <summary>symbols.qualified_name of the accessor.</summary>
    QName: string;
    /// <summary>symbols.name of the accessor.</summary>
    Name : string;
    /// <summary>member_accesses.accessor_kind: 'field' or 'method'.</summary>
    Kind : string;
  end;

  /// <summary>The collected facts of one member selection in one mode.</summary>
  /// <remarks>Built only by CollectMemberAccess, which hands the caller ownership. The site map
  /// is owned here and freed by the destructor; every other member is a value.</remarks>
  TMemberAccessData = class
  private
    FSel             : TMemberSelection;
    FUnitName        : string;
    FMode            : string;
    FShowWrite       : Boolean;  // dl:ok referenced-never-set@37b2 -- REVIEWED 2026-10-17: linter FP -- CollectMemberAccess assigns it through Result.F... in the same unit (logged to draglint-gaps.log)
    FShowRead        : Boolean;  // dl:ok referenced-never-set@f4ff -- REVIEWED 2026-10-17: linter FP -- CollectMemberAccess assigns it through Result.F... in the same unit (logged to draglint-gaps.log)
    FTotalWrites     : Integer;
    FTotalReads      : Integer;
    FDistinctRoutines: Integer;
    FTotalSites      : Integer;
    FWriteRoutines   : TArray<TRoutineHits>;
    FReadRoutines    : TArray<TRoutineHits>;
    FWTop            : TRanked<TRoutineHits>;
    FRTop            : TRanked<TRoutineHits>;
    FMismatches      : TArray<string>;
    FCrossCheck      : string;
    FWU              : TUnreportedAccess;  // dl:ok referenced-never-set@aee1 -- REVIEWED 2026-10-17: linter FP -- CollectMemberAccess assigns it through Result.F... in the same unit (logged to draglint-gaps.log)
    FRU              : TUnreportedAccess;  // dl:ok referenced-never-set@46b0 -- REVIEWED 2026-10-17: linter FP -- CollectMemberAccess assigns it through Result.F... in the same unit (logged to draglint-gaps.log)
    FBacking         : TArray<TBackingAccessor>;
    FSites           : TObjectDictionary<string, TList<TSiteAnchor>>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>The resolved field or property (Kind is 'field' or 'property').</summary>
    property Sel: TMemberSelection read FSel;
    /// <summary>UnitNameOf(Sel.Path).</summary>
    property UnitName: string read FUnitName;
    /// <summary>MODE_WRITE, MODE_READ or MODE_BOTH, as asked.</summary>
    property Mode: string read FMode;
    /// <summary>True when the writers wing is rendered (Mode is write or both).</summary>
    property ShowWrite: Boolean read FShowWrite;
    /// <summary>True when the readers wing is rendered (Mode is read or both).</summary>
    property ShowRead: Boolean read FShowRead;
    /// <summary>Write sites find-callers reports, whatever Mode renders.</summary>
    property TotalWrites: Integer read FTotalWrites;
    /// <summary>Read sites find-callers reports, whatever Mode renders.</summary>
    property TotalReads: Integer read FTotalReads;
    /// <summary>Case-blind distinct routines across the RENDERED modes only.</summary>
    property DistinctRoutines: Integer read FDistinctRoutines;
    /// <summary>Sites across the RENDERED modes only.</summary>
    property TotalSites: Integer read FTotalSites;
    /// <summary>The writers, ranked (Sites descending, then name); empty when not ShowWrite.</summary>
    property WriteRoutines: TArray<TRoutineHits> read FWriteRoutines;
    /// <summary>The readers, ranked; empty when not ShowRead.</summary>
    property ReadRoutines: TArray<TRoutineHits> read FReadRoutines;
    /// <summary>WriteRoutines capped; HiddenSites is the sites of the routines cut.</summary>
    property WTop: TRanked<TRoutineHits> read FWTop;
    /// <summary>ReadRoutines capped.</summary>
    property RTop: TRanked<TRoutineHits> read FRTop;
    /// <summary>One '&lt;routine&gt; &lt;mode&gt;: verb N, sql M' per shown routine where the two routes disagree.</summary>
    property Mismatches: TArray<string> read FMismatches;
    /// <summary>'agree' or 'mismatch: ...'; surfaced, never smoothed.</summary>
    property CrossCheck: string read FCrossCheck;
    /// <summary>The unbound writes named like the member.</summary>
    property WU: TUnreportedAccess read FWU;
    /// <summary>The unbound reads named like the member.</summary>
    property RU: TUnreportedAccess read FRU;
    /// <summary>The accessors of a property in query order; empty for a field.</summary>
    property Backing: TArray<TBackingAccessor> read FBacking;
    /// <summary>The sites of one routine in one mode (the PS $sites["routine|mode"] lookup).</summary>
    /// <param name="pRoutine">The routine's qualified name; case-blind.</param>
    /// <param name="pMode">MODE_WRITE or MODE_READ.</param>
    /// <returns>The sites in line, column order; empty when the index has none for that key.</returns>
    function SitesOf(const pRoutine, pMode: string): TArray<TSiteAnchor>;
    /// <summary>The bundle header's own wording for one count (the PS $writesLabel / $readsLabel).</summary>
    /// <param name="pU">WU or RU.</param>
    /// <returns>'resolved &lt;kind&gt; sites reported by find-callers' plus the unreported tail; '' (the PS $null) when nothing is unreported.</returns>
    function CountLabel(const pU: TUnreportedAccess): string;
    /// <summary>The routine count's own wording (the PS $routinesLabel).</summary>
    /// <returns>'routines reported by find-callers' when a rendered direction has unreported refs, else '' (the PS $null).</returns>
    function RoutinesLabel: string;
  end;

/// <summary>What find-callers does NOT report, as a ' + ...' tail (the PS Get-UnreportedTail).</summary>
/// <param name="pU">The unreported refs of one kind.</param>
/// <param name="pSel">The selection, for the member name and its file.</param>
/// <returns>'' when nothing is unreported.</returns>
function UnreportedTail(const pU: TUnreportedAccess; const pSel: TMemberSelection): string;

/// <summary>A count named for what it is (the PS Format-AccessCount).</summary>
/// <param name="pN">The number of sites find-callers reports.</param>
/// <param name="pU">The unreported refs of the same kind.</param>
/// <param name="pSel">The selection.</param>
/// <returns>'N resolved kind(s) reported by find-callers + ...' when pU.Total &gt; 0, else 'N kind' with a plural s unless N is 1.</returns>
function FormatAccessCount(pN: Integer; const pU: TUnreportedAccess; const pSel: TMemberSelection): string;

/// <summary>The note for a zero in the rendered direction (the PS Get-ZeroNote).</summary>
/// <param name="pKind">'write' or 'read'.</param>
/// <param name="pU">The unreported refs of that kind.</param>
/// <param name="pOtherN">The other direction's reported count.</param>
/// <param name="pOtherU">The other direction's unreported refs.</param>
/// <param name="pSel">The selection.</param>
/// <returns>The zero, named, with the other direction's count beside it in brackets.</returns>
function ZeroNote(const pKind: string; const pU: TUnreportedAccess; pOtherN: Integer;
  const pOtherU: TUnreportedAccess; const pSel: TMemberSelection): string;

/// <summary>PS steps 1-5 plus Get-UnreportedAccess and the backing query for one member.</summary>
/// <param name="pIndex">The open index; not owned.</param>
/// <param name="pStore">A read-only store on the same file; not owned. It feeds ResolvedCallersForName.</param>
/// <param name="pTarget">The member's qualified or bare name.</param>
/// <param name="pMode">MODE_WRITE, MODE_READ or MODE_BOTH (case-blind).</param>
/// <param name="pCap">How many routines per wing are kept; Cap 20 is the PS default.</param>
/// <returns>The facts; the caller frees it.</returns>
/// <exception cref="EChartsQuestion">pMode is none of write, read, both.</exception>
/// <exception cref="EChartsIndex">The name is not in the index, is ambiguous, or is a method (the text is ResolveMemberSelection's).</exception>
/// <remarks>MODE_BOTH is accepted so the data layer keeps the PS lines verbatim (ruling R5);
/// the question unit never passes it. Opens no connection of its own.</remarks>
function CollectMemberAccess(pIndex: TChartsIndex; const pStore: ISymbolStore; const pTarget, pMode: string;
  pCap: Integer): TMemberAccessData;

implementation

uses
  System.Classes, System.Generics.Defaults, DRagLint.Query.Callers, DRagLint.Charts.Question,
  DRagLint.Charts.PsSort, DRagLint.Charts.Sql;

const
  ENCL_SELECT = 'encl.qualified_name';

{ ---- TMemberAccessData ---- }

constructor TMemberAccessData.Create;
begin
  inherited Create;
  FSites:= TObjectDictionary<string, TList<TSiteAnchor>>.Create([doOwnsValues], TIStringComparer.Ordinal);
end;

destructor TMemberAccessData.Destroy;
begin
  FSites.Free;
  inherited Destroy;
end;

function TMemberAccessData.SitesOf(const pRoutine, pMode: string): TArray<TSiteAnchor>;
begin
  var List: TList<TSiteAnchor>;
  if FSites.TryGetValue(pRoutine + '|' + pMode, List) then
    Result:= List.ToArray
  else
    Result:= nil;
end;

function TMemberAccessData.CountLabel(const pU: TUnreportedAccess): string;
begin
  Result:= '';
  if pU.Total > 0 then
    Result:= 'resolved ' + pU.Kind + ' sites reported by find-callers' + UnreportedTail(pU, FSel);
end;

function TMemberAccessData.RoutinesLabel: string;
begin
  Result:= '';
  if (FShowWrite and (FWU.Total > 0)) or (FShowRead and (FRU.Total > 0)) then
    Result:= 'routines reported by find-callers';
end;

{ ---- the M7 texts ---- }

function UnreportedTail(const pU: TUnreportedAccess; const pSel: TMemberSelection): string;
begin
  Result:= '';
  if pU.Same > 0 then
    Result:= Result + Format(' + %d unbound %s(s) named %s in %s', [pU.Same, pU.Kind, pSel.Name, FileNameOf(pSel.Path)]);
  if pU.Elsewhere > 0 then
    Result:= Result + Format(' + %d unbound same-name %s(s) in other files (may be other symbols)', [pU.Elsewhere, pU.Kind]);
end;

function FormatAccessCount(pN: Integer; const pU: TUnreportedAccess; const pSel: TMemberSelection): string;
begin
  if pU.Total > 0 then
    Result:= Format('%d resolved %s(s) reported by find-callers%s', [pN, pU.Kind, UnreportedTail(pU, pSel)])
  else
  begin
    Result:= Format('%d %s', [pN, pU.Kind]);
    if pN <> 1 then
      Result:= Result + 's';
  end;
end;

function ZeroNote(const pKind: string; const pU: TUnreportedAccess; pOtherN: Integer;
  const pOtherU: TUnreportedAccess; const pSel: TMemberSelection): string;
begin
  var Head:= 'no ' + pKind + ' sites';
  if pU.Total > 0 then
    Head:= FormatAccessCount(0, pU, pSel);
  Result:= Head + ' (' + FormatAccessCount(pOtherN, pOtherU, pSel) + ')';
end;

{ ---- the collection ---- }

// PS Group-Routines (101-106): a case-blind group per caller whose name keeps the FIRST-SEEN casing,
// ranked Sites descending then name. The composite comparison is total, so the group order
// Group-Object hands Sort-Object cannot change the result.
function GroupRoutines(const pHits: TArray<TQueryCallerRow>): TArray<TRoutineHits>;
begin
  Result:= nil;
  var Position:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for var Hit in pHits do
    begin
      var At: Integer;
      if Position.TryGetValue(Hit.CallerQName, At) then
        Inc(Result[At].Sites)
      else
      begin
        Position.Add(Hit.CallerQName, Length(Result));
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)].Routine:= Hit.CallerQName;
        Result[High(Result)].Sites:= 1;
      end;
    end;
  finally
    Position.Free;
  end;
  TPsSort<TRoutineHits>.Sort(Result,
    function(const pA, pB: TRoutineHits): Integer
    begin
      Result:= pB.Sites - pA.Sites;
      if Result = 0 then
        Result:= CompareGroupKeys(pA.Routine, pB.Routine);
    end);
end;

// The hits whose target is the selected member, in one mode (PS 89-94); an empty pMode keeps both.
function HitsOf(const pRows: TQueryCallerRows; const pQName, pMode: string): TArray<TQueryCallerRow>;
begin
  Result:= nil;
  for var Row in pRows do
    if SameText(Row.TargetQName, pQName) and ((pMode = '') or SameText(Row.Mode, pMode)) then
      Result:= Result + [Row];
end;

// PS 162-184 verbatim: the two arms (the member or its accessor; a bare ref bound to the member)
function SiteSql(const pSel: TMemberSelection; const pShownNames: TArray<string>): string;
begin
  var Join:= TChartsIndex.EnclosingRoutineJoin('r');
  var QName:= TChartsIndex.SqlText(pSel.QName);
  var InList:= TChartsIndex.SqlInList(pShownNames);
  Result:=
    'SELECT ' + ENCL_SELECT + ' AS routine, ma.mode AS mode, f.path AS path,' + sLineBreak +
    '       r.start_line AS ln, r.start_col AS col' + sLineBreak +
    '  FROM member_accesses ma' + sLineBreak +
    '  JOIN refs r    ON r.id = ma.ref_id' + sLineBreak +
    '  JOIN symbols m ON m.id = ma.member_symbol_id' + sLineBreak +
    '  JOIN files f   ON f.id = r.file_id' + sLineBreak +
    '  LEFT JOIN symbols acc ON acc.id = ma.accessor_symbol_id' + sLineBreak +
    '  ' + Join + sLineBreak +
    ' WHERE (m.qualified_name = ''' + QName + '''' + sLineBreak +
    '        OR acc.qualified_name = ''' + QName + ''')' + sLineBreak +
    '   AND ' + ENCL_SELECT + ' IN (' + InList + ')' + sLineBreak +
    'UNION ALL' + sLineBreak +
    'SELECT ' + ENCL_SELECT + ' AS routine, r.kind AS mode, f.path AS path,' + sLineBreak +
    '       r.start_line AS ln, r.start_col AS col' + sLineBreak +
    '  FROM refs r' + sLineBreak +
    '  JOIN files f ON f.id = r.file_id' + sLineBreak +
    '  ' + Join + sLineBreak +
    ' WHERE r.symbol_id = ' + IntToStr(pSel.Id) + ' AND r.kind IN (''read'', ''write'')' + sLineBreak +
    '   AND NOT EXISTS (SELECT 1 FROM member_accesses ma WHERE ma.ref_id = r.id)' + sLineBreak +
    '   AND ' + ENCL_SELECT + ' IN (' + InList + ')' + sLineBreak +
    ' ORDER BY ln, col';
end;

// PS 139-197: one query for the SITE anchors of the shown routines, keyed "routine|mode"
procedure LoadSites(pIndex: TChartsIndex; pData: TMemberAccessData);
begin
  var Names: TArray<string>:= nil;
  for var Row in pData.FWTop.Shown do
    Names:= Names + [Row.Routine];
  for var Row in pData.FRTop.Shown do
    Names:= Names + [Row.Routine];
  Names:= SortUniqueNames(Names);
  if Length(Names) = 0 then
    Exit;
  var Rows:= pIndex.Query(SiteSql(pData.FSel, Names));
  try
    for var Row in Rows do
    begin
      var Key:= Row.S('routine') + '|' + Row.S('mode');
      var List: TList<TSiteAnchor>;
      if not pData.FSites.TryGetValue(Key, List) then
      begin
        List:= TList<TSiteAnchor>.Create;
        pData.FSites.Add(Key, List);
      end;
      var Site: TSiteAnchor;
      Site.Path:= Row.S('path');
      Site.Line:= Row.I('ln');
      Site.Col:= Row.I('col');
      List.Add(Site);
    end;
  finally
    Rows.Free;
  end;
end;

// PS 203-214: the verb and the SQL are two routes to one fact; a disagreement is a finding
procedure CrossCheckSites(pData: TMemberAccessData);
begin
  pData.FMismatches:= nil;
  var Pairs: array[0..1] of record
    Rows: TArray<TRoutineHits>;
    Mode: string;
  end;
  Pairs[0].Rows:= pData.FWTop.Shown;
  Pairs[0].Mode:= MODE_WRITE;
  Pairs[1].Rows:= pData.FRTop.Shown;
  Pairs[1].Mode:= MODE_READ;
  for var Pair in Pairs do
    for var Row in Pair.Rows do
    begin
      var Found:= Length(pData.SitesOf(Row.Routine, Pair.Mode));
      if Found <> Row.Sites then
        pData.FMismatches:= pData.FMismatches +
          [Format('%s %s: verb %d, sql %d', [Row.Routine, Pair.Mode, Row.Sites, Found])];
    end;
  pData.FCrossCheck:= 'agree';
  if Length(pData.FMismatches) > 0 then
    pData.FCrossCheck:= 'mismatch: ' + string.Join('; ', pData.FMismatches);
end;

// PS 342-364 Get-UnreportedAccess: refs of one kind named like the member and bound to nothing
function UnreportedOf(pIndex: TChartsIndex; const pSel: TMemberSelection; const pKind: string): TUnreportedAccess;
begin
  Result:= Default(TUnreportedAccess);
  Result.Kind:= pKind;
  var Nm:= TChartsIndex.SqlText(pSel.Name);
  var Pth:= TChartsIndex.SqlText(pSel.Path);
  var Unbound:= 'r.kind = ''' + pKind + ''' AND r.symbol_id IS NULL AND lower(r.name_text) = lower(''' + Nm + ''')';
  var Counts:= pIndex.Query(
    'SELECT (f.path = ''' + Pth + ''') AS same, COUNT(*) AS c' + sLineBreak +
    '  FROM refs r JOIN files f ON f.id = r.file_id' + sLineBreak +
    ' WHERE ' + Unbound + sLineBreak +
    ' GROUP BY (f.path = ''' + Pth + ''')');
  try
    for var Row in Counts do
      if Row.I('same') = 1 then
        Result.Same:= Row.I('c')
      else
        Result.Elsewhere:= Row.I('c');
  finally
    Counts.Free;
  end;
  if Result.Same > 0 then
  begin
    var Lines:= pIndex.Query(
      'SELECT r.start_line AS ln FROM refs r JOIN files f ON f.id = r.file_id' + sLineBreak +  // dl:ok sql-injection-concat@6442 -- REVIEWED 2026-10-17: Pth comes from TChartsIndex.SqlText and the rest is constant text or an integer; TChartsIndex.Query takes text, as the PS did
      ' WHERE ' + Unbound + ' AND f.path = ''' + Pth + '''' + sLineBreak +
      ' ORDER BY r.start_line LIMIT ' + IntToStr(UNREPORTED_LINES_MAX));
    try
      for var Row in Lines do
        Result.SameLines:= Result.SameLines + [':' + IntToStr(Row.I('ln'))];
    finally
      Lines.Free;
    end;
  end;
  Result.Total:= Result.Same + Result.Elsewhere;
end;

// PS 440-458: the accessors of a property, in name order; a field has none
function BackingOf(pIndex: TChartsIndex; const pSel: TMemberSelection): TArray<TBackingAccessor>;
begin
  Result:= nil;
  if not SameText(pSel.Kind, 'property') then
    Exit;
  var Rows:= pIndex.Query(
    'SELECT DISTINCT acc.qualified_name AS acc, acc.name AS nm, ma.accessor_kind AS k' + sLineBreak +
    '  FROM member_accesses ma' + sLineBreak +
    '  JOIN symbols m   ON m.id = ma.member_symbol_id' + sLineBreak +
    '  JOIN symbols acc ON acc.id = ma.accessor_symbol_id' + sLineBreak +
    ' WHERE m.qualified_name = ''' + TChartsIndex.SqlText(pSel.QName) + '''' + sLineBreak +
    ' ORDER BY acc.name');
  try
    for var Row in Rows do
    begin
      var Acc: TBackingAccessor;
      Acc.QName:= Row.S('acc');
      Acc.Name:= Row.S('nm');
      Acc.Kind:= Row.S('k');
      Result:= Result + [Acc];
    end;
  finally
    Rows.Free;
  end;
end;

// the PS ValidateSet, which gave the refusal for free
function CanonicalMode(const pMode: string): string;
begin
  if SameText(pMode, MODE_WRITE) then
    Exit(MODE_WRITE);
  if SameText(pMode, MODE_READ) then
    Exit(MODE_READ);
  if SameText(pMode, MODE_BOTH) then
    Exit(MODE_BOTH);
  raise EChartsQuestion.Create(pMode + ' is not a mode');
end;

function CollectMemberAccess(pIndex: TChartsIndex; const pStore: ISymbolStore; const pTarget, pMode: string;
  pCap: Integer): TMemberAccessData;
begin
  var Mode:= CanonicalMode(pMode);
  Result:= TMemberAccessData.Create;
  var Built:= False;
  try
    Result.FMode:= Mode;
    Result.FShowWrite:= (Mode = MODE_WRITE) or (Mode = MODE_BOTH);
    Result.FShowRead:= (Mode = MODE_READ) or (Mode = MODE_BOTH);
    { ---- 1. the selection, REFUSING an ambiguous name ---- }
    var Found: Boolean;
    Result.FSel:= pIndex.ResolveMemberSelection(pTarget, ['field', 'property'], False, RESOLVE_HINT_DEFAULT, Found);
    Result.FUnitName:= UnitNameOf(Result.FSel.Path);
    { ---- 2. the routines and the TOTALS, uncapped, from the engine's own routine ---- }
    var Rows:= ResolvedCallersForName(pStore, Result.FSel.Name);
    var WriteHits:= HitsOf(Rows, Result.FSel.QName, MODE_WRITE);
    var ReadHits:= HitsOf(Rows, Result.FSel.QName, MODE_READ);
    Result.FTotalWrites:= Length(WriteHits);
    Result.FTotalReads:= Length(ReadHits);
    var Rendered: TArray<TQueryCallerRow>:= nil;
    if Result.FShowWrite then
    begin
      Result.FWriteRoutines:= GroupRoutines(WriteHits);
      Rendered:= Rendered + WriteHits;
    end;
    if Result.FShowRead then
    begin
      Result.FReadRoutines:= GroupRoutines(ReadHits);
      Rendered:= Rendered + ReadHits;
    end;
    var Distinct:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
    try
      for var Hit in Rendered do
        Distinct.AddOrSetValue(Hit.CallerQName, True);
      Result.FDistinctRoutines:= Distinct.Count;
    finally
      Distinct.Free;
    end;
    Result.FTotalSites:= Length(Rendered);
    { ---- 3. rank, cap and DISCLOSE (the site function is passed: HiddenSites is summed) ---- }
    var SiteCount:= function(pRow: TRoutineHits): Integer
      begin
        Result:= pRow.Sites;
      end;
    Result.FWTop:= TRanked<TRoutineHits>.TopRanked(Result.FWriteRoutines, pCap, SiteCount);
    Result.FRTop:= TRanked<TRoutineHits>.TopRanked(Result.FReadRoutines, pCap, SiteCount);
    { ---- 4./5. the site anchors for the shown routines, and the cross-check ---- }
    LoadSites(pIndex, Result);
    CrossCheckSites(Result);
    { ---- the unreported populations (both kinds always) and the backing ---- }
    Result.FWU:= UnreportedOf(pIndex, Result.FSel, MODE_WRITE);
    Result.FRU:= UnreportedOf(pIndex, Result.FSel, MODE_READ);
    Result.FBacking:= BackingOf(pIndex, Result.FSel);
    Built:= True;
  finally
    if not Built then
      FreeAndNil(Result);
  end;
end;

end.
