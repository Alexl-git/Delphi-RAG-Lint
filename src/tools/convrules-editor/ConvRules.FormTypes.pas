unit ConvRules.FormTypes;

{ The distinct component TYPES used on one or more .dfm forms, plus the pure
  predicates that decide how each one is presented in the form-types panel.

  WHY A SEPARATE UNIT FROM ConvRules.Usage. Usage answers "which PROPERTIES of a
  chosen class does this form assign" -- it needs a From class and reports property
  names. This unit answers the question that comes BEFORE that one: "what types are
  on this form at all, and which of them are worth writing a rule for". The two
  share ParseBlockHeader (exported by Usage for exactly this reason) so there is one
  DFM object-header parser, not two.

  NOTHING HERE FILTERS THE LIST DOWN TO VISUAL CONTROLS. Owner's ruling 2026-09-04:
  any type on a form may be worth converting -- TStringField -> TFDStringField is a
  real conversion -- so the visual/non-visual distinction is presented as a MARK and
  never as a filter.

  VCL-free and side-effect-free, so every decision here is unit-tested headlessly. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.RegularExpressions
  , ConvRules.SkipList
  ;

type
  /// <summary>Whether a form type is a visual control, as far as the index can
  /// tell.</summary>
  /// <remarks>
  /// tvkUnknown is NOT a synonym for non-visual: it means the type was
  /// not found in the descendant set the caller supplied (unindexed, or a
  /// project-local type). Rendering it as "not a control" would turn absence of
  /// evidence into evidence of absence, so the panel shows '?'.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (ConvRules.FormTypes.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTypeVisualKind = (tvkUnknown, tvkVisual, tvkNonVisual);

  /// <summary>Where a class row came from.</summary>
  /// <remarks>
  /// roDfm: instantiated on the form (the real conversion candidates).
  /// roPas: declared by the unit. roBoth: both -- a form class is normally this.
  /// roDfm is ordinal 0, so Default(TFormTypeRow) -- as ScanDfmTypes builds every
  /// row -- already carries the right origin without an explicit assignment.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (ConvRules.FormTypes.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRowOrigin = (roDfm, roPas, roBoth);

  /// <summary>What the row means to the operator, and so how it is painted.</summary>
  /// <remarks>
  /// Skipped WINS over Ruled: it is the user's explicit decision and must
  /// not be masked by a derived fact. Before 2026-09-20 both rendered as the same
  /// grey, which made "already done" and "filtered out" indistinguishable -- the
  /// defect this type exists to remove.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (ConvRules.FormTypes.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRowState = (rsToDo, rsRuled, rsSkipped);

  /// <summary>One distinct component type found on the scanned form(s), or
  /// declared in the unit.</summary>
  /// <remarks>
  /// ScanDfmTypes fills TypeName and Count only. Visual, Origin, Ruled,
  /// RuledBy and RuleCount are decoration applied afterwards by the caller, which
  /// is what keeps the harvest independent of the index and of the rule catalog.
  /// Skipped is the user's own mark, loaded from and saved to the skip file -- it
  /// is deliberately NOT derived, so re-scanning a form never discards a decision.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.FormTypes.MergeFormTypes (ConvRules.FormTypes.pas), ConvRules.FormTypes.RowsFromCounts (ConvRules.FormTypes.pas), ConvRules.FormTypes.ScanDfmTypes (ConvRules.FormTypes.pas), ConvRules.FormTypes.SortedByName (ConvRules.FormTypes.pas), declaration (ConvRules.FormTypes.pas) (+4 more)</para>
  /// <para>Used in units: ConvRules.FormTypes, ConvRules.MainForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFormTypeRow = record
    TypeName : string         ;
    Count    : Integer        ;
    Visual   : TTypeVisualKind;
    Origin   : TRowOrigin     ;
    Skipped  : Boolean        ;
    Ruled    : Boolean        ;
    RuledBy  : string         ;
    RuleCount: Integer        ;
  end;

  /// <summary>The progress line: how many classes, and where they stand.</summary>
  /// <remarks>
  /// Ruled + Skipped + ToDo always sums to Total -- CountRows partitions
  /// every row into exactly one bucket, via RowState.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.FormTypes.CountRows (ConvRules.FormTypes.pas), ConvRules.MainForm.TConvRulesForm.RefreshFormTypes (ConvRules.MainForm.pas), declaration (ConvRules.FormTypes.pas)</para>
  /// <para>Used in units: ConvRules.FormTypes, ConvRules.MainForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRowCounts = record
    Total  : Integer;
    Ruled  : Integer;
    Skipped: Integer;
    ToDo   : Integer;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.FormTypes.MergeFormTypes (ConvRules.FormTypes.pas), ConvRules.MainForm.TConvRulesForm.HarvestFormTypes (ConvRules.MainForm.pas), declaration (ConvRules.FormTypes.pas), declaration (ConvRules.MainForm.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFormTypeRows = TArray<TFormTypeRow>;

/// <summary>PURE: the distinct component types declared in one .dfm text, with an
/// instance count each, sorted by type name (case-insensitive ascending).</summary>
/// <param name="AText">The whole .dfm as text. A binary .dfm simply yields
/// nothing, as it does everywhere else in this editor.</param>
/// <returns>One row per distinct type; Count is the number of 'object'/'inherited'/
/// 'inline' declarations of it. Only TypeName and Count are set.</returns>
/// <remarks>
/// Name-ascending, not count-descending, on purpose: it groups a family
/// (every TOvc*) together, which is how a conversion is actually chosen. The high
/// counts are noise -- VARINSP.dfm's largest is 388 TLabel.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.HarvestFormTypes (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.BlockFile.SplitRawLines, ConvRules.FormTypes.RowsFromCounts, ConvRules.Usage.ParseBlockHeader/2, Default, UpperCase</para>
/// <para>Returns: RowsFromCounts(Counts)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockFile.SplitRawLines"/>
/// <seealso cref="ConvRules.FormTypes.RowsFromCounts"/>
/// <seealso cref="ConvRules.Usage.ParseBlockHeader"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ScanDfmTypes(const AText: string): TFormTypeRows;

/// <summary>PURE: union of several forms' type rows, summing the counts of a type
/// that appears on more than one.</summary>
/// <param name="AParts">One array per scanned form; empty parts are ignored.</param>
/// <returns>The merged rows, sorted as ScanDfmTypes sorts.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.HarvestFormTypes (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.FormTypes.RowsFromCounts, UpperCase</para>
/// <para>Returns: RowsFromCounts(Counts)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.FormTypes.RowsFromCounts"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MergeFormTypes(const AParts: TArray<TFormTypeRows>): TFormTypeRows;

/// <summary>PURE: True when AUnitName is a standard Delphi VCL or FMX unit.</summary>
/// <param name="AUnitName">A declaring unit name, qualified or not; '' is False.</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
/// <remarks>
/// Deliberately LITERAL -- only the 'Vcl.' and 'FMX.' namespaces, because
/// that is what the checkbox offering this says. System./Data./Winapi. types such
/// as TIntegerField are RTL but are not "standard Delphi controls", and silently
/// hiding 103 TIntegerField behind a box labelled VCL/FMX would be a surprise.
/// Use a regex condition for those.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.FormTypes.TypeIsExcluded (ConvRules.FormTypes.pas)</para>
/// <para>Calls: StartsText, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsStandardVclOrFmxUnit(const AUnitName: string): Boolean;

/// <summary>PURE: True when a type should be greyed as excluded by the filter.</summary>
/// <param name="ATypeName">The bare type name, e.g. 'TOvcTable'.</param>
/// <param name="ADeclaringUnit">Its declaring unit, or '' when unresolved.</param>
/// <param name="APatterns">Exclusion regexes; a type is excluded when ANY of them
/// matches (OR), so order is irrelevant. Blank patterns are skipped.</param>
/// <param name="AExcludeStandard">Also exclude anything whose declaring unit
/// satisfies IsStandardVclOrFmxUnit.</param>
/// <param name="AError">'' on success; otherwise the FIRST malformed pattern and
/// its message. A malformed pattern never excludes and never raises.</param>
/// <returns>True when the type is excluded.</returns>
/// <remarks>
/// Matching is case-insensitive and UNANCHORED, so 'Ovc' matches
/// 'TOvcTable' -- anchor with ^ or $ to be strict. A malformed pattern failing
/// OPEN (excluding nothing) is only safe because AError is surfaced in the panel;
/// a silent fail-open here would hide the fact that a condition never ran.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: ConvRules.FormTypes.IsStandardVclOrFmxUnit, Format, Trim</para>
/// <para>Returns: StdHit or PatHit</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Mutates: AError (out)</para>
/// <seealso cref="ConvRules.FormTypes.IsStandardVclOrFmxUnit"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TypeIsExcluded(const ATypeName, ADeclaringUnit: string; const APatterns: TArray<string>; AExcludeStandard: Boolean; out AError: string): Boolean;

/// <summary>PURE: union of a form's .dfm instance rows and a unit's declared
/// class names into one class-row set, origin-marked.</summary>
/// <param name="ADfmRows">Rows already scanned from the form (ScanDfmTypes /
/// MergeFormTypes); their order and Count survive unchanged.</param>
/// <param name="APasClasses">Class names declared in the unit; blank entries are
/// ignored.</param>
/// <returns>The .dfm rows first (unchanged order), then the pas-only names
/// name-sorted; a name present in both becomes ONE row with Origin = roBoth.
/// </returns>
/// <remarks>
/// Matching is case-insensitive (SameText). The .dfm rows lead because they are
/// the classes a conversion actually targets; declared-only classes are offered
/// after, so the operator sees "what is really on the form" before "what else
/// this unit merely declares".
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.HarvestUnitClasses (ConvRules.MainForm.pas)</para>
/// <para>Calls: CompareText, Copy, Default, SameText, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MergeClassRows(const ADfmRows: TFormTypeRows; const APasClasses: TArray<string>): TFormTypeRows;

/// <summary>PURE: the HarvestUnitClasses status-line suffix for one
/// TEngineAdapter.OutlineClasses outcome.</summary>
/// <param name="ASucceeded">OutlineClasses' own return value.</param>
/// <param name="AIndexedNow">OutlineClasses' AIndexedNow -- True only when a
/// scratch index had to be built to answer. Ignored when ASucceeded is
/// False: a failed call has nothing to say about indexing.</param>
/// <param name="AFileName">The unit's bare file name (e.g.
/// ExtractFileName of the .pas path); used only in the "scratch index built"
/// message.</param>
/// <param name="AError">OutlineClasses' AError; used only in the
/// fallback-to-text-scan message, quoted verbatim.</param>
/// <returns>'' when the engine answered without having to index (ASucceeded
/// and not AIndexedNow) -- nothing worth telling the operator. A one-time
/// "scratch index built" note when ASucceeded and AIndexedNow. A
/// fallback-to-text-scan NOTE naming AError when not ASucceeded.</returns>
/// <remarks>
/// PURE: no process spawn, no I/O -- classifies an outcome the caller already
/// computed. Deliberately independent of how many classes were found: a
/// legitimately class-less unit (e.g. a non-form utility unit) is not an
/// error and gets no message of its own, same as before this function
/// existed. Extracted from HarvestUnitClasses (ConvRules.MainForm.pas, which
/// ConvRulesModelTests.dpr does not compile) so this branching is reachable
/// by an automated test.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.HarvestUnitClasses (ConvRules.MainForm.pas)</para>
/// <para>Calls: Format</para>
/// <para>Returns: Format(' NOTE: the indexer could not list classes (%s) -- fell back to a text scan, which cannot see conditionals or comments.', [AError]); Format(' (%s was not in any index; a local scratch index was built for it -- once only)', [AFileName]); ''</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DescribeOutlineOutcome(ASucceeded, AIndexedNow: Boolean; const AFileName, AError: string): string;

/// <summary>PURE: the row's state -- what the operator should see and how the
/// row should be painted.</summary>
/// <param name="ARow">A decorated row.</param>
/// <returns>rsSkipped when Skipped is set (wins), else rsRuled when Ruled is
/// set, else rsToDo.</returns>
/// <remarks>
/// Skipped is an explicit user decision and must never be masked by a
/// derived fact such as Ruled.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.FormTypes.CountRows (ConvRules.FormTypes.pas), ConvRules.MainForm.TConvRulesForm.FormTypeDrawItem (ConvRules.MainForm.pas)</para>
/// <para>Returns: rsSkipped; rsRuled; rsToDo</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RowState(const ARow: TFormTypeRow): TRowState;

/// <summary>PURE: partitions ARows into Total/Ruled/Skipped/ToDo via RowState.
/// </summary>
/// <param name="ARows">The full row set, unfiltered.</param>
/// <returns>Ruled + Skipped + ToDo always equals Total -- every row is counted
/// exactly once.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.FormTypes.RowState, Default</para>
/// <para>Returns: Default(TRowCounts)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.FormTypes.RowState"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CountRows(const ARows: TFormTypeRows): TRowCounts;

/// <summary>PURE: the indexes of ARows whose TypeName matches ASearch.</summary>
/// <param name="ARows">The full row set; indexes are into this array.</param>
/// <param name="ASearch">A case-insensitive substring match against TypeName;
/// blank or whitespace-only means "everything is visible".</param>
/// <returns>Indexes in ascending order; the search filters VISIBILITY only and
/// never changes CountRows' totals.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes (ConvRules.MainForm.pas)</para>
/// <para>Calls: ContainsText, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function VisibleRowIndexes(const ARows: TFormTypeRows; const ASearch: string): TArray<Integer>;

/// <summary>PURE: maps a list-box position through a visible-row index to the
/// row it stands for.</summary>
/// <param name="AVisibleRows">The list-slot -> row-index map, as VisibleRowIndexes
/// returns it.</param>
/// <param name="AListIndex">The list box's ItemIndex (0-based); -1 means no
/// selection.</param>
/// <param name="ARowCount">Length of the full row array AVisibleRows indexes
/// into -- NOT Length(AVisibleRows).</param>
/// <returns>The row index into the full row array, or -1 when AListIndex is out
/// of range, AVisibleRows is empty, or the mapped row index no longer fits
/// ARowCount (a stale map read against a row array that has since shrunk).</returns>
/// <remarks>
/// This is the ONLY place a list position becomes a row index. The list
/// shows only the rows the search box leaves visible, so a list slot and a row
/// index are two different numbers the moment a search is active; indexing the
/// row array with a list position directly addresses the wrong class.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.FormTypeDrawItem (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.SelectedRowIndex (ConvRules.MainForm.pas)</para>
/// <para>Returns: -1; AVisibleRows[AListIndex]</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveSelectedRow(const AVisibleRows: TArray<Integer>; AListIndex, ARowCount: Integer): Integer;

/// <summary>PURE: the reverse of ResolveSelectedRow -- the list-box position that
/// currently shows ARowIndex, so a row can be re-selected after a refresh.</summary>
/// <param name="AVisibleRows">The list-slot -> row-index map, as VisibleRowIndexes
/// returns it.</param>
/// <param name="ARowIndex">A row index into the full row array.</param>
/// <returns>The list slot showing that row, or -1 when the row is not currently
/// visible (filtered out, or not present in the map at all).</returns>
/// <remarks>
/// Linear scan -- AVisibleRows is one list box's worth of rows, not a large
/// index, so there is nothing to gain from a reverse lookup structure.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.ToggleFormTypeSkip (ConvRules.MainForm.pas)</para>
/// <para>Returns: -1; k</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ListIndexForRow(const AVisibleRows: TArray<Integer>; ARowIndex: Integer): Integer;

/// <summary>PURE: the display text for one form-types-list row -- origin,
/// visual mark, type name, instance count and ruled-by suffix, in that
/// order.</summary>
/// <param name="ARow">A decorated row.</param>
/// <returns>'&lt;org&gt; &lt;mark&gt; TypeName', with '  (Count)' appended when
/// Count is nonzero, '  -- RuledBy' appended when Ruled, and a further
/// '  +N more' when RuleCount counts more rules than the one named in
/// RuledBy.</returns>
/// <remarks>
/// Extracted from FormTypeDrawItem (ConvRules.MainForm.pas, which
/// ConvRulesModelTests.dpr does not compile) so the three renderings are
/// reachable by an automated test. Colour and the skipped strikethrough are
/// VCL painting decisions and stay in FormTypeDrawItem; this function only
/// produces the text.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.FormTypeDrawItem (ConvRules.MainForm.pas)</para>
/// <para>Calls: Format</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DescribeFormTypeRow(const ARow: TFormTypeRow): string;

/// <summary>PURE: the form-types panel's progress-line caption.</summary>
/// <param name="ACnt">The row counts, as CountRows partitions them.</param>
/// <param name="AVisibleCount">How many rows the search box currently leaves
/// visible (Length of VisibleRowIndexes' result).</param>
/// <param name="AFilterError">The first malformed exclusion pattern's
/// message, or '' when the filter is well-formed.</param>
/// <returns>'FILTER ERROR -- ' plus AFilterError when it is set (this wins
/// over everything else, since a malformed filter's counts cannot be
/// trusted); otherwise '&lt;shown&gt; of &lt;total&gt; shown -- ...' when the
/// search is hiding rows; otherwise '&lt;total&gt; classes -- ...'.</returns>
/// <remarks>
/// Extracted from RefreshFormTypes (ConvRules.MainForm.pas, which
/// ConvRulesModelTests.dpr does not compile) so the three-way branching is
/// reachable by an automated test.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes (ConvRules.MainForm.pas)</para>
/// <para>Calls: Format</para>
/// <para>Returns: 'FILTER ERROR -- ' + AFilterError; Format('%d of %d shown -- %d ruled, %d skipped, %d to do', [AVisibleCount, ACnt.Total, ACnt.Ruled, ACnt.Skipped, ACnt.ToDo]); Format('%d classes -- %d ruled, %d skipped, %d to do', [ACnt.Total, ACnt.Ruled, ACnt.Skipped, ACnt.ToDo])</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormTypesProgressCaption(const ACnt: TRowCounts; AVisibleCount: Integer; const AFilterError: string): string;

/// <summary>PURE: stamps a parsed skip list's marks onto a row set.</summary>
/// <param name="ARows">The rows to stamp; not mutated in place.</param>
/// <param name="AList">The parsed skip list -- IsSkipped is the source of truth.</param>
/// <returns>A copy of ARows with every row's Skipped set from
/// ConvRules.SkipList.IsSkipped(AList, TypeName).</returns>
/// <remarks>
/// A row not present in AList.Classes comes back UNMARKED, even if it was marked
/// before this call -- a hand edit that removes a "skip" line from the file must
/// win the moment the file is next loaded, the same "file is truth" rule
/// ApplySkipMarks (ConvRules.MainForm.pas) exists to apply on every harvest.
/// </remarks>
function StampSkipMarks(const ARows: TFormTypeRows; const AList: TSkipList): TFormTypeRows;

/// <summary>PURE: folds a row set's current Skipped flags into a skip list.</summary>
/// <param name="AList">The skip list to fold into; its Filters and Foreign lines
/// pass through unchanged.</param>
/// <param name="ARows">The current rows.</param>
/// <returns>The updated skip list, ready for ConvRules.SkipList.EmitSkipList.
/// </returns>
/// <remarks>
/// Writes EVERY row -- marked AND unmarked -- via
/// ConvRules.SkipList.SetSkipped, which is what makes UN-marking a class
/// persist to the file rather than simply omitting a "skip" line that was
/// never there to begin with. A class absent from ARows (not on the current
/// unit/form) is left UNTOUCHED in AList -- this function never evicts a mark
/// for a class it was not told about.
/// </remarks>
function SkipListFromRows(const AList: TSkipList; const ARows: TFormTypeRows): TSkipList;

/// <summary>PURE: marks every row TypeIsExcluded accepts as "do not convert".</summary>
/// <param name="ARows">The rows to test; not mutated in place.</param>
/// <param name="APatterns">Regex patterns, OR'd -- see TypeIsExcluded.</param>
/// <param name="ADeclaringUnits">Per-row declaring unit, PARALLEL to ARows (index i
/// answers for ARows[i]). The caller resolves these, because it costs an index
/// lookup per type (~1.7 s each) and must run only on demand, never as a side
/// effect of this pure function.</param>
/// <param name="AExcludeStandard">Also match rows whose declaring unit is
/// Vcl.*/FMX.* -- see IsStandardVclOrFmxUnit.</param>
/// <param name="AHits">Out: how many PREVIOUSLY-unmarked rows this call marked.
/// A row already marked stays marked and is not counted again.</param>
/// <param name="AError">Out: the first malformed pattern's message, or ''.</param>
/// <returns>A copy of ARows with every matching row's Skipped set True.</returns>
/// <remarks>
/// PURE and side-effect-free: it does not touch a skip list, only the rows --
/// the caller (ApplyNamedFilterClick, ConvRules.MainForm.pas) folds the result
/// into FSkipList and saves it, and records the filter itself by name for the
/// next session.
/// </remarks>
function ApplyNamedFilterToRows(const ARows: TFormTypeRows; const APatterns: TArray<string>; const ADeclaringUnits: TArray<string>; AExcludeStandard: Boolean; out AHits: Integer; out AError: string): TFormTypeRows;

implementation

uses
  System.StrUtils
  , ConvRules.Usage
  , ConvRules.BlockFile
  ;

const
  /// The namespaces the standard-controls checkbox covers. See IsStandardVclOrFmxUnit.
  STD_CONTROL_NAMESPACES: array[0..1] of string = ('Vcl.', 'FMX.');

  { Sorts rows by TypeName, case-insensitive ascending, and hands back the array.
  One place so ScanDfmTypes and MergeFormTypes cannot drift apart on ordering. }
function SortedByName(const ARows: TFormTypeRows): TFormTypeRows;
begin
  Result:= Copy(ARows, 0, Length(ARows));
  TArray.Sort<TFormTypeRow>(Result, TComparer<TFormTypeRow>.Construct( function(const L, R: TFormTypeRow): Integer begin Result:= CompareText(L.TypeName, R.TypeName); end));
end;

{ Folds counted type names out of a Counts map into sorted rows. }
function RowsFromCounts(ACounts: TDictionary<string, TFormTypeRow>): TFormTypeRows;
var
  Row: TFormTypeRow;
  i  : Integer     ;
begin
  SetLength(Result, ACounts.Count);
  i:= 0;
  for Row in ACounts.Values do
  begin
    Result[i]:= Row;
    Inc(i);
  end;
  Result:= SortedByName(Result);
end;

function ScanDfmTypes(const AText: string): TFormTypeRows;
var
  Lines : TArray<TRawLine>                 ;
  Counts: TDictionary<string, TFormTypeRow>;
  i     : Integer                          ;
  Cls   : string                           ;
  Key   : string                           ;
  Row   : TFormTypeRow                     ;
begin
  Counts:= TDictionary<string, TFormTypeRow>.Create;
  try
    Lines:= SplitRawLines(AText);
    for i:= 0 to High(Lines) do
    begin
      // ParseBlockHeader keys off the line's FIRST TOKEN, so a type named inside a
      // quoted value ("Caption = 'object fake: TNotReal'") can never reach here --
      // its first token is the property name. That is why no literal-stripping pass
      // is needed for the header scan, unlike ScanDfmText's terminator search.
      if not ParseBlockHeader(Lines[i].Text, Cls) then
        Continue;
      if Cls = '' then
        Continue;

      Key:= UpperCase(Cls);
      if Counts.TryGetValue(Key, Row) then
        Inc(Row.Count)
      else
      begin
        Row:= Default(TFormTypeRow);
        Row.TypeName:= Cls; // first spelling seen wins
        Row.Count   := 1;
      end;
      Counts.AddOrSetValue(Key, Row);
    end; // for
    Result:= RowsFromCounts(Counts);
  finally
    Counts.Free;
  end; // try
end; // function

function MergeFormTypes(const AParts: TArray<TFormTypeRows>): TFormTypeRows;
var
  Counts: TDictionary<string, TFormTypeRow>;
  Part  : TFormTypeRows                    ;
  Src   : TFormTypeRow                     ;
  Row   : TFormTypeRow                     ;
  Key   : string                           ;
begin
  Counts:= TDictionary<string, TFormTypeRow>.Create;
  try
    for Part in AParts do
    for Src  in Part   do
      begin
        if Src.TypeName = '' then
          Continue;
        Key:= UpperCase(Src.TypeName);
        if Counts.TryGetValue(Key, Row) then
          Inc(Row.Count, Src.Count)
        else
          Row:= Src;
        Counts.AddOrSetValue(Key, Row);
      end;
    Result:= RowsFromCounts(Counts);
  finally
    Counts.Free;
  end; // try
end; // function

function IsStandardVclOrFmxUnit(const AUnitName: string): Boolean;
var
  Ns: string;
begin
  Result:= False;
  if Trim(AUnitName) = '' then
    Exit;
  for Ns in STD_CONTROL_NAMESPACES do
    if StartsText(Ns, Trim(AUnitName)) then
      Exit(True);
end;

function TypeIsExcluded(const ATypeName, ADeclaringUnit: string; const APatterns: TArray<string>; AExcludeStandard: Boolean; out AError: string): Boolean;
var
  P      : string ;
  StdHit : Boolean;
  PatHit : Boolean;
begin
  AError:= '';
  StdHit:= AExcludeStandard and IsStandardVclOrFmxUnit(ADeclaringUnit);
  PatHit:= False;

  // Every pattern is evaluated even once one has matched, so a malformed condition
  // LATER in the list still reports. Reporting is the only thing that makes the
  // fail-open below safe: a bad pattern excludes nothing, and if that were silent
  // the user would read an un-greyed row as "my filter says keep this".
  for P in APatterns do
  begin
    if Trim(P) = '' then
      Continue;
    try
      if TRegEx.IsMatch(ATypeName, P, [roIgnoreCase]) then
        PatHit:= True;
    except
      on E: Exception do
        if AError = '' then
          AError:= Format('bad pattern "%s": %s', [P, E.Message]);
    end;
  end; // for

  Result:= StdHit or PatHit;
end; // function

function StampSkipMarks(const ARows: TFormTypeRows; const AList: TSkipList): TFormTypeRows;
var
  i: Integer;
begin
  Result:= Copy(ARows, 0, Length(ARows));
  for i:= 0 to High(Result) do
    Result[i].Skipped:= IsSkipped(AList, Result[i].TypeName);
end; // function

function SkipListFromRows(const AList: TSkipList; const ARows: TFormTypeRows): TSkipList;
var
  i: Integer;
begin
  Result:= AList;
  for i:= 0 to High(ARows) do
    Result:= SetSkipped(Result, ARows[i].TypeName, ARows[i].Skipped);
end; // function

function ApplyNamedFilterToRows(const ARows: TFormTypeRows; const APatterns: TArray<string>; const ADeclaringUnits: TArray<string>; AExcludeStandard: Boolean; out AHits: Integer; out AError: string): TFormTypeRows;
var
  i     : Integer;
  DeclU : string ;
  Err   : string ;
begin
  Result:= Copy(ARows, 0, Length(ARows));
  AHits := 0;
  AError:= '';
  for i:= 0 to High(Result) do
  begin
    if i <= High(ADeclaringUnits) then
      DeclU:= ADeclaringUnits[i]
    else
      DeclU:= '';
    if TypeIsExcluded(Result[i].TypeName, DeclU, APatterns, AExcludeStandard, Err) then
    begin
      if not Result[i].Skipped then
        Inc(AHits);
      Result[i].Skipped:= True;
    end;
    if (Err <> '') and (AError = '') then
      AError:= Err;
  end; // for
end; // function

function MergeClassRows(const ADfmRows: TFormTypeRows; const APasClasses: TArray<string>): TFormTypeRows;
var
  j   : Integer;
  Nm  : string ;
  Hit : Boolean;
  Pas : TArray<string>;
  Row : TFormTypeRow  ;
begin
  // .dfm rows keep their order (ScanDfmTypes already sorted them by name) and lead,
  // because they are the classes a conversion actually targets. Declared-only
  // classes follow, name-sorted. roDfm is ordinal 0, so a row ScanDfmTypes built
  // with Default(TFormTypeRow) already carries the right origin.
  Result:= Copy(ADfmRows);
  Pas   := nil;
  for Nm in APasClasses do
  begin
    if Trim(Nm) = '' then
      Continue;
    Hit:= False;
    for j:= 0 to High(Result) do
      if SameText(Result[j].TypeName, Nm) then
      begin
        Result[j].Origin:= roBoth;
        Hit             := True;
        Break;
      end;
    if not Hit then
      Pas:= Pas + [Trim(Nm)];
  end;

  TArray.Sort<string>(Pas, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result:= CompareText(L, R);
    end));

  for Nm in Pas do
  begin
    Row         := Default(TFormTypeRow);
    Row.TypeName:= Nm;
    Row.Count   := 0;
    Row.Origin  := roPas;
    Result      := Result + [Row];
  end;
end; // function

function DescribeOutlineOutcome(ASucceeded, AIndexedNow: Boolean; const AFileName, AError: string): string;
begin
  if not ASucceeded then
    Exit(Format(' NOTE: the indexer could not list classes (%s) -- fell back to a text scan, which cannot see conditionals or comments.', [AError]));
  if AIndexedNow then
    Exit(Format(' (%s was not in any index; a local scratch index was built for it -- once only)', [AFileName]));
  Result:= '';
end; // function

function RowState(const ARow: TFormTypeRow): TRowState;
begin
  if ARow.Skipped then
    Exit(rsSkipped);
  if ARow.Ruled then
    Exit(rsRuled);
  Result:= rsToDo;
end; // function

function CountRows(const ARows: TFormTypeRows): TRowCounts;
var
  R: TFormTypeRow;
begin
  Result:= Default(TRowCounts);
  for R in ARows do
  begin
    Inc(Result.Total);
    case RowState(R) of
      rsSkipped: Inc(Result.Skipped);
      rsRuled  : Inc(Result.Ruled  );
    else
      Inc(Result.ToDo);
    end;
  end;
end; // function

function VisibleRowIndexes(const ARows: TFormTypeRows; const ASearch: string): TArray<Integer>;
var
  i: Integer;
  S: string ;
begin
  Result:= nil;
  S     := Trim(ASearch);
  for i:= 0 to High(ARows) do
    if (S = '') or ContainsText(ARows[i].TypeName, S) then
      Result:= Result + [i];
end; // function

function ResolveSelectedRow(const AVisibleRows: TArray<Integer>; AListIndex, ARowCount: Integer): Integer;
begin
  Result:= -1;
  if (AListIndex < 0) or (AListIndex > High(AVisibleRows)) then
    Exit;
  Result:= AVisibleRows[AListIndex];
  if (Result < 0) or (Result >= ARowCount) then
    Result:= -1;
end; // function

function ListIndexForRow(const AVisibleRows: TArray<Integer>; ARowIndex: Integer): Integer;
var
  k: Integer;
begin
  Result:= -1;
  for k:= 0 to High(AVisibleRows) do
    if AVisibleRows[k] = ARowIndex then
      Exit(k);
end; // function

function DescribeFormTypeRow(const ARow: TFormTypeRow): string;
var
  Mark: string;
  Org : string;
begin
  case ARow.Visual of
    tvkVisual   : Mark:= '[V]';
    tvkNonVisual: Mark:= '[N]';
  else
    Mark:= '[?]';
  end;

  // Origin is what tells a conversion candidate from a class the unit merely
  // declares; without it the two are indistinguishable in one list. roBoth
  // reads as dfm, same as roDfm -- the .dfm rows lead the merged list (see
  // MergeClassRows), so "on the form" is the more useful thing to say first.
  if ARow.Origin = roPas then
    Org:= 'pas'
  else
    Org:= 'dfm';

  Result:= Format('%s %s %s', [Org, Mark, ARow.TypeName]);
  if ARow.Count > 0 then
    Result:= Result + Format('  (%d)', [ARow.Count]);
  if ARow.Ruled then
  begin
    Result:= Result + '  -- ' + ARow.RuledBy;
    if ARow.RuleCount > 1 then
      Result:= Result + Format('  +%d more', [ARow.RuleCount - 1]);
  end;
end; // function

function FormTypesProgressCaption(const ACnt: TRowCounts; AVisibleCount: Integer; const AFilterError: string): string;
begin
  // A malformed pattern excludes nothing, so without this branch the operator
  // would read an un-greyed row as "my filter kept this" when the condition
  // never ran at all.
  if AFilterError <> '' then
    Result:= 'FILTER ERROR -- ' + AFilterError
  else if AVisibleCount < ACnt.Total then
    Result:= Format('%d of %d shown -- %d ruled, %d skipped, %d to do', [AVisibleCount, ACnt.Total, ACnt.Ruled, ACnt.Skipped, ACnt.ToDo])
  else
    Result:= Format('%d classes -- %d ruled, %d skipped, %d to do', [ACnt.Total, ACnt.Ruled, ACnt.Skipped, ACnt.ToDo]);
end; // function

end.
