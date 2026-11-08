unit DRagLint.Parser.Markdown;

(* E-PARITY-GRAPHIFY (wave 147): Markdown documents as TEXT NODES.

   Implements IParser for .md files. Emits no symbols and no references -- a
   Markdown file never takes part in name resolution. What it emits is one
   string_literals row per block, source = 'md':

     kind 'md-heading'  an ATX (# .. ######) or setext (=== / ---) heading
     kind 'md-text'     a paragraph (its lines joined by one space) or one
                        list item

   owner_name is the text of the nearest heading above the block ('' before
   the first heading), so a hit names the section it sits in. Fenced code
   (``` / ~~~), a YAML front-matter block that opens on line 1, and HTML
   comments are NOT text nodes: they are code or markup, not prose.

   The link to code is made by NAME, at query time, by whoever reads the rows
   (graph --format json|html: a `backticked` identifier that names an indexed
   symbol becomes a text edge). Nothing is resolved here. *)

interface

uses
  System.SysUtils
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Markdown text-node extractor: one md-heading / md-text string
  /// literal per heading, paragraph or list item of a .md file.</summary>
  /// <remarks>
  /// Line-based, not a CommonMark implementation: indented code blocks, HTML
  /// blocks and nested list structure are read as plain text. Stateless and
  /// thread-safe: every Parse call owns its own state.
  /// </remarks>
  TMarkdownParser = class(TInterfacedObject, IParser)
    public
      /// <summary>The files.language value of a Markdown file.</summary>
      /// <returns>'markdown'.</returns>
      function LanguageName: string                                               ;
      /// <summary>The extensions this parser claims.</summary>
      /// <returns>['.md'].</returns>
      /// <remarks>A directory walk does NOT admit .md even so (see
      /// TIndexer.WalkAndIndex); a project index admits the .md files beside
      /// its project file (ExpandProjectScope).</remarks>
      function FileExtensions: TArray<string>                                     ;
      /// <summary>Splits a Markdown document into text nodes.</summary>
      /// <param name="ASource">The file bytes, UTF-8 (a BOM is skipped). Must not be
      /// pre-processed: a {$IFDEF} in prose is text.</param>
      /// <param name="AFilePath">Unused; part of the IParser contract.</param>
      /// <returns>A result whose Literals hold the nodes in document order
      /// (source 'md', 1-based lines and columns); Symbols and References are
      /// empty.</returns>
      function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

implementation

uses
  System.StrUtils
  , System.Math
  , System.Generics.Collections
  , DRagLint.Core.Model
  ;

const
  { A text node longer than this is cut: a node is a search hit, not a copy. }
  MAX_NODE_CHARS = 4000;
  { CommonMark: up to three spaces of indent still open a heading or a fence. }
  MAX_BLOCK_INDENT = 3;
  { Shortest code fence: ``` or ~~~. }
  MIN_FENCE_LEN = 3;
  { Deepest ATX heading: ######. }
  MAX_ATX_LEVEL = 6;

type
  TMdState = class
    Literals : TList<TStringLiteral>;
    Heading  : string               ;
    ParaText : TStringBuilder       ;
    ParaLine : Integer              ;
    ParaCol  : Integer              ;
    ParaEndL : Integer              ;
    ParaEndC : Integer              ;
    ParaLines: Integer              ;
    FenceChar: Char                 ; { #0 = not inside a fence }
    FenceLen : Integer              ;
    InFront  : Boolean              ; { inside a YAML front-matter block }
    InComment: Boolean              ; { inside a multi-line HTML comment }
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AKind, AText: string; ALine, ACol, AEndLine, AEndCol: Integer);
    procedure Append(const AText: string; ALine, ACol, AEndCol: Integer);
    procedure Flush;
    function SkipLine(const ABody: string; AIndent, ALineNo: Integer): Boolean;
    function TryHeading(const ABody: string; AIndent, ALineNo, AEndCol: Integer): Boolean;
  end;

constructor TMdState.Create;
begin
  inherited Create;
  Literals:= TList<TStringLiteral>.Create;
  ParaText:= TStringBuilder.Create;
end;

destructor TMdState.Destroy;
begin
  ParaText.Free;
  Literals.Free;
  inherited Destroy;
end;

{ Collapses every run of whitespace to one space and trims; caps the length. }
function NormaliseText(const AText: string): string;
var
  Sb   : TStringBuilder;
  Ch   : Char          ;
  Space: Boolean       ;
begin
  Sb:= TStringBuilder.Create;
  try
    Space:= False;
    for Ch in AText do
      if Ch <= ' ' then Space:= Sb.Length > 0
      else
      begin
        if Space then Sb.Append(' ');
        Space:= False;
        Sb.Append(Ch);
      end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
  if Length(Result) > MAX_NODE_CHARS then Result:= Copy(Result, 1, MAX_NODE_CHARS);
end;

procedure TMdState.Add(const AKind, AText: string; ALine, ACol, AEndLine, AEndCol: Integer);
var
  Lit: TStringLiteral;
begin
  Lit:= Default(TStringLiteral);
  Lit.Text:= NormaliseText(AText);
  if Lit.Text = '' then Exit;
  Lit.Source   := 'md';
  Lit.Kind     := AKind;
  Lit.OwnerName:= Heading;
  Lit.StartLine:= ALine;
  Lit.StartCol := ACol;
  Lit.EndLine  := AEndLine;
  Lit.EndCol   := AEndCol;
  Literals.Add(Lit);
end;

procedure TMdState.Append(const AText: string; ALine, ACol, AEndCol: Integer);
begin
  if ParaLines = 0 then
  begin
    ParaLine:= ALine;
    ParaCol := ACol;
  end
  else ParaText.Append(' ');
  ParaText.Append(AText);
  ParaEndL:= ALine;
  ParaEndC:= AEndCol;
  Inc(ParaLines);
end;

procedure TMdState.Flush;
begin
  if ParaLines > 0 then Add('md-text', ParaText.ToString, ParaLine, ParaCol, ParaEndL, ParaEndC);
  ParaText.Clear;
  ParaLines:= 0;
end;

{ Number of leading spaces (a tab counts as four, CommonMark's tab stop). }
function IndentOf(const ALine: string): Integer;
const
  TAB_WIDTH = 4;
var
  Ch: Char;
begin
  Result:= 0;
  for Ch in ALine do
    if Ch = ' ' then Inc(Result)
    else if Ch = #9 then Inc(Result, TAB_WIDTH)
    else Break;
end;

{ Length of the run of AChar at the start of AText. }
function RunOf(const AText: string; AChar: Char): Integer;
begin
  Result:= 0;
  while (Result < Length(AText)) and (AText[Result + 1] = AChar) do Inc(Result);
end;

{ True when AText is a list-item marker followed by a space; AContentAt is the
  1-based index of the item's first content character. }
function IsListItem(const AText: string; out AContentAt: Integer): Boolean;
var
  I: Integer;
begin
  Result:= False;
  AContentAt:= 0;
  if AText = '' then Exit;
  if CharInSet(AText[1], ['-', '*', '+']) then I:= 2
  else
  begin
    I:= 1;
    while (I <= Length(AText)) and CharInSet(AText[I], ['0'..'9']) do Inc(I);
    if (I = 1) or (I > Length(AText)) or not CharInSet(AText[I], ['.', ')']) then Exit;
    Inc(I);
  end;
  if (I <= Length(AText)) and not CharInSet(AText[I], [' ', #9]) then Exit;
  while (I <= Length(AText)) and CharInSet(AText[I], [' ', #9]) do Inc(I);
  AContentAt:= I;
  Result:= True;
end;

{ ATX heading text: strips the opening #s and an optional closing #-run. }
function AtxText(const AText: string; ALevel: Integer): string;
var
  Tail: Integer;
begin
  Result:= Trim(Copy(AText, ALevel + 1, MaxInt));
  Tail:= Length(Result);
  while (Tail > 0) and (Result[Tail] = '#') do Dec(Tail);
  if (Tail = 0) or (Result[Tail] = ' ') then Result:= Trim(Copy(Result, 1, Tail));
end;

function TMarkdownParser.LanguageName: string;
begin
  Result:= 'markdown';
end;

function TMarkdownParser.FileExtensions: TArray<string>;
begin
  Result:= ['.md'];
end;

{ Front matter, fenced code and HTML comments: lines that are never prose.
  True when the line belongs to one of them (or opens one), so the caller
  skips it. }
function TMdState.SkipLine(const ABody: string; AIndent, ALineNo: Integer): Boolean;
begin
  Result:= True;
  if InFront then
  begin
    if (ALineNo > 1) and ((ABody = '---') or (ABody = '...')) then InFront:= False;
    Exit;
  end;
  if FenceChar <> #0 then
  begin
    if (AIndent <= MAX_BLOCK_INDENT) and (RunOf(ABody, FenceChar) >= FenceLen)
      and (Trim(Copy(ABody, RunOf(ABody, FenceChar) + 1, MaxInt)) = '') then FenceChar:= #0;
    Exit;
  end;
  if InComment then
  begin
    if ContainsStr(ABody, '-->') then InComment:= False;
    Exit;
  end;
  if StartsStr('<!--', ABody) then
  begin
    Flush;
    InComment:= not ContainsStr(Copy(ABody, Length('<!--') + 1, MaxInt), '-->');
    Exit;
  end;
  if (AIndent <= MAX_BLOCK_INDENT) and ((RunOf(ABody, '`') >= MIN_FENCE_LEN) or (RunOf(ABody, '~') >= MIN_FENCE_LEN)) then
  begin
    Flush;
    FenceChar:= ABody[1];
    FenceLen := RunOf(ABody, FenceChar);
    Exit;
  end;
  Result:= False;
end;

{ ATX heading, or a setext underline: True when the line was consumed. A setext
  underline turns a ONE-line open paragraph into a heading; any other ===/---
  line is a thematic break and just closes the block. }
function TMdState.TryHeading(const ABody: string; AIndent, ALineNo, AEndCol: Integer): Boolean;
var
  Level: Integer;
begin
  Result:= False;
  if AIndent > MAX_BLOCK_INDENT then Exit;
  Level:= RunOf(ABody, '#');
  if InRange(Level, 1, MAX_ATX_LEVEL) and ((Length(ABody) = Level) or CharInSet(ABody[Level + 1], [' ', #9])) then
  begin
    Flush;
    Heading:= NormaliseText(AtxText(ABody, Level));
    Add('md-heading', Heading, ALineNo, AIndent + 1, ALineNo, AEndCol);
    Exit(True);
  end;
  if (RunOf(ABody, '=') <> Length(ABody)) and (RunOf(ABody, '-') <> Length(ABody)) then Exit;
  if ParaLines = 1 then
  begin
    Heading:= NormaliseText(ParaText.ToString);
    Add('md-heading', Heading, ParaLine, ParaCol, ALineNo, AEndCol);
    ParaText.Clear;
    ParaLines:= 0;
  end
  else Flush;
  Result:= True;
end;

function TMarkdownParser.Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
var
  State    : TMdState      ;
  Lines    : TArray<string>;
  Raw      : string        ;
  Line     : string        ;
  Body     : string        ;
  I        : Integer       ;
  Indent   : Integer       ;
  ContentAt: Integer       ;
begin
  Result:= Default(TParseResult);
  Raw:= TEncoding.UTF8.GetString(ASource);
  if (Raw <> '') and (Raw[1] = #$FEFF) then Delete(Raw, 1, 1);
  Lines:= Raw.Split([#10]);
  State:= TMdState.Create;
  try
    State.InFront:= (Length(Lines) > 0) and (Trim(Lines[0]) = '---');
    for I:= 0 to High(Lines) do
    begin
      Line:= Lines[I];
      if EndsStr(#13, Line) then SetLength(Line, Length(Line) - 1);
      Indent:= IndentOf(Line);
      Body:= Trim(Line);
      if State.SkipLine(Body, Indent, I + 1) then Continue;
      if (Body <> '') and State.TryHeading(Body, Indent, I + 1, Length(Line) + 1) then Continue;
      while StartsStr('>', Body) do Body:= TrimLeft(Copy(Body, 2, MaxInt)); { a quote is prose }
      if Body = '' then State.Flush
      else if IsListItem(Body, ContentAt) then
      begin
        State.Flush;
        State.Append(Copy(Body, ContentAt, MaxInt), I + 1, Indent + ContentAt, Length(Line) + 1);
      end
      else State.Append(Body, I + 1, Indent + 1, Length(Line) + 1);
    end;
    State.Flush;
    Result.Literals:= State.Literals.ToArray;
  finally
    State.Free;
  end;
end;

end.
