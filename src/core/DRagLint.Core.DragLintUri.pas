unit DRagLint.Core.DragLintUri;

/// <summary>Parses and validates a draglint:// click-to-source URI -- the
/// security gate the GUI protocol handler (drag-lint-open.exe) runs before it
/// writes anything to the IDE's open-source pipe.</summary>
/// <remarks>
/// <para>A port of the validation in charts\src\Open-DragLintUri.ps1 (its
/// URI parsing and Test-DragLintTarget); tests\fixtures\T68_draglint_uri.dpr
/// carries the UH-* case table of charts\src\Test-DragLintProtocol.ps1. ANY web
/// page can carry a draglint:// link, so the URI is hostile until proven
/// otherwise.</para>
/// <para>The PATH verdict is DragLint.Plugin.OpenSourcePath.IsOpenableSourcePath,
/// the same gate the IDE pipe server applies, so the browser side and the IDE
/// side cannot drift; its reason text is reported as-is. One rule of the script
/// is checked here on top of it: a reserved device name is the part of a
/// segment before its FIRST dot, trimmed (CON.x.pas and NUL .pas are devices),
/// where the gate only strips the last extension.</para>
/// <para>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</para>
/// </remarks>

interface

type
  /// <summary>A validated click-to-source target: what the handler writes to the IDE pipe.</summary>
  TDragLintTarget = record
    /// <summary>The file, percent-decoded once; an absolute local drive path to a source file.</summary>
    File_: string;
    /// <summary>The 1-based line; an absent, empty or 0 line is 1.</summary>
    Line : Integer;
    /// <summary>The column as given (ASCII digits), or '' when the URI has none.</summary>
    Col  : string;
    /// <summary>The pipe frame: file, line and (when given) col separated by TAB, ending in LF.</summary>
    /// <returns>The UTF-8-ready text; never contains a TAB or LF inside a field (ParseDragLintUri refused them).</returns>
    function Payload: string;
  end;

/// <summary>Parses and validates a draglint://open?file=..&amp;line=..[&amp;col=..] URI.</summary>
/// <param name="pUri">The URI exactly as the browser handed it (one argument).</param>
/// <param name="pTarget">On True, the file (as decoded), the line (1-based; 0 and absent become 1) and col text.</param>
/// <param name="pReason">On False, why: the reasons of Open-DragLintUri.ps1 (no uri given, not a draglint uri,
/// no file= in uri, duplicate key, control character in file/line/col, line is not a number, col is not a number,
/// reserved device name) or IsOpenableSourcePath's. '' on True.</param>
/// <returns>True only when every rule passes.</returns>
/// <remarks>Pure and thread-safe; never touches the file system (the gate runs BEFORE any FileExists, which on a
/// UNC path is itself the network access being prevented). The scheme match is CASE-INSENSITIVE, as the script's
/// PowerShell -notmatch is; surrounding whitespace and trailing '/' are trimmed; the host/path part before '?' is
/// ignored. Query keys are lower-cased (ASCII); a pair without '=' or with an empty key is ignored. Every key at
/// most once -- never last-wins. Percent decoding (%XX as UTF-8 only) happens once; an invalid UTF-8 sequence stays
/// literal; a decoded control character is refused, a '+' is not a space.</remarks>
function ParseDragLintUri(const pUri: string; out pTarget: TDragLintTarget; out pReason: string): Boolean;  // dl:ok unused-public-symbol@0cc2 -- REVIEWED 2026-10-14: called by drag-lint-open.exe (its own project) and T68, neither in this index

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,  // dl:ok unused-unit-in-uses@6171 -- REVIEWED 2026-10-14: TCharHelper.IsWhiteSpace in TrimWhiteSpace; removing it fails E2671
  System.Generics.Collections,
  DragLint.Plugin.OpenSourcePath;

