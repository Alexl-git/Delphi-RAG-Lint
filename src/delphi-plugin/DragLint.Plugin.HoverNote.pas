unit DragLint.Plugin.HoverNote;

(* What the status strip says about the place a hover asked about (owner request
   2026-11-25, lane 1.54.1 HOVERNOTE).

   Four pure pieces, no Open Tools API and no VCL, so
   tests\plugin\run_v1541_HOVERNOTE.ps1 drives them outside the IDE:

     * the token under a (row, column) of a Pascal source, with its kind;
     * the note texts (announce / empty answer) made from that token;
     * the pointer -> text column arithmetic, including the two places that have
       NO cell: the gutter and an editor without a grid;
     * the strip's texts and layout while a job runs, and the memo that keeps an
       empty answer from being repeated on every timer tick. *)

interface

type
  /// <summary>What kind of thing lies under a source position.</summary>
  TDLTokenKind = (
    htkBlank              , { white space, past the end of the line or of the file }
    htkIdent              , { an identifier: the only kind that can be "not indexed" }
    htkKeyword            , { a reserved word }
    htkDirective          , { a directive word that is never used as a name (override, stdcall) }
    htkNumber             ,
    htkOperator           , { operator or punctuation }
    htkInComment          ,
    htkInString           , { in a string literal, or a #nn character constant }
    htkInCompilerDirective  { inside a brace-dollar compiler directive }
  );

  /// <summary>The token (or white-space run) under one source position.</summary>
  /// <remarks>Start0 / End0 are 0-based columns of the row, End0 exclusive. Past
  /// the end of a line End0 is MaxInt; past the end of the file Start0 is 0.</remarks>
  TDLToken = record
    Kind  : TDLTokenKind;
    Text  : string ;
    Start0: Integer;
    End0  : Integer;
  end;

  /// <summary>Where a pointer X lies in an editor's grid.</summary>
  TDLCellVerdict = (
    hcvNoGrid, { no usable char width: nothing can be asked }
    hcvGutter, { left of the code: no text cell }
    hcvText    { a text column }
  );

  /// <summary>Remembers the place an EMPTY hover answer belongs to, so a resting
  /// pointer neither repeats the note nor asks again on every tick.</summary>
  /// <remarks>Forgotten by Clear (the pointer moved) and by a changed index
  /// generation (an index job finished). Main thread only; pure.</remarks>
  TDLEmptyMemo = record
  private
    FSet       : Boolean;
    FFile      : string ;
    FRow       : Integer;
    FStart     : Integer;
    FEnd       : Integer;
    FGeneration: Integer;
  public
    /// <summary>Stores the place of an empty answer.</summary>
    /// <param name="AFile">File of the token.</param>
    /// <param name="ARow0">0-based row.</param>
    /// <param name="AToken">The token; its column span is the place.</param>
    /// <param name="AGeneration">Index generation the answer was made from.</param>
    procedure Remember(const AFile: string; ARow0: Integer; const AToken: TDLToken; AGeneration: Integer);
    /// <summary>Forgets the place.</summary>
    procedure Clear;
    /// <summary>True when the position is on the remembered token and the index
    /// has not changed since.</summary>
    /// <param name="AFile">File under the pointer.</param>
    /// <param name="ARow0">0-based row under the pointer.</param>
    /// <param name="ACol0">0-based column under the pointer.</param>
    /// <param name="AGeneration">Index generation now.</param>
    /// <returns>False once the pointer or the index moved on.</returns>
    function Holds(const AFile: string; ARow0, ACol0, AGeneration: Integer): Boolean;
  end;

  /// <summary>Pixel layout of the strip's one-line row.</summary>
  /// <remarks>A width of 0 means "not shown".</remarks>
  TDLStripLayout = record
    NoteLeft     : Integer;
    NoteWidth    : Integer;
    ProgressLeft : Integer;
    ProgressWidth: Integer;
    DepthLeft    : Integer;
    DepthWidth   : Integer;
    BarLeft      : Integer;
    BarWidth     : Integer;
    CancelLeft   : Integer;
    CancelWidth  : Integer;
  end;

  /// <summary>The running job as the strip shows it.</summary>
  TDLStripJob = record
    Running: Boolean; { a job runs }
    IsIndex: Boolean; { it is an index job (jkReindex) }
    Title  : string ;
    Percent: Integer; { -1 = unknown }
    Phase  : string ;
    Beat   : string ; { the engine's own heartbeat text; '' = none }
  end;

/// <summary>The token under a 0-based position of a Pascal source.</summary>
/// <param name="ASource">The whole buffer text (multi-line comments are lexed from the top).</param>
/// <param name="ARow0">0-based row; past the last row is htkBlank.</param>
/// <param name="ACol0">0-based character column; past the end of the line is htkBlank.</param>
/// <returns>The token; in a comment, string or compiler directive the WORD under the position.</returns>
/// <remarks>Pure; never raises. White space is htkBlank wherever it lies.</remarks>
function DLTokenInText(const ASource: string; ARow0, ACol0: Integer): TDLToken;

/// <summary>DLTokenInText for a CARET, which may stand just after a name.</summary>
/// <param name="ASource">The whole buffer text.</param>
/// <param name="ARow0">0-based row.</param>
/// <param name="ACol0">0-based column of the caret.</param>
/// <returns>The token at the column; when that is no word and the character before is part of a word, that word.</returns>
function DLCaretTokenInText(const ASource: string; ARow0, ACol0: Integer): TDLToken;

/// <summary>The note after the engine answered with nothing.</summary>
/// <param name="AToken">What is under the pointer / caret.</param>
/// <returns>'X' is not indexed for an identifier; 'X' (kind) for other tokens; the SPACE text for a blank.</returns>
function DLEmptyAnswerNote(const AToken: TDLToken): string;

/// <summary>The note while a hover question is on its way.</summary>
/// <param name="AToken">The token the question is about.</param>
/// <returns>'drag-lint: hover X...'; the SPACE text for a blank.</returns>
function DLHoverAnnounceNote(const AToken: TDLToken): string;

/// <summary>Short name of a token kind, for telemetry.</summary>
/// <param name="AKind">The kind.</param>
/// <returns>blank, ident, keyword, directive, number, operator, comment, string or compdir.</returns>
function DLTokenKindName(AKind: TDLTokenKind): string;

/// <summary>Maps a client X to a 0-based VISUAL text column.</summary>
/// <param name="AClientX">Pointer X in the editor control's client area.</param>
/// <param name="ACodeLeft">Client X where the first visible column begins.</param>
/// <param name="ACharWidth">Pixel width of one cell.</param>
/// <param name="ALeftColumn1">1-based first visible column (horizontal scroll).</param>
/// <param name="ACol0">Receives the column; -1 unless hcvText.</param>
/// <returns>hcvNoGrid when ACharWidth or ALeftColumn1 is not positive, hcvGutter left of the code.</returns>
function DLColumnAt(AClientX, ACodeLeft, ACharWidth, ALeftColumn1: Integer; out ACol0: Integer): TDLCellVerdict;

/// <summary>The strip's two texts: the note and, next to it, the running job.</summary>
/// <param name="AJob">The running job.</param>
/// <param name="ANote">The transient note; '' = none.</param>
/// <param name="AIdle">The text of an idle strip without a note.</param>
/// <param name="ALeft">Receives the left text ('' = none).</param>
/// <param name="AProgress">Receives the progress text ('' when no job runs).</param>
/// <remarks>With a note an index job reads 'reindexing... 42% phase'; without one, and for
/// every other job, its title, percent and phase as before. The progress never yields to the note.</remarks>
procedure DLStripTexts(const AJob: TDLStripJob; const ANote, AIdle: string; out ALeft, AProgress: string);

/// <summary>Lays the strip's row out; the note is ellipsised first.</summary>
/// <param name="AWidth">Strip width.</param>
/// <param name="ANoteTextW">Pixel width of the note text; 0 = none.</param>
/// <param name="AProgressTextW">Pixel width of the progress text; 0 = no job.</param>
/// <param name="AHasDepth">The 'N queued' label has text.</param>
/// <returns>The layout. Space is taken from the note, then the bar, then the depth
/// label, before the progress text loses a pixel.</returns>
function DLStripLayout(AWidth, ANoteTextW, AProgressTextW: Integer; AHasDepth: Boolean): TDLStripLayout;

implementation

uses
  System.SysUtils
  , System.Math
  , System.Character
  ;

const
  { Reserved words, space-delimited for a whole-word Pos. }
  RESERVED_WORDS =
    ' and array as asm begin case class const constructor destructor dispinterface div do downto else end ' +
    'except exports file finalization finally for function goto if implementation in inherited initialization ' +
    'inline interface is label library mod nil not object of or packed procedure program property raise record ' +
    'repeat resourcestring set shl shr string then threadvar to try type unit until uses var while with xor ';
  { Directive words nobody names a symbol after. Read, Write, Name, Index,
    Message, Default ... are common names and stay identifiers. }
  DIRECTIVE_WORDS =
    ' abstract assembler cdecl delayed deprecated dispid dynamic experimental external far forward implements ' +
    'near nodefault noreturn overload override pascal private protected public published reintroduce ' +
    'safecall sealed stdcall stored strict unsafe varargs virtual winapi ';
  TWO_CHAR_OPERATORS = ' := <= >= <> .. ';
  NOTE_PREFIX = 'drag-lint: ';
  SPACE_NOTE  = NOTE_PREFIX + '<SPACE> is under the cursor';
  { Longer tokens are cut in the note; the strip is one line. }
  MAX_NOTE_TOKEN = 60;
  { A triple-quoted string opens with at least this many quotes. }
  MULTILINE_QUOTES = 3;
  { The strip's geometry, in pixels. }
  STRIP_INSET      = 6;
  STRIP_RIGHT_EDGE = 4;
  STRIP_GAP        = 8;
  STRIP_TEXT_GAP   = 10;
  STRIP_CANCEL_W   = 60;
  STRIP_BAR_W      = 150;
  STRIP_DEPTH_W    = 80;
  { Below this a label shows an ellipsis and no text: hide it. }
  STRIP_MIN_TEXT_W = 24;
  { Below this the progress bar is a smudge: hide it. }
  STRIP_MIN_BAR_W  = 20;

{ ---- the memo ---- }

procedure TDLEmptyMemo.Remember(const AFile: string; ARow0: Integer; const AToken: TDLToken; AGeneration: Integer);
begin
  FSet       := True;
  FFile      := AFile;
  FRow       := ARow0;
  FStart     := AToken.Start0;
  FEnd       := AToken.End0;
  FGeneration:= AGeneration;
end;

procedure TDLEmptyMemo.Clear;
begin
  FSet:= False;
end;

function TDLEmptyMemo.Holds(const AFile: string; ARow0, ACol0, AGeneration: Integer): Boolean;
begin
  Result:= FSet and (FGeneration = AGeneration) and SameText(FFile, AFile);
  if Result then Result:= (FRow = ARow0) and (ACol0 >= FStart) and (ACol0 < FEnd);
end;

{ ---- the token ---- }

function IsWordChar(AChar: Char): Boolean;
begin
  Result:= (AChar = '_') or AChar.IsLetterOrDigit;
end;

function IsBlankChar(AChar: Char): Boolean;
begin
  Result:= AChar <= ' ';
end;

function Listed(const AList, AWord: string): Boolean;
begin
  Result:= AList.Contains(' ' + LowerCase(AWord) + ' ');
end;

{ 1-based index of the first character of row ARow0 and the row's length; False
  when the source has no such row. }
function FindRow(const ASource: string; ARow0: Integer; out AStart, ALen: Integer): Boolean;
var
  Row: Integer;
  I  : Integer;
begin
  AStart:= 1;
  ALen  := 0;
  if ARow0 < 0 then Exit(False);
  Row:= 0;
  while Row < ARow0 do
  begin
    I:= Pos(#10, ASource, AStart);
    if I = 0 then Exit(False);
    AStart:= I + 1;
    Inc(Row);
  end;
  I:= AStart;
  while (I <= Length(ASource)) and (ASource[I] <> #10) do Inc(I);
  ALen:= I - AStart;
  if (ALen > 0) and (ASource[AStart + ALen - 1] = #13) then Dec(ALen);
  Result:= True;
end;

{ Index of the last character of a region that opens at I and is closed by AClose. }
function RegionEnd(const ASource, AClose: string; I, AOpenLen: Integer): Integer;
var
  P: Integer;
begin
  P:= Pos(AClose, ASource, I + AOpenLen);
  Result:= if P = 0 then Length(ASource) else P + Length(AClose) - 1;
end;

{ Index of the last character of the string literal that opens at I. }
function StringEnd(const ASource: string; I: Integer): Integer;
var
  Quotes: Integer;
  Eol   : Integer;
begin
  Quotes:= 0;
  while (I + Quotes <= Length(ASource)) and (ASource[I + Quotes] = '''') do Inc(Quotes);
  Eol:= I + Quotes;
  while (Eol <= Length(ASource)) and CharInSet(ASource[Eol], [' ', #9, #13]) do Inc(Eol);
  { Delphi 12 multi-line string: an odd run of 3 or more quotes ends its line;
    the same run closes it. }
  if (Quotes >= MULTILINE_QUOTES) and Odd(Quotes) and ((Eol > Length(ASource)) or (ASource[Eol] = #10)) then
    Exit(RegionEnd(ASource, StringOfChar('''', Quotes), I, Quotes));
  Result:= I + 1;
  while Result <= Length(ASource) do
  begin
    if CharInSet(ASource[Result], [#10, #13]) then Exit(Result - 1); { unterminated }
    if ASource[Result] = '''' then
    begin
      if (Result = Length(ASource)) or (ASource[Result + 1] <> '''') then Exit;
      Inc(Result); { a doubled quote is one character of the literal }
    end;
    Inc(Result);
  end;
  Result:= Length(ASource);
end;

{ Index of the last character of the number that opens at I. }
function NumberEnd(const ASource: string; I: Integer): Integer;
var
  Next: Char;
  Part: Boolean; { the next character belongs to the number }
begin
  Result:= I;
  while Result < Length(ASource) do
  begin
    Next:= ASource[Result + 1];
    { '1.5' continues, '1..5' does not; '1E+3' continues }
    case Next of
      '.'     : Part:= (Result + 2 <= Length(ASource)) and ASource[Result + 2].IsDigit;
      '+', '-': Part:= CharInSet(ASource[Result], ['e', 'E']);
      else       Part:= IsWordChar(Next);
    end;
    if not Part then Exit;
    Inc(Result);
  end;
end;

{ Last index of the comment, compiler directive or string that opens at I; 0 when
  none does. }
function DelimitedEnd(const ASource: string; I: Integer; out AKind: TDLTokenKind): Integer;
var
  Two: string;
begin
  Two   := Copy(ASource, I, Length('(*'));
  Result:= 0;
  AKind := htkInComment;
  if ASource[I] = '{' then
  begin
    if Two = '{$' then AKind:= htkInCompilerDirective;
    Result:= RegionEnd(ASource, '}', I, Length('{'));
  end
  else if Two = '(*' then
  begin
    if Copy(ASource, I, Length('(*$')) = '(*$' then AKind:= htkInCompilerDirective;
    Result:= RegionEnd(ASource, '*)', I, Length('(*'));
  end
  else if Two = '//' then
  begin
    Result:= I;
    while (Result < Length(ASource)) and not CharInSet(ASource[Result + 1], [#10, #13]) do Inc(Result);
  end
  else if ASource[I] = '''' then
  begin
    AKind := htkInString;
    Result:= StringEnd(ASource, I);
  end;
end;

{ Last index of the word that opens at I. }
function WordEnd(const ASource: string; I: Integer): Integer;
begin
  Result:= I;
  while (Result < Length(ASource)) and IsWordChar(ASource[Result + 1]) do Inc(Result);
end;

function WordKind(const AWord: string): TDLTokenKind;
begin
  Result:= if Listed(RESERVED_WORDS, AWord) then htkKeyword
           else if Listed(DIRECTIVE_WORDS, AWord) then htkDirective
           else htkIdent;
end;

{ Kind and last index of the lexical unit that opens at I (not white space). }
function UnitAt(const ASource: string; I: Integer; out AKind: TDLTokenKind): Integer;
var
  C   : Char;
  Next: Char;
begin
  Result:= DelimitedEnd(ASource, I, AKind);
  if Result > 0 then Exit;
  C   := ASource[I];
  Next:= if I < Length(ASource) then ASource[I + 1] else #0;
  { '#13' and '#$0D' are character constants; '$FF' / '%101' are numbers }
  if (C = '#') and (Next.IsDigit or (Next = '$')) then
  begin
    AKind := htkInString;
    Result:= WordEnd(ASource, if Next = '$' then I + 1 else I);
  end
  else if CharInSet(C, ['$', '%']) and Next.IsLetterOrDigit then
  begin
    AKind := htkNumber;
    Result:= WordEnd(ASource, I);
  end
  else if C.IsDigit then
  begin
    AKind := htkNumber;
    Result:= NumberEnd(ASource, I);
  end
  else if IsWordChar(C) or ((C = '&') and IsWordChar(Next)) then
  begin
    Result:= WordEnd(ASource, I);
    AKind := WordKind(Copy(ASource, I, Result - I + 1));
  end
  else
  begin
    AKind := htkOperator;
    Result:= if Listed(TWO_CHAR_OPERATORS, string(C) + Next) then I + 1 else I;
  end;
end;

{ The span around AAt, inside [ALo..AHi], of characters of the same class (word /
  other non-blank). }
procedure WordSpan(const ASource: string; AAt, ALo, AHi: Integer; out AFrom, ATo: Integer);
var
  IsWord: Boolean;

  function Same(AIndex: Integer): Boolean;
  begin
    Result:= not IsBlankChar(ASource[AIndex]) and (IsWordChar(ASource[AIndex]) = IsWord);
  end;

begin
  IsWord:= IsWordChar(ASource[AAt]);
  AFrom := AAt;
  ATo   := AAt;
  while (AFrom > ALo) and Same(AFrom - 1) do Dec(AFrom);
  while (ATo < AHi) and Same(ATo + 1) do Inc(ATo);
end;

{ The white-space run of one row around AAt. }
function BlankToken(const ASource: string; AAt, ARowStart, ARowLen: Integer): TDLToken;
var
  First: Integer;
  Last : Integer;
begin
  First:= AAt;
  Last := AAt;
  while (First > ARowStart) and IsBlankChar(ASource[First - 1]) do Dec(First);
  while (Last < ARowStart + ARowLen - 1) and IsBlankChar(ASource[Last + 1]) do Inc(Last);
  Result       := Default(TDLToken);
  Result.Start0:= First - ARowStart;
  Result.End0  := Last - ARowStart + 1;
end;

function DLTokenInText(const ASource: string; ARow0, ACol0: Integer): TDLToken;
var
  RowStart: Integer;
  RowLen  : Integer;
  At      : Integer;
  First   : Integer;
  Last    : Integer;
  Kind    : TDLTokenKind;
begin
  Result     := Default(TDLToken);
  Result.End0:= MaxInt;
  if not FindRow(ASource, ARow0, RowStart, RowLen) or (ACol0 < 0) then Exit;
  if ACol0 >= RowLen then
  begin
    Result.Start0:= RowLen;
    Exit;
  end;
  At:= RowStart + ACol0;
  if IsBlankChar(ASource[At]) then Exit(BlankToken(ASource, At, RowStart, RowLen));
  First:= 1;
  Last := 0;
  Kind := htkOperator;
  while First <= At do
  begin
    if IsBlankChar(ASource[First]) then
    begin
      Inc(First);
      Continue;
    end;
    Last:= UnitAt(ASource, First, Kind);
    if Last >= At then Break;
    First:= Last + 1;
  end;
  { a #nn constant is one token; inside the delimited kinds the word is }
  if (Kind in [htkInComment, htkInString, htkInCompilerDirective]) and (ASource[First] <> '#') then
    WordSpan(ASource, At, Max(First, RowStart), Min(Last, RowStart + RowLen - 1), First, Last);
  Result.Kind  := Kind;
  Result.Text  := Copy(ASource, First, Last - First + 1);
  Result.Start0:= First - RowStart;
  Result.End0  := Last - RowStart + 1;
end;

function DLCaretTokenInText(const ASource: string; ARow0, ACol0: Integer): TDLToken;
var
  Before: TDLToken;
begin
  Result:= DLTokenInText(ASource, ARow0, ACol0);
  if (ACol0 <= 0) or (Result.Kind not in [htkBlank, htkOperator]) then Exit;
  Before:= DLTokenInText(ASource, ARow0, ACol0 - 1);
  if (Before.Text <> '') and IsWordChar(Before.Text[Length(Before.Text)]) then Result:= Before;
end;

{ ---- the note ---- }

function ShortToken(const AToken: TDLToken): string;
begin
  Result:= if Length(AToken.Text) > MAX_NOTE_TOKEN then Copy(AToken.Text, 1, MAX_NOTE_TOKEN) + '...' else AToken.Text;
end;

function DLEmptyAnswerNote(const AToken: TDLToken): string;
const
  KIND_TEXT: array[TDLTokenKind] of string = ('', ' is not indexed', ' (keyword)', ' (directive)', ' (number)',
    ' (operator)', ' (in a comment)', ' (in a string)', ' (in a compiler directive)');
begin
  if AToken.Kind = htkBlank then Exit(SPACE_NOTE);
  Result:= NOTE_PREFIX + '''' + ShortToken(AToken) + '''' + KIND_TEXT[AToken.Kind];
end;

function DLHoverAnnounceNote(const AToken: TDLToken): string;
begin
  Result:= if AToken.Kind = htkBlank then SPACE_NOTE else NOTE_PREFIX + 'hover ' + ShortToken(AToken) + '...';
end;

function DLTokenKindName(AKind: TDLTokenKind): string;
const
  NAMES: array[TDLTokenKind] of string = ('blank', 'ident', 'keyword', 'directive', 'number', 'operator', 'comment',
    'string', 'compdir');
begin
  Result:= NAMES[AKind];
end;

{ ---- the pointer ---- }

function DLColumnAt(AClientX, ACodeLeft, ACharWidth, ALeftColumn1: Integer; out ACol0: Integer): TDLCellVerdict;
begin
  ACol0:= -1;
  if (ACharWidth <= 0) or (ALeftColumn1 <= 0) then Exit(hcvNoGrid);
  if AClientX < ACodeLeft then Exit(hcvGutter);
  ACol0 := (AClientX - ACodeLeft) div ACharWidth + ALeftColumn1 - 1;
  Result:= hcvText;
end;

{ ---- the strip ---- }

procedure DLStripTexts(const AJob: TDLStripJob; const ANote, AIdle: string; out ALeft, AProgress: string);
var
  Pct: string;
begin
  AProgress:= '';
  if not AJob.Running then
  begin
    ALeft:= if ANote <> '' then ANote else AIdle;
    Exit;
  end;
  ALeft:= ANote;
  Pct  := if AJob.Percent >= 0 then IntToStr(AJob.Percent) + '%' else '';
  if AJob.IsIndex and (ANote <> '') then
  begin
    AProgress:= 'reindexing...';
    if Pct <> '' then AProgress:= AProgress + ' ' + Pct + (if AJob.Phase <> '' then ' ' + AJob.Phase else '')
    else if AJob.Beat <> '' then AProgress:= AProgress + ' [' + AJob.Beat + ']';
    Exit;
  end;
  AProgress:= AJob.Title + '  ' +
    (if Pct <> '' then Pct + (if AJob.Phase <> '' then '  ' + AJob.Phase else '')
     else if AJob.Beat <> '' then '[' + AJob.Beat + ']'
     else '...');
end;

function DLStripLayout(AWidth, ANoteTextW, AProgressTextW: Integer; AHasDepth: Boolean): TDLStripLayout;
var
  BarW  : Integer;
  DepthW: Integer;
  Room  : Integer;

  { Pixels left for the two texts with the bar and depth label as they stand;
    negative when those alone do not fit. }
  function TextRoom: Integer;
  begin
    Result:= Room - (if BarW > 0 then BarW + STRIP_GAP else 0) - (if DepthW > 0 then DepthW + STRIP_GAP else 0);
  end;

begin
  Result:= Default(TDLStripLayout);
  Result.CancelWidth:= STRIP_CANCEL_W;
  Result.CancelLeft := AWidth - STRIP_RIGHT_EDGE - STRIP_CANCEL_W;
  Room  := Result.CancelLeft - STRIP_GAP - STRIP_INSET;
  BarW  := if AProgressTextW > 0 then STRIP_BAR_W else 0;
  DepthW:= if AHasDepth then STRIP_DEPTH_W else 0;
  if AProgressTextW > TextRoom then
  begin
    BarW:= BarW - (AProgressTextW - TextRoom);
    if BarW < STRIP_MIN_BAR_W then BarW:= 0;
    if AProgressTextW > TextRoom then DepthW:= 0;
  end;

  Result.ProgressWidth:= Max(0, Min(AProgressTextW, TextRoom));
  Result.NoteWidth    := Min(ANoteTextW, TextRoom - (if AProgressTextW > 0 then Result.ProgressWidth + STRIP_TEXT_GAP else 0));
  if (Result.NoteWidth < ANoteTextW) and (Result.NoteWidth < STRIP_MIN_TEXT_W) then Result.NoteWidth:= 0;
  Result.NoteLeft     := STRIP_INSET;
  Result.ProgressLeft := STRIP_INSET + (if Result.NoteWidth > 0 then Result.NoteWidth + STRIP_TEXT_GAP else 0);

  Result.BarWidth  := BarW;
  Result.BarLeft   := Result.CancelLeft - STRIP_GAP - BarW;
  Result.DepthWidth:= DepthW;
  Result.DepthLeft := (if BarW > 0 then Result.BarLeft else Result.CancelLeft) - STRIP_GAP - DepthW;
end;

end.
