/// <summary>The comment_facts producer (wave 151, lane W1): every comment of a
/// Pascal source file as TCommentFactRow rows, with its anchor.</summary>
/// <remarks>Spec: docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md.
/// The indexer (TIndexer.IndexFileBody) calls ExtractCommentFacts for every
/// parsed file and hands the rows to ISymbolStore.PutFileFacts. Directives
/// ({$..} / (*$..*)) are not comments and get no row. 151 builds the table
/// only: Parser.DocComments, Lint.ReviewMarker and Lint.Bookmarks keep their
/// own scanners; tests\autotest\run_comment_facts_parity.ps1 proves the table
/// carries the same `///` blocks, dl:ok markers and dl:bk anchors they compute.
/// Comment blanking (150 W2) is NO-GO: nothing here changes what is parsed.</remarks>
unit DRagLint.Index.CommentFacts;

interface

uses
  DRagLint.Core.Model;

/// <summary>True when ExtractCommentFacts produces rows for a file with this
/// path: a Pascal source (.pas, .dpr, .dpk, .inc, .pp, .lpr).</summary>
/// <param name="AFilePath">Full path or bare file name; only the extension is read.</param>
/// <returns>False for every other extension (.dfm, .sql, ...).</returns>
function IsCommentFactsFile(const AFilePath: string): Boolean;  // dl:ok unused-public-symbol@8666 -- public on purpose: the parity harness (tests\fixtures\comment-facts-151) and future table readers pick files by it

/// <summary>The comment rows of one file, in source order.</summary>
/// <param name="AFilePath">Full path of the file; IsCommentFactsFile decides by
/// its extension whether it has comment facts ([] otherwise).</param>
/// <param name="AText">The decoded text the DocInsight scanner sees
/// (IndexFileBody's SourceText); offsets are into this text.</param>
/// <param name="ASymbols">The file's parsed symbols (TParseResult.Symbols);
/// TCommentFactRow.AnchorSymbolIdx indexes this array (-1 = none). May be
/// empty: the rows and their kinds are lexical, only the anchors need it.</param>
/// <returns>One row per comment. Lexing honours string literals (a `//` or `{`
/// inside quotes is text; a single-quoted string ends at its line break; a
/// Delphi 12+ `'''` multi-line string runs to its closing quote run),
/// skips directives, and does not nest: the opener decides the terminator
/// (`(* { } *)` is ONE row). An unterminated comment runs to the end of the
/// text. A line comment ends before its CR / LF. Kind is `///` for three or
/// more slashes (as TDocCommentScanner reads them), else the opener.</returns>
/// <remarks>Anchors, decided after the lexing pass:
/// <para>`end-of-line` -- code precedes the comment on its line; the anchor is
/// the first symbol (lowest array index) declared on that line, else the
/// innermost routine whose implementation body holds the line, else none.</para>
/// <para>`next-declaration` -- own-line comment whose comment run (own-line
/// rows on touching lines) ends directly above a declaration line, inside the
/// DocRegionInGapWindow(.., DOC_ALLOW_GAP) window the doc attribution uses; a
/// declaration line is a symbol's StartLine or a routine's ImplStartLine. The
/// anchor is the first symbol (lowest index) starting on that line.</para>
/// <para>`statement` -- own-line comment inside a routine implementation
/// (after its header line, up to its end line); the anchor is the innermost
/// such routine (an addition to the spec, which names anchors only for
/// next-declaration / end-of-line rows: a dl:bk inside a body anchors to its
/// routine).</para>
/// <para>`block` -- any other own-line comment; no anchor.</para>
/// Line breaks: CRLF, a lone LF and a lone CR each end a line (the
/// TDocCommentScanner rule). Col is 1-based in UTF-8 bytes. Pure; thread-safe.</remarks>
function ExtractCommentFacts(const AFilePath, AText: string;
  const ASymbols: TArray<TSymbol>): TArray<TCommentFactRow>;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.StrUtils
  , System.Math
  ;

