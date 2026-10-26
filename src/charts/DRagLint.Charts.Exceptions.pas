unit DRagLint.Charts.Exceptions;

(* The exception-paths helpers: the ref classifier (RAISE / HANDLE / other, decided by the
  SOURCE TOKEN around a name-filtered ref), the source-only scan (bare except, raise;,
  raise <var> -- statements that carry no ref), the try-block nesting scan, the re-raise
  test of one handler, the per-EDGE upward walk of a raised type, and the index-wide stats.
  Each routine is a port of the named function in charts\src\Emit-Common.ps1 (line numbers
  of 2026-10-13); the PowerShell output is the reference (spec P3/P4).

  PS TRAPS CLOSED HERE: `-match` / `-eq` / `-ieq` / `switch` are case-insensitive while
  `-cnotmatch` and [regex]::Replace are not; .NET \s also matches #$85 and #$A0 and .NET \w
  / \b count Latin-1 letters as word characters (PS_WS, PS_WORD); .NET Match.Index is
  0-based, Delphi TMatch.Index 1-based; Sort-Object on integers sorts numerically. *)

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Charts.Index
  , DRagLint.Charts.Source
  ;

type
  /// <summary>A 1-based inclusive line span (the PS $Skip pair).</summary>
  TLineSpan = record
    /// <summary>First line.</summary>
    FromLine: Integer;
    /// <summary>Last line.</summary>
    ToLine  : Integer;
    /// <summary>Builds a span.</summary>
    /// <param name="pFrom">First line.</param>
    /// <param name="pTo">Last line.</param>
    /// <returns>The span.</returns>
    class function Make(pFrom, pTo: Integer): TLineSpan; static;
  end;

  /// <summary>One source-only exception statement. Port of a Get-ExceptionSourceRowsIn row.</summary>
  TExceptionSourceRow = record
    /// <summary>bare-except | on-except | reraise | raise-var | raise-create | raise-other.</summary>
    Kind: string;
    /// <summary>1-based line.</summary>
    Line: Integer;
    /// <summary>1-based column of the keyword.</summary>
    Col : Integer;
    /// <summary>'except', 'raise' or 'raise &lt;var&gt;'.</summary>
    Text: string;
  end;

  /// <summary>The source-only rows of one range of one file. Port of the Get-ExceptionSourceRows result.</summary>
  TExceptionSourceScan = record
    /// <summary>The indexed path.</summary>
    Path : string;
    /// <summary>The file differs from the indexed copy; no rows.</summary>
    Stale: Boolean;
    /// <summary>The rows.</summary>
    Rows : TArray<TExceptionSourceRow>;
  end;

  /// <summary>One try-block. Positions are line * 100000 + column, as Int64: the PS arithmetic widens,
  /// and a line past 21474 would overflow an Integer.</summary>
  TTryBlock = record
    /// <summary>The `try`.</summary>
    TryPos    : Int64;
    /// <summary>The `except`; 0 when none.</summary>
    ExceptPos : Int64;
    /// <summary>The `finally`; 0 when none.</summary>
    FinallyPos: Int64;
    /// <summary>The closing `end`.</summary>
    EndPos    : Int64;
    /// <summary>The `on` clauses of the except part.</summary>
    OnPos     : TArray<Int64>;
  end;

  /// <summary>The try-blocks of one span. Port of the Get-TryBlocks result.</summary>
  TTryBlocks = record
    /// <summary>False: the nesting could not be decided (Blocks empty).</summary>
    Decided: Boolean;
    /// <summary>Why not decided; '' when decided.</summary>
    Reason : string;
    /// <summary>The blocks, in the order their `end` was met.</summary>
    Blocks : TArray<TTryBlock>;
  end;

  /// <summary>What the caller's edge evaluation decided (the PS $Evaluate result).</summary>
  /// <remarks>The walk reads only Stopped; Tag is the caller's own handle on its richer result.</remarks>
  TEdgeVerdict = record
    /// <summary>The caller stops the type on this edge.</summary>
    Stopped: Boolean;
    /// <summary>Caller-defined.</summary>
    Tag    : Integer;
  end;

  /// <summary>Evaluates ONE edge: does caller pCaller stop pType on its calls to pCallee at pSites?</summary>
  TEvaluateEdge = reference to function(pCaller, pCallee: Integer; const pSites: TArray<Int64>; const pType: string): TEdgeVerdict;
  /// <summary>Which of pIds have a caller at all (asked only at the depth bound).</summary>
  THasCallers = reference to function(const pIds: TArray<Integer>): TArray<Integer>;

  /// <summary>One evaluated edge of the walk.</summary>
  TWalkEdge = record
    /// <summary>The caller.</summary>
    Caller : Integer;
    /// <summary>The callee.</summary>
    Callee : Integer;
    /// <summary>The call sites (positions).</summary>
    Sites  : TArray<Int64>;
    /// <summary>The evaluation.</summary>
    Verdict: TEdgeVerdict;
  end;

  /// <summary>The upward walk of one raised type. Port of the Invoke-ExceptionWalk result.</summary>
  TExceptionWalk = record
    /// <summary>The type walked.</summary>
    TypeName     : string;
    /// <summary>Every evaluated edge, in evaluation order.</summary>
    Edges        : TArray<TWalkEdge>;
    /// <summary>Callers that pass the type, ascending (the focus excluded).</summary>
    Passing      : TArray<Integer>;
    /// <summary>Distinct callers looked at.</summary>
    Evaluated    : Integer;
    /// <summary>Passing nodes at the bound whose callers exist but were not walked, ascending.</summary>
    Escapes      : TArray<Integer>;
    /// <summary>Passing callers with no resolved caller at all, ascending.</summary>
    Ends         : TArray<Integer>;
    /// <summary>Distinct capped callers of passing nodes, ascending (never "no caller").</summary>
    Capped       : TArray<Integer>;
    /// <summary>The focus itself has no caller.</summary>
    FocusNoCaller: Boolean;
    /// <summary>Levels walked.</summary>
    Levels       : Integer;
  end;

  /// <summary>One incoming call edge of a callee.</summary>
  TCallerEdge = record
    /// <summary>The caller.</summary>
    Caller: Integer;
    /// <summary>Its call sites (positions).</summary>
    Sites : TArray<Int64>;
  end;

  /// <summary>The caller graph the walk runs over (the PS $CallersOf / $Fetched / $CappedOf).</summary>
  TExceptionGraph = class
  private
    FCallersOf: TObjectDictionary<Integer, TList<TCallerEdge>>;
    FFetched  : TDictionary<Integer, Boolean>;
    FCappedOf : TObjectDictionary<Integer, TList<Integer>>;
  public
    /// <summary>Constructor: an empty graph.</summary>
    constructor Create;
    /// <summary>Frees the graph.</summary>
    destructor Destroy; override;
    /// <summary>Records that pCaller calls pCallee at pSites (a walked edge).</summary>
    /// <param name="pCallee">The callee.</param>
    /// <param name="pCaller">The caller.</param>
    /// <param name="pSites">Its call sites.</param>
    procedure AddCaller(pCallee, pCaller: Integer; const pSites: TArray<Int64>);
    /// <summary>Records a caller of pCallee kept out by the caller cap (once).</summary>
    /// <param name="pCallee">The callee.</param>
    /// <param name="pCaller">The capped caller.</param>
    procedure AddCapped(pCallee, pCaller: Integer);
    /// <summary>Marks pNode as one whose callers were queried.</summary>
    /// <param name="pNode">The node.</param>
    procedure MarkFetched(pNode: Integer);
    /// <summary>Unmarks pNode (a test hook: the PS removes a key).</summary>
    /// <param name="pNode">The node.</param>
    procedure UnmarkFetched(pNode: Integer);
    /// <summary>Whether pNode's callers were queried.</summary>
    /// <param name="pNode">The node.</param>
    /// <returns>True when fetched.</returns>
    function Fetched(pNode: Integer): Boolean;
    /// <summary>pCallee's walked incoming edges, in insertion order.</summary>
    /// <param name="pCallee">The callee.</param>
    /// <returns>A copy; empty when none.</returns>
    function CallersOf(pCallee: Integer): TArray<TCallerEdge>;
    /// <summary>pCallee's capped callers, in insertion order.</summary>
    /// <param name="pCallee">The callee.</param>
    /// <returns>A copy; empty when none.</returns>
    function CappedOf(pCallee: Integer): TArray<Integer>;
  end;

  /// <summary>The index-wide exception candidates, classified. Port of the Get-ExceptionIndexStats result.</summary>
  TExceptionStats = record
    /// <summary>Name-filtered refs.</summary>
    Candidates    : Integer;
    /// <summary>Classified raise (the PS Raise).</summary>
    RaiseSites    : Integer;
    /// <summary>Classified handle (the PS Handle).</summary>
    HandleSites   : Integer;
    /// <summary>Classified other (dropped and counted).</summary>
    Dropped       : Integer;
    /// <summary>In a stale file.</summary>
    Stale         : Integer;
    /// <summary>Distinct routines holding a raise.</summary>
    RaiseRoutines : Integer;
    /// <summary>Distinct routines holding a handle.</summary>
    HandleRoutines: Integer;
    /// <summary>Distinct files.</summary>
    Files         : Integer;
    /// <summary>Of them fresh.</summary>
    FreshFiles    : Integer;
  end;

  /// <summary>The index-backed exception helpers over one Delphi index.</summary>
  /// <remarks>Caches the non-class name set (per index) like the PS $script: cache. Neither
  /// the index nor the reader is owned. Not thread-safe.</remarks>
  TExceptionIndex = class
  private
    FIndex   : TChartsIndex;
    FReader  : TSourceReader;
    FNonClass: TDictionary<string, Boolean>;
    FFactsProbed: Boolean;
    FHasFacts   : Boolean;
    function FactIndexStats: TExceptionStats;
  public
    /// <summary>Constructor: the helpers over one index.</summary>
    /// <param name="pIndex">The Delphi index; not owned.</param>
    /// <param name="pReader">A source reader over it; not owned.</param>
    constructor Create(pIndex: TChartsIndex; pReader: TSourceReader);
    /// <summary>Frees the cache.</summary>
    destructor Destroy; override;
    /// <summary>Whether a name counts as a reference to an exception TYPE.</summary>
    /// <param name="pName">A name.</param>
    /// <returns>True for `E&lt;Capital&gt;...` with a lower-case letter, or `Exception`, unless the
    /// index declares it ONLY as something other than a class.</returns>
    /// <remarks>Port of Test-ExceptionTypeName (Emit-Common.ps1:2517); the pattern is
    /// case-SENSITIVE (-cnotmatch) and so is the set (a default HashSet).</remarks>
    function IsExceptionTypeName(const pName: string): Boolean;
    /// <summary>The source-only rows of one range of one file, gated on freshness.</summary>
    /// <param name="pPath">The indexed file.</param>
    /// <param name="pFrom">First line.</param>
    /// <param name="pTo">Last line.</param>
    /// <param name="pSkip">Spans to leave out (nested routines).</param>
    /// <returns>The scan; Stale with no rows when the file is not the indexed copy.</returns>
    /// <remarks>Port of Get-ExceptionSourceRows (Emit-Common.ps1:2451).</remarks>
    function SourceRows(const pPath: string; pFrom, pTo: Integer; const pSkip: TArray<TLineSpan>): TExceptionSourceScan;
    /// <summary>The index-wide exception candidates, classified by their source token.</summary>
    /// <returns>The counts.</returns>
    /// <remarks>Port of Get-ExceptionIndexStats (Emit-Common.ps1:2740). The PS per-run cache
    /// is not ported: a caller keeps the result.</remarks>
    function IndexStats: TExceptionStats;
    /// <summary>Whether this index carries the raise / handle facts (refs.kind raise, raise-expr,
    /// reraise, handle, handle-all), so a raise or handler site is joined by kind instead of being
    /// classified from the source text around a read / type_use.</summary>
    /// <returns>True when refs holds at least one row of the five kinds. Probed once, then cached.</returns>
    /// <remarks>Keyed on the rows, not on the extractor version: the version that adds them is
    /// bumped once by the 1.36.0 merge, and a version bump re-parses EVERY file, so a DB is either
    /// all-facts or none. A post-bump DB with no raise and no handler anywhere reads False and takes
    /// the source path, which finds nothing either. Spec 2026-10-26-extract-raise-handle-facts 5.1.</remarks>
    function HasRaiseHandleFacts: Boolean;
  end;

