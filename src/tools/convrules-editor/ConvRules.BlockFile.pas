unit ConvRules.BlockFile;

{ Pure block splitter for the curation form.

  A rule-book (.rules) or catalog (.castlib) file is split into an ORDERED list of
  blocks, each holding its RAW TEXT verbatim -- header line, body, comments,
  blank lines, unknown directives and the file's own line terminators. Every
  curation operation moves raw text; nothing is ever re-emitted from a parsed
  model, because:

    - sample.rules asserts that '//' and ';' hand comments survive round-trip;
    - LoadCastLibText deliberately tolerates unknown keys so newer files stay
      readable by older builds -- re-emitting would silently delete them.

  So the load-bearing guarantee of this unit is: JoinBlocks(SplitXxxBlocks(T)) = T,
  byte for byte, for any T.

  Pure + headless (no VCL, no file system, no process spawn) so it is unit-tested
  against inline fixtures and the real shipped files. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  /// <summary>One source line plus the exact terminator that followed it.</summary>
  /// <remarks>Eol is '' for a final line with no terminator, otherwise the bytes
  /// actually found (#13#10, #10 or #13). Text+Eol concatenated over all lines
  /// reproduces the source exactly -- this is why the unit does not use
  /// TStringList, whose Text property normalises terminators.</remarks>
  TRawLine = record
    Text: string;
    Eol : string;
  end;

  /// <summary>What a block is.</summary>
  TRuleBlockKind = (
    rbkPreamble,   // content before the first real block (file header comments)
    rbkConvert,    // .rules: '#convert From -> To [, unit ...]'
    rbkCast,       // .castlib: 'cast <Name> ... end'
    rbkEnum        // .castlib: 'enum <Name> ... end'
  );

  /// <summary>One block of a rule-book or catalog file, carrying its verbatim text.</summary>
  /// <remarks>RawText includes the header line and every terminator inside the
  /// block, so blocks concatenate back into the original file. StartLine/EndLine
  /// are 1-based line numbers in the source, for display only.</remarks>
  TRuleBlock = record
    Kind     : TRuleBlockKind;
    Header   : string;    // the header line verbatim (no terminator); '' for a preamble
    RawText  : string;    // the whole block including its header, verbatim
    StartLine: Integer;
    EndLine  : Integer;
  end;

  TRuleBlocks = TArray<TRuleBlock>;

/// <summary>PURE: split text into lines, keeping each line's exact terminator.</summary>
/// <param name="AText">Any text; '' yields an empty array.</param>
/// <returns>Lines in order; concatenating Text+Eol reproduces AText byte for byte.</returns>
function SplitRawLines(const AText: string): TArray<TRawLine>;

/// <summary>PURE: the first whitespace-delimited token of a line, '' when blank.</summary>
function FirstToken(const ALine: string): string;

/// <summary>PURE: the second whitespace-delimited token of a line, '' when absent.</summary>
function SecondToken(const ALine: string): string;

/// <summary>PURE: split a .rules text into blocks. A block starts at a line whose
/// first token is '#convert' and runs to the line before the next '#convert', or
/// to end of file. Anything before the first '#convert' is one rbkPreamble block.</summary>
function SplitRulesBlocks(const AText: string): TRuleBlocks;

/// <summary>PURE: split a .castlib text into blocks. A block starts at a line whose
/// first token is 'cast' or 'enum'. Content before the first block becomes an
/// rbkPreamble block; content between blocks (including the 'end' line and any
/// trailing blanks) attaches to the PRECEDING block, so nothing is orphaned.</summary>
function SplitCastLibBlocks(const AText: string): TRuleBlocks;

/// <summary>PURE: pick the grammar from APath's extension -- '.castlib' uses the
/// catalog grammar, anything else (.rules and reFind files) uses the DSL grammar.</summary>
function SplitBlocksFor(const APath, AText: string): TRuleBlocks;

/// <summary>PURE: what the curation grid shows for a block: the type pair for a
/// #convert, the bare NAME for a cast/enum, '(file header)' for a preamble.</summary>
function BlockLabel(const ABlock: TRuleBlock): string;

/// <summary>PURE: rejoin blocks in order. JoinBlocks(SplitRulesBlocks(T)) = T.</summary>
function JoinBlocks(const ABlocks: TRuleBlocks): string;

/// <summary>PURE: the line terminator this block uses (its first line's), or CRLF
/// when the block has none (a single unterminated line).</summary>
function BlockEol(const ABlock: TRuleBlock): string;

implementation

function SplitRawLines(const AText: string): TArray<TRawLine>;
var
  List : TList<TRawLine>;
  i, St: Integer;
  L    : TRawLine;
begin
  List := TList<TRawLine>.Create;
  try
    i := 1;
    St := 1;
    while i <= Length(AText) do
    begin
      if CharInSet(AText[i], [#13, #10]) then
      begin
        L.Text := Copy(AText, St, i - St);
        if (AText[i] = #13) and (i < Length(AText)) and (AText[i + 1] = #10) then
        begin
          L.Eol := #13#10;
          Inc(i, 2);
        end
        else
        begin
          L.Eol := AText[i];
          Inc(i);
        end;
        List.Add(L);
        St := i;
      end
      else
        Inc(i);
    end;
    if St <= Length(AText) then
    begin
      L.Text := Copy(AText, St, MaxInt);
      L.Eol  := '';
      List.Add(L);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FirstToken(const ALine: string): string;
var
  S: string;
  p: Integer;
begin
  S := TrimLeft(ALine);
  p := 1;
  while (p <= Length(S)) and (S[p] > ' ') do Inc(p);
  Result := Copy(S, 1, p - 1);
end;

function SecondToken(const ALine: string): string;
var
  S: string;
begin
  S := TrimLeft(ALine);
  S := TrimLeft(Copy(S, Length(FirstToken(S)) + 1, MaxInt));
  Result := FirstToken(S);
end;

type
  { Decides whether a line starts a new block, and of what kind. A plain function
    pointer (not "of object") so the two grammars stay unit-level and closure-free. }
  THeaderTest = function(const ALine: string; out AKind: TRuleBlockKind): Boolean;

function RulesHeaderTest(const ALine: string; out AKind: TRuleBlockKind): Boolean;
begin
  AKind := rbkConvert;
  Result := SameText(FirstToken(ALine), '#convert');
end;

function CastLibHeaderTest(const ALine: string; out AKind: TRuleBlockKind): Boolean;
var
  Tok: string;
begin
  Tok := FirstToken(ALine);
  if SameText(Tok, 'cast') then      begin AKind := rbkCast; Exit(True); end;
  if SameText(Tok, 'enum') then      begin AKind := rbkEnum; Exit(True); end;
  AKind := rbkPreamble;
  Result := False;
end;

{ The one splitting loop. Lines that do not start a block accumulate into the
  current block; before the first header they accumulate into a preamble block. }
function SplitOnHeaders(const AText: string; ATest: THeaderTest): TRuleBlocks;
var
  Lines : TArray<TRawLine>;
  Blocks: TList<TRuleBlock>;
  Cur   : TRuleBlock;
  Have  : Boolean;
  i     : Integer;
  Kind  : TRuleBlockKind;
begin
  Lines  := SplitRawLines(AText);
  Blocks := TList<TRuleBlock>.Create;
  try
    Have := False;
    Cur  := Default(TRuleBlock);
    for i := 0 to High(Lines) do
    begin
      if ATest(Lines[i].Text, Kind) then
      begin
        if Have then Blocks.Add(Cur);
        Cur := Default(TRuleBlock);
        Cur.Kind      := Kind;
        Cur.Header    := Lines[i].Text;
        Cur.StartLine := i + 1;
        Have := True;
      end
      else if not Have then
      begin
        Cur := Default(TRuleBlock);
        Cur.Kind      := rbkPreamble;
        Cur.Header    := '';
        Cur.StartLine := i + 1;
        Have := True;
      end;
      Cur.RawText := Cur.RawText + Lines[i].Text + Lines[i].Eol;
      Cur.EndLine := i + 1;
    end;
    if Have then Blocks.Add(Cur);
    Result := Blocks.ToArray;
  finally
    Blocks.Free;
  end;
end;

function SplitRulesBlocks(const AText: string): TRuleBlocks;
begin
  Result := SplitOnHeaders(AText, RulesHeaderTest);
end;

function SplitCastLibBlocks(const AText: string): TRuleBlocks;
begin
  Result := SplitOnHeaders(AText, CastLibHeaderTest);
end;

function SplitBlocksFor(const APath, AText: string): TRuleBlocks;
begin
  if SameText(ExtractFileExt(APath), '.castlib') then
    Result := SplitCastLibBlocks(AText)
  else
    Result := SplitRulesBlocks(AText);
end;

function BlockLabel(const ABlock: TRuleBlock): string;
begin
  case ABlock.Kind of
    rbkConvert:
      Result := Trim(Copy(TrimLeft(ABlock.Header), Length('#convert') + 1, MaxInt));
    rbkCast, rbkEnum:
      Result := SecondToken(ABlock.Header);
  else
    Result := '(file header)';
  end;
end;

function JoinBlocks(const ABlocks: TRuleBlocks): string;
var
  B: TRuleBlock;
begin
  Result := '';
  for B in ABlocks do
    Result := Result + B.RawText;
end;

function BlockEol(const ABlock: TRuleBlock): string;
var
  Lines: TArray<TRawLine>;
begin
  Lines := SplitRawLines(ABlock.RawText);
  if (Length(Lines) > 0) and (Lines[0].Eol <> '') then
    Result := Lines[0].Eol
  else
    Result := #13#10;
end;

end.
