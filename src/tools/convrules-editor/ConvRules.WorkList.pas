unit ConvRules.WorkList;

{ The Work list (editor-1270 Task 3, owner ruling 2026-10-11: a NEW tab beside
  Convert): everything a converted unit's code still uses from the old
  components, read from convert-apply's apply/1 pas_uses[] (engine 1.27.0,
  capability pas_uses). Pure -- parsing, filter, sort, display text and the
  double-click decision; ConvRules.WorkListTab renders, ConvRulesModelTests.dpr
  pins every rule here. }

interface

uses
  System.JSON
  ;

const
  /// <summary>pas_uses status: the From member has no #link and the To type has no
  /// member of that name -- the code will not compile.</summary>
  PAS_USE_UNMAPPED        = 'unmapped';
  /// <summary>pas_uses status: a global (type, constant, routine) declared in a unit
  /// the book #unuse'd -- left dangling.</summary>
  PAS_USE_GLOBAL_DANGLING = 'global-dangling';
  /// <summary>pas_uses status: a #link with a class cast the engine refuses to apply
  /// at a .pas site.</summary>
  PAS_USE_CAST_REFUSED    = 'cast-refused';
  /// <summary>pas_uses status: a #link through a dotted path the engine does not
  /// rewrite in the .pas.</summary>
  PAS_USE_NOT_REWRITTEN   = 'not-rewritten';
  /// <summary>pas_uses status: the To type has a member of the same name.</summary>
  PAS_USE_SAME_NAME       = 'same-name';
  /// <summary>pas_uses status: a #link renamed (or identity-mapped) the member.</summary>
  PAS_USE_MAPPED          = 'mapped';

  /// <summary>pas_uses resolution (engine 1.28.2, capability pas_uses_resolution): the
  /// From class was resolved in the unit's scope; declaring_unit / declared_in are facts.</summary>
  PAS_RES_RESOLVED         = 'resolved';
  /// <summary>pas_uses resolution: several units declare the From class and the unit's
  /// scope does not choose one; candidates[] names them.</summary>
  PAS_RES_AMBIGUOUS        = 'ambiguous';
  /// <summary>pas_uses resolution: no unit in scope declares the From class.</summary>
  PAS_RES_CLASS_NOT_FOUND  = 'class-not-found';
  /// <summary>pas_uses resolution: the class was found, the member was not.</summary>
  PAS_RES_MEMBER_NOT_FOUND = 'member-not-found';
  /// <summary>pas_uses resolution: the member's kind could not be determined.</summary>
  PAS_RES_KIND_UNKNOWN     = 'kind-unknown';

  /// <summary>Instance column text of a global row (Instance '').</summary>
  WORK_GLOBAL_INSTANCE = '(global)';
  /// <summary>From -&gt; To column text of a global row.</summary>
  WORK_GLOBAL_PAIR     = '--';
  /// <summary>Summary when the engine does not report pas_uses.</summary>
  WORK_NO_CAPABILITY   = 'no work list (engine has no pas_uses)';
  /// <summary>Summary when the run converted no unit (every unit failed, was
  /// refused, rolled back or skipped).</summary>
  WORK_NO_CONVERTED    = 'no work list (no unit converted)';
  /// <summary>Summary before the first Convert run of the session.</summary>
  WORK_NO_RUN          = 'no work list yet -- run Convert first';
  /// <summary>The status-filter entry for every status outside the six PAS_USE_* values
  /// (a newer engine's word, or '' when the engine sent none). The parentheses keep it
  /// from colliding with an engine status, which is a lower-case hyphenated word.</summary>
  WORK_STATUS_OTHER    = '(other)';

