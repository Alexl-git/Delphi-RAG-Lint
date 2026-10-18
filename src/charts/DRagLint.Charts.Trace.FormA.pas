unit DRagLint.Charts.Trace.FormA;

(* The round-trip step MODEL and its Form A text: builders, a canonical writer and a parser for what
  the writer emits (a port of charts\src\Trace.FormA.ps1; the PS output is the reference). Pure: no
  index access and no file writes. The question unit builds the model and writes the bytes; the tests
  prove the round trip (spec AC-2).

  Canonical layout (the ONLY layout ReadFormA reads):

    TRACE <name>
      TITLE "<title>"
      FROM <selection>
      INDEX <a> + <b> + <c> AS OF <date>
      REGENERATE <command>
      TIERS <t> -> <t> -> ...
    <blank>
    <SECTION>
      -- <note>                    (an EMPTY section only, or DERIVED's lead-in above its rows)
    [NN] [<ACTOR> ]<text>[ [by name]|[inferred]] @<file>:<line>[ -- <note>]
           WHEN|UNLESS <condition> @<file>:<line>[ -- <note>]
           <FACET> <text>[ @<file>:<line>][ -- <note>]
    [NN] [<ACTOR> ]CROSSES <text> @<file>:<line>[ -- <note>]
    [NN] [<ACTOR> ]STOPS <reason> @<file>:<line>[ -- <note>]
    <blank>
    END TRACE  <n> steps, <n> conditions, <n> crossings, <n> unresolved.

  A note is `in <Routine>`, then `; <free text>`, then `; ask <E>`, each part optional and in that
  order, so the parser splits it back. Free text never contains `; `. A text never contains ` @`,
  ` [` or ` -- `, and no field holds a CR or LF: the model refuses both, which keeps the line
  regexes unambiguous. Conditions are written VERBATIM and UNQUOTED; the model refuses the two things
  that would make the line ambiguous (an ` @<file>:<line>` or an ` -- ` inside one). The TITLE is
  quoted and refuses a double-quote.

  PowerShell traps closed here: -cmatch is case-sensitive and -match is NOT, so every regex below is
  case-sensitive except where the script used -match (the anchor shape, the actor / kind / head word
  guards and the note parts, which use IgnoreCase); -split "\r\n" keeps empty strings (the parser drops
  the final empty element); a property set after creation (Item.Number, Section.Note, Trace.Title)
  is a plain field here. Refusal messages are the PowerShell throw texts, verbatim. *)

interface

uses
  System.SysUtils, System.Generics.Collections;

const
  /// <summary>The facet heads a step's child line may open with (REGENERATE: the command that traces a DERIVED row's source).</summary>
  FORMA_FACETS: array[0..8] of string = ('VIA', 'ONTO', 'AT', 'CONTRACT', 'FROM', 'TO', 'OVER', 'WITH', 'REGENERATE');
  /// <summary>The condition keywords.</summary>
  FORMA_CONDS: array[0..1] of string = ('WHEN', 'UNLESS');
  /// <summary>The actor words a numbered line may carry before its text.</summary>
  FORMA_ACTORS: array[0..3] of string = ('USER', 'CLIENT', 'SERVER', 'DATABASE');
  /// <summary>The shape of an anchor: &lt;file leaf&gt;:&lt;line&gt; without the '@' (tested case-insensitively).</summary>
  RE_FORMA_ANCHOR = '^[A-Za-z0-9_$.\-]+:\d+$';

type
  /// <summary>A refusal of the model (a text the writer or parser cannot keep faithful); the message is the PowerShell throw text.</summary>
  EChartsTrace = class(Exception);

  /// <summary>The recomputed END TRACE counts (never stored on the model).</summary>
  TTraceCounts = record
    /// <summary>Numbered lines across all sections.</summary>
    Steps     : Integer;
    /// <summary>Children of Kind 'cond'.</summary>
    Conditions: Integer;
    /// <summary>Items of Kind 'crosses'.</summary>
    Crossings : Integer;
    /// <summary>Items of Kind 'stops' (in every section).</summary>
    Unresolved: Integer;
  end;

  /// <summary>A line under a step: a condition (Kind 'cond') or a facet (Kind 'facet').</summary>
  /// <remarks>One class; the two PowerShell objects differ by Kind. Owned by its TTraceItem.</remarks>
  TTraceChild = class
  public
    /// <summary>'cond' or 'facet'.</summary>
    Kind     : string;
    /// <summary>cond: WHEN or UNLESS.</summary>
    Keyword  : string;
    /// <summary>cond: the guard text, verbatim.</summary>
    Condition: string;
    /// <summary>facet: the head word (one of FORMA_FACETS).</summary>
    Head     : string;
    /// <summary>facet: the text after the head.</summary>
    Text     : string;
    /// <summary>The anchor '&lt;file&gt;:&lt;line&gt;' ('' allowed for a facet).</summary>
    Anchor   : string;
    /// <summary>The free-text note part.</summary>
    Note     : string;
    /// <summary>cond: the ask part (E-number).</summary>
    Ask      : string;
    /// <summary>cond: the routine the condition hangs on when it is another routine's ('in Routine' note part).</summary>
    Routine  : string;
  end;

  /// <summary>One numbered line of the trace (Kind step | stops | crosses) with its child lines.</summary>
  /// <remarks>Owns Children. The walker fields (Line .. Omits) are set by Trace.Walk and ignored by
  /// WriteFormA; they are Add-Member properties in the PowerShell. Number is assigned by WriteFormA.</remarks>
  TTraceItem = class
  public
    /// <summary>'step', 'stops' or 'crosses'.</summary>
    Kind       : string;
    /// <summary>The 1-based number WriteFormA (or ReadFormA) assigned.</summary>
    Number     : Integer;
    /// <summary>USER, CLIENT, SERVER, DATABASE or ''.</summary>
    Actor      : string;
    /// <summary>The line text (never opens with an actor, kind or counted head word).</summary>
    Text       : string;
    /// <summary>'', 'by name' or 'inferred'.</summary>
    Grade      : string;
    /// <summary>The anchor '&lt;file&gt;:&lt;line&gt;' (required for every kind, AC-11).</summary>
    Anchor     : string;
    /// <summary>The 'in Routine' note part.</summary>
    Routine    : string;
    /// <summary>The free-text note part.</summary>
    Note       : string;
    /// <summary>The 'ask E' note part.</summary>
    Ask        : string;
    /// <summary>The condition and facet lines under the step; owned.</summary>
    Children   : TObjectList<TTraceChild>;
    /// <summary>Trace.Walk only: the source line the step was found on (0 = unset).</summary>
    Line       : Integer;
    /// <summary>Trace.Walk only: the owning routine's symbol id (0 = unset).</summary>
    Owner      : Integer;
    /// <summary>Trace.Walk only: a CROSSES item's pipe command name.</summary>
    Command    : string;
    /// <summary>Trace.Walk only: the callee's symbol id on a CALLS step (0 = unset).</summary>
    CalleeId   : Integer;
    /// <summary>Trace.Walk only: how many caller conditions were hung on the step (0 = none).</summary>
    CallerConds: Integer;
    /// <summary>Trace.Walk only: True on an OMITS step.</summary>
    Omits      : Boolean;
    /// <summary>Constructor: creates an empty item with an empty Children list.</summary>
    constructor Create;
    /// <summary>Frees Children.</summary>
    destructor Destroy; override;
  end;

  /// <summary>A named group of items.</summary>
  /// <remarks>Owns Items. Note stands for an EMPTY section (or leads DERIVED's rows).</remarks>
  TTraceSection = class
  public
    /// <summary>The upper-case section name.</summary>
    Name : string;
    /// <summary>The generated '  -- note' line under the header.</summary>
    Note : string;
    /// <summary>The numbered items; owned.</summary>
    Items: TObjectList<TTraceItem>;
    /// <summary>Constructor: creates an empty section.</summary>
    constructor Create;
    /// <summary>Frees Items.</summary>
    destructor Destroy; override;
  end;

  /// <summary>The whole trace: header attributes plus sections.</summary>
  /// <remarks>Owns Sections and everything under them. Free it when done.</remarks>
  TTrace = class
  public
    /// <summary>The TRACE name.</summary>
    Name      : string;
    /// <summary>The quoted TITLE (no double-quote).</summary>
    Title     : string;
    /// <summary>The FROM selection.</summary>
    From      : string;
    /// <summary>The INDEX list.</summary>
    Index     : string;
    /// <summary>The single-word AS OF date.</summary>
    AsOf      : string;
    /// <summary>The REGENERATE command.</summary>
    Regenerate: string;
    /// <summary>The TIERS chain.</summary>
    Tiers     : string;
    /// <summary>The sections in order; owned.</summary>
    Sections  : TObjectList<TTraceSection>;
    /// <summary>Constructor: creates an empty trace.</summary>
    constructor Create;
    /// <summary>Frees Sections.</summary>
    destructor Destroy; override;
  end;

/// <summary>Creates a trace with no sections.</summary>
/// <param name="pName">The TRACE name.</param>
/// <param name="pTitle">The quoted TITLE; must carry no double-quote.</param>
/// <param name="pFrom">The FROM selection.</param>
/// <param name="pIndex">The INDEX list ('a + b + c').</param>
/// <param name="pAsOf">The single-word AS OF date.</param>
/// <param name="pRegenerate">The REGENERATE command.</param>
/// <param name="pTiers">The TIERS chain.</param>
/// <returns>A new trace; the caller frees it.</returns>
/// <remarks>Refuses (EChartsTrace, via TestTraceTitle) a title that carries a double-quote.</remarks>
function NewTrace(const pName, pTitle, pFrom, pIndex, pAsOf, pRegenerate, pTiers: string): TTrace;

/// <summary>Appends an empty section to pTrace.</summary>
/// <param name="pTrace">The trace that owns the new section.</param>
/// <param name="pName">An upper-case word (case-sensitive ^[A-Z]+$).</param>
/// <returns>The section (owned by pTrace).</returns>
/// <exception cref="EChartsTrace">The name is not an upper-case word.</exception>
function AddTraceSection(pTrace: TTrace; const pName: string): TTraceSection;

/// <summary>Creates a numbered item.</summary>
/// <param name="pKind">step, stops or crosses.</param>
/// <param name="pText">The line text; TestTraceText (head rules) applies.</param>
/// <param name="pAnchor">'&lt;file&gt;:&lt;line&gt;' without the '@'; REQUIRED for every kind (AC-11).</param>
/// <param name="pGrade">'', 'by name' or 'inferred'.</param>
/// <param name="pRoutine">The 'in Routine' note part.</param>
/// <param name="pNote">The free-text note part.</param>
/// <param name="pAsk">The 'ask E' note part.</param>
/// <param name="pActor">'' or one of FORMA_ACTORS (case-sensitive); an actor word in pText is refused instead.</param>
/// <returns>A new item; the caller adds it to a section (which owns it) or frees it.</returns>
/// <exception cref="EChartsTrace">Bad kind, anchor ('AC-11'), grade, actor, or a text TestTraceText refuses.</exception>
function NewTraceStep(const pKind, pText, pAnchor: string; const pGrade: string = ''; const pRoutine: string = '';
  const pNote: string = ''; const pAsk: string = ''; const pActor: string = ''): TTraceItem;

/// <summary>Creates a WHEN / UNLESS child line; the condition is kept verbatim.</summary>
/// <param name="pKeyword">WHEN or UNLESS (case-sensitive).</param>
/// <param name="pCondition">The guard text; TraceCondProblem must name nothing.</param>
/// <param name="pAnchor">'&lt;file&gt;:&lt;line&gt;' without the '@'.</param>
/// <param name="pNote">The free-text note part.</param>
/// <param name="pAsk">The 'ask E' note part.</param>
/// <param name="pRoutine">Set when the condition hangs on a step of ANOTHER routine; written as the note's 'in Routine'.</param>
/// <returns>A new child; the caller adds it to an item's Children (owned) or frees it.</returns>
/// <exception cref="EChartsTrace">Bad keyword or anchor, empty condition, a condition TraceCondProblem names, or a line break.</exception>
function NewTraceCond(const pKeyword, pCondition, pAnchor: string; const pNote: string = ''; const pAsk: string = '';
  const pRoutine: string = ''): TTraceChild;

/// <summary>Creates a facet child line (VIA ONTO AT CONTRACT FROM TO OVER WITH REGENERATE).</summary>
/// <param name="pHead">One of FORMA_FACETS (case-sensitive).</param>
/// <param name="pText">The text after the head; TestTraceText applies.</param>
/// <param name="pAnchor">'' or '&lt;file&gt;:&lt;line&gt;' without the '@'.</param>
/// <param name="pNote">The free-text note part.</param>
/// <returns>A new child; the caller adds it to an item's Children or frees it.</returns>
/// <exception cref="EChartsTrace">Bad head, bad anchor, or a text TestTraceText refuses.</exception>
function NewTraceFacet(const pHead, pText: string; const pAnchor: string = ''; const pNote: string = ''): TTraceChild;

/// <summary>Why a condition cannot be written unquoted and read back verbatim.</summary>
/// <param name="pCondition">The condition text.</param>
/// <returns>'' when it can; else the reason (it reads as its anchor, or as its note).</returns>
function TraceCondProblem(const pCondition: string): string;

/// <summary>Refuses a text the line regexes would misread.</summary>
/// <param name="pText">The text to check.</param>
/// <param name="pWhat">Names the field in the message ('step text', 'facet text').</param>
/// <param name="pHead">True for a STEP text: adds the head-word rules (counted words, section word before STOPS, lone annotation).</param>
/// <exception cref="EChartsTrace">The text is empty, has a line break, ' @', ' [', ' -- ', a leading '--', a trailing ' --', or a refused head.</exception>
procedure TestTraceText(const pText, pWhat: string; pHead: Boolean = False);

/// <summary>Refuses a title that cannot be quoted verbatim.</summary>
/// <param name="pTitle">The title to check.</param>
/// <exception cref="EChartsTrace">The title carries a double-quote.</exception>
procedure TestTraceTitle(const pTitle: string);

/// <summary>The END TRACE line of pCounts; the ONE builder, so the text and the chart cannot word it two ways.</summary>
/// <param name="pCounts">The counts to word.</param>
/// <returns>'END TRACE  n steps, n conditions, n crossings, n unresolved.'</returns>
function FormatTraceEndLine(const pCounts: TTraceCounts): string;

/// <summary>The counts recomputed from the items (AC-3).</summary>
/// <param name="pTrace">The trace to count.</param>
/// <returns>Steps, conditions (cond children), crossings and unresolved (stops items, in every section).</returns>
function TraceCounts(pTrace: TTrace): TTraceCounts;

/// <summary>How many items and children carry a non-empty anchor.</summary>
/// <param name="pTrace">The trace to count.</param>
/// <returns>The anchor count.</returns>
function TraceAnchors(pTrace: TTrace): Integer;

/// <summary>AC-11: the numbered lines of a Form A text whose own anchor is not a clickable source span.</summary>
/// <param name="pText">A Form A text.</param>
/// <returns>The offending lines, in order.</returns>
/// <remarks>The anchor is the last thing before the first ' -- ', so one quoted in the note does not count;
/// 'index:0' is not clickable either.</remarks>
function TraceUnclickable(const pText: string): TArray<string>;

/// <summary>Joins the note parts: 'in Routine; free text; ask E'.</summary>
/// <param name="pRoutine">One word with no ';', or ''.</param>
/// <param name="pNote">Free text without '; ' or a line break, or ''.</param>
/// <param name="pAsk">One word with no ';', or ''.</param>
/// <returns>The joined note, '' when all three are empty.</returns>
/// <exception cref="EChartsTrace">A part is malformed ('; ' in the note, a line break, a routine or ask that is not one word).</exception>
function FormatTraceNote(const pRoutine, pNote, pAsk: string): string;

/// <summary>Splits a note back into its parts.</summary>
/// <param name="pNote">A note as FormatTraceNote joins it.</param>
/// <param name="pRoutine">The 'in X' part, only when it is the FIRST piece.</param>
/// <param name="pAsk">The 'ask X' part.</param>
/// <returns>The remaining free text, pieces joined by '; '.</returns>
function SplitTraceNote(const pNote: string; out pRoutine, pAsk: string): string;

/// <summary>The canonical Form A text. Numbers the items in place, recomputes the counts, refuses any byte outside 0x20-0x7E/CR/LF.</summary>
/// <param name="pTrace">The trace to write.</param>
/// <returns>The text, CRLF line ends, ending in the END TRACE line.</returns>
/// <exception cref="EChartsTrace">An empty or multi-line header, a quote in the title, a note with steps, or non-ASCII ('not 7-bit ASCII').</exception>
function WriteFormA(pTrace: TTrace): string;

/// <summary>Reads the canonical layout back into a model; any line it cannot place is an error and the END TRACE counts must recompute.</summary>
/// <param name="pText">A Form A text as WriteFormA emits it.</param>
/// <returns>A new trace; the caller frees it.</returns>
/// <exception cref="EChartsTrace">E-EOL (bare LF or no final CRLF), E-NO-END, E-COUNTS, or an unparseable line.</exception>
function ReadFormA(const pText: string): TTrace;

implementation

uses
  System.StrUtils, System.RegularExpressions;

const
  CRLF = #13#10;
  MIN_NUMBER_DIGITS = 2;
  NOTE_SEP = '; ';
  RE_ROUTINE_WORD = '^[^\s;]+$';
  RE_BARE_LF = '(?<!\r)\n';
  RE_LINE_BREAK = '[\r\n]';
  RE_NOTE_IN_ONLY = '^in \S+$';
  RE_NOTE_ASK_ONLY = '^ask \S+$';
  RE_NOTE_IN = '^in (\S+)$';
  RE_NOTE_ASK = '^ask (\S+)$';
  RE_ACTOR_SPACE = '^(USER|CLIENT|SERVER|DATABASE) ';
  RE_KIND_SPACE = '^(CROSSES|STOPS) ';
  RE_HEAD_ACTOR_KIND = '^(USER|CLIENT|SERVER|DATABASE|CROSSES|STOPS)(\s|$)';
  RE_HEAD_COUNTED = '^(WHEN|UNLESS|GUARD|UNRESOLVED)(\s|$)';
  RE_HEAD_SECTION = '^(WRITE|READ|RESPONSE|ANCHOR|DERIVED|ALSO|USER|CLIENT|SERVER|DATABASE|PIPE)\s+(STOPS|CROSSES)(\s|$)';
  RE_HEAD_ANNOTATION = '^[\[@]';
  RE_COND_ANCHOR = ' @[A-Za-z0-9_$.\-]+:\d+';
  RE_CLICKABLE = ' @[A-Za-z0-9_$.\-]+\.(pas|dfm|dpr|inc|sql):[1-9]\d*$';
  RE_NUMBERED = '^\[\d{2,3}\] ';
  RE_SECTION_NAME = '^[A-Z]+$';
  RE_NON_ASCII = '[^\x0D\x0A\x20-\x7E]';
  RE_WHITESPACE = '\s';
  RE_H_TRACE = '^TRACE (.+)$';
  RE_H_TITLE = '^  TITLE "([^"]*)"$';
  RE_H_FROM = '^  FROM (.+)$';
  RE_H_INDEX = '^  INDEX (.+) AS OF (\S+)$';
  RE_H_REGENERATE = '^  REGENERATE (.+)$';
  RE_H_TIERS = '^  TIERS (.+)$';
  RE_SECTION_NOTE = '^  -- (.+)$';
  RE_STEP = '^\[(\d{2,3})\] (?:(USER|CLIENT|SERVER|DATABASE) )?(?:(CROSSES|STOPS) )?(.*?)(?: \[(by name|inferred)\])?(?: @(\S+))?(?: -- (.*))?$';
  RE_COND = '^       (WHEN|UNLESS) (.+?) @([A-Za-z0-9_$.\-]+:\d+)(?: -- (.*))?$';
  RE_FACET = '^       (VIA|ONTO|AT|CONTRACT|FROM|TO|OVER|WITH|REGENERATE) (.*?)(?: @(\S+))?(?: -- (.*))?$';
  RE_END = '^END TRACE  (\d+) steps, (\d+) conditions, (\d+) crossings, (\d+) unresolved\.$';
  STEP_NUMBER = 1;
  STEP_ACTOR = 2;
  STEP_KIND = 3;
  STEP_TEXT = 4;
  STEP_GRADE = 5;
  STEP_ANCHOR = 6;
  STEP_NOTE = 7;
  COND_KEYWORD = 1;
  COND_TEXT = 2;
  COND_ANCHOR = 3;
  COND_NOTE = 4;
  FACET_HEAD = 1;
  FACET_TEXT = 2;
  FACET_ANCHOR = 3;
  FACET_NOTE = 4;
  END_STEPS = 1;
  END_CONDITIONS = 2;
  END_CROSSINGS = 3;
  END_UNRESOLVED = 4;
  KIND_STEP = 'step';
  KIND_STOPS = 'stops';
  KIND_CROSSES = 'crosses';
  KIND_COND = 'cond';
  KIND_FACET = 'facet';
  HEADER_KEYS: array[0..6] of string = ('Name', 'Title', 'From', 'Index', 'AsOf', 'Regenerate', 'Tiers');

procedure Refuse(const pMessage: string);
begin
  raise EChartsTrace.Create(pMessage);
end;

procedure CheckCount(const pName: string; pDeclared, pGot: Integer);
begin
  if pGot <> pDeclared then
    Refuse('Read-FormA: END TRACE ' + pName + ' declared ' + IntToStr(pDeclared) + ', recomputed ' + IntToStr(pGot) + ' (E-COUNTS)');
end;

function InList(const pValue: string; const pList: array of string): Boolean;
begin
  Result:= False;
  for var S in pList do
    if SameStr(S, pValue) then
      Exit(True);
end;

function Rx(const pText, pPattern: string; pIgnoreCase: Boolean = False): Boolean;
begin
  if pIgnoreCase then
    Result:= TRegEx.IsMatch(pText, pPattern, [roIgnoreCase])
  else
    Result:= TRegEx.IsMatch(pText, pPattern);
end;

{ a group value; PCRE reports fewer groups when the trailing optional ones did not take part }
function Grp(const pMatch: TMatch; pIndex: Integer): string;
begin
  if pIndex < pMatch.Groups.Count then
    Result:= pMatch.Groups[pIndex].Value
  else
    Result:= '';
end;

function ListText(const pList: array of string; const pSep: string): string;
begin
  var Sb:= TStringBuilder.Create;
  try
    for var I:= 0 to High(pList) do
    begin
      if I > 0 then
        Sb.Append(pSep);
      Sb.Append(pList[I]);
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ TTraceItem }

