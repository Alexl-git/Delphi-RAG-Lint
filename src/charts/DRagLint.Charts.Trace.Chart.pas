unit DRagLint.Charts.Trace.Chart;

(* The round-trip CHART: the numbered trace drawn as a picture (a port of charts\src\Trace.Chart.ps1;
  the PowerShell output is the reference, byte for byte). A PURE function of the Form A model: no index
  access, no source reads, no file writes. The question unit passes ReadFormA of the bytes it wrote, so
  the chart is a pure function of trace.dlgraph (RT9), plus the leaf -> one-full-path map the bundle
  page already builds for its links. The result is the dot text and a manifest saying where every
  step, condition and facet went; the layout (dot.exe) is the caller's.

  The picture. Four lanes, left to right, from the TIERS header (client -> pipe -> server -> database).
  A step's lane comes from its SECTION and actor word, never from an index. Steps become ROWS of a
  card, one card per (lane, routine): a `CALLS X` step is a row of X's card, a step `in X` a row of
  X's card, so the request and its response read in one place. The ANCHOR's client rows are one chain
  card; a `.sql`-anchored step in the DATABASE lane is a column node (cylinder) every direction meets
  at; each send anchor is ONE crossing node holding the request and the response; a STOPS is its own
  red node; a FIRES step is a small event node; ALSO is a dashed sub-cluster. A WHEN / UNLESS is a
  guard ROW under the step it gates, verbatim (wrapped, never shortened, never quoted); a guard whose
  else note names a line also gets a red failure edge to that line. Identical rows in one card (the
  EnsureLoaded / LoadFromInternal sub-walk both directions run) are drawn ONCE carrying both numbers,
  `[21]/[51]`.

  Nothing is silently smaller. Every number is either on a drawn row or named in a disclosure row
  (`+N more ... not shown -- [aa]-[bb] ...`) that the Legend repeats; the Legend also carries the END
  TRACE line byte for byte, every section's generated note, and how many labels were shortened. The
  size rules: ALSO shows every row up to Caps.Also (15); a routine card, the anchor chain and the
  DERIVED card fold plain rows past Caps.Rows (14) but never a protected row (a guard, a crossing, a
  STOPS, a failure edge, a column); above Caps.Nodes (45) nodes the ladder folds ALSO, then every card
  with no protected row, and if the chart is still above the cap it is drawn anyway and the Legend
  says so. A fold of k rows draws one disclosure row on the card and one in the Legend, so a fold of
  fewer than 3 rows saves nothing and is not made; above Caps.Folds (5) folds the Legend carries ONE
  summary row (the folded steps' ranges when the row stays within CHART_SUMMARY_WIDTH characters, else
  only their count).

  Unknown section names, actor words outside the TIERS and an unnumbered item RAISE EChartsTrace
  (R19): a grammar that grows must grow this renderer, never fall into a default lane.

  PowerShell traps closed here: -match is case-INsensitive and -cmatch is not (the else-note tests
  use roIgnoreCase, the rest are exact); a hashtable and an [ordered] dictionary compare string keys
  case-INsensitively (the node, edge, fail-node and anchor-path maps use TIStringComparer); a
  pipeline that yields one element is a scalar (the WITH labels keep their empty strings, so
  `with[0]` can be ''); `$Node.Rows.IndexOf` counts the folded rows too (a port name is its row
  position); `Sort-Object -Unique` on ints is numeric; `-f '{0:00}'` is at least two digits; the
  5-line shortening raises the shortened count even when no cut fits. *)

interface

uses
  System.SysUtils, System.Generics.Collections, DRagLint.Charts.Trace.FormA;

const
  /// <summary>The section names the renderer knows (the Trace.FormA grammar's).</summary>
  CHART_SECTIONS: array[0..7] of string = ('ANCHOR', 'DERIVED', 'WRITE', 'SERVER', 'DATABASE', 'RESPONSE', 'READ', 'ALSO');
  /// <summary>The widest a cell line grows before it breaks.</summary>
  CHART_WIDTH = 72;
  /// <summary>The most lines a step row may take before its body is shortened.</summary>
  CHART_MAX_LINES = 5;
  /// <summary>The longest Legend summary row that still names the folded ranges.</summary>
  CHART_SUMMARY_WIDTH = 120;
  /// <summary>Lane ink: CLIENT border, fill, header.</summary>
  LANE_INK_CLIENT: array[0..2] of string = ('#2563EB', '#F2F6FF', '#1D4ED8');
  /// <summary>Lane ink: PIPE border, fill, header.</summary>
  LANE_INK_PIPE: array[0..2] of string = ('#B45309', '#FFF8EC', '#92400E');
  /// <summary>Lane ink: SERVER border, fill, header.</summary>
  LANE_INK_SERVER: array[0..2] of string = ('#047857', '#EEFBF4', '#065F46');
  /// <summary>Lane ink: DATABASE border, fill, header.</summary>
  LANE_INK_DATABASE: array[0..2] of string = ('#7C3AED', '#F6F1FF', '#5B21B6');
  /// <summary>Row text ink.</summary>
  INK_TEXT = '#1F2933';
  /// <summary>Dim ink (step numbers, anchors, notes).</summary>
  INK_DIM = '#6B7684';
  /// <summary>Guard keyword ink.</summary>
  INK_GUARD = '#B45309';
  /// <summary>Failure ink.</summary>
  INK_FAIL = '#B91C1C';
  /// <summary>Facet head ink.</summary>
  INK_FACET = '#0F766E';
  /// <summary>ALSO ink.</summary>
  INK_ALSO = '#8A94A6';

type
  /// <summary>The size caps of a chart (the PS -Caps hashtable, every key present).</summary>
  TChartCaps = record
    /// <summary>ALSO rows drawn before the rest fold.</summary>
    Also : Integer;
    /// <summary>Rows of a card, the anchor chain or DERIVED before plain rows fold.</summary>
    Rows : Integer;
    /// <summary>Nodes above which the ladder folds ALSO, then protected-row-free cards.</summary>
    Nodes: Integer;
    /// <summary>Folds above which the Legend carries one summary row.</summary>
    Folds: Integer;
    /// <summary>The defaults: 15 / 14 / 45 / 5.</summary>
    /// <returns>The default caps.</returns>
    class function Default: TChartCaps; static;
  end;

  /// <summary>One styled run of a cell: the PS segment @(text, ink, point size, bold).</summary>
  TChartSeg = record
    /// <summary>The run's text (escaped when the cell is built); '' is skipped.</summary>
    Text: string;
    /// <summary>The font colour; '' for none.</summary>
    Ink : string;
    /// <summary>The point size; 0 for none.</summary>
    Size: Integer;
    /// <summary>True for bold.</summary>
    Bold: Boolean;
    /// <summary>Builds a segment.</summary>
    /// <param name="pText">The run's text.</param>
    /// <param name="pInk">The font colour or ''.</param>
    /// <param name="pSize">The point size or 0.</param>
    /// <param name="pBold">True for bold.</param>
    /// <returns>The segment.</returns>
    class function Make(const pText, pInk: string; pSize: Integer; pBold: Boolean): TChartSeg; static;
  end;

  /// <summary>Where every step, condition and facet of the trace went, and the chart's totals.</summary>
  /// <remarks>Steps maps a step number (unpadded, '1') to 'drawn:&lt;node&gt;:&lt;port&gt;' or
  /// 'disclosed:&lt;legend row&gt;'. Conds and Facets are keyed '&lt;step&gt;|&lt;keyword or
  /// head&gt;|&lt;anchor or text&gt;' with the same values (a REGENERATE facet goes
  /// 'tooltip:&lt;node&gt;:&lt;port&gt;'). Owned by the caller of TraceChart.</remarks>
  TChartManifest = class
  private
    FSteps: TDictionary<string, string>;
    FConds: TDictionary<string, string>;
    FFacets: TDictionary<string, string>;
    FCollapses: TList<string>;
    FNodes: Integer;
    FLanes: string;
    FMerged: string;
    FUnlinked: Integer;
    FShortened: Integer;
    FLadder: string;
  public
    /// <summary>Step number -> where it went.</summary>
    property Steps: TDictionary<string, string> read FSteps write FSteps;
    /// <summary>Condition key -> where it went.</summary>
    property Conds: TDictionary<string, string> read FConds write FConds;
    /// <summary>Facet key -> where it went.</summary>
    property Facets: TDictionary<string, string> read FFacets write FFacets;
    /// <summary>The Legend rows that hid numbers.</summary>
    property Collapses: TList<string> read FCollapses write FCollapses;
    /// <summary>The node count (before any fold: folding removes rows, not nodes).</summary>
    property Nodes: Integer read FNodes write FNodes;
    /// <summary>'client/pipe/server/database' card counts.</summary>
    property Lanes: string read FLanes write FLanes;
    /// <summary>The multi-number rows, '[21]/[51]' joined by ','.</summary>
    property Merged: string read FMerged write FMerged;
    /// <summary>Anchored cells that had no single full path.</summary>
    property Unlinked: Integer read FUnlinked write FUnlinked;
    /// <summary>Step labels shortened to the line limit.</summary>
    property Shortened: Integer read FShortened write FShortened;
    /// <summary>The ladder rungs used, 'also,cards' (in order, no repeats).</summary>
    property Ladder: string read FLadder write FLadder;
    /// <summary>Constructor: creates an empty manifest.</summary>
    constructor Create;
    /// <summary>Frees the maps.</summary>
    destructor Destroy; override;
  end;

  /// <summary>The chart: the dot text and its manifest.</summary>
  /// <remarks>The caller frees Manifest.</remarks>
  TTraceChart = record
    /// <summary>The dot text, CRLF line ends, 7-bit ASCII.</summary>
    Dot     : string;
    /// <summary>Where every number went; owned by the caller.</summary>
    Manifest: TChartManifest;
  end;