type
  /// <summary>One pas_uses[] entry: a member or global the unit's code uses, and
  /// what the conversion did about it.</summary>
  /// <remarks>Every string is '' and Count / Lines are 0 / [] when the engine left
  /// the key out or sent the wrong JSON type; the row is kept with what is known.
  /// A GLOBAL row has Instance '' and FromType ''.</remarks>
  TPasUseRow = record
    /// <summary>The run that produced the row (TWorkRun.RunId).</summary>
    RunId        : Integer;
    /// <summary>The unit's .pas -- the full path once the Convert tab stamped it
    /// (WorkRunOf); apply/1 'unit' as parsed.</summary>
    UnitPas      : string;
    /// <summary>instance -- the converted component; '' for a global.</summary>
    Instance     : string;
    /// <summary>from_type.</summary>
    FromType     : string;
    /// <summary>to_type.</summary>
    ToType       : string;
    /// <summary>member -- the member or global name the code uses.</summary>
    Member       : string;
    /// <summary>kind -- property, method, type, ... ('' when the engine did not say).</summary>
    Kind         : string;
    /// <summary>visibility.</summary>
    Visibility   : string;
    /// <summary>declaring_unit -- the unit declaring the member or global.</summary>
    DeclaringUnit: string;
    /// <summary>declared_in -- the class declaring the member; '' for a global.</summary>
    DeclaredIn   : string;
    /// <summary>status -- one of the PAS_USE_* values, or a newer engine's word.</summary>
    Status       : string;
    /// <summary>lines -- the .pas lines of the uses; non-numbers are skipped.</summary>
    Lines        : TArray<Integer>;
    /// <summary>count -- the number of uses; Length(Lines) when absent or not a number.</summary>
    Count        : Integer;
    /// <summary>resolution -- how the engine found the declaring unit: one of the
    /// PAS_RES_* values, or a newer engine's word; '' when the engine did not say (an
    /// engine without pas_uses_resolution: ParseApplyJson clears it).</summary>
    Resolution   : string;
    /// <summary>candidates -- the units that could declare the From class (ambiguous);
    /// string entries only, others skipped; [] when absent.</summary>
    Candidates   : TArray<string>;
  end;

  /// <summary>What the Work list shows. An empty field means "all".</summary>
  TWorkFilter = record
    /// <summary>The statuses shown (exact, case-insensitive); WORK_STATUS_OTHER matches
    /// every status outside the six PAS_USE_* values, '' included; [] = every status
    /// unless NoStatus.</summary>
    Statuses: TArray<string>;
    /// <summary>True = no status is chosen (every box unchecked): nothing is shown.</summary>
    NoStatus: Boolean;
    /// <summary>The unit shown (UnitPas, case-insensitive); '' = every unit.</summary>
    UnitPas : string;
    /// <summary>A case-insensitive substring of Member or Instance; '' = no text filter.</summary>
    Text    : string;
  end;

  /// <summary>How a row is painted: work statuses are bold, unmapped and
  /// global-dangling also red.</summary>
  TWorkStyle = (wsPlain, wsBold, wsBoldRed);

  /// <summary>Why the Work list holds what it holds.</summary>
  /// <remarks>wlsNoRun: no Convert run yet. wlsNoCapability: the run's engine does not
  /// report pas_uses. wlsNoConverted: the run converted no unit. wlsRows: Rows is the
  /// run's work list (possibly empty: the converted code uses nothing).</remarks>
  TWorkListState = (wlsNoRun, wlsNoCapability, wlsNoConverted, wlsRows);

  /// <summary>One run's Work list, handed from the Convert tab to the host.</summary>
  /// <remarks>Known limits (deferred to the final review): two books on one unit that
  /// report the same global at shifted lines give two rows (WorkRunOf drops exact repeats
  /// only). A Convert that is refused before it runs (Preflight, a gate) hands no TWorkRun,
  /// so the Work list keeps the previous run's rows.</remarks>
  TWorkRun = record
    /// <summary>The Convert tab's run counter; every row carries it.</summary>
    RunId: Integer;
    /// <summary>See TWorkListState.</summary>
    State: TWorkListState;
    /// <summary>The pas_uses rows of every converted unit, stamped with RunId and the
    /// unit's full path; [] unless State is wlsRows.</summary>
    Rows : TArray<TPasUseRow>;
  end;

  /// <summary>The outcome of a double-click on a Work list row.</summary>
  TWorkGoTo = record
    /// <summary>True = copy Clip to the clipboard and show Status; False = show Status
    /// as an error and copy nothing.</summary>
    Ok    : Boolean;
    /// <summary>'&lt;full path&gt;(&lt;line&gt;)' -- the compiler-message form; the bare
    /// path when the row has no line.</summary>
    Clip  : string;
    /// <summary>The status-bar text.</summary>
    Status: string;
  end;