constructor TTraceItem.Create;
begin
  inherited Create;
  Children:= TObjectList<TTraceChild>.Create;
end;

destructor TTraceItem.Destroy;
begin
  Children.Free;
  inherited;
end;

{ TTraceSection }

constructor TTraceSection.Create;
begin
  inherited Create;
  Items:= TObjectList<TTraceItem>.Create;
end;

destructor TTraceSection.Destroy;
begin
  Items.Free;
  inherited;
end;

{ TTrace }

constructor TTrace.Create;
begin
  inherited Create;
  Sections:= TObjectList<TTraceSection>.Create;
end;

destructor TTrace.Destroy;
begin
  Sections.Free;
  inherited;
end;

procedure TestTraceTitle(const pTitle: string);
begin
  if pTitle.Contains('"') then
    Refuse('Form A title carries a double-quote, so it cannot be quoted verbatim: ' + pTitle);
end;

procedure TestTraceText(const pText, pWhat: string; pHead: Boolean);
begin
  if Trim(pText) = '' then
    Refuse('Form A ' + pWhat + ' is empty');
  if Rx(pText, RE_LINE_BREAK) then
    Refuse('Form A ' + pWhat + ' must not contain a line break: ' + pText);
  if pText.Contains(' @') or pText.Contains(' [') or pText.Contains(' -- ') then
    Refuse('Form A ' + pWhat + ' must not contain '' @'', '' ['' or '' -- '': ' + pText);
  { a trailing ' --' becomes ' -- ' before the anchor or note; a leading '--' makes the checker strip the line }
  if pText.EndsWith(' --') or pText.StartsWith('--') then
    Refuse('Form A ' + pWhat + ' must not begin with ''--'' or end with '' --'': ' + pText);
  if Rx(pText, RE_ACTOR_SPACE, True) then
    Refuse('Form A ' + pWhat + ' must not begin with an actor word (pass -Actor): ' + pText);
  if Rx(pText, RE_KIND_SPACE, True) then
    Refuse('Form A ' + pWhat + ' must not begin with CROSSES or STOPS (pass -Kind): ' + pText);
  if not pHead then
    Exit;
  if Rx(pText, RE_HEAD_ACTOR_KIND, True) then
    Refuse('Form A ' + pWhat + ' must not be or begin with an actor or kind word (pass -Actor / -Kind): ' + pText);
  if Rx(pText, RE_HEAD_COUNTED, True) then
    Refuse('Form A ' + pWhat + ' must not begin with a counted head word (WHEN UNLESS GUARD UNRESOLVED): ' + pText);
  if Rx(pText, RE_HEAD_SECTION, True) then
    Refuse('Form A ' + pWhat + ' must not be a section word before STOPS / CROSSES: ' + pText);
  if Rx(pText, RE_HEAD_ANNOTATION, True) then
    Refuse('Form A ' + pWhat + ' must not begin with ''['' or ''@'' (the checker drops an annotation token): ' + pText);