const
  ANCHOR_EOL   = 'end-of-line';
  ANCHOR_DECL  = 'next-declaration';
  ANCHOR_STMT  = 'statement';
  ANCHOR_BLOCK = 'block';
  KIND_LINE    = '//';
  KIND_DOC     = '///';
  KIND_BRACE   = '{';
  KIND_PAREN   = '(*';
  UTF8_PAIR_BYTES = 4; { a UTF-16 surrogate pair is one 4-byte UTF-8 sequence, counted on its high half }
  UTF8_BMP_BYTES  = 3; { any other code unit at or above U+0800 }
  COMMENT_FACT_EXTS: array[0..5] of string = ('.pas', '.dpr', '.dpk', '.inc', '.pp', '.lpr');
  MIN_ML_QUOTES = 3; { a Delphi 12+ multi-line string opens with an odd run of >= 3 quotes }

function IsCommentFactsFile(const AFilePath: string): Boolean;
var
  Ext: string;
begin
  Ext:= ExtractFileExt(AFilePath);
  Result:= MatchText(Ext, COMMENT_FACT_EXTS);
end;

{ UTF-8 byte length of one UTF-16 code unit: a surrogate pair is 4 bytes, all on its high half. }
function Utf8Len(AChar: Char): Integer;
begin
  case Ord(AChar) of
    0..$7F       : Result:= 1;
    $80..$7FF    : Result:= 2;
    $D800..$DBFF : Result:= UTF8_PAIR_BYTES;
    $DC00..$DFFF : Result:= 0;
  else
    Result:= UTF8_BMP_BYTES;
  end;
end;

type
  { One lexed comment before anchoring; offsets 1-based, Stop exclusive. }
  TRawComment = record
    Start      : Integer;
    Stop       : Integer;
    Kind       : string ;
    CodeBefore : Boolean;
  end;