/// <summary>PURE: reads an apply/1 pas_uses[] array.</summary>
/// <param name="AArr">The array; nil reads as empty.</param>
/// <param name="AUnitPas">Stamped on every row as UnitPas.</param>
/// <param name="ARunId">Stamped on every row as RunId.</param>
/// <returns>One row per object entry, in the engine's order; never raises. A
/// non-object entry is skipped; a missing or wrongly-typed field reads as '' / [] /
/// 0 (a JSON number is never a string), and Count falls back to Length(Lines).
/// resolution and candidates[] (string entries only) are read whatever the engine;
/// ParseApplyJson clears them for an engine without pas_uses_resolution.</returns>
function ParsePasUses(const AArr: TJSONArray; const AUnitPas: string; ARunId: Integer): TArray<TPasUseRow>;

/// <summary>PURE: True for the statuses that are work to do -- unmapped,
/// global-dangling, cast-refused, not-rewritten (case-insensitive).</summary>
/// <param name="AStatus">A pas_uses status.</param>
/// <returns>See summary; False for same-name, mapped and any unknown word.</returns>
function IsWorkStatus(const AStatus: string): Boolean;

/// <summary>PURE: how a row of AStatus is painted.</summary>
/// <param name="AStatus">A pas_uses status.</param>
/// <returns>wsBoldRed for unmapped and global-dangling, wsBold for the other work
/// statuses (IsWorkStatus), else wsPlain.</returns>
function WorkStyleOf(const AStatus: string): TWorkStyle;

/// <summary>PURE: the six known statuses, in sort order (unmapped first).</summary>
/// <returns>The PAS_USE_* values, in STATUS order.</returns>
function WorkStatuses: TArray<string>;

/// <summary>PURE: the entries of the tab's status filter.</summary>
/// <returns>WorkStatuses, then WORK_STATUS_OTHER.</returns>
function WorkFilterEntries: TArray<string>;

/// <summary>PURE: the filter the tab starts with.</summary>
/// <returns>Statuses = the four work statuses (IsWorkStatus) and WORK_STATUS_OTHER (an
/// unknown status is never hidden by default), every unit, no text.</returns>
function DefaultWorkFilter: TWorkFilter;

/// <summary>PURE: the filter of the tab's controls.</summary>
/// <param name="AChecked">The checked status-filter entries (WorkFilterEntries).</param>
/// <param name="AUnitPas">The chosen unit; '' = every unit.</param>
/// <param name="AText">The text box; trimmed.</param>
/// <returns>Statuses = AChecked; NoStatus when AChecked is empty, so an all-unchecked
/// filter shows nothing rather than everything.</returns>
function WorkFilterOf(const AChecked: TArray<string>; const AUnitPas, AText: string): TWorkFilter;

/// <summary>PURE: the rows AFilter lets through, order kept.</summary>
/// <param name="ARows">The run's rows.</param>
/// <param name="AFilter">See TWorkFilter; an empty field filters nothing.</param>
/// <returns>A new array; ARows is not changed.</returns>
function FilterRows(const ARows: TArray<TPasUseRow>; const AFilter: TWorkFilter): TArray<TPasUseRow>;

/// <summary>PURE: sorts the rows in place.</summary>
/// <param name="ARows">The rows.</param>
/// <remarks>Order: status rank (unmapped, global-dangling, cast-refused,
/// not-rewritten, same-name, mapped, anything else last), then unit, then instance
/// with globals ('') last within a unit, then member; text compares are
/// case-insensitive. Stable for equal keys.</remarks>
procedure SortRows(var ARows: TArray<TPasUseRow>);

