unit DRagLint.Core.OutputEncoding;

{ The engine's stdout / stderr encoding (owner ruling 2026-10-26,
  docs\INBOX-engine-output-ansi-and-nonansi-input-lossy.md).

  Before this unit, Output and ErrOutput used the RTL default: the ANSI code
  page for a file or a pipe. A character outside it became `?`, and one inside
  it (e9 for U+00E9 on cp1252) reached a UTF-8 reader -- the LSP, which reads
  `lint --json` as UTF-8 -- as an invalid byte.

  Now both Text files are switched to CP_UTF8 at start-up, so the RTL hands
  this unit's write routine the exact UTF-8 of everything written, and the
  routine re-encodes the bytes for the selected mode:

    ascii (default)  7-bit ASCII; every non-ASCII UTF-16 code unit becomes
                     \uXXXX, lower-case hex (a non-BMP character is its
                     surrogate pair). Inside --json that IS the JSON escape, so
                     a JSON reader recovers the exact text. ASCII text passes
                     through byte for byte, so every existing reader of an
                     all-ASCII run sees the bytes it always saw.
    utf8             UTF-8, no BOM (the RTL's own write routine, untouched).
    utf16            UTF-16LE, no BOM.

  Writers that go to the std handles directly (WriteFile on GetStdHandle) are
  not Text files and do not pass through here; they call EncodeForOutput. }

interface

uses
  System.SysUtils,
  System.IOUtils
  ;

type
  /// <summary>The byte encoding the engine writes to stdout and stderr.</summary>
  TOutputEncoding = (oeAscii, oeUtf8, oeUtf16);

const
  /// <summary>The command-line switch that selects the output encoding.</summary>
  OUTPUT_ENCODING_SWITCH = '--output-encoding';
  /// <summary>The .drag-lint.json defaults-file key that selects it.</summary>
  OUTPUT_ENCODING_CONFIG_KEY = 'outputEncoding';
  /// <summary>The accepted values, as the help text and the errors spell them.</summary>
  OUTPUT_ENCODING_VALUES = 'ascii|utf8|utf16';

/// <summary>Parses an --output-encoding value.</summary>
/// <param name="pText">ascii, utf8 or utf16; case-insensitive, `utf-8` and
/// `utf-16` accepted as spellings of the same two.</param>
/// <param name="pEncoding">The parsed mode; oeAscii when the text is not one of
/// them.</param>
/// <returns>True when pText names a mode.</returns>
function TryParseOutputEncoding(const pText: string; out pEncoding: TOutputEncoding): Boolean;

/// <summary>The canonical name of a mode (ascii, utf8, utf16).</summary>
/// <param name="pEncoding">The mode.</param>
/// <returns>The name --output-encoding accepts for it.</returns>
function OutputEncodingName(pEncoding: TOutputEncoding): string;

/// <summary>Escapes every non-ASCII UTF-16 code unit of pText as \uXXXX
/// (lower-case hex); ASCII is returned unchanged.</summary>
/// <param name="pText">Any text.</param>
/// <returns>Pure 7-bit ASCII text; equal to pText when pText is ASCII.</returns>
/// <remarks>Deterministic. Exactly reversible inside JSON (a literal backslash
/// there is already `\\`); in plain text it is reversible unless the original
/// itself held a backslash, `u` and four hex digits.</remarks>
function EscapeNonAscii(const pText: string): string;

/// <summary>pText as the bytes the current output mode writes.</summary>
/// <param name="pText">The text to write.</param>
/// <returns>Escaped ASCII, UTF-8 or UTF-16LE bytes; never a BOM.</returns>
/// <remarks>For writers that bypass Output / ErrOutput and write the std
/// handles directly. Thread-safe: it only reads the current mode.</remarks>
function EncodeForOutput(const pText: string): TBytes;

/// <summary>Selects the encoding of Output and ErrOutput from now on.</summary>
/// <param name="pEncoding">The mode to use.</param>
/// <remarks>Flushes both files first, so bytes already buffered are written in
/// the mode they were written under. Call from the main thread, before any
/// worker thread writes to Output or ErrOutput. Idempotent.</remarks>
procedure InstallOutputEncoding(pEncoding: TOutputEncoding);