/// <summary>Classifies ONE name-filtered ref by the stripped text around it.</summary>
/// <param name="pCtx">Its source context (TSourceReader.SourceContext).</param>
/// <param name="pKind">refs.kind.</param>
/// <returns>stale | raise (a read after `raise`, before `.Create...`) | handle (a type_use after
/// `on` or `on &lt;id&gt;:`) | other.</returns>
/// <remarks>Port of Get-ExceptionRefClass (Emit-Common.ps1:2418). A qualifier before the name is
/// skipped; when nothing (or only `E:`) precedes it, the previous line's tail is read in front.</remarks>
function ExceptionRefClass(const pCtx: TSourceContext; const pKind: string): string;

/// <summary>The source-only exception statements of a line range, over STRIPPED lines.</summary>
/// <param name="pLines">Stripped lines.</param>
/// <param name="pFrom">First line (clamped to 1).</param>
/// <param name="pTo">Last line (clamped to the count).</param>
/// <param name="pSkip">Spans to leave out.</param>
/// <returns>The rows, in line then column order.</returns>
/// <remarks>Port of Get-ExceptionSourceRowsIn (Emit-Common.ps1:2462).</remarks>
function ExceptionSourceRowsIn(const pLines: TArray<string>; pFrom, pTo: Integer; const pSkip: TArray<TLineSpan>): TArray<TExceptionSourceRow>;

