unit DRagLint.Core.Encoding;

{ v0.86 (Task 3): transcode source bytes to valid UTF-8 at every byte-ingest
  boundary. The whole text pipeline downstream assumes UTF-8 -- tree-sitter is
  fed TSInputEncodingUTF8 and ~30 slice helpers call TEncoding.UTF8.GetString.
  A VALID CP1252 file whose bytes are not valid UTF-8 (e.g. 0xAE '(R)' / 0xA9
  '(C)' in a copyright resourcestring -- the SOFTWID.PAS class) threw
  EEncodingError during literal extraction, so the file was SKIPPED at index and
  errored at lint. Applying EnsureUtf8Bytes once at each ingest site means the
  bytes flowing into every downstream UTF8.GetString are already valid UTF-8, so
  no downstream site needs changing. }

interface

uses
  System.SysUtils
  , System.Classes
  ;

/// <summary>Returns ABytes as valid UTF-8 for the parse/slice pipeline.</summary>
/// <param name="ABytes">Raw file bytes exactly as read from disk. Empty is valid.</param>
/// <returns>Bytes guaranteed to be valid UTF-8 (never with a BOM):
/// <list type="bullet">
/// <item>UTF-8 BOM (EF BB BF): the BOM is stripped; the remainder is returned unchanged.</item>
/// <item>UTF-16 LE BOM (FF FE) / BE BOM (FE FF): transcoded to UTF-8.</item>
/// <item>Already-valid UTF-8 (no BOM): returned unchanged (identity passthrough).</item>
/// <item>Anything else: treated as ANSI (Windows-1252) and transcoded to UTF-8.</item>
/// </list></returns>
/// <remarks>
/// Validation is a strict, explicit UTF-8 continuation-byte scan -- no
/// exception-driven control flow. The content sha256 / file-identity checks in
/// TIndexer.IndexFile stay computed over the RAW file bytes, NOT this result, so
/// the up-to-date/incremental-skip contract is unchanged for pure-ASCII files
/// (ASCII is valid UTF-8, so this returns the input unchanged). Pure function;
/// thread-safe (no shared state; the CP1252 encoding it allocates is freed).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.LintTree.RunLintTree (DRagLint.Analysis.LintTree.pas), DRagLint.Analysis.LintTree.ValidateAndResolve (DRagLint.Analysis.LintTree.pas), DRagLint.CLI.ApplyLineMarkers.LineIsPreprocessorInactive (DRagLint.CLI.pas), DRagLint.CLI.ApplyLineMarkers.LinesOf (DRagLint.CLI.pas), DRagLint.CLI.MarkedRuleIds (DRagLint.CLI.pas) (+28 more)</para>
/// <para>Calls: DRagLint.Core.Encoding.IsValidUtf8, Move</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 54 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Encoding.IsValidUtf8"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EnsureUtf8Bytes(const ABytes: TBytes): TBytes;

/// <summary>True when every byte of ABytes belongs to a well-formed UTF-8
/// sequence (RFC 3629: no overlong forms, no surrogates, max U+10FFFF).</summary>
/// <param name="ABytes">Raw bytes, without a BOM. Empty and pure ASCII are valid.</param>
/// <returns>True for valid UTF-8; False at the first malformed sequence.</returns>
/// <remarks>
/// Pure; thread-safe. Exposed (W5-D, 2026-10-25) so the text-edit
/// writer (TTextFileFormat.Decode) tells a BOM-less UTF-8 file from an ANSI
/// one by the SAME rule the indexer uses in EnsureUtf8Bytes.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.Encoding.EnsureUtf8Bytes (DRagLint.Core.Encoding.pas), DRagLint.Refactor.TextEdit.TTextFileFormat.Decode (DRagLint.Refactor.TextEdit.pas)</para>
/// <para>Calls: Cardinal</para>
/// <para>Returns: True; False</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 64 lines (full implementation)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsValidUtf8(const ABytes: TBytes): Boolean;