/// <summary>PURE: a row's Declared in cell -- never a guessed unit presented as fact.</summary>
/// <param name="ARow">The row.</param>
/// <returns>Resolution '' or resolved: DeclaringUnit.DeclaredIn, or whichever of the two
/// is set; ambiguous: 'ambiguous: ' + the candidates joined by ', '; class-not-found /
/// member-not-found / kind-unknown: '(class not found)' / '(member not found)' / '(kind
/// unknown)'; any other value: '(' + Resolution + ')'.</returns>
function DeclaredInText(const ARow: TPasUseRow): string;

/// <summary>PURE: a row's grid cells.</summary>
/// <param name="ARow">The row.</param>
/// <returns>Unit (file name) | Instance | From -&gt; To | Member | Kind | Status |
/// Lines (comma-separated) | Declared in (DeclaredInText). Kind shows '(unknown)' when
/// the engine sent no kind but did send a resolution. A global row shows Instance
/// '(global)' and From -&gt; To '--'.</returns>
function RowDisplay(const ARow: TPasUseRow): TArray<string>;

/// <summary>PURE: the column captions RowDisplay fills.</summary>
/// <returns>Unit, Instance, From -&gt; To, Member, Kind, Status, Lines, Declared in.</returns>
function WorkColumns: TArray<string>;

/// <summary>PURE: the Work list's summary line.</summary>
/// <param name="ARows">The run's rows (unfiltered).</param>
/// <param name="AState">Why the list holds what it holds; wlsRows by default.</param>
/// <returns>For wlsRows: 'N to work on (U unmapped, G global, C cast-refused, R
/// not-rewritten), M mapped / same-name', then ', K other' when K &gt; 0 rows have a
/// status outside the six (counted in neither part); else WORK_NO_RUN,
/// WORK_NO_CAPABILITY or WORK_NO_CONVERTED.</returns>
function WorkListSummary(const ARows: TArray<TPasUseRow>; AState: TWorkListState = wlsRows): string;

/// <summary>PURE: the rows a new run leaves on the Work list.</summary>
/// <param name="AOld">The rows shown so far (an earlier run).</param>
/// <param name="ANew">The new run's rows.</param>
/// <param name="ANewRunId">The new run's id.</param>
/// <returns>Only rows carrying ANewRunId, from either array: a new run REPLACES the
/// list, and never mixes two runs' rows -- also when the new run has no rows.</returns>
function MergeRun(const AOld, ANew: TArray<TPasUseRow>; ANewRunId: Integer): TArray<TPasUseRow>;

/// <summary>PURE: the distinct units of ARows, in first-seen order.</summary>
/// <param name="ARows">The rows.</param>
/// <returns>UnitPas values, case-insensitively distinct.</returns>
function WorkUnits(const ARows: TArray<TPasUseRow>): TArray<string>;

/// <summary>PURE: what a double-click on ARow does.</summary>
/// <param name="ARow">The row.</param>
/// <param name="AFileExists">ARow.UnitPas exists on disk.</param>
/// <param name="ALineCount">The file's line count (read by the caller).</param>
/// <returns>Ok with Clip '&lt;path&gt;(&lt;first line&gt;)' and Status 'Copied
/// &lt;file&gt;(&lt;line&gt;) to the clipboard -- line &lt;line&gt;' (the clipboard holds
/// the compiler-message form; the IDE's Go to line takes only the number); not Ok with Status
/// '&lt;path&gt; not found' for a missing file, or '&lt;path&gt; has only N line(s) --
/// line L is past its end (the file changed since the run)'.</returns>
function WorkGoTo(const ARow: TPasUseRow; AFileExists: Boolean; ALineCount: Integer): TWorkGoTo;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Defaults
  , System.Generics.Collections
  ;