/// <summary>The SQL pre-filter of exception-type names.</summary>
/// <param name="pColumn">The column.</param>
/// <returns>'(&lt;col&gt; GLOB ''E[A-Z]*[a-z]*'' OR &lt;col&gt; = ''Exception'')'.</returns>
/// <remarks>Port of Get-ExceptionNameSql (Emit-Common.ps1:2514).</remarks>
function ExceptionNameSql(const pColumn: string): string;

/// <summary>The five raise / handle fact kinds as a SQL IN-list body.</summary>
/// <returns>'''raise'',''raise-expr'',''reraise'',''handle'',''handle-all''' -- from the REF_KIND_*
/// constants of DRagLint.Core.Model, so the extractor and the chart read one declaration.</returns>
/// <remarks>Every name-filtered candidate query excludes these kinds: a fact row sits on the same
/// identifier as the read / type_use it describes and must never be counted as a second,
/// dropped candidate.</remarks>
function ExceptionFactKindsSql: string;

/// <summary>The try-blocks of one span, from a nesting scan of stripped lines.</summary>
/// <param name="pLines">Stripped lines.</param>
/// <param name="pFrom">First line.</param>
/// <param name="pTo">Last line.</param>
/// <returns>Decided with the blocks, or not decided with the reason.</returns>
/// <remarks>Port of Get-TryBlocks (Emit-Common.ps1:2555). Tokens after '.', '&amp;' or a word
/// character are identifiers; inside `asm` only `end` counts; a `case` inside a `record` opens nothing.</remarks>
function TryBlocks(const pLines: TArray<string>; pFrom, pTo: Integer): TTryBlocks;

/// <summary>The innermost try-block whose EXCEPT part holds a position.</summary>
/// <param name="pBlocks">TryBlocks' result.</param>
/// <param name="pPos">A position (line * 100000 + column).</param>
/// <param name="pBlock">The block.</param>
/// <returns>False when none holds it.</returns>
/// <remarks>Port of Find-HandlerBlock (Emit-Common.ps1:2603).</remarks>
function FindHandlerBlock(const pBlocks: TTryBlocks; pPos: Int64; out pBlock: TTryBlock): Boolean;

/// <summary>Whether the handler at a position re-raises what it caught.</summary>
/// <param name="pLines">Stripped lines.</param>
/// <param name="pBlock">The block whose except part holds pPos.</param>
/// <param name="pPos">The handler's position.</param>
/// <param name="pBare">pPos is the block's bare `except`.</param>
/// <returns>True for `raise;` (or `raise` before else/end) or `raise V` of the handler's own variable.</returns>
/// <remarks>Port of Test-HandlerReraises (Emit-Common.ps1:2621). Line-granular.</remarks>
function HandlerReraises(const pLines: TArray<string>; const pBlock: TTryBlock; pPos: Int64; pBare: Boolean): Boolean;

/// <summary>The upward walk of ONE raised type over the call EDGES of a caller graph.</summary>
/// <param name="pFocusId">The routine that raises.</param>
/// <param name="pGraph">The caller graph.</param>
/// <param name="pDepth">Levels to walk.</param>
/// <param name="pType">The type.</param>
/// <param name="pEvaluate">Edge evaluation.</param>
/// <param name="pHasCallers">Caller existence at the bound.</param>
/// <returns>The walk.</returns>
/// <remarks>Port of Invoke-ExceptionWalk (Emit-Common.ps1:2671): every incoming edge is
/// evaluated on its own; a node passes when ANY incoming edge is not stopped, and a passing node
/// is expanded once (which also ends a cycle).</remarks>
function InvokeExceptionWalk(pFocusId: Integer; pGraph: TExceptionGraph; pDepth: Integer; const pType: string;
  const pEvaluate: TEvaluateEdge; const pHasCallers: THasCallers): TExceptionWalk;