/// <summary>The 0-based CHARACTER column of a position in a UTF-8 buffer: the number of UTF-16 code units
/// (the unit a Delphi string indexes) from the start of the line up to the position.</summary>
/// <param name="ASource">The UTF-8 bytes the parser parsed (EnsureUtf8Bytes' result).</param>
/// <param name="AByteOffset">The position's byte offset in ASource (a tree-sitter node's StartByte / EndByte).</param>
/// <param name="AByteColumn">The position's byte column in its line (the node's StartPoint / EndPoint column).</param>
/// <returns>AByteColumn when the line prefix is pure ASCII; fewer when it holds a multi-byte character
/// (two for a character outside the BMP, which is a surrogate pair in a string); AByteColumn when the
/// two arguments disagree with ASource (no line start inside the buffer).</returns>
/// <remarks>
/// 1.52 EXTGAPS2: tree-sitter reports BYTE columns, every index column (refs, symbols, uses,
/// literals, data_flows, with scopes) is a CHARACTER column -- the column a reader of the source line
/// counts. Pure; thread-safe. Pinned by tests\autotest\run_extgaps2_extraction.ps1.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Doc.Facts.CatchSpansOf.AddTry (DRagLint.Doc.Facts.pas), DRagLint.Index.CallResolver.CollectWithStatements (DRagLint.Index.CallResolver.pas), DRagLint.Index.DataFlowFacts.TCollector.AssignSlot (DRagLint.Index.DataFlowFacts.pas), DRagLint.Index.DataFlowFacts.TCollector.EmitExitRows (DRagLint.Index.DataFlowFacts.pas) (+34 more)</para>
/// <para>Calls: Cardinal, Integer</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function Utf8ByteColToCharCol(const ASource: TBytes; AByteOffset, AByteColumn: Cardinal): Integer;

/// <summary>The inverse of Utf8ByteColToCharCol for code that keeps byte offsets: the 1-based BYTE column of
/// the 1-based CHARACTER column ACharCol on the line that starts at byte ALineStart.</summary>
/// <param name="ASource">UTF-8 bytes.</param>
/// <param name="ALineStart">Byte offset of the line's first byte in ASource.</param>
/// <param name="ACharCol">1-based character (UTF-16 unit) column, an index column.</param>
/// <returns>ACharCol on a pure-ASCII prefix; larger past a multi-byte character. Past the line end (LF) or the
/// buffer the remaining columns count one byte each.</returns>
/// <remarks>
/// 1.52 EXTGAPS2. Pure; thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Diagnostics.ParseCache.TAstParseCache.ByteCol (DRagLint.Diagnostics.ParseCache.pas), DRagLint.LSP.Server.ByteCol0Of (DRagLint.LSP.Server.pas), DRagLint.Refactor.Unwith.LoadRowsOf (DRagLint.Refactor.Unwith.pas)</para>
/// <para>Returns: I - ALineStart + 1 + (ACharCol - 1 - Units)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function Utf8CharColToByteCol(const ASource: TBytes; ALineStart, ACharCol: Integer): Integer;

/// <summary>The lines of a source file decoded the way the indexer decodes it (EnsureUtf8Bytes): a
/// UTF-8 / UTF-16 BOM is honoured and dropped, BOM-less valid UTF-8 is UTF-8, anything else is
/// Windows-1252.</summary>
/// <param name="APath">The source file; it must exist.</param>
/// <returns>One string per line, CR / LF / CRLF breaks removed, no trailing empty line for a final
/// line break (the TFile.ReadAllLines shape).</returns>
/// <remarks>TFile.ReadAllBytes' own exceptions (file missing / unreadable) propagate unchanged. GitHub #16 (1.52): TFile.ReadAllLines(APath, TEncoding.ANSI) kept a UTF-8 BOM as the
/// text (three ANSI characters) and decoded every UTF-8 character as two ANSI ones, so context printed
/// mojibake for a unit saved as UTF-8. Thread-safe. Pinned by tests\autotest\run_v152_GH16.ps1.</remarks>
function ReadSourceFileLines(const APath: string): TArray<string>;