/// <summary>The mode InstallOutputEncoding last selected (oeAscii before any
/// call).</summary>
/// <returns>The current mode.</returns>
function CurrentOutputEncoding: TOutputEncoding;

/// <summary>Reads --output-encoding from the raw command line (ParamStr), for
/// the decisions made before ParseArgs runs.</summary>
/// <param name="pEncoding">The mode named on the command line, when found and
/// valid.</param>
/// <param name="pValue">The text after the switch ('' when it is the last
/// argument).</param>
/// <returns>True when the switch is present (valid or not).</returns>
function OutputEncodingOnCommandLine(out pEncoding: TOutputEncoding; out pValue: string): Boolean;

/// <summary>Writes a file a verb produces (--output, a report) in the current
/// output mode, so the file obeys --output-encoding exactly as stdout does.</summary>
/// <param name="pPath">Target file; created or truncated.</param>
/// <param name="pText">The text to write.</param>
/// <remarks>ascii: non-ASCII becomes \uXXXX and is counted as lost output; utf8:
/// UTF-8 without BOM; utf16: UTF-16LE without BOM. When the text is a JSON object
/// and characters were lost so far in this run, a "lossy_output":N member is added
/// as its first member.</remarks>
procedure WriteOutputFile(const pPath, pText: string);

/// <summary>How many non-ASCII characters this run wrote as \uXXXX escapes
/// (ascii mode only).</summary>
/// <returns>The count; 0 when nothing was lost or the mode is not ascii.</returns>
function LossyOutputCount: Integer;

/// <summary>The one-line warning text for pCount lost characters.</summary>
/// <param name="pCount">Characters escaped in this run, greater than 0.</param>
/// <returns>Pure ASCII text naming the count, the --output-encoding switch and
/// the outputEncoding key of .drag-lint.json.</returns>
function LossyOutputWarning(pCount: Integer): string;

implementation

uses
  Winapi.Windows,
  System.SyncObjs
  ;

const
  ASCII_LIMIT       = $80;
  ESCAPE_PREFIX     = '\u';     { + 4 lower-case hex digits }
  MAX_UTF8_SEQ      = 4;
  UTF8_CONT_MASK    = $C0;   { 10xxxxxx: a continuation byte }
  UTF8_CONT_BITS    = $80;
  { the smallest lead byte of a 2-, 3- and 4-byte sequence }
  UTF8_LEAD_MIN: array[2..MAX_UTF8_SEQ] of Byte = ($C0, $E0, $F0);

var
  GEncoding: TOutputEncoding = oeAscii;
  GInstalled: Boolean = False;
  GLossy: Integer = 0;
  { An incomplete UTF-8 sequence left at the end of one buffer flush, kept for
    the next: the RTL flushes a full buffer wherever it happens to end. Index 0
    is Output, 1 is ErrOutput. }
  GCarry: array[0..1] of array[0..MAX_UTF8_SEQ - 1] of Byte;
  GCarryLen: array[0..1] of Integer;

function TryParseOutputEncoding(const pText: string; out pEncoding: TOutputEncoding): Boolean;
var
  T: string;
begin
  T:= LowerCase(Trim(pText));
  Result:= True;
  if T = 'ascii' then pEncoding:= oeAscii
  else if (T = 'utf8') or (T = 'utf-8') then pEncoding:= oeUtf8
  else if (T = 'utf16') or (T = 'utf-16') then pEncoding:= oeUtf16
  else
  begin
    pEncoding:= oeAscii;
    Result:= False;
  end;
end;

function OutputEncodingName(pEncoding: TOutputEncoding): string;
begin
  case pEncoding of
    oeUtf8 : Result:= 'utf8';
    oeUtf16: Result:= 'utf16';
  else
    Result:= 'ascii';
  end;
end;

function EscapeNonAscii(const pText: string): string;
const
  ESCAPE_HEX_DIGITS = 4;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB:= TStringBuilder.Create(Length(pText));
  try
    for C in pText do
      if Ord(C) < ASCII_LIMIT then SB.Append(C)
      else SB.Append(ESCAPE_PREFIX).Append(LowerCase(IntToHex(Ord(C), ESCAPE_HEX_DIGITS)));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure CountLost(const pText: string);