const
  // STATUS_ORDER indices: the status rank SortRows uses, and WorkListSummary's counters.
  RANK_UNMAPPED      = 0;
  RANK_GLOBAL        = 1;
  RANK_CAST_REFUSED  = 2;
  RANK_NOT_REWRITTEN = 3;
  RANK_SAME_NAME     = 4;
  RANK_MAPPED        = 5;
  // WorkStatuses lists them in this order.
  STATUS_ORDER: array[RANK_UNMAPPED..RANK_MAPPED] of string = (PAS_USE_UNMAPPED, PAS_USE_GLOBAL_DANGLING, PAS_USE_CAST_REFUSED,
    PAS_USE_NOT_REWRITTEN, PAS_USE_SAME_NAME, PAS_USE_MAPPED);
  // The STATUS_ORDER entries before RANK_SAME_NAME are the work statuses.
  WORK_STATUS_COUNT = RANK_SAME_NAME;
  SUMMARY_FMT  = '%d to work on (%d unmapped, %d global, %d cast-refused, %d not-rewritten), %d mapped / same-name';
  PAIR_FMT     = '%s -> %s';
  OTHER_FMT    = ', %d other';
  GOTO_FMT     = '%s(%d)';
  COPIED_FMT   = 'Copied %s to the clipboard -- line %d';
  // DeclaredInText / RowDisplay: an unresolved row's cells -- never a guessed unit.
  AMBIGUOUS_PREFIX        = 'ambiguous: ';
  CLASS_NOT_FOUND_CELL    = '(class not found)';
  MEMBER_NOT_FOUND_CELL   = '(member not found)';
  KIND_UNKNOWN_DECL_CELL  = '(kind unknown)';
  OTHER_RESOLUTION_FMT    = '(%s)';
  KIND_UNKNOWN_CELL       = '(unknown)';
  COPIED_NO_LINE_FMT = 'Copied %s -- the engine recorded no line for this use';
  NOT_FOUND_FMT = '%s not found';
  PAST_EOF_FMT  = '%s has only %d line(s) -- line %d is past its end (the file changed since the run)';

// A string value's text; '' for any other JSON type. The TJSONNumber test is defensive:
// TJSONNumber descended from TJSONString in older RTLs (Delphi 13's does not), and a
// number is never a name.
function JText(AVal: TJSONValue): string;
begin
  if (AVal is TJSONString) and not (AVal is TJSONNumber) then
    Result:= TJSONString(AVal).Value
  else
    Result:= '';
end;

// A string field; '' when absent or not a JSON string.
function JStr(AObj: TJSONObject; const AKey: string): string;
begin
  Result:= JText(AObj.Values[AKey]);
end;

// The string entries of an array field; non-strings are skipped, a non-array reads as [].
function JStrings(AObj: TJSONObject; const AKey: string): TArray<string>;
var
  LVal: TJSONValue;
begin
  Result:= nil;
  LVal:= AObj.Values[AKey];
  if not (LVal is TJSONArray) then
    Exit;
  for var LItem: TJSONValue in TJSONArray(LVal) do
    if (LItem is TJSONString) and not (LItem is TJSONNumber) then
      Result:= Result + [JText(LItem)];
end;

// AVal as an Integer: a JSON number whose text is an Integer. TJSONNumber.AsInt is
// StrToInt and RAISES on 12.5, 1e3 or a value beyond Integer -- never call it here.
function JInt(AVal: TJSONValue; out AInt: Integer): Boolean;
begin
  AInt:= 0;
  Result:= (AVal is TJSONNumber) and TryStrToInt(AVal.Value, AInt);
end;

// The integers of a 'lines' value: an array's Integer entries (others skipped), or one.
function JLines(AVal: TJSONValue): TArray<Integer>;
var
  LInt: Integer;
begin
  Result:= nil;
  if JInt(AVal, LInt) then
    Exit(TArray<Integer>.Create(LInt));
  if not (AVal is TJSONArray) then
    Exit;
  for var LItem: TJSONValue in TJSONArray(AVal) do
    if JInt(LItem, LInt) then
      Result:= Result + [LInt];
end;