/// <summary>The break positions of a text at a width: greedy, the last breakable space that keeps the line within the width, else the first one after it (a token longer than the width stays whole, never cut).</summary>
/// <param name="pText">The text to break.</param>
/// <param name="pWidth">The line width.</param>
/// <returns>The 0-based positions of the breaking spaces, ascending.</returns>
/// <remarks>A breakable space is ONE space between two non-spaces, so rejoining the pieces with one space returns the text exactly (a condition holding two spaces keeps them). Port of Get-ChartBreaks.</remarks>
function ChartBreaks(const pText: string; pWidth: Integer): TArray<Integer>;

/// <summary>The HTML of one cell from styled runs; each break space becomes a left-aligned line break.</summary>
/// <param name="pSegs">The runs; the breaks are computed over their concatenation.</param>
/// <param name="pWidth">The line width.</param>
/// <returns>FONT elements, text escaped; an empty run is skipped (an empty FONT is a dot syntax error).</returns>
/// <remarks>Port of ConvertTo-ChartCellHtml.</remarks>
function ChartCellHtml(const pSegs: TArray<TChartSeg>; pWidth: Integer = CHART_WIDTH): string;

/// <summary>Step numbers as the disclosure rows print them: two digits, runs folded.</summary>
/// <param name="pNums">The numbers, any order, duplicates allowed.</param>
/// <returns>'[74]-[76], [80]'.</returns>
/// <remarks>Port of Format-ChartNumbers.</remarks>
function FormatChartNumbers(const pNums: TArray<Integer>): string;

/// <summary>The lane of one step, from the text (section and actor word).</summary>
/// <param name="pSection">The section name.</param>
/// <param name="pItem">The step.</param>
/// <param name="pLanes">The upper-case tier words of the TIERS header.</param>
/// <returns>CLIENT, PIPE, SERVER or DATABASE.</returns>
/// <exception cref="EChartsTrace">The section has no lane rule, or the lane is not in the TIERS header (R19).</exception>
function TraceChartLane(const pSection: string; pItem: TTraceItem; const pLanes: TArray<string>): string;

/// <summary>What a step text names as its callee: `CALLS X`.</summary>
/// <param name="pText">The step text.</param>
/// <returns>X, or '' when none.</returns>
function TraceChartCallee(const pText: string): string;

/// <summary>What a step text names as its target: `CALLS X`, `... VIA X`, `FIRES d.E -> X`.</summary>
/// <param name="pText">The step text.</param>
/// <returns>X, or '' when none.</returns>
function TraceChartTarget(const pText: string): string;

/// <summary>The label words of a crossing edge, from its WITH facet.</summary>
/// <param name="pWith">The facet text.</param>
/// <returns>The whole alternative set when the facet is one (`rspError or rspOK`), the command when a payload follows it, else ''.</returns>
function TraceChartWithLabel(const pWith: string): string;

/// <summary>One Form A line of an item, for a tooltip (the text's own words, never re-phrased).</summary>
/// <param name="pItem">The step.</param>
/// <param name="pNums">The number text, e.g. '[09]'.</param>
/// <returns>'[09] SERVER CALLS X @file:1 -- note'.</returns>
function FormatTraceChartTip(pItem: TTraceItem; const pNums: string): string;

/// <summary>The chart of a numbered trace.</summary>
/// <param name="pTrace">A model whose items carry their numbers (ReadFormA's result, or the model after WriteFormA); not freed.</param>
/// <param name="pAnchorPaths">Leaf -> the one full path the indexes hold (case-insensitive); rows on any other leaf stay unlinked. May be nil.</param>
/// <param name="pCaps">The size caps (TChartCaps.Default).</param>
/// <returns>The dot text and its manifest; the caller frees the manifest.</returns>
/// <remarks>Not thread-safe. Port of ConvertTo-TraceChart. RT9: the chart is a pure function of the text. Raises
/// EChartsTrace (R19, raised by the builder this calls) for: no TIERS header, a tier with no lane style, an unknown
/// section, an actor outside the TIERS, an unnumbered item, a trace with no steps, or a dot that is not 7-bit ASCII.</remarks>
function TraceChart(pTrace: TTrace; pAnchorPaths: TDictionary<string, string>; const pCaps: TChartCaps): TTraceChart;

implementation

uses
  System.Classes, System.Generics.Defaults, System.Math, System.RegularExpressions,
  DRagLint.Charts.Text, DRagLint.Charts.Dot;

const
  CRLF = #13#10;
  SPACE_CH = ' ';
  KIND_CARD = 'card';
  KIND_ALSO = 'also';
  KIND_DERIVED = 'derived';
  KIND_STOPS = 'stops';
  KIND_CROSSES = 'crosses';
  KIND_CROSSING = 'crossing';
  KIND_COLUMN = 'column';
  KIND_EVENT = 'event';
  KIND_ANCHOR = 'anchor';
  KIND_COND = 'cond';
  KIND_FACET = 'facet';
  SEC_WRITE = 'WRITE';
  SEC_READ = 'READ';
  LANE_CLIENT = 'CLIENT';
  LANE_PIPE = 'PIPE';
  LANE_SERVER = 'SERVER';
  LANE_DATABASE = 'DATABASE';
  MIN_FOLD_ROWS = 3;
  ASCII_CR = 13;
  ASCII_LF = 10;
  ASCII_FIRST = 32;
  ASCII_LAST = 126;
  SIZE_SMALL = 10;
  SIZE_NORMAL = 11;
  SIZE_HEADER = 12;
  SIZE_TITLE = 13;
  NO_SIZE = 0;
  NUM_DIGITS = 2;
  LEGEND_ROOT = 'legend';
  DISCLOSED = 'disclosed:';
  FULL_TEXT_TAIL = ', full text in trace.dlgraph';
  RE_SQL_ANCHOR = '\.sql:\d+$';
  RE_CALLEE = '^CALLS (\S+)';
  RE_VIA = ' VIA (\S+)';
  RE_FIRES_TARGET = '^FIRES \S+ -> (\S+)';
  RE_WITH_SET = '^[A-Za-z_]\w*(?: or [A-Za-z_]\w*)*$';
  RE_WITH_CMD = '^([A-Za-z_]\w*) [''"(]';
  RE_FROM_LINE = '^from (:\d+)';
  RE_ELSE_NOTE = '^else ';
  RE_ELSE_FAIL = '^else (.*?) @([A-Za-z0-9_$.\-]+:\d+)';
  RE_SUBJECT = '^\S+ (\S+)';
  RE_TIER_SPLIT = '\s*->\s*';
  PS_TRACE_ERR = 'ConvertTo-TraceChart: ';