var
  C: Char;
begin
  for C in pText do
    if Ord(C) >= ASCII_LIMIT then TInterlocked.Increment(GLossy);
end;

function EncodeForOutput(const pText: string): TBytes;
begin
  case GEncoding of
    oeUtf8 : Result:= TEncoding.UTF8.GetBytes(pText);
    oeUtf16: Result:= TEncoding.Unicode.GetBytes(pText);
  else
  begin
    Result:= TEncoding.ASCII.GetBytes(EscapeNonAscii(pText));
    CountLost(pText);
  end;
  end;
end;

{ How many bytes at the END of pSrc[0..pLen-1] are an INCOMPLETE UTF-8
  sequence (0..3): the RTL flushes a full buffer wherever it happens to end. }
function IncompleteTail(const pSrc: TBytes; pLen: Integer): Integer;
var
  I, K, Need: Integer;
begin
  Result:= 0;
  I:= pLen - 1;
  while (I >= 0) and (pLen - I <= MAX_UTF8_SEQ) do
  begin
    if (pSrc[I] and UTF8_CONT_MASK) <> UTF8_CONT_BITS then
    begin
      { a lead byte (or ASCII): how long a sequence does it start? }
      Need:= 1;
      for K:= Low(UTF8_LEAD_MIN) to High(UTF8_LEAD_MIN) do
        if pSrc[I] >= UTF8_LEAD_MIN[K] then Need:= K;
      if pLen - I < Need then Result:= pLen - I;
      Exit;
    end;
    Dec(I);
  end;
end;

function IsAsciiOnly(pSrc: PByte; pLen: Cardinal): Boolean;
var
  I: Cardinal;
begin
  Result:= True;
  if pLen = 0 then Exit;
  for I:= 0 to pLen - 1 do
    if pSrc[I] >= ASCII_LIMIT then Exit(False);
end;

function WriteAllRaw(pHandle: THandle; pSrc: PByte; pLen: Cardinal): Integer;
var
  Done, Written: DWORD;
begin
  Result:= 0;
  Done:= 0;
  while Done < pLen do
  begin
    if not WriteFile(pHandle, pSrc[Done], pLen - Done, Written, nil) then Exit(GetLastError);
    if Written = 0 then Exit(ERROR_WRITE_FAULT);
    Inc(Done, Written);
  end;
end;

{ The InOutFunc of Output / ErrOutput in the ascii and utf16 modes: the RTL
  filled t.BufPtr with UTF-8 (CodePage = CP_UTF8); decode the complete
  sequences, re-encode them with EncodeForOutput and keep an incomplete tail
  for the next flush. A malformed byte decodes to U+FFFD. }
function ReencodingTextOut(var t: TTextRec): Integer;
var
  Slot, Total, Keep: Integer;
  Src, Dst: TBytes;
