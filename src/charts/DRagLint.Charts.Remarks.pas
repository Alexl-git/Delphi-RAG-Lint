unit DRagLint.Charts.Remarks;

{ Locates and replaces the DocInsight '/// <remarks>' block that holds a drag-lint
  report (spec S1a-S1c). The block is found from ONE line the caller names; nothing
  else in the unit is scanned. A replace changes the bytes of that block and nothing
  else: encoding (UTF-8 with or without BOM, or ANSI), the file's line-end style and
  a missing final newline are all kept. No VCL, no engine dependency beyond the
  header parser. }

interface

uses
  DRagLint.Charts.ReportHeader;

type
  /// <summary>One '/// &lt;remarks&gt;' ... '/// &lt;/remarks&gt;' block of a unit.</summary>
  TRemarksBlock = record
    /// <summary>First line of the block (the '&lt;remarks&gt;' line), 1-based.</summary>
    StartLine: Integer;
    /// <summary>Last line of the block (the '&lt;/remarks&gt;' line), 1-based, inclusive.</summary>
    EndLine  : Integer;
    /// <summary>The leading whitespace of the '&lt;remarks&gt;' line.</summary>
    Indent   : string;
    /// <summary>The raw physical lines StartLine..EndLine, line ends removed.</summary>
    Lines    : TArray<string>;
  end;

/// <summary>Finds the remarks block that contains one line.</summary>
/// <param name="pLines">The unit's lines, line ends removed.</param>
/// <param name="pLine">1-based line the caller named (the caret).</param>
/// <param name="pBlock">The block; Default(TRemarksBlock) when the result is False.</param>
/// <param name="pWhyNot">'line N is not inside a /// &lt;remarks&gt; block' when the
/// result is False, else ''.</param>
/// <returns>True when pLine lies between a '/// &lt;remarks&gt;' line and its
/// '/// &lt;/remarks&gt;' line.</returns>
/// <remarks>Walks up from pLine over '///' lines to '/// &lt;remarks&gt;' and down to
/// '/// &lt;/remarks&gt;'; meeting the other tag first, or a line that is not a '///'
/// line, means pLine is outside every block. Only the caret's block is returned, so a
/// unit with two blocks never mixes them. Pure; thread-safe.</remarks>
function FindRemarksBlockAt(const pLines: TArray<string>; pLine: Integer;
  out pBlock: TRemarksBlock; out pWhyNot: string): Boolean;

/// <summary>Whether a remarks block holds a drag-lint report (S1b).</summary>
/// <param name="pBlock">A block from FindRemarksBlockAt.</param>
/// <param name="pHeader">The parsed header; Default when the result is False.</param>
/// <returns>True when ParseReportHeader accepts the block's lines (the header sentence
/// follows the '&lt;remarks&gt;' line).</returns>
/// <remarks>A UTF-8 BOM character left on the first line is dropped before parsing
/// (ParseReportHeader does not strip one). Pure.</remarks>
function RemarksBlockIsReport(const pBlock: TRemarksBlock; out pHeader: TReportHeader): Boolean;

/// <summary>Replaces exactly one remarks block in a file with a new block.</summary>
/// <param name="pPath">The unit's path.</param>
/// <param name="pBlock">The block to replace, as found in the CURRENT file content.</param>
/// <param name="pNewDocInsightBlock">The new block, '/// ...' lines without indent
/// (what FormatReportAsDocInsight makes); CRLF, LF or CR separated; a trailing line end
/// is ignored.</param>
/// <param name="pWhyNot">The reason when the result is False, else ''.</param>
/// <returns>True when the file was rewritten.</returns>
/// <remarks>Keeps every byte outside the block. Encoding: a UTF-8 BOM is kept; a file
/// with no BOM that is valid UTF-8 and has high bytes stays UTF-8 without BOM; anything
/// else is ANSI. Line ends: the file's own (the first line end found; CRLF when it has
/// none); the block's last line keeps whatever terminator it had, so a block at the end
/// of a file with no final newline gets none. Every new line gets pBlock.Indent. Refuses
/// (file untouched) when the file cannot be read, the lines StartLine..EndLine no longer
/// equal pBlock.Lines, or the write fails. Not thread-safe per file.</remarks>
function ReplaceRemarksBlockInFile(const pPath: string; const pBlock: TRemarksBlock;
  const pNewDocInsightBlock: string; out pWhyNot: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils;

const
  DOC_PREFIX = '///';
  TAG_OPEN = '/// <remarks>';
  TAG_CLOSE = '/// </remarks>';
  BOM_CHAR = #$FEFF;
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);
  ASCII_LIMIT = $7F;
  FIRST_LINE = 1;
  MISSING = -1;