/// <summary>The whole text of a source file decoded as ReadSourceFileLines decodes it (BOM honoured
/// and dropped, BOM-less valid UTF-8 as UTF-8, else Windows-1252); line breaks are kept as in the file.</summary>
/// <param name="APath">The source file; it must exist.</param>
/// <returns>The decoded text, without a BOM.</returns>
/// <remarks>TFile.ReadAllBytes' own exceptions (file missing / unreadable) propagate unchanged. GitHub #16 follow-up (1.52): replaces TFile.ReadAllText(APath, TEncoding.ANSI) in the
/// read-only source readers. Thread-safe. The decoder it shares with ReadSourceFileLines is pinned by tests\autotest\run_v152_GH16.ps1.</remarks>
function ReadSourceFileText(const APath: string): string;

implementation

uses
  System.IOUtils;
const
  CP_ANSI_LATIN = 1252; { Windows-1252, the ANSI fallback for bytes that are not valid UTF-8 }

{ Strict UTF-8 validation: an explicit continuation-byte walk with the RFC 3629
  bounds (max U+10FFFF, no overlong forms, no surrogate code points D800..DFFF).
  Returns True iff every byte belongs to a well-formed UTF-8 sequence. No
  exceptions are used for control flow. }
function IsValidUtf8(const ABytes: TBytes): Boolean;
var
  I, N   : Integer;
  B0     : Byte   ;
  Extra  : Integer;  { number of continuation bytes expected after the lead byte }
  CP     : Cardinal;
  MinCP  : Cardinal; { smallest code point legal for this sequence length (overlong guard) }
  J, Cont: Integer;
begin
  Result:= True;
  N:= Length(ABytes);
  I:= 0;
  while I < N do
  begin
    B0:= ABytes[I];
    if B0 < $80 then
    begin
      { 0xxxxxxx -- ASCII }
      Inc(I);
      Continue;
    end
    else if (B0 >= $C2) and (B0 <= $DF) then
    begin
      { 110xxxxx -- 2-byte sequence. C0/C1 are always overlong -> excluded above. }
      Extra := 1;
      CP    := B0 and $1F;
      MinCP := $80;
    end
    else if (B0 >= $E0) and (B0 <= $EF) then
    begin
      { 1110xxxx -- 3-byte sequence. }
      Extra := 2;
      CP    := B0 and $0F;
      MinCP := $800;
    end
    else if (B0 >= $F0) and (B0 <= $F4) then
    begin
      { 11110xxx -- 4-byte sequence. F5..F7 would exceed U+10FFFF. }
      Extra := 3;
      CP    := B0 and $07;
      MinCP := $10000;
    end
    else
    begin
      { 80..BF stray continuation, or C0/C1/F5..FF: not a legal lead byte. }
      Exit(False);
    end;

    { Consume the expected continuation bytes (each must be 10xxxxxx). }
    if I + Extra >= N then Exit(False);
    for J:= 1 to Extra do
    begin
      Cont:= ABytes[I + J];
      if (Cont and $C0) <> $80 then Exit(False);
      CP:= (CP shl 6) or Cardinal(Cont and $3F);
    end;

    { Reject overlong encodings, surrogates, and out-of-range code points. }
    if CP < MinCP then Exit(False);
    if (CP >= $D800) and (CP <= $DFFF) then Exit(False);
    if CP > $10FFFF then Exit(False);

    Inc(I, Extra + 1);
  end;
end;

function EnsureUtf8Bytes(const ABytes: TBytes): TBytes;
var
  N     : Integer   ;
  Enc   : TEncoding ;
  S     : string    ;