/// <summary>Integers joined with ',' (the PS "$($a -join ',')").</summary>
/// <param name="pValues">The integers.</param>
/// <returns>The text.</returns>
function IntsText(const pValues: TArray<Integer>): string;

implementation

uses
  System.RegularExpressions
  , System.Math
  , System.Generics.Defaults
  , DRagLint.Core.Model
  ;

const
  POS_SCALE = 100000;
  { .NET \s and \w over Latin-1 text }
  WS = '[\s\x{85}\x{A0}]';
  WORD_CLASS = '\w\x{AA}\x{B5}\x{BA}\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{FF}';
  WD = '[' + WORD_CLASS + ']';
  NOT_AFTER_WORD = '(?<!' + WD + ')';
  NOT_BEFORE_WORD = '(?!' + WD + ')';
  QUALIFIER_TAIL_PATTERN = '(?:[A-Za-z_]' + WD + '*' + WS + '*\.' + WS + '*)+$';
  LABEL_PATTERN = '(?i)^[A-Za-z_]' + WD + '*' + WS + '*:$';
  RAISE_END_PATTERN = '(?i)' + NOT_AFTER_WORD + 'raise' + WS + '*$';
  CREATE_AFTER_PATTERN = '(?i)^' + WS + '*\.' + WS + '*Create' + WD + '*' + NOT_BEFORE_WORD;
  ON_END_PATTERN = '(?i)' + NOT_AFTER_WORD + 'on(' + WS + '+[A-Za-z_]' + WD + '*' + WS + '*:)?' + WS + '*$';
  KEYWORD_PATTERN = '(?i)' + NOT_AFTER_WORD + '(except|raise)' + NOT_BEFORE_WORD;
  ON_START_PATTERN = '(?i)^' + WS + '*on' + NOT_BEFORE_WORD;
  SEMI_START_PATTERN = '^' + WS + '*;';
  BLOCK_END_PATTERN = '(?i)^' + WS + '*(else|end|until|except|finally)' + NOT_BEFORE_WORD;
  RAISE_CREATE_PATTERN = '(?i)^' + WS + '*[A-Za-z_][' + WORD_CLASS + '\s\x{85}\x{A0}\.]*?\.' + WS + '*Create' + WD + '*' + NOT_BEFORE_WORD;
  RAISE_VAR_PATTERN = '(?i)^' + WS + '*([A-Za-z_]' + WD + '*)(?>' + WS + '*)(?![\.\(' + WORD_CLASS + '])';
  TRY_TOKEN_PATTERN = '(?i)(?<![' + WORD_CLASS + '&\.])(begin|end|case|record|asm|try|except|finally|on)' + NOT_BEFORE_WORD;
  HANDLER_VAR_PATTERN = '(?i)^on' + WS + '+([A-Za-z_]' + WD + '*)' + WS + '*:';
  EXCEPTION_NAME_PATTERN = '^(E[A-Z]' + WD + '*[a-z]' + WD + '*|Exception)$';
  KIND_RERAISE = 'reraise';
  KIND_RAISE_VAR = 'raise-var';
  CLASS_RAISE = 'raise';
  CLASS_HANDLE = 'handle';
  CLASS_OTHER = 'other';
  CLASS_STALE = 'stale';

function IntsText(const pValues: TArray<Integer>): string;
begin
  var Parts: TArray<string>:= [];
  for var V in pValues do
    Parts:= Parts + [IntToStr(V)];
  Result:= string.Join(',', Parts);
end;

function IntIn(const pValues: TArray<Integer>; pValue: Integer): Boolean;
begin
  for var V in pValues do
    if V = pValue then
      Exit(True);
  Result:= False;
end;

function SortedInts(const pValues: TArray<Integer>; pUnique: Boolean): TArray<Integer>;
begin
  Result:= Copy(pValues);
  TArray.Sort<Integer>(Result);
  if not pUnique then
    Exit;
  var N:= 0;
  for var K:= 0 to Length(Result) - 1 do
    if (N = 0) or (Result[N - 1] <> Result[K]) then
    begin
      Result[N]:= Result[K];
      Inc(N);
    end;
  SetLength(Result, N);
end;

class function TLineSpan.Make(pFrom, pTo: Integer): TLineSpan;
begin
  Result.FromLine:= pFrom;
  Result.ToLine:= pTo;
end;

function IsBlank(const pS: string): Boolean;
begin
  Result:= PsTrim(pS) = '';
end;

function ExceptionRefClass(const pCtx: TSourceContext; const pKind: string): string;
begin
  if pCtx.Stale then
    Exit(CLASS_STALE);
  if IsBlank(pCtx.Token) then
    Exit(CLASS_OTHER);
  var B:= TRegEx.Replace(pCtx.Before, QUALIFIER_TAIL_PATTERN, '');
  var Bt:= PsTrim(B);
  if (Bt = '') or TRegEx.IsMatch(Bt, LABEL_PATTERN) then
    B:= pCtx.PrevLine + ' ' + Bt;
  if SameText(pKind, 'read') and TRegEx.IsMatch(B, RAISE_END_PATTERN) and TRegEx.IsMatch(pCtx.After, CREATE_AFTER_PATTERN) then
    Exit(CLASS_RAISE);
  if SameText(pKind, 'type_use') and TRegEx.IsMatch(B, ON_END_PATTERN) then
    Exit(CLASS_HANDLE);
  Result:= CLASS_OTHER;
end;

function Skipped(pLine: Integer; const pSkip: TArray<TLineSpan>): Boolean;
begin
  for var S in pSkip do
    if (pLine >= S.FromLine) and (pLine <= S.ToLine) then
      Exit(True);
  Result:= False;
end;