begin
  Result:= 0;
  Slot:= if @t = @ErrOutput then 1 else 0;
  Total:= GCarryLen[Slot] + Integer(t.BufPos);
  if Total = 0 then Exit;
  { The common case -- ascii mode, nothing carried, an all-ASCII buffer -- is
    written as it stands, exactly as the RTL's own routine would. }
  if (GEncoding = oeAscii) and (GCarryLen[Slot] = 0) and IsAsciiOnly(PByte(t.BufPtr), t.BufPos) then
  begin
    Result:= WriteAllRaw(t.Handle, PByte(t.BufPtr), t.BufPos);
    t.BufPos:= 0;
    Exit;
  end;
  SetLength(Src, Total);
  if GCarryLen[Slot] > 0 then Move(GCarry[Slot][0], Src[0], GCarryLen[Slot]);
  if t.BufPos > 0 then Move(t.BufPtr^, Src[GCarryLen[Slot]], t.BufPos);
  t.BufPos:= 0;
  Keep:= IncompleteTail(Src, Total);
  GCarryLen[Slot]:= Keep;
  if Keep > 0 then Move(Src[Total - Keep], GCarry[Slot][0], Keep);
  if Total = Keep then Exit;
  Dst:= EncodeForOutput(TEncoding.UTF8.GetString(Src, 0, Total - Keep));
  if Length(Dst) > 0 then Result:= WriteAllRaw(t.Handle, @Dst[0], Length(Dst));
end;

{ Opens a std Text file the way the RTL's first write would, so the InOutFunc
  set below is not overwritten by that lazy open later. }
procedure EnsureOpen(var pText: Text);
begin
  if TTextRec(pText).Mode <> fmOutput then
  begin
    TTextRec(pText).Flags:= tfCRLF * Byte(DefaultTextLineBreakStyle);
    Rewrite(pText);
  end;
end;

var
  { The RTL's own write routine for a std stream, captured on first install;
    the utf8 mode restores it. }
  TextOutOriginal: Pointer = nil;

procedure InstallOn(var pText: Text);
begin
  EnsureOpen(pText);
  Flush(pText);
  { Only a std stream: a Text redirected to a file (AssignFile(Output, 'NUL'))
    keeps its own routine. }
  if TTextRec(pText).Name[0] <> #0 then Exit;
  SetTextCodePage(pText, CP_UTF8);
  if GEncoding = oeUtf8 then TTextRec(pText).InOutFunc:= TextOutOriginal
  else TTextRec(pText).InOutFunc:= @ReencodingTextOut;
end;

procedure InstallOutputEncoding(pEncoding: TOutputEncoding);
begin
  if GInstalled then
  begin
    Flush(Output);
    Flush(ErrOutput);
  end
  else
  begin
    EnsureOpen(Output);
    EnsureOpen(ErrOutput);
    TextOutOriginal:= TTextRec(Output).InOutFunc;
  end;
  GEncoding:= pEncoding;
  GInstalled:= True;
  InstallOn(Output);
  InstallOn(ErrOutput);
end;

function CurrentOutputEncoding: TOutputEncoding;
begin
  Result:= GEncoding;
end;

function OutputEncodingOnCommandLine(out pEncoding: TOutputEncoding; out pValue: string): Boolean;
var
  I: Integer;
begin
  pEncoding:= oeAscii;
  pValue:= '';
  Result:= False;
  for I:= 1 to ParamCount do
    if SameText(ParamStr(I), OUTPUT_ENCODING_SWITCH) then
    begin
      Result:= True;
      if I < ParamCount then pValue:= ParamStr(I + 1);
      TryParseOutputEncoding(pValue, pEncoding);
    end;
end;


function LossyOutputCount: Integer;
begin
  if GEncoding = oeAscii then Result:= GLossy else Result:= 0;
end;

function LossyOutputWarning(pCount: Integer): string;
begin
  Result:= Format('drag-lint: warning: %d non-ASCII character(s) were written as \uXXXX escapes ' +
    '(output encoding ascii). To write them as-is: add --output-encoding utf8 (or utf16) to the ' +
    'command line, or set "outputEncoding": "utf8" in drag-lint.json / .drag-lint.json.', [pCount]);
end;

procedure WriteOutputFile(const pPath, pText: string);
var
  Text: string;
  Pending: Integer;
begin
  Text:= pText;
  if GEncoding = oeAscii then
  begin
    Pending:= 0;
    for var C in pText do
      if Ord(C) >= ASCII_LIMIT then Inc(Pending);
    { a JSON object report: say how much was lost, as its first member }
    if (GLossy + Pending > 0) and (Length(Text) > 1) and (Text[1] = '{') and (Text[2] <> '}') then
      Text:= '{"lossy_output":' + IntToStr(GLossy + Pending) + ',' + Copy(Text, 2, MaxInt);
  end;
  TFile.WriteAllBytes(pPath, EncodeForOutput(Text));
end;

procedure WarnLossyOnce;
var
  N: Integer;
begin
  N:= LossyOutputCount;
  if N <= 0 then Exit;
  try
    Writeln(ErrOutput, LossyOutputWarning(N));
    Flush(ErrOutput);
  except
    { stderr closed: nothing left to warn on }
  end;
end;

initialization
finalization
  WarnLossyOnce;

end.