begin
  N:= Length(ABytes);
  if N = 0 then Exit(nil);

  { UTF-8 BOM (EF BB BF): strip it; the remainder is already UTF-8. }
  if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    SetLength(Result, N - 3);
    if N - 3 > 0 then Move(ABytes[3], Result[0], N - 3);
    { A BOM file can still carry a stray ANSI byte (B07): fall back to CP1252 for the remainder. }
    if not IsValidUtf8(Result) then
    begin
      Enc:= TEncoding.GetEncoding(CP_ANSI_LATIN);
      try
        S:= Enc.GetString(Result);
      finally
        Enc.Free;
      end;
      Result:= TEncoding.UTF8.GetBytes(S);
    end;
    Exit;
  end;

  { UTF-16 LE BOM (FF FE) -> decode as UTF-16LE, re-encode UTF-8. }
  if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    S:= TEncoding.Unicode.GetString(ABytes);           { skips its own BOM }
    Exit(TEncoding.UTF8.GetBytes(S));
  end;

  { UTF-16 BE BOM (FE FF) -> decode as UTF-16BE, re-encode UTF-8. }
  if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    S:= TEncoding.BigEndianUnicode.GetString(ABytes);  { skips its own BOM }
    Exit(TEncoding.UTF8.GetBytes(S));
  end;

  { No BOM: if the bytes are already valid UTF-8, pass them through unchanged
    (this is the pure-ASCII fast path -- ASCII is valid UTF-8). }
  if IsValidUtf8(ABytes) then Exit(ABytes);

  { Otherwise treat as ANSI (Windows-1252) and transcode to UTF-8. }
  Enc:= TEncoding.GetEncoding(1252);
  try
    S:= Enc.GetString(ABytes);
  finally
    Enc.Free;  { GetEncoding returns an encoding the caller must free }
  end;
  Result:= TEncoding.UTF8.GetBytes(S);
end;

function Utf8ByteColToCharCol(const ASource: TBytes; AByteOffset, AByteColumn: Cardinal): Integer;
const
  UTF8_CONT_FIRST = $80; { 10xxxxxx: a continuation byte, no character of its own }
  UTF8_LEAD2_FIRST = $C0; { 110xxxxx / 1110xxxx: a BMP character, one UTF-16 unit }
  UTF8_LEAD4_FIRST = $F0; { 11110xxx: outside the BMP, a surrogate pair }
begin
  Result:= Integer(AByteColumn);
  if (AByteColumn = 0) or (AByteColumn > AByteOffset) or (AByteOffset > Cardinal(Length(ASource))) then Exit;
  Result:= 0;
  for var I: Integer:= Integer(AByteOffset - AByteColumn) to Integer(AByteOffset) - 1 do
  begin
    var B: Byte:= ASource[I];
    if B < UTF8_CONT_FIRST then Inc(Result)
    else if B >= UTF8_LEAD4_FIRST then Inc(Result, 2)
    else if B >= UTF8_LEAD2_FIRST then Inc(Result);
  end;
end;

function Utf8CharColToByteCol(const ASource: TBytes; ALineStart, ACharCol: Integer): Integer;
const
  LF = 10;
  UTF8_CONT_FIRST = $80;
  UTF8_LEAD2_FIRST = $C0;
  UTF8_LEAD4_FIRST = $F0;
begin
  if ALineStart < 0 then Exit(ACharCol);
  var Units: Integer:= 0;
  var I: Integer:= ALineStart;
  while (Units < ACharCol - 1) and (I < Length(ASource)) and (ASource[I] <> LF) do
  begin
    var B: Byte:= ASource[I];
    if B >= UTF8_LEAD4_FIRST then Inc(Units, 2) else Inc(Units);
    Inc(I);
    while (I < Length(ASource)) and (ASource[I] >= UTF8_CONT_FIRST) and (ASource[I] < UTF8_LEAD2_FIRST) do Inc(I);
  end;
  Result:= I - ALineStart + 1 + (ACharCol - 1 - Units);
end;

function ReadSourceFileLines(const APath: string): TArray<string>;
var
  Lines: TStringList;
begin
  Lines:= TStringList.Create;
  try
    Lines.Text:= TEncoding.UTF8.GetString(EnsureUtf8Bytes(TFile.ReadAllBytes(APath)));
    Result:= Lines.ToStringArray;
  finally
    Lines.Free;
  end; // try
end; // function

function ReadSourceFileText(const APath: string): string;
begin
  Result:= TEncoding.UTF8.GetString(EnsureUtf8Bytes(TFile.ReadAllBytes(APath)));
end; // function

end.