{ What follows a keyword: the rest of its line, else the next non-blank line. }
function RestAfter(const pLines: TArray<string>; pLine: Integer; const pT: string; pAfter: Integer): string;
begin
  Result:= Copy(pT, pAfter, MaxInt);
  if not IsBlank(Result) then
    Exit;
  Result:= '';
  for var K:= pLine to Length(pLines) - 1 do
    if not IsBlank(pLines[K]) then
      Exit(pLines[K]);
end;

{ The kind and text of one `raise` by what follows it. }
procedure ClassifyRaise(const pRest: string; var pRow: TExceptionSourceRow);
begin
  pRow.Text:= 'raise';
  if TRegEx.IsMatch(pRest, SEMI_START_PATTERN) or IsBlank(pRest) or TRegEx.IsMatch(pRest, BLOCK_END_PATTERN) then
    pRow.Kind:= KIND_RERAISE
  else if TRegEx.IsMatch(pRest, RAISE_CREATE_PATTERN) then
    pRow.Kind:= 'raise-create'
  else
  begin
    { atomic whitespace: `raise Foo (x)` must not backtrack into a match }
    var M:= TRegEx.Match(pRest, RAISE_VAR_PATTERN);
    if M.Success then
    begin
      pRow.Kind:= KIND_RAISE_VAR;
      pRow.Text:= 'raise ' + M.Groups[1].Value;
    end
    else
      pRow.Kind:= 'raise-other';
  end;
end;

function ExceptionSourceRowsIn(const pLines: TArray<string>; pFrom, pTo: Integer; const pSkip: TArray<TLineSpan>): TArray<TExceptionSourceRow>;
begin
  Result:= [];
  var Hi:= Min(pTo, Length(pLines));
  for var Ln:= Max(pFrom, 1) to Hi do
  begin
    if Skipped(Ln, pSkip) then
      Continue;
    var T:= pLines[Ln - 1];
    for var M in TRegEx.Matches(T, KEYWORD_PATTERN) do
    begin
      var Rest:= RestAfter(pLines, Ln, T, M.Index + M.Length);
      var Row:= Default(TExceptionSourceRow);
      Row.Line:= Ln;
      Row.Col:= M.Index;
      if SameText(M.Groups[1].Value, 'except') then
      begin
        Row.Kind:= if TRegEx.IsMatch(Rest, ON_START_PATTERN) then 'on-except' else 'bare-except';
        Row.Text:= 'except';
      end
      else
        ClassifyRaise(Rest, Row);
      Result:= Result + [Row];
    end;
  end;
end;

function ExceptionNameSql(const pColumn: string): string;
begin
  Result:= Format('(%0:s GLOB ''E[A-Z]*[a-z]*'' OR %0:s = ''Exception'')', [pColumn]);
end;

function ExceptionFactKindsSql: string;
begin
  Result:= QuotedStr(REF_KIND_RAISE) + ',' + QuotedStr(REF_KIND_RAISE_EXPR) + ',' + QuotedStr(REF_KIND_RERAISE) + ',' +
    QuotedStr(REF_KIND_HANDLE) + ',' + QuotedStr(REF_KIND_HANDLE_ALL);
end;

type
  { One open block of the nesting scan (the PS stack object). }
  TOpenBlock = record
    Kind      : string;
    Pos       : Int64;
    ExceptPos : Int64;
    FinallyPos: Int64;
    OnPos     : TArray<Int64>;
  end;

  { The scan state: the open-block stack, the closed try-blocks, and the first failure. }
  TTryScan = record
    Stack : TArray<TOpenBlock>;
    Blocks: TArray<TTryBlock>;
    Fail  : string;
    procedure Token(const pWord: string; pPos: Int64; pLine: Integer);
    procedure CloseEnd(pPos: Int64; pLine: Integer);
  end;

procedure TTryScan.CloseEnd(pPos: Int64; pLine: Integer);
begin
  if Length(Stack) = 0 then
  begin
    Fail:= Format('an `end` at line %d closes nothing', [pLine]);
    Exit;
  end;
  var Top:= Stack[High(Stack)];
  SetLength(Stack, Length(Stack) - 1);
  if Top.Kind <> 'try' then
    Exit;
  var B: TTryBlock;
  B.TryPos:= Top.Pos;
  B.ExceptPos:= Top.ExceptPos;
  B.FinallyPos:= Top.FinallyPos;
  B.EndPos:= pPos;
  B.OnPos:= Top.OnPos;
  Blocks:= Blocks + [B];
end;

procedure TTryScan.Token(const pWord: string; pPos: Int64; pLine: Integer);
begin
  var HasTop:= Length(Stack) > 0;
  var TopKind:= if HasTop then Stack[High(Stack)].Kind else '';
  if (TopKind = 'asm') and (pWord <> 'end') then
    Exit;
  if pWord = 'end' then
    CloseEnd(pPos, pLine)
  else if (pWord = 'except') or (pWord = 'finally') then
  begin
    if (TopKind <> 'try') or (Stack[High(Stack)].ExceptPos <> 0) or (Stack[High(Stack)].FinallyPos <> 0) then
      Fail:= Format('`%s` at line %d has no open try', [pWord, pLine])
    else if pWord = 'except' then
      Stack[High(Stack)].ExceptPos:= pPos
    else
      Stack[High(Stack)].FinallyPos:= pPos;
  end
  else if pWord = 'on' then
  begin
    if (TopKind = 'try') and (Stack[High(Stack)].ExceptPos <> 0) then
      Stack[High(Stack)].OnPos:= Stack[High(Stack)].OnPos + [pPos];
  end
  else if not ((pWord = 'case') and (TopKind = 'record')) then
  begin
    var O:= Default(TOpenBlock);
    O.Kind:= pWord;
    O.Pos:= pPos;
    Stack:= Stack + [O];
  end;
end;

function TryBlocks(const pLines: TArray<string>; pFrom, pTo: Integer): TTryBlocks;
var
  S: TTryScan;