type
  TFileEncoding = (feAnsi, feUtf8, feUtf8Bom);

  /// <summary>Where one physical line sits in the decoded text.</summary>
  TLineSpan = record
    /// <summary>Offset (1-based) of the first character.</summary>
    Start: Integer;
    /// <summary>Length without the terminator.</summary>
    Len  : Integer;
    /// <summary>Length of the terminator (0, 1 or 2).</summary>
    TermLen: Integer;
  end;

function IsDocLine(const pLine: string): Boolean;
begin
  Result:= pLine.TrimLeft.StartsWith(DOC_PREFIX);
end;

function IsTag(const pLine, pTag: string): Boolean;
begin
  Result:= pLine.Trim = pTag;
end;

function LeadingWhitespace(const pLine: string): string;
begin
  var N:= 0;
  while (N < Length(pLine)) and ((pLine[N + 1] = ' ') or (pLine[N + 1] = #9)) do
    Inc(N);
  Result:= Copy(pLine, 1, N);
end;

function FindRemarksBlockAt(const pLines: TArray<string>; pLine: Integer;
  out pBlock: TRemarksBlock; out pWhyNot: string): Boolean;
begin
  pBlock:= Default(TRemarksBlock);
  pWhyNot:= Format('line %d is not inside a /// <remarks> block', [pLine]);
  Result:= False;
  if (pLine < FIRST_LINE) or (pLine > Length(pLines)) or not IsDocLine(pLines[pLine - 1]) then
    Exit;
  var First:= pLine;
  while (First >= FIRST_LINE) and IsDocLine(pLines[First - 1]) and not IsTag(pLines[First - 1], TAG_OPEN) do
  begin
    // Meeting the closing tag above the caret means the caret is between two blocks.
    if (First < pLine) and IsTag(pLines[First - 1], TAG_CLOSE) then
      Exit;
    Dec(First);
  end;
  if (First < FIRST_LINE) or not IsTag(pLines[First - 1], TAG_OPEN) then
    Exit;
  var Last:= pLine;
  while (Last <= Length(pLines)) and IsDocLine(pLines[Last - 1]) and not IsTag(pLines[Last - 1], TAG_CLOSE) do
  begin
    if (Last > pLine) and IsTag(pLines[Last - 1], TAG_OPEN) then
      Exit;
    Inc(Last);
  end;
  if (Last > Length(pLines)) or not IsTag(pLines[Last - 1], TAG_CLOSE) then
    Exit;
  pBlock.StartLine:= First;
  pBlock.EndLine:= Last;
  pBlock.Indent:= LeadingWhitespace(pLines[First - 1]);
  pBlock.Lines:= Copy(pLines, First - 1, Last - First + 1);
  pWhyNot:= '';
  Result:= True;
end;

function RemarksBlockIsReport(const pBlock: TRemarksBlock; out pHeader: TReportHeader): Boolean;
begin
  var Lines:= Copy(pBlock.Lines);
  if (Length(Lines) > 0) and Lines[0].StartsWith(BOM_CHAR) then
    Lines[0]:= Lines[0].Substring(1);
  Result:= ParseReportHeader(Lines, pHeader);
end;

{ Splits decoded text into line spans without losing the terminators (CRLF, LF or
  lone CR), so a replace can leave every other character exactly as it was. }
function SplitSpans(const pText: string): TArray<TLineSpan>;
begin
  var Spans: TArray<TLineSpan>:= [];
  var I:= 1;
  var N:= Length(pText);
  while I <= N do
  begin
    var S:= I;
    while (I <= N) and (pText[I] <> #13) and (pText[I] <> #10) do
      Inc(I);
    var Span: TLineSpan;
    Span.Start:= S;
    Span.Len:= I - S;
    Span.TermLen:= 0;
    if I <= N then
    begin
      Span.TermLen:= if (pText[I] = #13) and (I < N) and (pText[I + 1] = #10) then 2 else 1;
      Inc(I, Span.TermLen);
    end;
    Spans:= Spans + [Span];
  end;
  Result:= Spans;
end;

function FirstLineEnd(const pText: string): string;
begin
  Result:= #13#10;
  for var I:= 1 to Length(pText) do
    if pText[I] = #10 then
      Exit(#10)
    else if pText[I] = #13 then
      Exit(if (I < Length(pText)) and (pText[I + 1] = #10) then #13#10 else #13);
end;

function HasBom(const pBytes: TBytes): Boolean;
begin
  Result:= (Length(pBytes) >= Length(UTF8_BOM)) and (pBytes[0] = UTF8_BOM[0])
    and (pBytes[1] = UTF8_BOM[1]) and (pBytes[2] = UTF8_BOM[2]);
end;

function HasHighByte(const pBytes: TBytes): Boolean;
begin
  for var B in pBytes do
    if B > ASCII_LIMIT then
      Exit(True);
  Result:= False;
end;

{ A strict UTF-8 decoder: MB_ERR_INVALID_CHARS makes it raise on invalid bytes, where
  TEncoding.UTF8 would silently substitute U+FFFD. }
function BytesAreValidUtf8(const pBytes: TBytes): Boolean;
const
  MB_ERR_INVALID_CHARS = 8;
begin
  var Strict:= TUTF8Encoding.Create(TEncoding.UTF8.CodePage, MB_ERR_INVALID_CHARS, 0);
  try
    try
      Strict.GetString(pBytes);
      Result:= True;
    except
      on EEncodingError do Result:= False;
    end;
  finally
    Strict.Free;
  end;
end;

function ReplaceRemarksBlockInFile(const pPath: string; const pBlock: TRemarksBlock;
  const pNewDocInsightBlock: string; out pWhyNot: string): Boolean;
begin
  Result:= False;
  pWhyNot:= '';
  var Bytes: TBytes;
  try
    Bytes:= TFile.ReadAllBytes(pPath);
  except
    on E: Exception do
    begin
      pWhyNot:= 'cannot read ' + pPath + ': ' + E.Message;
      Exit;
    end;
  end;
  var Enc: TFileEncoding;
  var Skip:= 0;
  if HasBom(Bytes) then
  begin
    Enc:= feUtf8Bom;
    Skip:= Length(UTF8_BOM);
  end
  else if HasHighByte(Bytes) and BytesAreValidUtf8(Bytes) then
    Enc:= feUtf8
  else
    Enc:= feAnsi;
  var Encoder: TEncoding:= if Enc = feAnsi then TEncoding.ANSI else TEncoding.UTF8;
  var Text:= Encoder.GetString(Bytes, Skip, Length(Bytes) - Skip);

  var Spans:= SplitSpans(Text);
  if (pBlock.StartLine < FIRST_LINE) or (pBlock.EndLine > Length(Spans))
    or (pBlock.EndLine < pBlock.StartLine)
    or (Length(pBlock.Lines) <> pBlock.EndLine - pBlock.StartLine + 1) then
  begin
    pWhyNot:= Format('lines %d-%d are no longer in %s', [pBlock.StartLine, pBlock.EndLine, pPath]);
    Exit;
  end;
  for var I:= 0 to High(pBlock.Lines) do
  begin
    var Sp:= Spans[pBlock.StartLine - 1 + I];
    if Copy(Text, Sp.Start, Sp.Len) <> pBlock.Lines[I] then
    begin
      pWhyNot:= Format('the file changed: line %d no longer matches the block', [pBlock.StartLine + I]);
      Exit;
    end;
  end;

  var Eol:= FirstLineEnd(Text);
  var NewText:= StringReplace(pNewDocInsightBlock, #13#10, #10, [rfReplaceAll]);
  NewText:= StringReplace(NewText, #13, #10, [rfReplaceAll]);
  if NewText.EndsWith(#10) then
    NewText:= Copy(NewText, 1, Length(NewText) - 1);
  var NewLines:= NewText.Split([#10]);
  var Joined:= '';
  for var I:= 0 to High(NewLines) do
    Joined:= Joined + (if I > 0 then Eol else '') + pBlock.Indent + NewLines[I];

  // The replaced range ends before the last line's terminator, which stays as it was.
  var First:= Spans[pBlock.StartLine - 1];
  var Last:= Spans[pBlock.EndLine - 1];
  var Prefix:= Copy(Text, 1, First.Start - 1);
  var Suffix:= Copy(Text, Last.Start + Last.Len, MaxInt);
  var Body:= Encoder.GetBytes(Prefix + Joined + Suffix);
  var Output: TBytes;
  if Enc = feUtf8Bom then
  begin
    SetLength(Output, Length(UTF8_BOM) + Length(Body));
    Move(UTF8_BOM[0], Output[0], Length(UTF8_BOM));
    if Length(Body) > 0 then
      Move(Body[0], Output[Length(UTF8_BOM)], Length(Body));
  end
  else
    Output:= Body;
  try
    TFile.WriteAllBytes(pPath, Output);
  except
    on E: Exception do
    begin
      pWhyNot:= 'cannot write ' + pPath + ': ' + E.Message;
      Exit;
    end;
  end;
  Result:= True;
end;

end.
