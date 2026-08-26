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
/// <para>Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.Closure.TClosureResolver.MaybePreprocess (DRagLint.Index.Closure.pas), DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition (DRagLint.LSP.Server.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas)</para>
/// <para>Calls: DRagLint.Core.Encoding.IsValidUtf8, Move</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 43 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Encoding.IsValidUtf8"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EnsureUtf8Bytes(const ABytes: TBytes): TBytes;

implementation

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

end.