begin
  S:= Default(TTryScan);
  var Hi:= Min(pTo, Length(pLines));
  var Ln:= Max(pFrom, 1);
  while (Ln <= Hi) and (S.Fail = '') do
  begin
    for var M in TRegEx.Matches(pLines[Ln - 1], TRY_TOKEN_PATTERN) do
    begin
      S.Token(M.Groups[1].Value.ToLowerInvariant, Int64(Ln) * POS_SCALE + M.Index, Ln);
      if S.Fail <> '' then
        Break;
    end;
    Inc(Ln);
  end;
  if (S.Fail = '') and (Length(S.Stack) > 0) then
    S.Fail:= Format('%d block(s) still open at the end of the span', [Length(S.Stack)]);
  Result.Decided:= S.Fail = '';
  Result.Reason:= S.Fail;
  Result.Blocks:= [];
  if Result.Decided then
    Result.Blocks:= S.Blocks;
end;

function FindHandlerBlock(const pBlocks: TTryBlocks; pPos: Int64; out pBlock: TTryBlock): Boolean;
begin
  pBlock:= Default(TTryBlock);
  Result:= False;
  for var B in pBlocks.Blocks do
    if (B.ExceptPos <> 0) and (B.ExceptPos <= pPos) and (pPos < B.EndPos) and (not Result or (B.ExceptPos > pBlock.ExceptPos)) then
    begin
      pBlock:= B;
      Result:= True;
    end;
end;

function HandlerReraises(const pLines: TArray<string>; const pBlock: TTryBlock; pPos: Int64; pBare: Boolean): Boolean;
var
  A, B: Integer;
begin
  var HandlerVar:= '';
  if pBare then
  begin
    A:= Integer(pBlock.ExceptPos div POS_SCALE);
    B:= Integer(pBlock.EndPos div POS_SCALE);
  end
  else
  begin
    var OnAt: Int64:= 0;
    var Next: Int64:= 0;
    for var P in pBlock.OnPos do
      if P <= pPos then
        OnAt:= Max(OnAt, P)
      else if (Next = 0) or (P < Next) then
        Next:= P;
    if OnAt = 0 then
      Exit(False);
    A:= Integer(OnAt div POS_SCALE);
    B:= if Next <> 0 then Max(A, Integer(Next div POS_SCALE) - 1) else Integer(pBlock.EndPos div POS_SCALE);
    var M:= TRegEx.Match(Copy(pLines[A - 1], Integer(OnAt mod POS_SCALE), MaxInt), HANDLER_VAR_PATTERN);
    if M.Success then
      HandlerVar:= M.Groups[1].Value;
  end;
  for var R in ExceptionSourceRowsIn(pLines, A, B, []) do
    if (R.Kind = KIND_RERAISE) or ((HandlerVar <> '') and (R.Kind = KIND_RAISE_VAR) and SameText(R.Text, 'raise ' + HandlerVar)) then
      Exit(True);
  Result:= False;
end;

{ ---- TExceptionGraph ---- }

constructor TExceptionGraph.Create;
begin
  inherited Create;
  FCallersOf:= TObjectDictionary<Integer, TList<TCallerEdge>>.Create([doOwnsValues]);
  FFetched:= TDictionary<Integer, Boolean>.Create;
  FCappedOf:= TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
end;

destructor TExceptionGraph.Destroy;
begin
  FCappedOf.Free;
  FFetched.Free;
  FCallersOf.Free;
  inherited Destroy;
end;

procedure TExceptionGraph.AddCaller(pCallee, pCaller: Integer; const pSites: TArray<Int64>);
var
  L: TList<TCallerEdge>;
  E: TCallerEdge;
begin
  L:= nil;
  if not FCallersOf.TryGetValue(pCallee, L) then
  begin
    L:= TList<TCallerEdge>.Create;
    FCallersOf.Add(pCallee, L);
  end;
  E.Caller:= pCaller;
  E.Sites:= pSites;
  L.Add(E);
end;

procedure TExceptionGraph.AddCapped(pCallee, pCaller: Integer);
var
  L: TList<Integer>;
begin
  L:= nil;
  if not FCappedOf.TryGetValue(pCallee, L) then
  begin
    L:= TList<Integer>.Create;
    FCappedOf.Add(pCallee, L);
  end;
  if not L.Contains(pCaller) then
    L.Add(pCaller);
end;

procedure TExceptionGraph.MarkFetched(pNode: Integer);
begin
  FFetched.AddOrSetValue(pNode, True);
end;

procedure TExceptionGraph.UnmarkFetched(pNode: Integer);
begin
  FFetched.Remove(pNode);
end;

function TExceptionGraph.Fetched(pNode: Integer): Boolean;
begin
  Result:= FFetched.ContainsKey(pNode);
end;

function TExceptionGraph.CallersOf(pCallee: Integer): TArray<TCallerEdge>;
var
  L: TList<TCallerEdge>;
begin
  L:= nil;
  Result:= [];
  if FCallersOf.TryGetValue(pCallee, L) then
    Result:= L.ToArray;
end;

function TExceptionGraph.CappedOf(pCallee: Integer): TArray<Integer>;
var
  L: TList<Integer>;
begin
  L:= nil;
  Result:= [];
  if FCappedOf.TryGetValue(pCallee, L) then
    Result:= L.ToArray;
end;

{ ---- the walk ---- }