type
  TChartRow = class
  private
    FSig: string;
    FItem: TTraceItem;
    FNums: TList<Integer>;
    FGuarded: Boolean;
    FFolded: Boolean;
    FPort: string;
  public
    property Sig: string read FSig write FSig;
    property Item: TTraceItem read FItem write FItem;
    property Nums: TList<Integer> read FNums write FNums;
    property Guarded: Boolean read FGuarded write FGuarded;
    property Folded: Boolean read FFolded write FFolded;
    property Port: string read FPort write FPort;
    constructor Create;
    destructor Destroy; override;
  end;

  TChartNode = class
  private
    FKey: string;
    FId: string;
    FKind: string;
    FLane: string;
    FTitle: string;
    FRows: TObjectList<TChartRow>;
    FFold: string;
    FFoldLegend: string;
  public
    property Key: string read FKey write FKey;
    property Id: string read FId write FId;
    property Kind: string read FKind write FKind;
    property Lane: string read FLane write FLane;
    property Title: string read FTitle write FTitle;
    property Rows: TObjectList<TChartRow> read FRows write FRows;
    property Fold: string read FFold write FFold;
    property FoldLegend: string read FFoldLegend write FFoldLegend;
    constructor Create;
    destructor Destroy; override;
  end;

  TChartEdge = class
  private
    FFrom: TChartNode;
    FDest: TChartNode;
    FKind: string;
    FNums: TList<Integer>;
    FExtras: TList<string>;
  public
    property From: TChartNode read FFrom write FFrom;
    property Dest: TChartNode read FDest write FDest;
    property Kind: string read FKind write FKind;
    property Nums: TList<Integer> read FNums write FNums;
    property Extras: TList<string> read FExtras write FExtras;
    constructor Create;
    destructor Destroy; override;
  end;

  TChartFail = class
  private
    FId: string;
    FText: string;
    FAnchor: string;
    FLane: string;
    FEdges: TList<string>;
  public
    property Id: string read FId write FId;
    property Text: string read FText write FText;
    property Anchor: string read FAnchor write FAnchor;
    property Lane: string read FLane write FLane;
    property Edges: TList<string> read FEdges write FEdges;
    constructor Create;
    destructor Destroy; override;
  end;

  TStepClass = record
    Key  : string;
    Kind : string;
    Title: string;
  end;

  TChartBuilder = class  // dl:ok high-response@da96 -- REVIEWED 2026-10-18: the builder IS ConvertTo-TraceChart's closures ($newNode, $addEdge, $fold, $cellRows, $nodeHtml) as private methods; its response set is the string and dot calls each makes, already split one method per PS closure
  strict private
    FTrace    : TTrace;
    FPaths    : TDictionary<string, string>;
    FCap      : TChartCaps;
    FLanes    : TArray<string>;
    FNodes    : TObjectList<TChartNode>;
    FNodeByKey: TDictionary<string, TChartNode>;
    FEdges    : TObjectList<TChartEdge>;
    FEdgeByKey: TDictionary<string, TChartEdge>;
    FFails    : TObjectList<TChartFail>;
    FFailByKey: TDictionary<string, TChartFail>;
    FLegend   : TList<string>;
    FManifest : TChartManifest;
    FUnlinked : Integer;
    FShortened: Integer;
    FSb       : TStringBuilder;
    procedure ReadLanes;
    function NewNode(const pKey, pKind, pLane, pTitle: string): TChartNode;
    procedure AddEdge(pFrom, pDest: TChartNode; const pKind: string; pNum: Integer; const pExtra: string);
    function OwnCard(const pRoutine, pLane: string): TChartNode;
    function ClassifyStep(const pSection: string; pItem: TTraceItem; const pLane: string; pPrev: TChartNode): TStepClass;
    procedure AddRow(pNode: TChartNode; const pKind: string; pItem: TTraceItem);
    procedure AddStepEdge(pItem: TTraceItem; pNode, pPrev, pAnchorNode: TChartNode; const pKind, pLane: string; pIsNew: Boolean);
    procedure WalkSteps;
    function Fold(pNode: TChartNode; const pRows: TArray<TChartRow>; const pNoun: string): Boolean;
    procedure ApplySizeRules;
    procedure FoldSummary;
    function Link(const pAnchor, pTip: string): string;
    function AlsoTarget(const pText: string): TChartNode;
    procedure BuildStepCells(pTb: TStringBuilder; pNode: TChartNode; pRow: TChartRow);
    procedure BuildCondCell(pTb: TStringBuilder; pNode: TChartNode; pRow: TChartRow; pCh: TTraceChild; const pPort: string);
    procedure BuildFacetCell(pTb: TStringBuilder; pNode: TChartNode; pRow: TChartRow; pCh: TTraceChild);
    function NodeHtml(pNode: TChartNode): string;
    function NodeAttr(pNode: TChartNode): string;
    function HeaderHtml: string;
    function LegendHtml: string;
    procedure EmitLanes(const pNodeLines: TDictionary<string, string>);
    procedure EmitEdges;
    procedure L(const pS: string);
    procedure CheckAscii(const pDot: string);
    procedure FinishManifest;
  public
    constructor Create(pTrace: TTrace; pAnchorPaths: TDictionary<string, string>; const pCaps: TChartCaps);
    destructor Destroy; override;
    function Build: TTraceChart;
  end;

function LaneInk(const pLane: string): TArray<string>;
begin
  if pLane = LANE_CLIENT then
    Result:= [LANE_INK_CLIENT[0], LANE_INK_CLIENT[1], LANE_INK_CLIENT[2]]
  else if pLane = LANE_PIPE then
    Result:= [LANE_INK_PIPE[0], LANE_INK_PIPE[1], LANE_INK_PIPE[2]]
  else if pLane = LANE_SERVER then
    Result:= [LANE_INK_SERVER[0], LANE_INK_SERVER[1], LANE_INK_SERVER[2]]
  else if pLane = LANE_DATABASE then
    Result:= [LANE_INK_DATABASE[0], LANE_INK_DATABASE[1], LANE_INK_DATABASE[2]]
  else
    Result:= nil;
end;

{ True when the step before ended on a crossing or a STOPS: the next node opens a new flow }
function AfterBreak(pPrev: TChartNode): Boolean;
begin
  Result:= (pPrev <> nil) and ((pPrev.Kind = KIND_CROSSING) or (pPrev.Kind = KIND_STOPS));
end;

function Two(pN: Integer): string;
begin
  Result:= Format('[%.*d]', [NUM_DIGITS, pN]);
end;

function SortedNums(pNums: TList<Integer>): TArray<Integer>;
begin
  Result:= pNums.ToArray;
  TArray.Sort<Integer>(Result);
end;

function JoinNums(pNums: TList<Integer>; const pSep: string): string;
begin
  Result:= '';
  for var N in SortedNums(pNums) do
    Result:= Result + (if Result = '' then '' else pSep) + Two(N);
end;

function JoinUniqueNums(pNums: TList<Integer>; const pSep: string): string;
var
  Prev: Integer;
begin
  Result:= '';
  Prev:= 0;
  for var N in SortedNums(pNums) do
  begin
    if (Result <> '') and (N = Prev) then
      Continue;
    Result:= Result + (if Result = '' then '' else pSep) + Two(N);
    Prev:= N;
  end;
end;

function ChartSqlAnchor(const pAnchor: string): Boolean;
begin
  Result:= TRegEx.IsMatch(pAnchor, RE_SQL_ANCHOR, [roIgnoreCase]);
end;

function ChartBreakable(const pT: string; pK: Integer): Boolean;
begin
  Result:= (pK > 0) and (pK + 1 < Length(pT)) and (pT[pK + 1] = SPACE_CH) and (pT[pK] <> SPACE_CH)
    and (pT[pK + 2] <> SPACE_CH);
end;

function ChartBreaks(const pText: string; pWidth: Integer): TArray<Integer>;
begin
  var Cuts:= TList<Integer>.Create;
  try
    var Start:= 0;
    while Length(pText) - Start > pWidth do
    begin
      var Cut:= -1;
      for var K:= Start + pWidth downto Start + 1 do
        if ChartBreakable(pText, K) then
        begin
          Cut:= K;
          Break;
        end;
      if Cut < 0 then
        for var K:= Start + pWidth + 1 to Length(pText) - 1 do
          if ChartBreakable(pText, K) then
          begin
            Cut:= K;
            Break;
          end;
      if Cut < 0 then
        Break;
      Cuts.Add(Cut);
      Start:= Cut + 1;
    end;
    Result:= Cuts.ToArray;
  finally
    Cuts.Free;
  end;
end;

function ChartCellHtml(const pSegs: TArray<TChartSeg>; pWidth: Integer): string;
begin
  var Breaks:= TList<Integer>.Create;
  var Sb:= TStringBuilder.Create;
  var Chunk:= TStringBuilder.Create;
  try
    var Plain:= TStringBuilder.Create;
    try
      for var S in pSegs do
        Plain.Append(S.Text);
      Breaks.AddRange(ChartBreaks(Plain.ToString, pWidth));
    finally
      Plain.Free;
    end;
    var Pos:= 0;
    for var S in pSegs do
    begin
      if S.Text = '' then
        Continue;
      var Open:= '<FONT' + (if S.Ink <> '' then ' COLOR="' + S.Ink + '"' else '')
        + (if S.Size <> NO_SIZE then ' POINT-SIZE="' + IntToStr(S.Size) + '"' else '') + '>'
        + (if S.Bold then '<B>' else '');
      var Close:= if S.Bold then '</B></FONT>' else '</FONT>';
      Sb.Append(Open);
      Chunk.Clear;
      for var K:= 0 to Length(S.Text) - 1 do
        if Breaks.Contains(Pos + K) then
        begin
          Sb.Append(XmlText(Chunk.ToString)).Append('<BR ALIGN="LEFT"/>');
          Chunk.Clear;
        end
        else
          Chunk.Append(S.Text[K + 1]);
      Sb.Append(XmlText(Chunk.ToString)).Append(Close);
      Inc(Pos, Length(S.Text));
    end;
    Result:= Sb.ToString;
  finally
    Chunk.Free;
    Sb.Free;
    Breaks.Free;
  end;
end;

function FormatChartNumbers(const pNums: TArray<Integer>): string;
begin
  var Sorted:= TList<Integer>.Create;
  try
    var Nums:= Copy(pNums);
    TArray.Sort<Integer>(Nums);
    for var N in Nums do
      if (Sorted.Count = 0) or (Sorted.Last <> N) then
        Sorted.Add(N);
    var Parts:= TList<string>.Create;
    try
      var I:= 0;
      while I < Sorted.Count do
      begin
        var J:= I;
        while (J + 1 < Sorted.Count) and (Sorted[J + 1] = Sorted[J] + 1) do
          Inc(J);
        Parts.Add(if J > I then Two(Sorted[I]) + '-' + Two(Sorted[J]) else Two(Sorted[I]));
        I:= J + 1;
      end;
      Result:= string.Join(', ', Parts.ToArray);
    finally
      Parts.Free;
    end;
  finally
    Sorted.Free;
  end;
end;