{ The lexing pass: every comment of AText in source order, directives and strings skipped. }
function LexComments(const AText: string): TList<TRawComment>;
var
  N, I, Q, Run: Integer;
  LineStart   : Integer; { 1-based index of the first char of the current line }
  LastCode    : Integer; { 1-based index of the last code char seen; 0 = none }
  C           : TRawComment;

  function At(AIdx: Integer): Char;
  begin
    Result:= if AIdx <= N then AText[AIdx] else #0;
  end;

  { Advances I over a line break at I (CRLF counts once) and starts the next line. }
  procedure StepBreak;
  begin
    if (AText[I] = #13) and (At(I + 1) = #10) then Inc(I);
    Inc(I);
    LineStart:= I;
  end;

  { Moves I to AStop, keeping LineStart on the line I lands on. }
  procedure SkipTo(AStop: Integer);
  begin
    while I < AStop do
      if CharInSet(AText[I], [#13, #10]) then StepBreak else Inc(I);
  end;

  procedure Add(AStop: Integer; const AKind: string);
  begin
    C.Start     := I;
    C.Stop      := AStop;
    C.Kind      := AKind;
    C.CodeBefore:= LastCode >= LineStart;
    Result.Add(C);
    SkipTo(AStop);
  end;

  { 1-based index just past the first ATerm at or after AFrom; N + 1 when absent. }
  function PastTerm(AFrom: Integer; const ATerm: string): Integer;
  var
    P: Integer;
  begin
    P:= Pos(ATerm, AText, AFrom);
    Result:= if P = 0 then N + 1 else P + Length(ATerm);
  end;

  function RestOfLineBlank(AFrom: Integer): Boolean;
  var
    P: Integer;
  begin
    P:= AFrom;
    while (P <= N) and CharInSet(AText[P], [' ', #9]) do Inc(P);
    Result:= (P > N) or CharInSet(AText[P], [#13, #10]);
  end;

begin
  Result   := TList<TRawComment>.Create;
  N        := Length(AText);
  I        := 1;
  LineStart:= 1;
  LastCode := 0;
  while I <= N do
  begin
    case AText[I] of
      #13, #10: StepBreak;
      ' ', #9 : Inc(I);
      '/':
        if At(I + 1) = '/' then
        begin
          Q:= I + 2;
          while (Q <= N) and not CharInSet(AText[Q], [#13, #10]) do Inc(Q);
          Add(Q, if At(I + 2) = '/' then KIND_DOC else KIND_LINE);
        end
        else
        begin
          LastCode:= I;
          Inc(I);
        end;
      '{':
        if At(I + 1) = '$' then
        begin
          Q:= PastTerm(I + 1, '}');
          SkipTo(Q);
          LastCode:= I - 1;
        end
        else Add(PastTerm(I + 1, '}'), KIND_BRACE);
      '(':
        if At(I + 1) <> '*' then
        begin
          LastCode:= I;
          Inc(I);
        end
        else if At(I + 2) = '$' then
        begin
          Q:= PastTerm(I + 2, '*)');
          SkipTo(Q);
          LastCode:= I - 1;
        end
        else Add(PastTerm(I + 2, '*)'), KIND_PAREN);
      '''':
        begin
          Run:= 0;
          while At(I + Run) = '''' do Inc(Run);
          if (Run >= MIN_ML_QUOTES) and Odd(Run) and RestOfLineBlank(I + Run) then
            Q:= PastTerm(I + Run, StringOfChar('''', Run)) { multi-line string: to its closing run }
          else
          begin
            Q:= I + 1;
            while (Q <= N) and not CharInSet(AText[Q], [#13, #10]) do
              if AText[Q] <> '''' then Inc(Q)
              else if At(Q + 1) = '''' then Inc(Q, 2)
              else
              begin
                Inc(Q);
                Break;
              end;
          end;
          SkipTo(Q);
          LastCode:= I - 1;
        end;
    else
      LastCode:= I;
      Inc(I);
    end;
  end;
end;

{ Line starts (1-based char index of each line's first char); Result[0] is line 1. }
function LineStarts(const AText: string): TArray<Integer>;
var
  L: TList<Integer>;
  I: Integer;
begin
  L:= TList<Integer>.Create;
  try
    L.Add(1);
    I:= 1;
    while I <= Length(AText) do
    begin
      if (AText[I] = #13) and (I < Length(AText)) and (AText[I + 1] = #10) then Inc(I);
      if CharInSet(AText[I], [#13, #10]) then L.Add(I + 1);
      Inc(I);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ 1-based line of char index AIdx; AHint is a line at or before it (rows come in order). }
function LineOf(const AStarts: TArray<Integer>; AIdx: Integer; var AHint: Integer): Integer;
begin
  while (AHint < High(AStarts)) and (AStarts[AHint + 1] <= AIdx) do Inc(AHint);
  Result:= AHint + 1;
end;

function ExtractCommentFacts(const AFilePath, AText: string;
  const ASymbols: TArray<TSymbol>): TArray<TCommentFactRow>;
var
  Raw       : TList<TRawComment>;
  Starts    : TArray<Integer>;
  DeclAt    : TArray<Integer>; { per line (1-based): first symbol index declared there, -1 }
  BodyOf    : TArray<Integer>; { per line: innermost routine whose body holds it, -1 }
  Routines  : TList<Integer>;
  I, J, Hint: Integer;
  Lines     : Integer;
  RunFirst  : Integer;
  Target    : Integer;
  Row       : TCommentFactRow;

  procedure NoteDecl(ALine, AIdx: Integer);
  begin
    if InRange(ALine, 1, Lines) and ((DeclAt[ALine] < 0) or (AIdx < DeclAt[ALine])) then DeclAt[ALine]:= AIdx;
  end;

  { The first declaration line in the doc window below AEndLine; 0 = none. }
  function DeclBelow(AEndLine: Integer): Integer;
  var
    L: Integer;
  begin
    Result:= 0;
    for L:= AEndLine + 1 to AEndLine + 1 + DOC_ALLOW_GAP do
      if (L <= Lines) and (DeclAt[L] >= 0) and DocRegionInGapWindow(AEndLine, L, DOC_ALLOW_GAP) then Exit(L);
  end;

begin
  Result:= nil;
  if (AText = '') or not IsCommentFactsFile(AFilePath) then Exit;
  Raw:= LexComments(AText);
  try
    if Raw.Count = 0 then Exit;
    Starts:= LineStarts(AText);
    Lines := Length(Starts);
    SetLength(Result, Raw.Count);
    Hint:= 0;
    for I:= 0 to Raw.Count - 1 do
    begin
      Row:= Default(TCommentFactRow);
      Row.StartOffset:= Raw[I].Start - 1;
      Row.EndOffset  := Raw[I].Stop - 1;
      Row.Line       := LineOf(Starts, Raw[I].Start, Hint);
      Row.Col        := 1;
      for J:= Starts[Row.Line - 1] to Raw[I].Start - 1 do Inc(Row.Col, Utf8Len(AText[J]));
      J:= Hint;
      Row.EndLine    := LineOf(Starts, Raw[I].Stop - 1, J);
      Row.Kind       := Raw[I].Kind;
      Row.Text       := Copy(AText, Raw[I].Start, Raw[I].Stop - Raw[I].Start);
      Row.AnchorKind := if Raw[I].CodeBefore then ANCHOR_EOL else '';
      Row.AnchorSymbolIdx:= -1;
      Result[I]:= Row;
    end;

    { Anchors: per-line maps of declarations and routine bodies, built once. }
    SetLength(DeclAt, Lines + 1);
    SetLength(BodyOf, Lines + 1);
    for J:= 0 to Lines do
    begin
      DeclAt[J]:= -1;
      BodyOf[J]:= -1;
    end;
    Routines:= TList<Integer>.Create;
    try
      for J:= 0 to High(ASymbols) do
      begin
        NoteDecl(ASymbols[J].StartLine, J);
        if (ASymbols[J].ImplStartLine > 0) and (ASymbols[J].ImplEndLine > ASymbols[J].ImplStartLine) then
        begin
          NoteDecl(ASymbols[J].ImplStartLine, J);
          Routines.Add(J);
        end;
      end;
      { paint bodies outer-first (ascending ImplStartLine), so a nested routine overwrites its host }
      Routines.Sort(TComparer<Integer>.Construct(
        function(const A, B: Integer): Integer
        begin
          Result:= ASymbols[A].ImplStartLine - ASymbols[B].ImplStartLine;
          if Result = 0 then Result:= A - B;
        end));
      for Target in Routines do
        for J:= ASymbols[Target].ImplStartLine + 1 to ASymbols[Target].ImplEndLine do
          if J <= Lines then BodyOf[J]:= Target;
    finally
      Routines.Free;
    end;

    I:= 0;
    while I <= High(Result) do
    begin
      if Result[I].AnchorKind = ANCHOR_EOL then
      begin
        Target:= DeclAt[Result[I].Line];
        if Target < 0 then Target:= BodyOf[Result[I].Line];
        Result[I].AnchorSymbolIdx:= Target;
        Inc(I);
        Continue;
      end;
      { an own-line comment run: own-line rows, each starting on or right after the previous one's end line }
      RunFirst:= I;
      while (I < High(Result)) and (Result[I + 1].AnchorKind = '') and (Result[I + 1].Line <= Result[I].EndLine + 1) do Inc(I);
      Target:= DeclBelow(Result[I].EndLine);
      for J:= RunFirst to I do
        if Target > 0 then
        begin
          Result[J].AnchorKind     := ANCHOR_DECL;
          Result[J].AnchorSymbolIdx:= DeclAt[Target];
        end
        else if BodyOf[Result[J].Line] >= 0 then
        begin
          Result[J].AnchorKind     := ANCHOR_STMT;
          Result[J].AnchorSymbolIdx:= BodyOf[Result[J].Line];
        end
        else Result[J].AnchorKind:= ANCHOR_BLOCK;
      Inc(I);
    end;
  finally
    Raw.Free;
  end;
end;

end.