type
  { The walk's working sets (the PS $w* locals). }
  TWalkState = class
  private
    FPassing  : TDictionary<Integer, Boolean>;
    FEvaluated: TDictionary<Integer, Boolean>;
    FCapped   : TDictionary<Integer, Boolean>;
    FEscapes  : TArray<Integer>;
    FEnds     : TArray<Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure NoteCapped(const pCap: TArray<Integer>);
    property Passing: TDictionary<Integer, Boolean> read FPassing;
    property Evaluated: TDictionary<Integer, Boolean> read FEvaluated;
    property Capped: TDictionary<Integer, Boolean> read FCapped;
    property Escapes: TArray<Integer> read FEscapes write FEscapes;
    property Ends: TArray<Integer> read FEnds write FEnds;
  end;

constructor TWalkState.Create;
begin
  inherited Create;
  FPassing:= TDictionary<Integer, Boolean>.Create;
  FEvaluated:= TDictionary<Integer, Boolean>.Create;
  FCapped:= TDictionary<Integer, Boolean>.Create;
end;

destructor TWalkState.Destroy;
begin
  FCapped.Free;
  FEvaluated.Free;
  FPassing.Free;
  inherited Destroy;
end;

procedure TWalkState.NoteCapped(const pCap: TArray<Integer>);
begin
  for var X in pCap do
    Capped.AddOrSetValue(X, True);
end;

{ The depth bound: nodes still carrying the type whose callers were not expanded. }
procedure ClassifyBound(pGraph: TExceptionGraph; const pFront: TArray<Integer>; const pHasCallers: THasCallers; pState: TWalkState);
begin
  var Unq: TArray<Integer>:= [];
  for var N in pFront do
    if not pGraph.Fetched(N) then
      Unq:= Unq + [N];
  var Has: TArray<Integer>:= [];
  if Length(Unq) > 0 then
    Has:= pHasCallers(Unq);
  for var N in pFront do
  begin
    var Cap:= pGraph.CappedOf(N);
    pState.NoteCapped(Cap);
    if pGraph.Fetched(N) then
    begin
      if Length(pGraph.CallersOf(N)) > 0 then
        pState.Escapes:= pState.Escapes + [N]
      else if Length(Cap) = 0 then
        pState.Ends:= pState.Ends + [N];
    end
    else if IntIn(Has, N) then
      pState.Escapes:= pState.Escapes + [N]
    else
      pState.Ends:= pState.Ends + [N];
  end;
end;

function InvokeExceptionWalk(pFocusId: Integer; pGraph: TExceptionGraph; pDepth: Integer; const pType: string;
  const pEvaluate: TEvaluateEdge; const pHasCallers: THasCallers): TExceptionWalk;
begin
  Result:= Default(TExceptionWalk);
  Result.TypeName:= pType;
  var St:= TWalkState.Create;
  try
    St.Passing.Add(pFocusId, True);
    var Front: TArray<Integer>:= [pFocusId];
    while (Length(Front) > 0) and (Result.Levels < pDepth) do
    begin
      Inc(Result.Levels);
      var Next: TArray<Integer>:= [];
      for var N in Front do
      begin
        var Cs:= pGraph.CallersOf(N);
        var Cap:= pGraph.CappedOf(N);
        St.NoteCapped(Cap);
        if Length(Cs) = 0 then
        begin
          { callers exist when the cap hid them; otherwise the node has none }
          if Length(Cap) > 0 then
            Continue;
          if N = pFocusId then
            Result.FocusNoCaller:= True
          else if pGraph.Fetched(N) then
            St.Ends:= St.Ends + [N]
          else
            St.Escapes:= St.Escapes + [N];
          Continue;
        end;
        for var E in Cs do
        begin
          var Edge: TWalkEdge;
          Edge.Caller:= E.Caller;
          Edge.Callee:= N;
          Edge.Sites:= E.Sites;
          Edge.Verdict:= pEvaluate(E.Caller, N, E.Sites, pType);
          St.Evaluated.AddOrSetValue(E.Caller, True);
          Result.Edges:= Result.Edges + [Edge];
          if not Edge.Verdict.Stopped and not St.Passing.ContainsKey(E.Caller) then
          begin
            St.Passing.Add(E.Caller, True);
            Next:= Next + [E.Caller];
          end;
        end;
      end;
      Front:= Next;
    end;
    if Length(Front) > 0 then
      ClassifyBound(pGraph, Front, pHasCallers, St);
    St.Passing.Remove(pFocusId);
    Result.Passing:= SortedInts(St.Passing.Keys.ToArray, False);
    Result.Evaluated:= St.Evaluated.Count;
    Result.Escapes:= SortedInts(St.Escapes, True);
    Result.Ends:= SortedInts(St.Ends, True);
    Result.Capped:= SortedInts(St.Capped.Keys.ToArray, False);
  finally
    St.Free;
  end;
end;

{ ---- TExceptionIndex ---- }

constructor TExceptionIndex.Create(pIndex: TChartsIndex; pReader: TSourceReader);
begin
  inherited Create;
  FIndex:= pIndex;
  FReader:= pReader;
end;

destructor TExceptionIndex.Destroy;
begin
  FNonClass.Free;
  inherited Destroy;
end;

function TExceptionIndex.IsExceptionTypeName(const pName: string): Boolean;
begin
  if not TRegEx.IsMatch(pName, EXCEPTION_NAME_PATTERN) then
    Exit(False);
  if FNonClass = nil then
  begin
    FNonClass:= TDictionary<string, Boolean>.Create;
    var Rows:= FIndex.AllRows('SELECT name AS name FROM symbols WHERE ' + ExceptionNameSql('name') +
      ' GROUP BY name HAVING SUM(kind = ''class'') = 0', 'name');
    try
      for var R in Rows do
        FNonClass.AddOrSetValue(R.S('name'), True);
    finally
      Rows.Free;
    end;
  end;
  Result:= not FNonClass.ContainsKey(pName);
end;

function TExceptionIndex.SourceRows(const pPath: string; pFrom, pTo: Integer; const pSkip: TArray<TLineSpan>): TExceptionSourceScan;
begin
  Result:= Default(TExceptionSourceScan);
  Result.Path:= pPath;
  if not FReader.SourceFresh(pPath) then
  begin
    Result.Stale:= True;
    Exit;
  end;
  Result.Rows:= ExceptionSourceRowsIn(FReader.StrippedSourceLines(FReader.ReadPath(pPath)), pFrom, pTo, pSkip);
end;

function TExceptionIndex.HasRaiseHandleFacts: Boolean;
begin
  if not FFactsProbed then
  begin
    var Rows:= FIndex.Query('SELECT 1 AS x FROM refs WHERE kind IN (' + ExceptionFactKindsSql + ') LIMIT 1');
    try
      FHasFacts:= Rows.Count > 0;
    finally
      Rows.Free;
    end;
    FFactsProbed:= True;
  end;
  Result:= FHasFacts;
end;

{ IndexStats over the facts: a name-filtered candidate is a raise / handle when a raise / handle
  fact sits on its identifier (same file, line, column), else it is dropped. Raise and handle sites
  are the exception-named FACT rows, so a qualified `raise U.EFoo.Create` (whose only candidate
  is the member-access on EFoo) is a raise site. Nothing reads source: Stale stays 0. }
function TExceptionIndex.FactIndexStats: TExceptionStats;
begin
  Result:= Default(TExceptionStats);
  var Files:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var RaiseAt:= TDictionary<Integer, Boolean>.Create;
  var HandleAt:= TDictionary<Integer, Boolean>.Create;
  var FactAt:= TDictionary<string, Boolean>.Create;
  var Rows:= FIndex.AllRows('SELECT r.id AS id, r.kind AS kind, r.name_text AS name, r.start_line AS line, r.start_col AS col, ' +
    'r.file_id AS fid, r.enclosing_symbol_id AS encl, f.path AS path FROM refs r JOIN files f ON f.id = r.file_id WHERE ' +
    ExceptionNameSql('r.name_text') + ' AND r.kind NOT IN (' + QuotedStr(REF_KIND_RAISE_EXPR) + ',' +
    QuotedStr(REF_KIND_RERAISE) + ',' + QuotedStr(REF_KIND_HANDLE_ALL) + ')', 'r.id');
  try
    for var R in Rows do
    begin
      var IsRaise:= R.S('kind') = REF_KIND_RAISE;
      if not (IsRaise or (R.S('kind') = REF_KIND_HANDLE)) or not IsExceptionTypeName(R.S('name')) then
        Continue;
      FactAt.AddOrSetValue(Format('%d:%d:%d', [R.I('fid'), R.I('line'), R.I('col')]), True);
      if IsRaise then
        Inc(Result.RaiseSites)
      else
        Inc(Result.HandleSites);
      if R.I('encl') = 0 then
        Continue;
      if IsRaise then
        RaiseAt.AddOrSetValue(R.I('encl'), True)
      else
        HandleAt.AddOrSetValue(R.I('encl'), True);
    end;
    for var R in Rows do
    begin
      if (R.S('kind') = REF_KIND_RAISE) or (R.S('kind') = REF_KIND_HANDLE) or not IsExceptionTypeName(R.S('name')) then
        Continue;
      Inc(Result.Candidates);
      var P:= R.S('path');
      if not Files.ContainsKey(P) then
        Files.Add(P, FReader.SourceFresh(P));
      if not FactAt.ContainsKey(Format('%d:%d:%d', [R.I('fid'), R.I('line'), R.I('col')])) then
        Inc(Result.Dropped);
    end;
    Result.RaiseRoutines:= RaiseAt.Count;
    Result.HandleRoutines:= HandleAt.Count;
    Result.Files:= Files.Count;
    for var Fresh in Files.Values do
      if Fresh then
        Inc(Result.FreshFiles);
  finally
    Rows.Free;
    FactAt.Free;
    HandleAt.Free;
    RaiseAt.Free;
    Files.Free;
  end;
end;

function TExceptionIndex.IndexStats: TExceptionStats;
begin
  if HasRaiseHandleFacts then
    Exit(FactIndexStats);
  Result:= Default(TExceptionStats);
  var Files:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var RaiseAt:= TDictionary<Integer, Boolean>.Create;
  var HandleAt:= TDictionary<Integer, Boolean>.Create;
  { the fact kinds are never candidates (ExceptionFactKindsSql); on a pre-facts DB they match nothing }
  var Rows:= FIndex.AllRows('SELECT r.id AS id, r.kind AS kind, r.name_text AS name, r.start_line AS line, r.start_col AS col, ' +
    'r.end_col AS ecol, r.enclosing_symbol_id AS encl, f.path AS path FROM refs r JOIN files f ON f.id = r.file_id WHERE ' +
    ExceptionNameSql('r.name_text') + ' AND r.kind NOT IN (' + ExceptionFactKindsSql + ')', 'r.id');
  try
    for var R in Rows do
    begin
      if not IsExceptionTypeName(R.S('name')) then
        Continue;
      Inc(Result.Candidates);
      var P:= R.S('path');
      if not Files.ContainsKey(P) then
        Files.Add(P, FReader.SourceFresh(P));
      var C:= FReader.SourceContext(P, R.I('line'), R.I('col'), R.I('ecol') - R.I('col'));
      var Cls:= ExceptionRefClass(C, R.S('kind'));
      if Cls = CLASS_RAISE then
        Inc(Result.RaiseSites)
      else if Cls = CLASS_HANDLE then
        Inc(Result.HandleSites)
      else if Cls = CLASS_STALE then
        Inc(Result.Stale)
      else
        Inc(Result.Dropped);
      if R.I('encl') = 0 then
        Continue;
      if Cls = CLASS_RAISE then
        RaiseAt.AddOrSetValue(R.I('encl'), True)
      else if Cls = CLASS_HANDLE then
        HandleAt.AddOrSetValue(R.I('encl'), True);
    end;
    Result.RaiseRoutines:= RaiseAt.Count;
    Result.HandleRoutines:= HandleAt.Count;
    Result.Files:= Files.Count;
    for var Fresh in Files.Values do
      if Fresh then
        Inc(Result.FreshFiles);
  finally
    Rows.Free;
    HandleAt.Free;
    RaiseAt.Free;
    Files.Free;
  end;
end;

end.