end;

function NewTrace(const pName, pTitle, pFrom, pIndex, pAsOf, pRegenerate, pTiers: string): TTrace;
begin
  TestTraceTitle(pTitle);
  Result:= TTrace.Create;
  Result.Name:= pName;
  Result.Title:= pTitle;
  Result.From:= pFrom;
  Result.Index:= pIndex;
  Result.AsOf:= pAsOf;
  Result.Regenerate:= pRegenerate;
  Result.Tiers:= pTiers;
end;

function AddTraceSection(pTrace: TTrace; const pName: string): TTraceSection;
begin
  if not Rx(pName, RE_SECTION_NAME) then
    Refuse('Add-TraceSection: ''' + pName + ''' is not an upper-case section name');
  Result:= TTraceSection.Create;
  Result.Name:= pName;
  pTrace.Sections.Add(Result);
end;

function NewTraceStep(const pKind, pText, pAnchor, pGrade, pRoutine, pNote, pAsk, pActor: string): TTraceItem;  // dl:ok too-many-parameters@1eeb -- REVIEWED 2026-10-17: the 8-parameter signature is the PowerShell New-TraceStep's own and its callers (Trace.Walk, ReadFormA) pass them positionally.
begin
  if not (SameText(pKind, KIND_STEP) or SameText(pKind, KIND_STOPS) or SameText(pKind, KIND_CROSSES)) then
    Refuse('New-TraceStep: kind ''' + pKind + ''' is not step/stops/crosses');
  if not Rx(pAnchor, RE_FORMA_ANCHOR, True) then
    Refuse('New-TraceStep: ''' + pText + ''' has no anchor ''<file>:<line>'' (AC-11: every step carries one); got ''' + pAnchor + '''');
  if not (SameText(pGrade, '') or SameText(pGrade, 'by name') or SameText(pGrade, 'inferred')) then
    Refuse('New-TraceStep: grade ''' + pGrade + ''' is not ''''/''by name''/''inferred''');
  if (pActor <> '') and not InList(pActor, FORMA_ACTORS) then
    Refuse('New-TraceStep: actor ''' + pActor + ''' is not USER/CLIENT/SERVER/DATABASE');
  TestTraceText(pText, 'step text', True);
  Result:= TTraceItem.Create;
  Result.Kind:= pKind;
  Result.Actor:= pActor;
  Result.Text:= pText;
  Result.Grade:= pGrade;
  Result.Anchor:= pAnchor;
  Result.Routine:= pRoutine;
  Result.Note:= pNote;
  Result.Ask:= pAsk;
end;

function TraceCondProblem(const pCondition: string): string;
begin
  Result:= '';
  if Rx(pCondition, RE_COND_ANCHOR, True) then
    Result:= 'carries '' @<file>:<line>'', which reads as its anchor'
  else if pCondition.Contains(' -- ') or pCondition.EndsWith(' --') then
    Result:= 'carries '' -- '', which reads as its note';
end;

function NewTraceCond(const pKeyword, pCondition, pAnchor, pNote, pAsk, pRoutine: string): TTraceChild;
begin
  if not InList(pKeyword, FORMA_CONDS) then
    Refuse('New-TraceCond: ''' + pKeyword + ''' is not WHEN/UNLESS');
  if not Rx(pAnchor, RE_FORMA_ANCHOR, True) then
    Refuse('New-TraceCond: ''' + pCondition + ''' has no anchor; got ''' + pAnchor + '''');
  if Trim(pCondition) = '' then
    Refuse('New-TraceCond: empty condition');
  var Why:= TraceCondProblem(pCondition);
  if Why <> '' then
    Refuse('New-TraceCond: the condition ' + Why + ', so it cannot be written verbatim: ' + pCondition);
  if Rx(pCondition, RE_LINE_BREAK) then
    Refuse('New-TraceCond: the condition must not contain a line break (join a wrapped condition first): ' + pCondition);
  Result:= TTraceChild.Create;
  Result.Kind:= KIND_COND;
  Result.Keyword:= pKeyword;
  Result.Condition:= pCondition;
  Result.Anchor:= pAnchor;
  Result.Note:= pNote;
  Result.Ask:= pAsk;
  Result.Routine:= pRoutine;
end;

function NewTraceFacet(const pHead, pText, pAnchor, pNote: string): TTraceChild;
begin
  if not InList(pHead, FORMA_FACETS) then
    Refuse('New-TraceFacet: ''' + pHead + ''' is not a facet head (' + ListText(FORMA_FACETS, '/') + ')');
  if (pAnchor <> '') and not Rx(pAnchor, RE_FORMA_ANCHOR, True) then
    Refuse('New-TraceFacet: bad anchor ''' + pAnchor + '''');
  TestTraceText(pText, 'facet text');
  Result:= TTraceChild.Create;
  Result.Kind:= KIND_FACET;
  Result.Head:= pHead;
  Result.Text:= pText;
  Result.Anchor:= pAnchor;
  Result.Note:= pNote;
end;

function FormatTraceEndLine(const pCounts: TTraceCounts): string;
begin
  Result:= 'END TRACE  ' + IntToStr(pCounts.Steps) + ' steps, ' + IntToStr(pCounts.Conditions) + ' conditions, ' +
    IntToStr(pCounts.Crossings) + ' crossings, ' + IntToStr(pCounts.Unresolved) + ' unresolved.';
end;

function TraceCounts(pTrace: TTrace): TTraceCounts;
begin
  Result:= Default(TTraceCounts);
  for var Sec in pTrace.Sections do
    for var Item in Sec.Items do
    begin
      Inc(Result.Steps);
      if SameText(Item.Kind, KIND_CROSSES) then
        Inc(Result.Crossings);
      if SameText(Item.Kind, KIND_STOPS) then
        Inc(Result.Unresolved);
      for var Ch in Item.Children do
        if SameText(Ch.Kind, KIND_COND) then
          Inc(Result.Conditions);
    end;
end;

function TraceAnchors(pTrace: TTrace): Integer;
begin
  Result:= 0;
  for var Sec in pTrace.Sections do
    for var Item in Sec.Items do
    begin
      if Item.Anchor <> '' then
        Inc(Result);
      for var Ch in Item.Children do
        if Ch.Anchor <> '' then
          Inc(Result);
    end;
end;

function TraceUnclickable(const pText: string): TArray<string>;
begin
  var Found:= TList<string>.Create;
  try
    for var L in pText.Split([CRLF]) do
    begin
      if not Rx(L, RE_NUMBERED) then
        Continue;
      var Cut:= Pos(' -- ', L);
      var Head:= L;
      if Cut > 0 then
        Head:= Copy(L, 1, Cut - 1);
      if not Rx(Head, RE_CLICKABLE, True) then
        Found.Add(L);
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

function FormatTraceNote(const pRoutine, pNote, pAsk: string): string;
begin
  Result:= '';
  if pRoutine <> '' then
  begin
    if not Rx(pRoutine, RE_ROUTINE_WORD) then
      Refuse('Form A routine must be one word with no '';'': ' + pRoutine);
    Result:= 'in ' + pRoutine;
  end;
  if pNote <> '' then
  begin
    if Rx(pNote, RE_LINE_BREAK) then
      Refuse('Form A note must not contain a line break: ' + pNote);
    if pNote.Contains(NOTE_SEP) then
      Refuse('Form A note must not contain ''; '' (it is the note separator): ' + pNote);
    if Rx(pNote, RE_NOTE_IN_ONLY, True) or Rx(pNote, RE_NOTE_ASK_ONLY, True) then
      Refuse('Form A note must not read like a routine or ask part: ' + pNote);
    if Result = '' then
      Result:= pNote
    else
      Result:= Result + NOTE_SEP + pNote;
  end;
  if pAsk <> '' then
  begin
    if not Rx(pAsk, RE_ROUTINE_WORD) then
      Refuse('Form A ask must be one word with no '';'': ' + pAsk);
    if Result = '' then
      Result:= 'ask ' + pAsk
    else
      Result:= Result + NOTE_SEP + 'ask ' + pAsk;
  end;
end;

function SplitTraceNote(const pNote: string; out pRoutine, pAsk: string): string;
begin
  pRoutine:= '';
  pAsk:= '';
  Result:= '';
  var First:= True;
  var AnyRest:= False;
  for var P in pNote.Split([NOTE_SEP]) do
  begin
    if P = '' then
      Continue;
    var M:= TRegEx.Match(P, RE_NOTE_IN, [roIgnoreCase]);
    var MAsk:= TRegEx.Match(P, RE_NOTE_ASK, [roIgnoreCase]);
    if First and M.Success then
      pRoutine:= Grp(M, 1)
    else if MAsk.Success then
      pAsk:= MAsk.Groups[1].Value
    else
    begin
      if AnyRest then
        Result:= Result + NOTE_SEP + P
      else
        Result:= P;
      AnyRest:= True;
    end;
    First:= False;
  end;
end;

function WriteFormA(pTrace: TTrace): string;
  function HeaderValue(const pKey: string): string;
  begin
    if pKey = 'Name' then
      Result:= pTrace.Name
    else if pKey = 'Title' then
      Result:= pTrace.Title
    else if pKey = 'From' then
      Result:= pTrace.From
    else if pKey = 'Index' then
      Result:= pTrace.Index
    else if pKey = 'AsOf' then
      Result:= pTrace.AsOf
    else if pKey = 'Regenerate' then
      Result:= pTrace.Regenerate
    else
      Result:= pTrace.Tiers;
  end;
begin
  for var K in HEADER_KEYS do
  begin
    if Trim(HeaderValue(K)) = '' then
      Refuse('Write-FormA: header ' + K + ' is empty');
    if Rx(HeaderValue(K), RE_LINE_BREAK) then
      Refuse('Write-FormA: header ' + K + ' contains a line break');
  end;
  if Rx(pTrace.AsOf, RE_WHITESPACE) then
    Refuse('Write-FormA: header AsOf must be one word (the parser reads ''AS OF <word>''): ' + pTrace.AsOf);
  TestTraceTitle(pTrace.Title);
  var Sb:= TStringBuilder.Create;
  try
    Sb.Append('TRACE ').Append(pTrace.Name).Append(CRLF);
    Sb.Append('  TITLE "').Append(pTrace.Title).Append('"').Append(CRLF);
    Sb.Append('  FROM ').Append(pTrace.From).Append(CRLF);
    Sb.Append('  INDEX ').Append(pTrace.Index).Append(' AS OF ').Append(pTrace.AsOf).Append(CRLF);
    Sb.Append('  REGENERATE ').Append(pTrace.Regenerate).Append(CRLF);
    Sb.Append('  TIERS ').Append(pTrace.Tiers).Append(CRLF);
    var N:= 0;
    for var Sec in pTrace.Sections do
    begin
      Sb.Append(CRLF).Append(Sec.Name).Append(CRLF);
      if Sec.Note <> '' then
      begin
        { a note stands for an EMPTY section (T6-R2), except in DERIVED, where it leads the rows (8.5) }
        if (Sec.Items.Count > 0) and not SameStr(Sec.Name, 'DERIVED') then
          Refuse('Write-FormA: section ' + Sec.Name + ' has steps AND a note -- a note stands only for an empty section (or leads DERIVED''s rows)');
        if Rx(Sec.Note, RE_LINE_BREAK) then
          Refuse('Write-FormA: section ' + Sec.Name + ' note contains a line break');
        Sb.Append('  -- ').Append(Sec.Note).Append(CRLF);
      end;
      for var Item in Sec.Items do
      begin
        Inc(N);
        Item.Number:= N;
        Sb.Append('[').Append(Format('%.*d', [MIN_NUMBER_DIGITS, N])).Append('] ');
        if Item.Actor <> '' then
          Sb.Append(Item.Actor).Append(' ');
        if SameText(Item.Kind, KIND_CROSSES) then
          Sb.Append('CROSSES ').Append(Item.Text)
        else if SameText(Item.Kind, KIND_STOPS) then
          Sb.Append('STOPS ').Append(Item.Text)
        else
        begin
          Sb.Append(Item.Text);
          if Item.Grade <> '' then
            Sb.Append(' [').Append(Item.Grade).Append(']');
        end;
        var Note:= FormatTraceNote(Item.Routine, Item.Note, Item.Ask);
        Sb.Append(' @').Append(Item.Anchor);
        if Note <> '' then
          Sb.Append(' -- ').Append(Note);
        Sb.Append(CRLF);
        for var Ch in Item.Children do
        begin
          var CnRoutine:= '';
          if SameText(Ch.Kind, KIND_COND) then
            CnRoutine:= Ch.Routine;
          var Cn:= FormatTraceNote(CnRoutine, Ch.Note, Ch.Ask);
          if SameText(Ch.Kind, KIND_COND) then
            { verbatim and unquoted: New-TraceCond refused what the parser would misread }
            Sb.Append('       ').Append(Ch.Keyword).Append(' ').Append(Ch.Condition).Append(' @').Append(Ch.Anchor)
          else
          begin
            Sb.Append('       ').Append(Ch.Head).Append(' ').Append(Ch.Text);
            if Ch.Anchor <> '' then
              Sb.Append(' @').Append(Ch.Anchor);
          end;
          if Cn <> '' then
            Sb.Append(' -- ').Append(Cn);
          Sb.Append(CRLF);
        end;
      end;
    end;
    Sb.Append(CRLF).Append(FormatTraceEndLine(TraceCounts(pTrace))).Append(CRLF);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
  var Bad:= TRegEx.Match(Result, RE_NON_ASCII);
  if Bad.Success then
  begin
    var LineNo:= 1;
    var At:= Pos(CRLF, Result);
    while (At > 0) and (At < Bad.Index) do
    begin
      Inc(LineNo);
      At:= PosEx(CRLF, Result, At + Length(CRLF));
    end;
    Refuse('Form A text is not 7-bit ASCII: byte 0x' + IntToHex(Ord(Bad.Value[1]), MIN_NUMBER_DIGITS) + ' at line ' + IntToStr(LineNo) +
      ' (offset ' + IntToStr(Bad.Index - 1) + ')');
  end;
end;

function ReadFormA(const pText: string): TTrace;
var
  Sec : TTraceSection;
  Cur : TTraceItem;
  Counts: TTraceCounts;
  HaveCounts: Boolean;
  Rn, Ask, Nt: string;
begin
  if Rx(pText, RE_BARE_LF) then
    Refuse('Read-FormA: bare LF (E-EOL)');
  if not pText.EndsWith(CRLF) then
    Refuse('Read-FormA: the last line does not end in CRLF (E-EOL)');
  var Lines:= pText.Split([CRLF]);   { the final empty element is dropped below }
  Result:= NewTrace('x', 'x', 'x', 'x', 'x', 'x', 'x');
  var Done:= False;
  try
    Sec:= nil;
    Cur:= nil;
    HaveCounts:= False;
    Counts:= Default(TTraceCounts);
    for var I:= 0 to High(Lines) - 1 do
    begin
      var Raw:= Lines[I];
      if Raw = '' then
        Continue;
      var M:= TRegEx.Match(Raw, RE_H_TRACE);
      if M.Success then
      begin
        Result.Name:= Grp(M, 1);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_H_TITLE);
      if M.Success then
      begin
        Result.Title:= Grp(M, 1);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_H_FROM);
      if M.Success then
      begin
        Result.From:= Grp(M, 1);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_H_INDEX);
      if M.Success then
      begin
        Result.Index:= Grp(M, 1);
        Result.AsOf:= Grp(M, 2);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_H_REGENERATE);
      if M.Success then
      begin
        Result.Regenerate:= Grp(M, 1);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_H_TIERS);
      if M.Success then
      begin
        Result.Tiers:= Grp(M, 1);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_END);
      if M.Success then
      begin
        Counts.Steps:= StrToInt(Grp(M, END_STEPS));
        Counts.Conditions:= StrToInt(Grp(M, END_CONDITIONS));
        Counts.Crossings:= StrToInt(Grp(M, END_CROSSINGS));
        Counts.Unresolved:= StrToInt(Grp(M, END_UNRESOLVED));
        HaveCounts:= True;
        Continue;
      end;
      if Rx(Raw, RE_SECTION_NAME) then
      begin
        Sec:= AddTraceSection(Result, Raw);
        Cur:= nil;
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_SECTION_NOTE);
      if M.Success and (Sec <> nil) and (Sec.Items.Count = 0) and (Sec.Note = '') then
      begin
        Sec.Note:= Grp(M, 1);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_STEP);
      if M.Success then
      begin
        if Sec = nil then
          Refuse('Read-FormA: a step before any section: ' + Raw);
        var Kind:= KIND_STEP;
        if Grp(M, STEP_KIND) = 'CROSSES' then
          Kind:= KIND_CROSSES
        else if Grp(M, STEP_KIND) = 'STOPS' then
          Kind:= KIND_STOPS;
        Nt:= SplitTraceNote(Grp(M, STEP_NOTE), Rn, Ask);
        Cur:= NewTraceStep(Kind, Grp(M, STEP_TEXT), Grp(M, STEP_ANCHOR), Grp(M, STEP_GRADE), Rn, Nt, Ask, Grp(M, STEP_ACTOR));
        Cur.Number:= StrToInt(Grp(M, STEP_NUMBER));
        Sec.Items.Add(Cur);
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_COND);
      if M.Success then
      begin
        if Cur = nil then
          Refuse('Read-FormA: a condition before any step: ' + Raw);
        Nt:= SplitTraceNote(Grp(M, COND_NOTE), Rn, Ask);
        Cur.Children.Add(NewTraceCond(Grp(M, COND_KEYWORD), Grp(M, COND_TEXT), Grp(M, COND_ANCHOR), Nt, Ask, Rn));
        Continue;
      end;
      M:= TRegEx.Match(Raw, RE_FACET);
      if M.Success then
      begin
        if Cur = nil then
          Refuse('Read-FormA: a facet before any step: ' + Raw);
        Nt:= SplitTraceNote(Grp(M, FACET_NOTE), Rn, Ask);
        Cur.Children.Add(NewTraceFacet(Grp(M, FACET_HEAD), Grp(M, FACET_TEXT), Grp(M, FACET_ANCHOR), Nt));
        Continue;
      end;
      Refuse('Read-FormA: unparseable line: ' + Raw);
    end;
    if not HaveCounts then
      Refuse('Read-FormA: no END TRACE line (E-NO-END)');
    var Got:= TraceCounts(Result);
    CheckCount('Steps', Counts.Steps, Got.Steps);
    CheckCount('Conditions', Counts.Conditions, Got.Conditions);
    CheckCount('Crossings', Counts.Crossings, Got.Crossings);
    CheckCount('Unresolved', Counts.Unresolved, Got.Unresolved);
    Done:= True;
  finally
    if not Done then
      Result.Free;
  end;
end;

end.