function ParsePasUses(const AArr: TJSONArray; const AUnitPas: string; ARunId: Integer): TArray<TPasUseRow>;
var
  LObj: TJSONObject;
  LRow: TPasUseRow;
begin
  Result:= nil;
  if AArr = nil then
    Exit;
  for var LVal: TJSONValue in AArr do
  begin
    if not (LVal is TJSONObject) then
      Continue;
    LObj:= TJSONObject(LVal);
    LRow:= Default(TPasUseRow);
    LRow.RunId        := ARunId;
    LRow.UnitPas      := AUnitPas;
    LRow.Instance     := JStr(LObj, 'instance');
    LRow.FromType     := JStr(LObj, 'from_type');
    LRow.ToType       := JStr(LObj, 'to_type');
    LRow.Member       := JStr(LObj, 'member');
    LRow.Kind         := JStr(LObj, 'kind');
    LRow.Visibility   := JStr(LObj, 'visibility');
    LRow.DeclaringUnit:= JStr(LObj, 'declaring_unit');
    LRow.DeclaredIn   := JStr(LObj, 'declared_in');
    LRow.Status       := JStr(LObj, 'status');
    LRow.Lines        := JLines(LObj.Values['lines']);
    if not JInt(LObj.Values['count'], LRow.Count) then
      LRow.Count:= Length(LRow.Lines);
    LRow.Resolution   := JStr(LObj, 'resolution');
    LRow.Candidates   := JStrings(LObj, 'candidates');
    Result:= Result + [LRow];
  end;
end;

// The sort rank of AStatus: its STATUS_ORDER index, Length(STATUS_ORDER) when unknown.
function StatusRank(const AStatus: string): Integer;
begin
  for var I: Integer:= Low(STATUS_ORDER) to High(STATUS_ORDER) do
    if SameText(AStatus, STATUS_ORDER[I]) then
      Exit(I);
  Result:= Length(STATUS_ORDER);
end;

function IsWorkStatus(const AStatus: string): Boolean;
begin
  Result:= StatusRank(AStatus) < WORK_STATUS_COUNT;
end;

function WorkStyleOf(const AStatus: string): TWorkStyle;
begin
  if SameText(AStatus, PAS_USE_UNMAPPED) or SameText(AStatus, PAS_USE_GLOBAL_DANGLING) then
    Result:= wsBoldRed
  else if IsWorkStatus(AStatus) then
    Result:= wsBold
  else
    Result:= wsPlain;
end;

function WorkStatuses: TArray<string>;
begin
  Result:= nil;
  for var LStatus: string in STATUS_ORDER do
    Result:= Result + [LStatus];
end;

function WorkFilterEntries: TArray<string>;
begin
  Result:= WorkStatuses + [WORK_STATUS_OTHER];
end;

function DefaultWorkFilter: TWorkFilter;
begin
  Result:= Default(TWorkFilter);
  Result.Statuses:= Copy(WorkStatuses, 0, WORK_STATUS_COUNT) + [WORK_STATUS_OTHER];
end;

function WorkFilterOf(const AChecked: TArray<string>; const AUnitPas, AText: string): TWorkFilter;
begin
  Result:= Default(TWorkFilter);
  Result.Statuses:= Copy(AChecked);
  Result.NoStatus:= Length(AChecked) = 0;
  Result.UnitPas := AUnitPas;
  Result.Text    := Trim(AText);
end;

// AFilter's statuses let a row of AStatus through: an exact entry, or WORK_STATUS_OTHER
// for a status outside the six.
function StatusPasses(const AStatus: string; const AFilter: TWorkFilter): Boolean;
begin
  if AFilter.NoStatus then
    Exit(False);
  if Length(AFilter.Statuses) = 0 then
    Exit(True);
  if StatusRank(AStatus) = Length(STATUS_ORDER) then
    Exit(MatchText(WORK_STATUS_OTHER, AFilter.Statuses));
  Result:= MatchText(AStatus, AFilter.Statuses);
end;