function TraceChartLane(const pSection: string; pItem: TTraceItem; const pLanes: TArray<string>): string;
begin
  var X:= pItem.Kind = KIND_CROSSES;
  if pSection = 'ANCHOR' then
    Result:= if X then LANE_PIPE else if ChartSqlAnchor(pItem.Anchor) then LANE_DATABASE else LANE_CLIENT
  else if pSection = 'DERIVED' then
    Result:= LANE_CLIENT
  else if (pSection = SEC_WRITE) or (pSection = 'RESPONSE') then
    Result:= if X then LANE_PIPE else LANE_CLIENT
  else if pSection = 'SERVER' then
    Result:= if X then LANE_PIPE else LANE_SERVER
  else if pSection = 'DATABASE' then
    Result:= if X then LANE_PIPE else LANE_DATABASE
  else if pSection = SEC_READ then
    Result:= if X then LANE_PIPE else if pItem.Actor <> '' then pItem.Actor else LANE_CLIENT
  else if pSection = 'ALSO' then
    Result:= LANE_CLIENT
  else
    raise EChartsTrace.Create(PS_TRACE_ERR + 'section ''' + pSection
      + ''' has no lane rule -- a grammar that grows must grow the renderer (R19)');
  var Known:= False;
  for var Lane in pLanes do
    if Lane = Result then
      Known:= True;
  if not Known then
    raise EChartsTrace.Create(PS_TRACE_ERR + 'step ' + Two(pItem.Number) + ' belongs in lane ' + Result
      + ', which the TIERS header (' + string.Join(' -> ', pLanes) + ') does not name (R19)');
end;

function TraceChartCallee(const pText: string): string;
begin
  var M:= TRegEx.Match(pText, RE_CALLEE);
  Result:= if M.Success then M.Groups[1].Value else '';
end;

function TraceChartTarget(const pText: string): string;
begin
  var M:= TRegEx.Match(pText, RE_CALLEE);
  if not M.Success then
    M:= TRegEx.Match(pText, RE_VIA);
  if not M.Success then
    M:= TRegEx.Match(pText, RE_FIRES_TARGET);
  Result:= if M.Success then M.Groups[1].Value else '';
end;

function TraceChartWithLabel(const pWith: string): string;
begin
  if TRegEx.IsMatch(pWith, RE_WITH_SET) then
    Exit(pWith);
  var M:= TRegEx.Match(pWith, RE_WITH_CMD);
  Result:= if M.Success then M.Groups[1].Value else '';
end;

function ItemHead(pItem: TTraceItem): string;
begin
  if pItem.Kind = 'crosses' then
    Result:= 'CROSSES ' + pItem.Text
  else if pItem.Kind = KIND_STOPS then
    Result:= 'STOPS ' + pItem.Text
  else
    Result:= pItem.Text + (if pItem.Grade <> '' then ' [' + pItem.Grade + ']' else '');
end;

function FormatTraceChartTip(pItem: TTraceItem; const pNums: string): string;
begin
  var Note:= FormatTraceNote(pItem.Routine, pItem.Note, pItem.Ask);
  Result:= pNums + ' ' + (if pItem.Actor <> '' then pItem.Actor + ' ' else '') + ItemHead(pItem) + ' @' + pItem.Anchor
    + (if Note <> '' then ' -- ' + Note else '');
end;

{ TChartCaps / TChartSeg / TChartManifest }

class function TChartCaps.Default: TChartCaps;
const
  DEFAULT_ALSO = 15;
  DEFAULT_ROWS = 14;
  DEFAULT_NODES = 45;
  DEFAULT_FOLDS = 5;
begin
  Result.Also:= DEFAULT_ALSO;
  Result.Rows:= DEFAULT_ROWS;
  Result.Nodes:= DEFAULT_NODES;
  Result.Folds:= DEFAULT_FOLDS;
end;

class function TChartSeg.Make(const pText, pInk: string; pSize: Integer; pBold: Boolean): TChartSeg;
begin
  Result.Text:= pText;
  Result.Ink:= pInk;
  Result.Size:= pSize;
  Result.Bold:= pBold;
end;

constructor TChartManifest.Create;
begin
  inherited Create;
  Steps:= TDictionary<string, string>.Create;
  Conds:= TDictionary<string, string>.Create;
  Facets:= TDictionary<string, string>.Create;
  Collapses:= TList<string>.Create;
end;

destructor TChartManifest.Destroy;
begin
  Collapses.Free;
  Facets.Free;
  Conds.Free;
  Steps.Free;
  inherited Destroy;
end;

{ builder records }

constructor TChartRow.Create;
begin
  inherited Create;
  Nums:= TList<Integer>.Create;
end;

destructor TChartRow.Destroy;
begin
  Nums.Free;
  inherited Destroy;
end;

constructor TChartNode.Create;
begin
  inherited Create;
  Rows:= TObjectList<TChartRow>.Create(True);
end;

destructor TChartNode.Destroy;
begin
  Rows.Free;
  inherited Destroy;
end;

constructor TChartEdge.Create;
begin
  inherited Create;
  Nums:= TList<Integer>.Create;
  Extras:= TList<string>.Create;
end;

destructor TChartEdge.Destroy;
begin
  Extras.Free;
  Nums.Free;
  inherited Destroy;
end;

constructor TChartFail.Create;
begin
  inherited Create;
  Edges:= TList<string>.Create;
end;

destructor TChartFail.Destroy;
begin
  Edges.Free;
  inherited Destroy;
end;

{ TChartBuilder }

constructor TChartBuilder.Create(pTrace: TTrace; pAnchorPaths: TDictionary<string, string>; const pCaps: TChartCaps);
begin
  inherited Create;
  FTrace:= pTrace;
  FCap:= pCaps;
  FPaths:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  if pAnchorPaths <> nil then
    for var Pair in pAnchorPaths do
      FPaths.AddOrSetValue(Pair.Key, Pair.Value);
  FNodes:= TObjectList<TChartNode>.Create(True);
  FNodeByKey:= TDictionary<string, TChartNode>.Create(TIStringComparer.Ordinal);
  FEdges:= TObjectList<TChartEdge>.Create(True);
  FEdgeByKey:= TDictionary<string, TChartEdge>.Create(TIStringComparer.Ordinal);
  FFails:= TObjectList<TChartFail>.Create(True);
  FFailByKey:= TDictionary<string, TChartFail>.Create(TIStringComparer.Ordinal);
  FLegend:= TList<string>.Create;
  FManifest:= TChartManifest.Create;
  FSb:= TStringBuilder.Create;
end;

destructor TChartBuilder.Destroy;
begin
  FSb.Free;
  FManifest.Free;
  FLegend.Free;
  FFailByKey.Free;
  FFails.Free;
  FEdgeByKey.Free;
  FEdges.Free;
  FNodeByKey.Free;
  FNodes.Free;
  FPaths.Free;
  inherited Destroy;
end;

procedure TChartBuilder.L(const pS: string);
begin
  FSb.Append(pS).Append(CRLF);
end;

procedure TChartBuilder.ReadLanes;
begin
  var Lanes:= TList<string>.Create;
  try
    for var Part in TRegEx.Split(FTrace.Tiers, RE_TIER_SPLIT) do
      if Part <> '' then
        Lanes.Add(UpperCase(Trim(Part)));
    FLanes:= Lanes.ToArray;
  finally
    Lanes.Free;
  end;
  if Length(FLanes) = 0 then
    raise EChartsTrace.Create(PS_TRACE_ERR + 'the trace has no TIERS header');
  for var Lane in FLanes do
    if LaneInk(Lane) = nil then
      raise EChartsTrace.Create(PS_TRACE_ERR + 'TIERS names ''' + Lane + ''', which has no lane style (R19)');
end;

function TChartBuilder.NewNode(const pKey, pKind, pLane, pTitle: string): TChartNode;
begin
  Result:= TChartNode.Create;
  Result.Key:= pKey;
  Result.Id:= 'n' + IntToStr(FNodes.Count + 1);
  Result.Kind:= pKind;
  Result.Lane:= pLane;
  Result.Title:= pTitle;
  FNodes.Add(Result);
  FNodeByKey.AddOrSetValue(pKey, Result);
end;

procedure TChartBuilder.AddEdge(pFrom, pDest: TChartNode; const pKind: string; pNum: Integer; const pExtra: string);
begin
  if (pFrom = nil) or (pDest = nil) or (pFrom = pDest) then
    Exit;
  var Key:= pFrom.Id + '>' + pDest.Id + '>' + pKind;
  var Edge: TChartEdge;
  if not FEdgeByKey.TryGetValue(Key, Edge) then
  begin
    Edge:= TChartEdge.Create;
    Edge.From:= pFrom;
    Edge.Dest:= pDest;
    Edge.Kind:= pKind;
    FEdges.Add(Edge);
    FEdgeByKey.Add(Key, Edge);
  end;
  Edge.Nums.Add(pNum);
  if (pExtra <> '') and not Edge.Extras.Contains(pExtra) then
    Edge.Extras.Add(pExtra);
end;

function TChartBuilder.OwnCard(const pRoutine, pLane: string): TChartNode;
begin
  Result:= nil;
  if pRoutine = '' then
    Exit;
  var First: TChartNode:= nil;
  for var N in FNodes do
    if (N.Kind = KIND_CARD) and (N.Title = pRoutine) then
    begin
      if SameText(N.Lane, pLane) then
        Exit(N);
      if First = nil then
        First:= N;
    end;
  Result:= First;
end;

function TChartBuilder.ClassifyStep(const pSection: string; pItem: TTraceItem; const pLane: string;
  pPrev: TChartNode): TStepClass;
begin
  var Callee:= TraceChartCallee(pItem.Text);
  if pSection = 'ALSO' then
  begin
    Result.Key:= KIND_ALSO;
    Result.Kind:= KIND_ALSO;
    Result.Title:= 'ALSO -- other routes to the anchor';
  end
  else if pSection = 'DERIVED' then
  begin
    Result.Key:= KIND_DERIVED;
    Result.Kind:= KIND_DERIVED;
    Result.Title:= 'DERIVED -- the fields the calculation reads';
  end
  else if pItem.Kind = KIND_STOPS then
  begin
    Result.Key:= 'stops|' + IntToStr(pItem.Number);
    Result.Kind:= KIND_STOPS;
    Result.Title:= 'STOPS';
  end
  else if pItem.Kind = KIND_CROSSES then
  begin
    Result.Key:= 'x|' + pItem.Anchor;
    Result.Kind:= KIND_CROSSING;
    Result.Title:= 'process boundary @' + pItem.Anchor;
  end
  else if (pLane = LANE_DATABASE) and ChartSqlAnchor(pItem.Anchor) then
  begin
    var M:= TRegEx.Match(pItem.Text, RE_SUBJECT);
    var Subj:= if M.Success then M.Groups[1].Value else pItem.Text;
    Result.Key:= 'col|' + pItem.Anchor + '|' + Subj;
    Result.Kind:= KIND_COLUMN;
    Result.Title:= Subj;
  end
  else if pSection = 'ANCHOR' then
  begin
    Result.Key:= KIND_ANCHOR;
    Result.Kind:= KIND_ANCHOR;
    Result.Title:= 'ANCHOR -- ' + FTrace.From;
  end
  else if pItem.Text.StartsWith('FIRES ', False) then
  begin
    Result.Key:= 'ev|' + IntToStr(pItem.Number);
    Result.Kind:= KIND_EVENT;
    Result.Title:= KIND_EVENT;
  end
  else
  begin
    Result.Kind:= KIND_CARD;
    if Callee <> '' then
    begin
      Result.Key:= 'card|' + pLane + '|' + Callee;
      Result.Title:= Callee;
    end
    else if pItem.Routine <> '' then
    begin
      Result.Key:= 'card|' + pLane + '|' + pItem.Routine;
      Result.Title:= pItem.Routine;
    end
    else if (pPrev <> nil) and (pPrev.Kind = KIND_CARD) and SameText(pPrev.Lane, pLane) then
    begin
      Result.Key:= pPrev.Key;
      Result.Title:= pPrev.Title;
    end
    else
    begin
      Result.Key:= 'card|' + pLane + '|#' + IntToStr(pItem.Number);
      Result.Title:= '(no routine named)';
    end;
  end;
end;

procedure TChartBuilder.AddRow(pNode: TChartNode; const pKind: string; pItem: TTraceItem);
begin
  var Parts:= TList<string>.Create;
  try
    for var Ch in pItem.Children do
      Parts.Add(if Ch.Kind = KIND_COND then 'c:' + Ch.Keyword + '|' + Ch.Condition + '|' + Ch.Anchor + '|' + Ch.Note  // dl:ok hardcoded-absolute-path@a84e -- REVIEWED 2026-10-18: 'c:' is the row-signature tag of a condition child (the PS $sig 'c:'), not a drive path
        else 'f:' + Ch.Head + '|' + Ch.Text + '|' + Ch.Anchor + '|' + Ch.Note);  // dl:ok hardcoded-absolute-path@a401 -- REVIEWED 2026-10-18: 'f:' is the row-signature tag of a facet child (the PS $sig 'f:'), not a drive path
    var Sig:= pItem.Kind + '|' + pItem.Text + '|' + pItem.Grade + '|' + pItem.Anchor + '|'
      + string.Join('||', Parts.ToArray);
    for var R in pNode.Rows do
      if R.Sig = Sig then
      begin
        R.Nums.Add(pItem.Number);
        Exit;
      end;
    var HasCond:= False;
    for var Ch in pItem.Children do
      if Ch.Kind = KIND_COND then
        HasCond:= True;
    var Row:= TChartRow.Create;
    Row.Sig:= Sig;
    Row.Item:= pItem;
    var ItemHolds:= (pItem.Kind = KIND_CROSSES) or (pItem.Kind = KIND_STOPS);
    var NodeHolds:= (pKind = KIND_COLUMN) or (pKind = KIND_CROSSING) or (pKind = KIND_STOPS);
    Row.Guarded:= ItemHolds or NodeHolds or HasCond;
    Row.Nums.Add(pItem.Number);
    pNode.Rows.Add(Row);
  finally
    Parts.Free;
  end;
end;

procedure TChartBuilder.AddStepEdge(pItem: TTraceItem; pNode, pPrev, pAnchorNode: TChartNode; const pKind, pLane: string;
  pIsNew: Boolean);
begin
  var Callee:= TraceChartCallee(pItem.Text);
  var Fires:= pItem.Text.StartsWith('FIRES ', False);
  var Own:= OwnCard(pItem.Routine, pLane);
  var Src: TChartNode:= nil;
  var Ek:= '';
  if Fires then
  begin
    Src:= if pAnchorNode <> nil then pAnchorNode else pPrev;
    Ek:= KIND_EVENT;
  end
  else if (Callee <> '') and (Own <> nil) and (Own <> pNode) then
  begin
    Src:= Own;
    Ek:= 'call';
  end
  else if pIsNew and (Own <> nil) and ((pKind = KIND_STOPS) or (pKind = KIND_EVENT)) then
  begin
    Src:= Own;
    Ek:= 'flow';
  end
  else if pIsNew or (Callee <> '') or (pKind = KIND_COLUMN) or (pKind = KIND_CROSSING) or AfterBreak(pPrev) then
  begin
    Src:= pPrev;
    Ek:= if Callee <> '' then 'call' else 'flow';
  end;
  if Src = nil then
    Exit;
  if (Src.Kind = KIND_CROSSING) or (pKind = KIND_CROSSING) then
    Ek:= KIND_CROSSING
  else if Src.Kind = KIND_EVENT then
    Ek:= KIND_EVENT;
  var Labels:= TList<string>.Create;
  try
    for var Ch in pItem.Children do
      if (Ch.Kind = KIND_FACET) and (Ch.Head = 'WITH') then
        Labels.Add(TraceChartWithLabel(Ch.Text));
    var Extra:= '';
    var FromLine:= TRegEx.Match(pItem.Note, RE_FROM_LINE);
    if (pKind = KIND_CROSSING) and (Labels.Count > 0) then
      Extra:= Labels[0]
    else if (Ek = 'call') and FromLine.Success then
      Extra:= 'from ' + FromLine.Groups[1].Value;
    AddEdge(Src, pNode, Ek, pItem.Number, Extra);
  finally
    Labels.Free;
  end;
end;

procedure TChartBuilder.WalkSteps;
begin
  var Prev: TChartNode:= nil;
  var AnchorNode: TChartNode:= nil;
  var Total:= 0;
  for var Sec in FTrace.Sections do
  begin
    var Known:= False;
    for var Name in CHART_SECTIONS do
      if Name = Sec.Name then
        Known:= True;
    if not Known then
      raise EChartsTrace.Create(PS_TRACE_ERR + 'unknown section ''' + Sec.Name
        + ''' -- a grammar that grows must grow the renderer (R19)');
    if ((Sec.Name = SEC_WRITE) or (Sec.Name = SEC_READ)) and (AnchorNode <> nil) then
      Prev:= AnchorNode;
    for var Item in Sec.Items do
    begin
      Inc(Total);
      if Item.Number <= 0 then
        raise EChartsTrace.Create(PS_TRACE_ERR
          + 'an item has no step number -- render Read-FormA''s model, or the model after Write-FormA');
      var Lane:= TraceChartLane(Sec.Name, Item, FLanes);
      var Cls:= ClassifyStep(Sec.Name, Item, Lane, Prev);
      var Node: TChartNode;
      var IsNew:= not FNodeByKey.TryGetValue(Cls.Key, Node);
      if IsNew then
        Node:= NewNode(Cls.Key, Cls.Kind, Lane, Cls.Title);
      if Cls.Kind = KIND_ANCHOR then
        AnchorNode:= Node;
      AddRow(Node, Cls.Kind, Item);
      if Cls.Kind <> KIND_ALSO then
      begin
        AddStepEdge(Item, Node, Prev, AnchorNode, Cls.Kind, Lane, IsNew);
        Prev:= Node;
      end;
    end;
  end;
  if Total = 0 then
    raise EChartsTrace.Create(PS_TRACE_ERR
      + 'the trace has no steps -- a one-step trace is a one-node chart, a zero-step one is not a trace');
end;

function TChartBuilder.Fold(pNode: TChartNode; const pRows: TArray<TChartRow>; const pNoun: string): Boolean;
begin
  Result:= Length(pRows) >= MIN_FOLD_ROWS;
  if not Result then
    Exit;
  if pNode.FoldLegend <> '' then
  begin
    FLegend.Remove(pNode.FoldLegend);
    FManifest.Collapses.Remove(pNode.FoldLegend);
  end;
  var Nums:= TList<Integer>.Create;
  try
    for var R in pRows do
    begin
      Nums.AddRange(R.Nums);
      R.Folded:= True;
    end;
    var Head:= DisclosureText(Length(pRows), 0, pNoun);
    var NumText:= FormatChartNumbers(Nums.ToArray);
    pNode.Fold:= Head + ' -- ' + NumText + FULL_TEXT_TAIL;
    pNode.FoldLegend:= Head + ' in ' + (if pNode.Kind = KIND_ALSO then 'ALSO' else pNode.Title) + ' -- ' + NumText
      + FULL_TEXT_TAIL;
  finally
    Nums.Free;
  end;
  FLegend.Add(pNode.FoldLegend);
  FManifest.Collapses.Add(pNode.FoldLegend);
  for var R in pRows do
  begin
    for var N in R.Nums do
      FManifest.Steps.AddOrSetValue(IntToStr(N), DISCLOSED + pNode.FoldLegend);
    for var Ch in R.Item.Children do
      if Ch.Kind = KIND_COND then
        FManifest.Conds.AddOrSetValue(IntToStr(R.Nums[0]) + '|' + Ch.Keyword + '|' + Ch.Anchor, DISCLOSED + pNode.FoldLegend)
      else
        FManifest.Facets.AddOrSetValue(IntToStr(R.Nums[0]) + '|' + Ch.Head + '|' + (if Ch.Anchor <> '' then Ch.Anchor else Ch.Text),
          DISCLOSED + pNode.FoldLegend);
  end;
end;

procedure TChartBuilder.ApplySizeRules;
var
  Node: TChartNode;
  Ladder: TList<string>;
begin
  // 2a. ALSO: every row up to the cap
  if FNodeByKey.TryGetValue(KIND_ALSO, Node) and (Node.Rows.Count > FCap.Also) then
    Fold(Node, Copy(Node.Rows.ToArray, FCap.Also, Node.Rows.Count - FCap.Also), 'routes');
  // 2b. a card's plain rows past the row cap; a protected row never folds
  for var N in FNodes.ToArray do
  begin
    if not ((N.Kind = KIND_CARD) or (N.Kind = KIND_ANCHOR) or (N.Kind = KIND_DERIVED)) then
      Continue;
    if N.Rows.Count <= FCap.Rows then
      Continue;
    var Prot:= 0;
    var Plain:= TList<TChartRow>.Create;
    try
      for var R in N.Rows do
        if R.Guarded then
          Inc(Prot)
        else
          Plain.Add(R);
      var Room:= Max(0, FCap.Rows - Prot);
      if Plain.Count > Room then
        Fold(N, Copy(Plain.ToArray, Room, Plain.Count - Room), 'steps');
    finally
      Plain.Free;
    end;
  end;
  // 2c. the ladder: above the node cap, ALSO folds whole, then every card with no protected row
  Ladder:= TList<string>.Create;
  try
    var NodeCount:= FNodes.Count;
    if NodeCount > FCap.Nodes then
    begin
      if FNodeByKey.TryGetValue(KIND_ALSO, Node) then
      begin
        var Open:= 0;
        for var R in Node.Rows do
          if not R.Folded then
            Inc(Open);
        if (Open > 0) and Fold(Node, Node.Rows.ToArray, 'routes') then
          Ladder.Add(KIND_ALSO);
      end;
      for var N in FNodes.ToArray do
      begin
        if not ((N.Kind = KIND_CARD) or (N.Kind = KIND_DERIVED)) then
          Continue;
        var HasProt:= False;
        for var R in N.Rows do
          if R.Guarded then
            HasProt:= True;
        if HasProt then
          Continue;
        if Fold(N, N.Rows.ToArray, 'steps') then
          Ladder.Add('cards');
      end;
      FLegend.Add(IntToStr(NodeCount) + ' nodes, above the ' + IntToStr(FCap.Nodes)
        + '-node readability cap: drawn anyway, nothing dropped');
    end;
    FoldSummary;
    var Seen:= TList<string>.Create;
    try
      for var Rung in Ladder do
        if not Seen.Contains(Rung) then
          Seen.Add(Rung);
      FManifest.Ladder:= string.Join(',', Seen.ToArray);
    finally
      Seen.Free;
    end;
  finally
    Ladder.Free;
  end;
end;

procedure TChartBuilder.FoldSummary;
begin
  var Folded:= TList<TChartNode>.Create;
  var Nums:= TList<Integer>.Create;
  try
    for var N in FNodes do
      if N.FoldLegend <> '' then
        Folded.Add(N);
    if Folded.Count <= FCap.Folds then
      Exit;
    var RowCount:= 0;
    for var N in Folded do
      for var R in N.Rows do
        if R.Folded then
        begin
          Inc(RowCount);
          Nums.AddRange(R.Nums);
        end;
    var Fn:= Nums.ToArray;
    TArray.Sort<Integer>(Fn);
    var Uniq:= TList<Integer>.Create;
    try
      for var V in Fn do
        if (Uniq.Count = 0) or (Uniq.Last <> V) then
          Uniq.Add(V);
      var Head:= IntToStr(Folded.Count) + ' cards folded (' + IntToStr(RowCount) + ' rows not shown)';
      var Tail:= 'the full trace is in the text answer';
      var Sum:= Head + ' -- ' + FormatChartNumbers(Uniq.ToArray) + ' -- ' + Tail;
      if Length(Sum) > CHART_SUMMARY_WIDTH then
        Sum:= Head + ' -- ' + IntToStr(Uniq.Count) + ' steps -- ' + Tail;
      for var N in Folded do
      begin
        FLegend.Remove(N.FoldLegend);
        FManifest.Collapses.Remove(N.FoldLegend);
      end;
      for var Tbl in [FManifest.Steps, FManifest.Conds, FManifest.Facets] do
      begin
        var Keys:= TList<string>.Create;
        try
          for var Pair in Tbl do
            if Pair.Value.StartsWith(DISCLOSED, True) then
              Keys.Add(Pair.Key);
          for var K in Keys do
            Tbl[K]:= DISCLOSED + Sum;
        finally
          Keys.Free;
        end;
      end;
      FLegend.Insert(0, Sum);
      FManifest.Collapses.Add(Sum);
    finally
      Uniq.Free;
    end;
  finally
    Nums.Free;
    Folded.Free;
  end;
end;

function TChartBuilder.Link(const pAnchor, pTip: string): string;
begin
  if pAnchor = '' then
    Exit('');
  var Colon:= LastDelimiter(':', pAnchor);
  var Leaf:= if Colon > 0 then Copy(pAnchor, 1, Colon - 1) else pAnchor;
  var Line:= StrToIntDef(Copy(pAnchor, Colon + 1, MaxInt), 0);
  var Full:= '';
  if Line > 0 then
    FPaths.TryGetValue(Leaf, Full);
  if Full = '' then
  begin
    Inc(FUnlinked);
    Exit(' TITLE="' + XmlText('ambiguous file name -- the indexes hold ' + Leaf
      + ' at zero or several paths; see trace.dlgraph') + '"');
  end;
  Result:= ' HREF="' + RowHref(Full, Line) + '" TITLE="' + XmlText(pTip) + '"';
end;

function TChartBuilder.AlsoTarget(const pText: string): TChartNode;
begin
  Result:= nil;
  var Tg:= TraceChartTarget(pText);
  if Tg = '' then
    Exit;
  var Hits:= 0;
  for var N in FNodes do
    if (N.Kind = KIND_CARD) and ((N.Title = Tg) or N.Title.EndsWith('.' + Tg, False)) then
    begin
      Inc(Hits);
      Result:= N;
    end;
  if Hits <> 1 then
    Result:= nil;
end;

procedure TChartBuilder.BuildCondCell(pTb: TStringBuilder; pNode: TChartNode; pRow: TChartRow; pCh: TTraceChild;
  const pPort: string);
begin
  var Segs:= TList<TChartSeg>.Create;
  try
    Segs.Add(TChartSeg.Make(pCh.Keyword, INK_GUARD, SIZE_NORMAL, True));
    Segs.Add(TChartSeg.Make(' ' + pCh.Condition, INK_TEXT, SIZE_NORMAL, False));
    Segs.Add(TChartSeg.Make(' @' + pCh.Anchor, INK_DIM, SIZE_SMALL, False));
    if TRegEx.IsMatch(pCh.Note, RE_ELSE_NOTE, [roIgnoreCase]) then
      Segs.Add(TChartSeg.Make(' -- ' + pCh.Note, INK_FAIL, SIZE_SMALL, False));
    var Cn:= FormatTraceNote(pCh.Routine, pCh.Note, pCh.Ask);
    var Tip:= pCh.Keyword + ' ' + pCh.Condition + ' @' + pCh.Anchor + (if Cn <> '' then ' -- ' + Cn else '');
    pTb.Append('<TR><TD PORT="' + pPort + '" ALIGN="LEFT" BALIGN="LEFT"' + Link(pCh.Anchor, Tip) + '>'
      + ChartCellHtml(Segs.ToArray) + '</TD></TR>');
  finally
    Segs.Free;
  end;
  for var N in pRow.Nums do
    FManifest.Conds.AddOrSetValue(IntToStr(N) + '|' + pCh.Keyword + '|' + pCh.Anchor, 'drawn:' + pNode.Id + ':' + pPort);
  var M:= TRegEx.Match(pCh.Note, RE_ELSE_FAIL, [roIgnoreCase]);
  if M.Success then
  begin
    var Ft:= M.Groups[1].Value;
    var Fa:= M.Groups[2].Value;
    var Fk:= 'fail|' + Fa + '|' + Ft;
    var Fail: TChartFail;
    if not FFailByKey.TryGetValue(Fk, Fail) then
    begin
      Fail:= TChartFail.Create;
      Fail.Id:= 'f' + IntToStr(FFails.Count + 1);
      Fail.Text:= 'else ' + Ft;
      Fail.Anchor:= Fa;
      Fail.Lane:= pNode.Lane;
      FFails.Add(Fail);
      FFailByKey.Add(Fk, Fail);
    end;
    Fail.Edges.Add(pNode.Id + ':' + pPort);
  end;
end;

procedure TChartBuilder.BuildFacetCell(pTb: TStringBuilder; pNode: TChartNode; pRow: TChartRow; pCh: TTraceChild);
begin
  var Segs:= TList<TChartSeg>.Create;
  try
    Segs.Add(TChartSeg.Make(pCh.Head, INK_FACET, SIZE_NORMAL, True));
    Segs.Add(TChartSeg.Make(' ' + pCh.Text, INK_TEXT, SIZE_NORMAL, False));
    if pCh.Anchor <> '' then
      Segs.Add(TChartSeg.Make(' @' + pCh.Anchor, INK_DIM, SIZE_SMALL, False));
    var Tip:= pCh.Head + ' ' + pCh.Text + (if pCh.Anchor <> '' then ' @' + pCh.Anchor else '')
      + (if pCh.Note <> '' then ' -- ' + pCh.Note else '');
    pTb.Append('<TR><TD ALIGN="LEFT" BALIGN="LEFT"' + Link(pCh.Anchor, Tip) + '>' + ChartCellHtml(Segs.ToArray)
      + '</TD></TR>');
  finally
    Segs.Free;
  end;
  for var N in pRow.Nums do
    FManifest.Facets.AddOrSetValue(IntToStr(N) + '|' + pCh.Head + '|' + (if pCh.Anchor <> '' then pCh.Anchor else pCh.Text),
      'drawn:' + pNode.Id + ':' + pRow.Port);
end;

procedure TChartBuilder.BuildStepCells(pTb: TStringBuilder; pNode: TChartNode; pRow: TChartRow);
begin
  var Item:= pRow.Item;
  var NumTxt:= JoinNums(pRow.Nums, '/');
  var Body:= if Item.Kind = KIND_CROSSES then 'CROSSES ' + Item.Text
    else if Item.Kind = KIND_STOPS then 'STOPS ' + Item.Text else Item.Text;
  var Grade:= if Item.Grade <> '' then ' [' + Item.Grade + ']' else '';
  var HeadTxt:= NumTxt + ' ' + Body + Grade;
  // past the line limit the BODY is shortened (at a break, ' ...' marking the cut) and the grade KEPT
  if Length(ChartBreaks(HeadTxt, CHART_WIDTH)) + 1 > CHART_MAX_LINES then
  begin
    var Lead:= NumTxt + ' ' + Body;
    var Cuts:= ChartBreaks(Lead, CHART_WIDTH);
    for var Ix:= High(Cuts) downto 0 do
    begin
      HeadTxt:= Copy(Lead, 1, Cuts[Ix]) + ' ...' + Grade;
      if Length(ChartBreaks(HeadTxt, CHART_WIDTH)) + 1 <= CHART_MAX_LINES then
        Break;
    end;
    Inc(FShortened);
  end;
  var Tips:= TList<string>.Create;
  try
    for var N in SortedNums(pRow.Nums) do
      Tips.Add(FormatTraceChartTip(Item, Two(N)));
    for var Ch in Item.Children do
      if (Ch.Kind = KIND_FACET) and (Ch.Head = 'REGENERATE') then
        Tips.Add('REGENERATE ' + Ch.Text);
    var Tip:= string.Join(' | ', Tips.ToArray);
    var Segs: TArray<TChartSeg>:= [TChartSeg.Make(NumTxt + ' ', INK_DIM, SIZE_NORMAL, False),
      TChartSeg.Make(Copy(HeadTxt, Length(NumTxt) + 2, MaxInt), INK_TEXT, NO_SIZE, Item.Kind = KIND_STOPS),
      TChartSeg.Make(' @' + Item.Anchor, INK_DIM, SIZE_SMALL, False)];
    var P:= 'p' + IntToStr(pNode.Rows.IndexOf(pRow) + 1);
    pRow.Port:= P;
    for var N in pRow.Nums do
      FManifest.Steps.AddOrSetValue(IntToStr(N), 'drawn:' + pNode.Id + ':' + P);
    pTb.Append('<TR><TD PORT="' + P + '" ALIGN="LEFT" BALIGN="LEFT"' + Link(Item.Anchor, Tip) + '>' + ChartCellHtml(Segs)
      + '</TD></TR>');
  finally
    Tips.Free;
  end;
  if (Item.Kind = KIND_STOPS) and (Item.Ask <> '') then
    pTb.Append('<TR><TD ALIGN="LEFT"><FONT COLOR="' + INK_FAIL + '" POINT-SIZE="' + IntToStr(SIZE_NORMAL) + '">ask '
      + XmlText(Item.Ask) + '</FONT></TD></TR>');
  var K:= 0;
  for var Ch in Item.Children do
  begin
    Inc(K);
    if Ch.Kind = KIND_COND then
      BuildCondCell(pTb, pNode, pRow, Ch, pRow.Port + 'c' + IntToStr(K))
    else if Ch.Head = 'REGENERATE' then
    begin
      for var N in pRow.Nums do
        FManifest.Facets.AddOrSetValue(IntToStr(N) + '|REGENERATE|' + Ch.Text, 'tooltip:' + pNode.Id + ':' + pRow.Port);
    end
    else
      BuildFacetCell(pTb, pNode, pRow, Ch);
  end;
end;

function TChartBuilder.NodeHtml(pNode: TChartNode): string;
begin
  var Ink:= LaneInk(pNode.Lane);
  var Tb:= TStringBuilder.Create;
  try
    var Bg:= if pNode.Kind = KIND_STOPS then '#FFF1F1' else if pNode.Kind = KIND_ALSO then '#FAFAFB' else '#FFFFFF';
    var Border:= if pNode.Kind = KIND_STOPS then INK_FAIL else if pNode.Kind = KIND_ALSO then INK_ALSO else Ink[0];
    var Hdr:= if pNode.Kind = KIND_STOPS then INK_FAIL else if pNode.Kind = KIND_ALSO then INK_ALSO else Ink[2];
    Tb.Append('<TABLE BORDER="1" COLOR="' + Border + '" CELLBORDER="0" CELLSPACING="1" CELLPADDING="3" BGCOLOR="' + Bg + '">');
    if (pNode.Kind <> KIND_STOPS) and (pNode.Kind <> KIND_EVENT) then
      Tb.Append('<TR><TD ALIGN="LEFT" BALIGN="LEFT" BGCOLOR="' + Hdr + '">'
        + ChartCellHtml([TChartSeg.Make(pNode.Title, '#FFFFFF', SIZE_HEADER, True)]) + '</TD></TR>');
    for var R in pNode.Rows do
    begin
      if R.Folded then
        Continue;
      BuildStepCells(Tb, pNode, R);
      if (pNode.Kind = KIND_ALSO) and (AlsoTarget(R.Item.Text) = nil) then
        AddDisclosureRow(Tb, 'converges outside the drawn path', INK_ALSO, SIZE_SMALL);
    end;
    if pNode.Fold <> '' then
      AddDisclosureRow(Tb, pNode.Fold, INK_DIM, SIZE_NORMAL);
    Tb.Append('</TABLE>');
    Result:= Tb.ToString;
  finally
    Tb.Free;
  end;
end;

function TChartBuilder.NodeAttr(pNode: TChartNode): string;
begin
  var Ink:= LaneInk(pNode.Lane);
  if pNode.Kind = KIND_COLUMN then
    Result:= 'shape=cylinder, style=filled, fillcolor="' + Ink[1] + '", color="' + Ink[0] + '", margin=0.12'
  else if pNode.Kind = KIND_STOPS then
    Result:= 'shape=note, style="filled,dashed", fillcolor="#FFF1F1", color="' + INK_FAIL + '", penwidth=1.5, margin=0.05'
  else if pNode.Kind = KIND_EVENT then
    Result:= 'shape=box, style="rounded,dashed", color="' + Ink[0] + '", margin=0.05'
  else
    Result:= 'shape=plain';
end;

function TChartBuilder.HeaderHtml: string;
begin
  var Hb:= TStringBuilder.Create;
  try
    Hb.Append('<TABLE BORDER="1" COLOR="#5B6674" CELLBORDER="0" CELLSPACING="1" CELLPADDING="4" BGCOLOR="#FFFFFF">');
    Hb.Append('<TR><TD ALIGN="LEFT" BALIGN="LEFT" BGCOLOR="#1F2933">'
      + ChartCellHtml([TChartSeg.Make('TRACE ' + FTrace.Name, '#FFFFFF', SIZE_TITLE, True)]) + '</TD></TR>');
    for var H in [FTrace.Title, 'FROM ' + FTrace.From, 'INDEX ' + FTrace.Index + ' AS OF ' + FTrace.AsOf,
      'TIERS ' + FTrace.Tiers] do
      Hb.Append('<TR><TD ALIGN="LEFT" BALIGN="LEFT">'
        + ChartCellHtml([TChartSeg.Make(H, INK_TEXT, SIZE_NORMAL, False)]) + '</TD></TR>');
    Hb.Append('</TABLE>');
    Result:= Hb.ToString;
  finally
    Hb.Free;
  end;
end;

function TChartBuilder.LegendHtml: string;
begin
  var Lb:= TStringBuilder.Create;
  try
    Lb.Append('<TABLE BORDER="1" COLOR="#8A94A6" CELLBORDER="0" CELLSPACING="1" CELLPADDING="3" BGCOLOR="#FFFFFF">');
    Lb.Append('<TR><TD ALIGN="LEFT" BGCOLOR="#5B6674"><FONT COLOR="#FFFFFF" POINT-SIZE="12"><B>'
      + 'LEGEND -- what the picture holds and what it does not</B></FONT></TD></TR>');
    AddDisclosureRow(Lb, FormatTraceEndLine(TraceCounts(FTrace)), INK_TEXT, SIZE_NORMAL);
    AddDisclosureRow(Lb, 'full text, every note and ask in trace.dlgraph', INK_DIM, SIZE_NORMAL);
    for var G in FLegend do
      AddDisclosureRow(Lb, G, INK_DIM, SIZE_NORMAL);
    for var Sec in FTrace.Sections do
      if Sec.Note <> '' then
        AddDisclosureRow(Lb, Sec.Name + ' -- ' + Sec.Note, INK_DIM, SIZE_NORMAL);
    if FShortened > 0 then
      AddDisclosureRow(Lb, IntToStr(FShortened) + ' label(s) shortened; the full text is in the tooltip and in trace.dlgraph',
        INK_DIM, SIZE_NORMAL);
    AddDisclosureRow(Lb, 'amber WHEN / UNLESS: the guard on the step above it, verbatim; red dashed: the failure branch it names',
      INK_ALSO, SIZE_SMALL);
    AddDisclosureRow(Lb, '[aa]/[bb]: one row both directions run; bold edges cross the process boundary', INK_ALSO, SIZE_SMALL);
    Lb.Append('</TABLE>');
    Result:= Lb.ToString;
  finally
    Lb.Free;
  end;
end;

procedure TChartBuilder.EmitLanes(const pNodeLines: TDictionary<string, string>);
begin
  for var Lane in FLanes do
  begin
    var InLane:= TList<TChartNode>.Create;
    var Fl:= TList<TChartFail>.Create;
    try
      for var N in FNodes do
        if SameText(N.Lane, Lane) then
          InLane.Add(N);
      for var F in FFails do
        if SameText(F.Lane, Lane) then
          Fl.Add(F);
      if (InLane.Count = 0) and (Fl.Count = 0) then
        Continue;
      var Ink:= LaneInk(Lane);
      L('  subgraph cluster_lane_' + LowerCase(Lane) + ' {');
      L('    label=<<B>' + Lane + '</B>>; labeljust=l; fontcolor="' + Ink[2] + '"; style="rounded,filled"; color="'
        + Ink[0] + '"; fillcolor="' + Ink[1] + '"; penwidth=1.5; margin=12;');
      for var N in InLane do
        if N.Kind <> KIND_ALSO then
          L(pNodeLines[N.Key]);
      for var N in InLane do
        if N.Kind = KIND_ALSO then
        begin
          L('    subgraph cluster_also {');
          L('      label=<<B>ALSO</B>>; labeljust=l; fontcolor="' + INK_ALSO + '"; style="rounded,dashed"; color="'
            + INK_ALSO + '"; fillcolor="#FFFFFF";');
          L('  ' + pNodeLines[N.Key]);
          L('    }');
        end;
      for var F in Fl do
      begin
        var Cell:= ChartCellHtml([TChartSeg.Make(F.Text, INK_FAIL, SIZE_NORMAL, False),
          TChartSeg.Make(' @' + F.Anchor, INK_DIM, SIZE_SMALL, False)]);
        L('    ' + F.Id + ' [shape=box, style="rounded,dashed", color="' + INK_FAIL + '", margin=0.05, label=<'
          + '<TABLE BORDER="0" CELLBORDER="0" CELLPADDING="2"><TR><TD ALIGN="LEFT" BALIGN="LEFT"'
          + Link(F.Anchor, F.Text + ' @' + F.Anchor) + '>' + Cell + '</TD></TR></TABLE>>];');
      end;
      L('  }');
    finally
      Fl.Free;
      InLane.Free;
    end;
  end;
end;

procedure TChartBuilder.EmitEdges;
begin
  for var E in FEdges do
  begin
    var Lbl:= JoinUniqueNums(E.Nums, '/') + (if E.Extras.Count > 0 then ' ' + string.Join(', ', E.Extras.ToArray) else '');
    var St:= '';
    if E.Kind = KIND_CROSSING then
      St:= 'penwidth=2.2, color="' + LANE_INK_PIPE[0] + '", fontcolor="' + LANE_INK_PIPE[2] + '"'
    else if E.Kind = KIND_EVENT then
      St:= 'style=dashed';
    var Attrs:= 'label="' + XmlText(Lbl) + '"' + (if St <> '' then ', ' + St else '');
    var ToIx:= -1;
    var FromIx:= -1;
    for var Q:= 0 to High(FLanes) do
    begin
      if SameText(FLanes[Q], E.Dest.Lane) then
        ToIx:= Q;
      if SameText(FLanes[Q], E.From.Lane) then
        FromIx:= Q;
    end;
    L('  ' + E.From.Id + ' -> ' + E.Dest.Id + ' [' + Attrs + (if ToIx < FromIx then ', constraint=false' else '') + '];');
  end;
  for var F in FFails do
    for var Src in F.Edges do
      L('  ' + Src + ' -> ' + F.Id + ' [style=dashed, color="' + INK_FAIL + '"];');
end;

procedure TChartBuilder.CheckAscii(const pDot: string);
begin
  for var I:= 1 to Length(pDot) do
  begin
    var C:= Ord(pDot[I]);
    if not ((C = ASCII_CR) or (C = ASCII_LF) or ((C >= ASCII_FIRST) and (C <= ASCII_LAST))) then
      raise EChartsTrace.Create(PS_TRACE_ERR + 'the dot is not 7-bit ASCII at offset ' + IntToStr(I - 1));
  end;
end;

procedure TChartBuilder.FinishManifest;
begin
  FManifest.Nodes:= FNodes.Count;
  var Counts:= TList<string>.Create;
  var Merged:= TList<string>.Create;
  try
    for var Ln in [LANE_CLIENT, LANE_PIPE, LANE_SERVER, LANE_DATABASE] do
    begin
      var Cnt:= 0;
      for var N in FNodes do
        if SameText(N.Lane, Ln) then
          Inc(Cnt);
      Counts.Add(IntToStr(Cnt));
    end;
    FManifest.Lanes:= string.Join('/', Counts.ToArray);
    for var N in FNodes do
      for var R in N.Rows do
        if (R.Nums.Count > 1) and not R.Folded then
          Merged.Add(JoinNums(R.Nums, '/'));
    FManifest.Merged:= string.Join(',', Merged.ToArray);
  finally
    Merged.Free;
    Counts.Free;
  end;
  FManifest.Unlinked:= FUnlinked;
  FManifest.Shortened:= FShortened;
end;

function TChartBuilder.Build: TTraceChart;
begin
  ReadLanes;
  WalkSteps;
  ApplySizeRules;
  L('digraph roundtrip {');
  L('  graph [rankdir=LR, fontname="Segoe UI", bgcolor="#FFFFFF", nodesep=0.3, ranksep=0.55, newrank=true, pad=0.3];');
  L('  node [shape=plain, fontname="Segoe UI", fontsize=12];');
  L('  edge [fontname="Segoe UI", fontsize=10, color="#5B6674", fontcolor="#5B6674", arrowsize=0.7];');
  var NodeLines:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    for var N in FNodes do
      NodeLines.AddOrSetValue(N.Key, '    ' + N.Id + ' [' + NodeAttr(N) + ', label=<' + NodeHtml(N) + '>];');
    var AlsoEdges:= TList<string>.Create;
    try
      var AlsoNode: TChartNode;
      if FNodeByKey.TryGetValue(KIND_ALSO, AlsoNode) then
        for var R in AlsoNode.Rows do
        begin
          if R.Folded then
            Continue;
          var Hit:= AlsoTarget(R.Item.Text);
          if Hit <> nil then
            AlsoEdges.Add('  ' + AlsoNode.Id + ':' + R.Port + ' -> ' + Hit.Id + ' [style=dotted, color="' + INK_ALSO
              + '", constraint=false, arrowhead=open];');
        end;
      var Hdr:= HeaderHtml;
      var Lg:= LegendHtml;
      L('  hdr [label=<' + Hdr + '>, tooltip="' + XmlText('REGENERATE ' + FTrace.Regenerate).Replace('\', '\\') + '"];');
      EmitLanes(NodeLines);
      L('  legend [label=<' + Lg + '>];');
      EmitEdges;
      for var A in AlsoEdges do
        L(A);
    finally
      AlsoEdges.Free;
    end;
  finally
    NodeLines.Free;
  end;
  L('  hdr -> legend [style=invis];');
  L('}');
  FinishManifest;
  Result.Dot:= FSb.ToString;
  CheckAscii(Result.Dot);
  Result.Manifest:= FManifest;
  FManifest:= nil;
end;

function TraceChart(pTrace: TTrace; pAnchorPaths: TDictionary<string, string>; const pCaps: TChartCaps): TTraceChart;
begin
  var Builder:= TChartBuilder.Create(pTrace, pAnchorPaths, pCaps);
  try
    Result:= Builder.Build;
  finally
    Builder.Free;
  end;
end;

end.