const
  SCHEME        = 'draglint://';
  KEY_FILE      = 'file';
  KEY_LINE      = 'line';
  KEY_COL       = 'col';
  TAB_CHAR      = #9;
  LF_CHAR       = #10;
  FIRST_PRINTABLE = #32;
  DEL_CHAR      = #127;
  // ^[0-9]{1,9}$ -- nine digits always fit an Integer.
  MAX_DIGITS    = 9;
  { 'X:\' -- drive letter, colon, backslash. }
  DRIVE_PREFIX_LEN = 3;
  { '%XX' }
  ESCAPE_LEN    = 3;
  HEX_DIGITS: TSysCharSet = ['0'..'9', 'A'..'F', 'a'..'f'];
  { UTF-8 lead-byte ranges and the sequence length each one announces. }
  UTF8_ASCII_END   = $7F;
  UTF8_LEAD2_FIRST = $C2;
  UTF8_LEAD3_FIRST = $E0;
  UTF8_LEAD4_FIRST = $F0;
  UTF8_LEAD4_LAST  = $F4;
  UTF8_CONT_FIRST  = $80;
  UTF8_CONT_LAST   = $BF;
  UTF8_LEN2 = 2;
  UTF8_LEN3 = 3;
  UTF8_LEN4 = 4;
  { Probe extension and reason prefix shared with the plugin's path gate. }
  PROBE_EXT       = '.pas';
  RESERVED_DEVICE = 'reserved device name';

function TDragLintTarget.Payload: string;
begin
  Result:= File_ + TAB_CHAR + IntToStr(Line);
  if Col <> '' then Result:= Result + TAB_CHAR + Col;
  Result:= Result + LF_CHAR;
end;

{ Char.IsWhiteSpace at both ends -- the .NET String.Trim the script uses, so a
  stray control character at an end is NOT silently trimmed away. }
function TrimWhiteSpace(const S: string): string;
var
  First, Last: Integer;
begin
  First:= 1;
  Last:= Length(S);
  while (First <= Last) and S[First].IsWhiteSpace do Inc(First);
  while (Last >= First) and S[Last].IsWhiteSpace do Dec(Last);
  Result:= Copy(S, First, Last - First + 1);
end;

function HasControlChar(const S: string): Boolean;
var
  C: Char;
begin
  Result:= False;
  for C in S do
    if (C < FIRST_PRINTABLE) or (C = DEL_CHAR) then Exit(True);
end;

// ^[0-9]{1,9}$ over ASCII digits only ([0-9], not \d, which takes any
// Unicode digit).
function IsAsciiNumber(const S: string): Boolean;
var
  C: Char;
begin
  Result:= (S <> '') and (Length(S) <= MAX_DIGITS);
  if not Result then Exit;
  for C in S do
    if not CharInSet(C, ['0'..'9']) then Exit(False);
end;

function IsEscapeAt(const S: string; AIndex: Integer): Boolean;
begin
  Result:= (AIndex + ESCAPE_LEN - 1 <= Length(S))
       and (S[AIndex] = '%')
       and CharInSet(S[AIndex + 1], HEX_DIGITS)
       and CharInSet(S[AIndex + 2], HEX_DIGITS);
end;

{ The sequence length a UTF-8 lead byte announces; 0 for a byte that cannot
  start one. }
function Utf8SequenceLength(ALead: Byte): Integer;
begin
  if ALead <= UTF8_ASCII_END then Result:= 1
  else if ALead < UTF8_LEAD2_FIRST then Result:= 0
  else if ALead < UTF8_LEAD3_FIRST then Result:= UTF8_LEN2
  else if ALead < UTF8_LEAD4_FIRST then Result:= UTF8_LEN3
  else if ALead <= UTF8_LEAD4_LAST then Result:= UTF8_LEN4
  else Result:= 0;
end;

{ Decodes ABytes[AStart..AStart+ALen-1] when it is one well-formed UTF-8
  sequence (round-trip exact: no overlong form, no surrogate). }
function TryDecodeSequence(const ABytes: TBytes; AStart, ALen: Integer; out AText: string): Boolean;
var
  I        : Integer;
  RoundTrip: TBytes;
begin
  AText:= '';
  if (ALen = 0) or (AStart + ALen > Length(ABytes)) then Exit(False);
  for I:= AStart + 1 to AStart + ALen - 1 do
    if (ABytes[I] < UTF8_CONT_FIRST) or (ABytes[I] > UTF8_CONT_LAST) then Exit(False);
  try
    AText:= TEncoding.UTF8.GetString(ABytes, AStart, ALen);
  except
    on EEncodingError do Exit(False);
  end;
  if AText = '' then Exit(False);
  RoundTrip:= TEncoding.UTF8.GetBytes(AText);
  Result:= (Length(RoundTrip) = ALen) and CompareMem(@RoundTrip[0], @ABytes[AStart], ALen);
end;

{ Appends one run of consecutive %XX escapes, decoded as UTF-8 sequence by
  sequence; a byte that does not start a well-formed sequence stays as its
  literal %XX (what [uri]::UnescapeDataString does). }
procedure AppendEscapeRun(const ARun: string; AOut: TStringBuilder);
var
  Bytes: TBytes;
  I, N : Integer;
  Text : string;
begin
  SetLength(Bytes, Length(ARun) div ESCAPE_LEN);
  for I:= 0 to High(Bytes) do
    Bytes[I]:= StrToInt('$' + Copy(ARun, I * ESCAPE_LEN + 2, 2));
  I:= 0;
  while I <= High(Bytes) do
  begin
    N:= Utf8SequenceLength(Bytes[I]);
    if TryDecodeSequence(Bytes, I, N, Text) then
    begin
      AOut.Append(Text);
      Inc(I, N);
    end
    else
    begin
      AOut.Append(Copy(ARun, I * ESCAPE_LEN + 1, ESCAPE_LEN));
      Inc(I);
    end;
  end;
end;

{ Percent-decodes once: %XX only, '+' stays '+', a '%' not followed by two hex
  digits stays literal. }
function PercentDecode(const S: string): string;
var
  I, RunStart: Integer;
  SB         : TStringBuilder;
begin
  SB:= TStringBuilder.Create(Length(S));
  try
    I:= 1;
    while I <= Length(S) do
      if IsEscapeAt(S, I) then
      begin
        RunStart:= I;
        while IsEscapeAt(S, I) do Inc(I, ESCAPE_LEN);
        AppendEscapeRun(Copy(S, RunStart, I - RunStart), SB);
      end
      else
      begin
        SB.Append(S[I]);
        Inc(I);
      end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ The script's device-name rule: the part of each segment before its FIRST dot,
  trailing spaces trimmed. The gate already covers the last-extension form;
  this adds CON.x.pas and NUL .pas. Returns '' or the refusal reason. }
function CheckDeviceBaseNames(const APath: string): string;
var
  Seg, Base, Drive, Why: string;
  Dot                  : Integer;
begin
  Result:= '';
  Drive:= Copy(APath, 1, DRIVE_PREFIX_LEN);
  for Seg in Copy(APath, DRIVE_PREFIX_LEN + 1, MaxInt).Split(['\']) do
  begin
    Dot:= Pos('.', Seg);
    Base:= TrimRight(if Dot > 0 then Copy(Seg, 1, Dot - 1) else Seg);
    { The gate judges the base name through a probe on the path's own drive:
      the device list lives in one place. }
    if not IsOpenableSourcePath(Drive + Base + PROBE_EXT, Why) and StartsText(RESERVED_DEVICE, Why) then
      Exit(Format(RESERVED_DEVICE + ' "%s"', [Base]));
  end;
end;

{ Splits the query into lower-cased keys and once-decoded values. Returns ''
  or the refusal reason (a duplicate key). }
function SplitQuery(const AQuery: string; AParts: TDictionary<string, string>): string;
var
  Pair, Key: string;
  EqPos    : Integer;
begin
  Result:= '';
  for Pair in AQuery.Split(['&']) do
  begin
    EqPos:= Pos('=', Pair);
    if EqPos <= 1 then Continue;
    Key:= LowerCase(Copy(Pair, 1, EqPos - 1));
    if AParts.ContainsKey(Key) then Exit(Format('duplicate %s= in uri', [Key]));
    AParts.Add(Key, PercentDecode(Copy(Pair, EqPos + 1, MaxInt)));
  end;
end;

{ Test-DragLintTarget: the verdict on the decoded (file, line, col), in the
  script's order. Fills pTarget only when the verdict is ''. }
function CheckTarget(const AFile, ALine, ACol: string; var pTarget: TDragLintTarget): string;
var
  Why: string;
begin
  if AFile = '' then Result:= 'no file= in uri'
  else if HasControlChar(AFile) then Result:= 'control character in file'
  else if HasControlChar(ALine) then Result:= 'control character in line'
  else if HasControlChar(ACol) then Result:= 'control character in col'
  else if not IsOpenableSourcePath(AFile, Why) then Result:= Why
  else Result:= CheckDeviceBaseNames(AFile);
  if (Result = '') and (ALine <> '') and not IsAsciiNumber(ALine) then Result:= 'line is not a number';
  if (Result = '') and (ACol <> '') and not IsAsciiNumber(ACol) then Result:= 'col is not a number';
  if Result <> '' then Exit;
  pTarget.File_:= AFile;
  pTarget.Line:= if ALine = '' then 1 else StrToInt(ALine);
  if pTarget.Line < 1 then pTarget.Line:= 1;
  pTarget.Col:= ACol;
end;

function ParseDragLintUri(const pUri: string; out pTarget: TDragLintTarget; out pReason: string): Boolean;
var
  U, Query, FileV, LineV, ColV: string;
  QPos : Integer;
  Parts: TDictionary<string, string>;
begin
  pTarget:= Default(TDragLintTarget);
  U:= TrimWhiteSpace(pUri);
  if U = '' then pReason:= 'no uri given'
  else
  begin
    { Browsers may append a trailing slash to the whole URI. }
    while EndsStr('/', U) do SetLength(U, Length(U) - 1);
    if not StartsText(SCHEME, U) then pReason:= 'not a draglint uri'
    else
    begin
      QPos:= Pos('?', U);
      Query:= if QPos > 0 then Copy(U, QPos + 1, MaxInt) else '';
      Parts:= TDictionary<string, string>.Create;
      try
        pReason:= SplitQuery(Query, Parts);
        if pReason = '' then
        begin
          Parts.TryGetValue(KEY_FILE, FileV);
          Parts.TryGetValue(KEY_LINE, LineV);
          Parts.TryGetValue(KEY_COL, ColV);
          pReason:= CheckTarget(FileV, LineV, ColV, pTarget);
        end;
      finally
        Parts.Free;
      end;
    end;
  end;
  Result:= pReason = '';
  if not Result then pTarget:= Default(TDragLintTarget);
end;

end.