// AFilter lets ARow through.
function Passes(const ARow: TPasUseRow; const AFilter: TWorkFilter): Boolean;
begin
  if not StatusPasses(ARow.Status, AFilter) then
    Exit(False);
  if (AFilter.UnitPas <> '') and not SameText(ARow.UnitPas, AFilter.UnitPas) then
    Exit(False);
  Result:= (AFilter.Text = '') or ContainsText(ARow.Member, AFilter.Text) or ContainsText(ARow.Instance, AFilter.Text);
end;

function FilterRows(const ARows: TArray<TPasUseRow>; const AFilter: TWorkFilter): TArray<TPasUseRow>;
begin
  Result:= nil;
  for var LRow: TPasUseRow in ARows do
    if Passes(LRow, AFilter) then
      Result:= Result + [LRow];
end;

// SortRows' order on two rows; the original index breaks ties (stable).
function CompareRows(const A, B: TPasUseRow; AIndexA, AIndexB: Integer): Integer;
begin
  Result:= StatusRank(A.Status) - StatusRank(B.Status);
  if Result = 0 then
    Result:= CompareText(A.UnitPas, B.UnitPas);
  if Result = 0 then
    Result:= Ord(A.Instance = '') - Ord(B.Instance = ''); // globals last within a unit
  if Result = 0 then
    Result:= CompareText(A.Instance, B.Instance);
  if Result = 0 then
    Result:= CompareText(A.Member, B.Member);
  if Result = 0 then
    Result:= AIndexA - AIndexB;
end;

procedure SortRows(var ARows: TArray<TPasUseRow>);
var
  LOrder: TArray<Integer>;
  LRows : TArray<TPasUseRow>;
begin
  // Sort indices, not records: TArray.Sort is not stable, the index tie-break makes it so.
  LRows:= ARows;
  SetLength(LOrder, Length(LRows));
  for var I: Integer:= 0 to High(LOrder) do
    LOrder[I]:= I;
  TArray.Sort<Integer>(LOrder, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result:= CompareRows(LRows[A], LRows[B], A, B);
    end));
  SetLength(ARows, Length(LRows));
  for var I: Integer:= 0 to High(LOrder) do
    ARows[I]:= LRows[LOrder[I]];
end;

// The Lines column: the line numbers, comma-separated.
function LinesText(const ALines: TArray<Integer>): string;
var
  LParts: TArray<string>;
begin
  LParts:= nil;
  for var LLine: Integer in ALines do
    LParts:= LParts + [IntToStr(LLine)];
  Result:= string.Join(', ', LParts);
end;

function DeclaredInText(const ARow: TPasUseRow): string;
begin
  if (ARow.Resolution = '') or SameText(ARow.Resolution, PAS_RES_RESOLVED) then
  begin
    if (ARow.DeclaringUnit <> '') and (ARow.DeclaredIn <> '') then
      Result:= ARow.DeclaringUnit + '.' + ARow.DeclaredIn
    else
      Result:= ARow.DeclaringUnit + ARow.DeclaredIn;
  end
  else if SameText(ARow.Resolution, PAS_RES_AMBIGUOUS) then
    Result:= AMBIGUOUS_PREFIX + string.Join(', ', ARow.Candidates)
  else if SameText(ARow.Resolution, PAS_RES_CLASS_NOT_FOUND) then
    Result:= CLASS_NOT_FOUND_CELL
  else if SameText(ARow.Resolution, PAS_RES_MEMBER_NOT_FOUND) then
    Result:= MEMBER_NOT_FOUND_CELL
  else if SameText(ARow.Resolution, PAS_RES_KIND_UNKNOWN) then
    Result:= KIND_UNKNOWN_DECL_CELL
  else
    Result:= Format(OTHER_RESOLUTION_FMT, [ARow.Resolution]);
end;

function RowDisplay(const ARow: TPasUseRow): TArray<string>;
var
  LInstance : string;
  LPair     : string;
  LKind     : string;
begin
  if ARow.Instance = '' then
  begin
    LInstance:= WORK_GLOBAL_INSTANCE;
    LPair    := WORK_GLOBAL_PAIR;
  end
  else
  begin
    LInstance:= ARow.Instance;
    LPair    := Format(PAIR_FMT, [ARow.FromType, ARow.ToType]);
  end;
  LKind:= if (ARow.Kind = '') and (ARow.Resolution <> '') then KIND_UNKNOWN_CELL else ARow.Kind;
  Result:= [ExtractFileName(ARow.UnitPas), LInstance, LPair, ARow.Member, LKind, ARow.Status, LinesText(ARow.Lines), DeclaredInText(ARow)];
end;

function WorkColumns: TArray<string>;
begin
  Result:= ['Unit', 'Instance', 'From -> To', 'Member', 'Kind', 'Status', 'Lines', 'Declared in'];
end;

function WorkListSummary(const ARows: TArray<TPasUseRow>; AState: TWorkListState): string;
var
  LCount: array[RANK_UNMAPPED..RANK_MAPPED] of Integer;
  LRank : Integer;
  LOther: Integer;
begin
  case AState of
    wlsNoRun       : Exit(WORK_NO_RUN);
    wlsNoCapability: Exit(WORK_NO_CAPABILITY);
    wlsNoConverted : Exit(WORK_NO_CONVERTED);
  end;
  FillChar(LCount, SizeOf(LCount), 0);
  LOther:= 0;
  for var LRow: TPasUseRow in ARows do
  begin
    LRank:= StatusRank(LRow.Status);
    if LRank <= High(LCount) then
      Inc(LCount[LRank])
    else
      Inc(LOther);
  end;
  Result:= Format(SUMMARY_FMT, [LCount[RANK_UNMAPPED] + LCount[RANK_GLOBAL] + LCount[RANK_CAST_REFUSED] + LCount[RANK_NOT_REWRITTEN],
    LCount[RANK_UNMAPPED], LCount[RANK_GLOBAL], LCount[RANK_CAST_REFUSED], LCount[RANK_NOT_REWRITTEN],
    LCount[RANK_SAME_NAME] + LCount[RANK_MAPPED]]);
  if LOther > 0 then
    Result:= Result + Format(OTHER_FMT, [LOther]);
end;

function MergeRun(const AOld, ANew: TArray<TPasUseRow>; ANewRunId: Integer): TArray<TPasUseRow>;
begin
  Result:= nil;
  for var LRow: TPasUseRow in AOld + ANew do
    if LRow.RunId = ANewRunId then
      Result:= Result + [LRow];
end;

function WorkUnits(const ARows: TArray<TPasUseRow>): TArray<string>;
begin
  Result:= nil;
  for var LRow: TPasUseRow in ARows do
    if not MatchText(LRow.UnitPas, Result) then
      Result:= Result + [LRow.UnitPas];
end;

function WorkGoTo(const ARow: TPasUseRow; AFileExists: Boolean; ALineCount: Integer): TWorkGoTo;
var
  LLine: Integer;
begin
  Result:= Default(TWorkGoTo);
  if not AFileExists then
  begin
    Result.Status:= Format(NOT_FOUND_FMT, [ARow.UnitPas]);
    Exit;
  end;
  if Length(ARow.Lines) = 0 then
  begin
    Result.Ok    := True;
    Result.Clip  := ARow.UnitPas;
    Result.Status:= Format(COPIED_NO_LINE_FMT, [ExtractFileName(ARow.UnitPas)]);
    Exit;
  end;
  LLine:= ARow.Lines[0];
  if LLine > ALineCount then
  begin
    Result.Status:= Format(PAST_EOF_FMT, [ARow.UnitPas, ALineCount, LLine]);
    Exit;
  end;
  Result.Ok    := True;
  Result.Clip  := Format(GOTO_FMT, [ARow.UnitPas, LLine]);
  Result.Status:= Format(COPIED_FMT, [Format(GOTO_FMT, [ExtractFileName(ARow.UnitPas), LLine]), LLine]);
end;

end.
