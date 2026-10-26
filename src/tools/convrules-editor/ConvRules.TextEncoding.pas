unit ConvRules.TextEncoding;

{ The text-encoding ladder of the rule-book files: detection, decode / encode,
  round-trip test, the characters a lower level would lose, and the pre-save
  decision. Pure: no forms, no engine. Spec:
  docs\superpowers\specs\2026-10-25-converter-text-encoding-design.md }

interface

uses
  System.SysUtils
  , System.IOUtils
  , System.Character
  , System.Generics.Collections;

type
  /// <summary>Ladder, lowest first. BOM variants are the same LEVEL as their base
  /// (LevelRank: Ascii7=0, Ascii8=1, Utf8=Utf8Bom=2, Utf16=Utf16Bom=3).</summary>
  TTextLevel = (tlAscii7, tlAscii8, tlUtf8, tlUtf8Bom, tlUtf16, tlUtf16Bom);

  /// <summary>Result of <see cref="DetectTextLevel"/>.</summary>
  TDetectedText = record
    Level: TTextLevel;
    /// <summary>False only for the "UTF-16 suspected" fallback to tlAscii8.</summary>
    Sure : Boolean;
    /// <summary>'' when Sure; else DETECT_UTF16_UNSURE.</summary>
    Note : string;
  end;

  /// <summary>One character a level cannot hold.</summary>
  TLostChar = record
    /// <summary>Unicode code point (a surrogate pair is ONE entry).</summary>
    Code: Integer;
    /// <summary>1-based line of the first occurrence (lines split on #10).</summary>
    Line: Integer;
    /// <summary>1-based Char index in that line.</summary>
    Col : Integer;
  end;

  /// <summary>What a save does: write silently, or ask first.</summary>
  TPreSaveAction = (psaWrite, psaAsk);

  /// <summary>Outcome of <see cref="PreSaveDecision"/>.</summary>
  TPreSaveDecision = record
    Action    : TPreSaveAction;
    /// <summary>The level to write at when Action = psaWrite.</summary>
    WriteLevel: TTextLevel;
    /// <summary>The level offered when Action = psaAsk.</summary>
    RaiseTo   : TTextLevel;
    /// <summary>First LOST_CHARS_SHOWN of them when psaAsk.</summary>
    Lost      : TArray<TLostChar>;
    LostTotal : Integer;
    /// <summary>Status-line tail for psaWrite ('' for the all-ASCII user).</summary>
    Note      : string;
  end;

const
  LOST_CHARS_SHOWN     = 8;
  UTF16_PROBE_BYTES    = 512;
  UTF16_MIN_BYTES      = 4;
  /// <summary>Share of odd-index zero bytes that makes BOM-less UTF-16 "sure".</summary>
  UTF16_SURE_RATIO     = 0.9;
  /// <summary>From here up to SURE: tlAscii8, Sure=False, Note=DETECT_UTF16_UNSURE.</summary>
  UTF16_SUSPECT_RATIO  = 0.5;
  DETECT_UTF16_UNSURE  = 'UTF-16 without BOM suspected but not sure -- read as ASCII-8 (ANSI)';
  NOTE_FITS_AFTER_ALL  = 'Encoding checked: every character fits %s.';
  NOTE_UTF16_BOM_ADDED = 'UTF-16 saved with a BOM (the engine cannot read UTF-16 without one).';
  ASK_SAVE_FMT         = '%d character(s) in %s cannot be saved as %s and would become "?":%s%s%sYes = save the book as %s instead (nothing is lost). Cancel = do not save.';

/// <summary>Rank of a level on the ladder: Ascii7=0, Ascii8=1, Utf8/Utf8Bom=2, Utf16/Utf16Bom=3.</summary>
/// <param name="ALevel">The level to rank.</param>
/// <returns>0..3 as described above.</returns>
function LevelRank(ALevel: TTextLevel): Integer;

/// <summary>Display name: 'ASCII-7' | 'ASCII-8 (ANSI code page N)' | 'UTF-8' | 'UTF-8 with BOM' | 'UTF-16' | 'UTF-16 with BOM'.</summary>
/// <param name="ALevel">The level to name.</param>
/// <returns>The display name.</returns>
function LevelName(ALevel: TTextLevel): string;

/// <summary>Inverse of <see cref="LevelName"/>, case-insensitive; 'ASCII-8' with any suffix.</summary>
/// <returns>False (ALevel = tlAscii7) when the name is unknown.</returns>
/// <param name="AName">A display name as produced by LevelName.</param>
/// <param name="ALevel">The parsed level; tlAscii7 when the name is unknown.</param>
function LevelFromName(const AName: string; out ALevel: TTextLevel): Boolean;  // dl:ok unused-public-symbol@8d2e -- REVIEWED 2026-10-26 LevelFromName is pinned by the model test name.roundtrip, which are outside this project's index

/// <summary>Classifies raw file bytes (BOM, ASCII, strict UTF-8, BOM-less UTF-16 probe, else ASCII-8).</summary>
/// <remarks>Order: empty = tlAscii7; BOM; if any NUL byte occurs in the first UTF16_PROBE_BYTES the UTF-16 probe decides ALONE (tlUtf16 sure / tlAscii8 unsure with Note / tlAscii8 sure); only without a NUL: all bytes below 128 = tlAscii7, strict UTF-8 = tlUtf8, else tlAscii8.</remarks>
/// <param name="ABytes">Raw file bytes.</param>
/// <returns>The detected level, sureness and note.</returns>
function DetectTextLevel(const ABytes: TBytes): TDetectedText;

/// <summary>Decodes bytes at a level; strips the BOM of a BOM level. A UTF-16 BE BOM decodes big-endian.</summary>
/// <param name="ABytes">Raw file bytes, with the BOM of a BOM level if any.</param>
/// <param name="ALevel">The level to decode at.</param>
/// <returns>The decoded text without BOM.</returns>
function DecodeText(const ABytes: TBytes; ALevel: TTextLevel): string;

/// <summary>Encodes text at a level; Utf8Bom / Utf16Bom prepend the preamble; UTF-16 is little-endian.
/// Characters the level cannot hold become '?'.</summary>
/// <param name="AText">The text to encode.</param>
/// <param name="ALevel">The level to encode at.</param>
/// <returns>The encoded bytes, preamble first for a BOM level.</returns>
function EncodeText(const AText: string; ALevel: TTextLevel): TBytes;

/// <summary>True when DecodeText(EncodeText(AText, L), L) = AText.</summary>
/// <param name="AText">The text to test.</param>
/// <param name="ALevel">The level to test at.</param>
/// <returns>True when nothing is lost at ALevel.</returns>
function RoundTrips(const AText: string; ALevel: TTextLevel): Boolean;

/// <summary>Lowest of tlAscii7, tlAscii8, tlUtf8 that round-trips the text.</summary>
/// <param name="AText">The text to test.</param>
/// <returns>The lowest sufficient level.</returns>
function NeededLevel(const AText: string): TTextLevel;

/// <summary>Distinct characters (by code point, first occurrence) that ALevel cannot hold.</summary>
/// <param name="AText">The text to scan.</param>
/// <param name="ALevel">The level that must hold it.</param>
/// <param name="AMax">At most this many entries are returned.</param>
/// <param name="ATotal">Number of distinct lost characters (not capped).</param>
/// <returns>Up to AMax lost characters in order of first occurrence.</returns>
function LostChars(const AText: string; ALevel: TTextLevel; AMax: Integer; out ATotal: Integer): TArray<TLostChar>;

/// <summary>One 'line N: U+XXXX' per entry, joined with sLineBreak.</summary>
/// <param name="ALost">Entries as returned by LostChars.</param>
/// <returns>The joined listing; empty for an empty array.</returns>
function LostCharsText(const ALost: TArray<TLostChar>): string;

/// <summary>The level a save writes at: tlUtf16 becomes tlUtf16Bom (D-B), others stay.</summary>
/// <param name="ACurrent">The book's current level.</param>
/// <returns>The level a save writes at.</returns>
function SaveLevelFor(ACurrent: TTextLevel): TTextLevel;

/// <summary>The level offered when the current one loses characters: from tlAscii7 / tlAscii8 it is
/// tlUtf8 (owner default); from a UTF level ACurrent.</summary>
/// <param name="ACurrent">The level that loses characters.</param>
/// <param name="ANeeded">The lowest level that holds the text (NeededLevel).</param>
/// <returns>The level to offer.</returns>
function RaiseTarget(ACurrent, ANeeded: TTextLevel): TTextLevel;

/// <summary>Offers a lower level for a UTF-16 book: ANeeded (tlAscii7/8/Utf8) when ACurrent is UTF-16
/// and LevelRank(ANeeded) &lt; 3; else ACurrent (= no offer).</summary>
/// <remarks>Never offers tlAscii8 (code-page bound; a UTF-16 book was never ASCII-8): ANeeded = tlAscii8 gives tlUtf8.</remarks>
/// <param name="ACurrent">The book's current level.</param>
/// <param name="ANeeded">The lowest level that holds the text (NeededLevel).</param>
/// <returns>The level to offer, or ACurrent when there is no offer.</returns>
function LowerOffer(ACurrent, ANeeded: TTextLevel): TTextLevel;

/// <summary>Decides a save: write at SaveLevelFor(ACurrent) when it round-trips, else ask to raise.</summary>
/// <param name="AText">The text about to be saved.</param>
/// <param name="ACurrent">The book's current level.</param>
/// <returns>Write silently, or ask with the lost characters.</returns>
function PreSaveDecision(const AText: string; ACurrent: TTextLevel): TPreSaveDecision;

/// <summary>Reads a file: bytes, detect, decode.</summary>
/// <remarks>Raises EInOutError (from TFile.ReadAllBytes) when the file cannot be read.</remarks>
/// <param name="APath">The file to read.</param>
/// <param name="ADetected">The detected level of the file.</param>
/// <returns>The decoded text.</returns>
function ReadTextDetect(const APath: string; out ADetected: TDetectedText): string;

/// <summary>Writes the text at the level.</summary>
/// <remarks>The CALLER has checked <see cref="RoundTrips"/>.</remarks>
/// <param name="APath">The file to write.</param>
/// <param name="AText">The text to write.</param>
/// <param name="ALevel">The level to encode at.</param>
procedure WriteTextAtLevel(const APath, AText: string; ALevel: TTextLevel);

implementation

const
  LEVEL_NAME_ASCII7   = 'ASCII-7';
  LEVEL_NAME_ASCII8   = 'ASCII-8';
  LEVEL_NAME_UTF8     = 'UTF-8';
  LEVEL_NAME_UTF8BOM  = 'UTF-8 with BOM';
  LEVEL_NAME_UTF16    = 'UTF-16';
  LEVEL_NAME_UTF16BOM = 'UTF-16 with BOM';
  RANK_ASCII8         = 1;
  RANK_UTF8           = 2;
  RANK_UTF16          = 3;
  BYTE_HIGH_BIT       = $80;
  LAST_ASCII          = $7F;
  LINE_FEED           = #10;
  SURROGATE_FIRST     = $D800;
  SURROGATE_LAST      = $DBFF;
  SURROGATE_LOW_FIRST = $DC00;
  SURROGATE_LOW_LAST  = $DFFF;

function LevelRank(ALevel: TTextLevel): Integer;
begin
  case ALevel of
    tlAscii7: Result:= 0;
    tlAscii8: Result:= RANK_ASCII8;
    tlUtf8, tlUtf8Bom: Result:= RANK_UTF8;
  else
    Result:= RANK_UTF16;
  end;
end;

function LevelName(ALevel: TTextLevel): string;
begin
  case ALevel of
    tlAscii7: Result:= LEVEL_NAME_ASCII7;
    tlAscii8: Result:= Format('%s (ANSI code page %d)', [LEVEL_NAME_ASCII8, TEncoding.ANSI.CodePage]);
    tlUtf8: Result:= LEVEL_NAME_UTF8;
    tlUtf8Bom: Result:= LEVEL_NAME_UTF8BOM;
    tlUtf16: Result:= LEVEL_NAME_UTF16;
  else
    Result:= LEVEL_NAME_UTF16BOM;
  end;
end;

function LevelFromName(const AName: string; out ALevel: TTextLevel): Boolean;
begin
  Result:= True;
  ALevel:= tlAscii7;
  if SameText(AName, LEVEL_NAME_ASCII7) then
    ALevel:= tlAscii7
  else if SameText(Copy(AName, 1, Length(LEVEL_NAME_ASCII8)), LEVEL_NAME_ASCII8) then
    ALevel:= tlAscii8
  else if SameText(AName, LEVEL_NAME_UTF8) then
    ALevel:= tlUtf8
  else if SameText(AName, LEVEL_NAME_UTF8BOM) then
    ALevel:= tlUtf8Bom
  else if SameText(AName, LEVEL_NAME_UTF16) then
    ALevel:= tlUtf16
  else if SameText(AName, LEVEL_NAME_UTF16BOM) then
    ALevel:= tlUtf16Bom
  else
    Result:= False;
end;

{ Strict UTF-8 check: no overlong forms, no surrogates, nothing above U+10FFFF. }
function IsValidUtf8(const ABytes: TBytes): Boolean;
var
  I, N, Need, K: Integer;
  B, B1: Byte;
begin
  Result:= False;
  I:= 0;
  N:= Length(ABytes);
  while I < N do
  begin
    B:= ABytes[I];
    if B <= LAST_ASCII then
    begin
      Inc(I);
      Continue;
    end;
    if (B >= $C2) and (B <= $DF) then  // dl:ok magic-literal@6617 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
      Need:= 1
    else if (B >= $E0) and (B <= $EF) then  // dl:ok magic-literal@af16 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
      Need:= 2
    else if (B >= $F0) and (B <= $F4) then  // dl:ok magic-literal@cde8 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
      Need:= 3  // dl:ok magic-literal@4ff7 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
    else
      Exit;
    if I + Need >= N then
      Exit;
    B1:= ABytes[I + 1];
    if ((B = $E0) and (B1 < $A0)) or ((B = $ED) and (B1 > $9F))  // dl:ok boolean-expression-complexity@f3ca, magic-literal@f3ca -- REVIEWED 2026-10-26 the RFC 3629 second-byte range table (overlong, surrogate and above-U+10FFFF lead bytes), one clause per row; named predicates would hide the table
      or ((B = $F0) and (B1 < $90)) or ((B = $F4) and (B1 > $8F)) then  // dl:ok magic-literal@6ec1 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
      Exit;
    for K:= 1 to Need do
      if (ABytes[I + K] and $C0) <> BYTE_HIGH_BIT then  // dl:ok magic-literal@1370 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
        Exit;
    Inc(I, Need + 1);
  end;
  Result:= True;
end;

{ Share of zero bytes among the odd-index bytes of the first UTF16_PROBE_BYTES. }
function OddZeroShare(const ABytes: TBytes): Double;
var
  I, N, Zeros: Integer;
begin
  N:= Length(ABytes);
  if N > UTF16_PROBE_BYTES then
    N:= UTF16_PROBE_BYTES;
  if N div 2 = 0 then
    Exit(0);
  Zeros:= 0;
  I:= 1;
  while I < N do
  begin
    if ABytes[I] = 0 then
      Inc(Zeros);
    Inc(I, 2);
  end;
  Result:= Zeros / (N div 2);
end;

function DetectTextLevel(const ABytes: TBytes): TDetectedText;  // dl:ok too-many-exit-points@0851 -- REVIEWED 2026-10-26 a flat ladder of BOM / format probes: each Exit returns a settled result, merging them would nest the ladder
var
  N, I: Integer;
  HasZero, HasHigh: Boolean;
  Share: Double;
begin
  Result.Level:= tlAscii7;
  Result.Sure:= True;
  Result.Note:= '';
  N:= Length(ABytes);
  if N = 0 then
    Exit;
  if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then  // dl:ok magic-literal@ceea -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
  begin
    Result.Level:= tlUtf8Bom;
    Exit;
  end;
  if (N >= 2) and (((ABytes[0] = $FF) and (ABytes[1] = $FE)) or ((ABytes[0] = $FE) and (ABytes[1] = $FF))) then  // dl:ok magic-literal@9e74 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
  begin
    Result.Level:= tlUtf16Bom;
    Exit;
  end;
  HasZero:= False;
  HasHigh:= False;
  for I:= 0 to N - 1 do
  begin
    if (ABytes[I] = 0) and (I < UTF16_PROBE_BYTES) then
      HasZero:= True
    else if ABytes[I] > LAST_ASCII then
      HasHigh:= True;
  end;
  if HasZero then
  begin
    Share:= OddZeroShare(ABytes);
    if (N >= UTF16_MIN_BYTES) and (N mod 2 = 0) and (Share >= UTF16_SURE_RATIO) then
    begin
      Result.Level:= tlUtf16;
      Exit;
    end;
    if Share >= UTF16_SUSPECT_RATIO then
    begin
      Result.Level:= tlAscii8;
      Result.Sure:= False;
      Result.Note:= DETECT_UTF16_UNSURE;
      Exit;
    end;
    Result.Level:= tlAscii8;
    Exit;
  end;
  if not HasHigh then
    Result.Level:= tlAscii7
  else if IsValidUtf8(ABytes) then
    Result.Level:= tlUtf8
  else
    Result.Level:= tlAscii8;
end;

function DecodeText(const ABytes: TBytes; ALevel: TTextLevel): string;
var
  Start, Len: Integer;
  Enc: TEncoding;
begin
  Start:= 0;
  Len:= Length(ABytes);
  case ALevel of
    tlAscii7, tlAscii8:
      Result:= TEncoding.ANSI.GetString(ABytes);
    tlUtf8, tlUtf8Bom:
    begin
      if (ALevel = tlUtf8Bom) and (Len >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then  // dl:ok magic-literal@7eec -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
        Start:= 3;  // dl:ok magic-literal@fc77 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
      Result:= TEncoding.UTF8.GetString(ABytes, Start, Len - Start);
    end;
  else
    begin
      Enc:= TEncoding.Unicode;
      if ALevel = tlUtf16Bom then
      begin
        if (Len >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then  // dl:ok magic-literal@5deb -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
          Start:= 2
        else if (Len >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then  // dl:ok magic-literal@d7d6 -- REVIEWED 2026-10-26 RFC 3629 UTF-8 lead/continuation bytes and the Unicode BOM bytes (EF BB BF, FF FE, FE FF); named constants would hide the byte pattern the comment cites
        begin
          Start:= 2;
          Enc:= TEncoding.BigEndianUnicode;
        end;
      end;
      Len:= (Len - Start) and not 1;
      Result:= Enc.GetString(ABytes, Start, Len);
    end;
  end;
end;

function EncodeText(const AText: string; ALevel: TTextLevel): TBytes;
var
  I: Integer;
begin
  case ALevel of
    tlAscii7:
    begin
      Result:= TEncoding.ANSI.GetBytes(AText);
      for I:= 0 to High(Result) do
        if Result[I] > LAST_ASCII then
          Result[I]:= Ord('?');
    end;
    tlAscii8: Result:= TEncoding.ANSI.GetBytes(AText);
    tlUtf8: Result:= TEncoding.UTF8.GetBytes(AText);
    tlUtf8Bom: Result:= TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(AText);
    tlUtf16: Result:= TEncoding.Unicode.GetBytes(AText);
  else
    Result:= TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(AText);
  end;
end;

function RoundTrips(const AText: string; ALevel: TTextLevel): Boolean;
begin
  Result:= DecodeText(EncodeText(AText, ALevel), ALevel) = AText;
end;

function NeededLevel(const AText: string): TTextLevel;
begin
  if RoundTrips(AText, tlAscii7) then
    Result:= tlAscii7
  else if RoundTrips(AText, tlAscii8) then
    Result:= tlAscii8
  else
    Result:= tlUtf8;
end;

function LostChars(const AText: string; ALevel: TTextLevel; AMax: Integer; out ATotal: Integer): TArray<TLostChar>;
var
  Seen: TDictionary<Integer, Boolean>;
  List: TList<TLostChar>;
  I, Line, Col, Code, Width: Integer;
  Item: TLostChar;
  Lost: Boolean;
  C: Char;
begin
  ATotal:= 0;
  Seen:= TDictionary<Integer, Boolean>.Create;
  List:= TList<TLostChar>.Create;
  try
    Line:= 1;
    Col:= 0;
    I:= 1;
    while I <= Length(AText) do
    begin
      C:= AText[I];
      Inc(Col);
      Width:= 1;
      Code:= Ord(C);
      if (Code >= SURROGATE_FIRST) and (Code <= SURROGATE_LAST) and (I < Length(AText))
        and (Ord(AText[I + 1]) >= SURROGATE_LOW_FIRST) and (Ord(AText[I + 1]) <= SURROGATE_LOW_LAST) then
      begin
        Code:= Ord(Char.ConvertToUtf32(C, AText[I + 1]));
        Width:= 2;
      end;
      if C = LINE_FEED then
      begin
        Inc(Line);
        Col:= 0;
      end
      else if (Code > LAST_ASCII) and not Seen.ContainsKey(Code) then
      begin
        Lost:= not RoundTrips(Copy(AText, I, Width), ALevel);
        Seen.Add(Code, Lost);
        if Lost then
        begin
          Inc(ATotal);
          if List.Count < AMax then
          begin
            Item.Code:= Code;
            Item.Line:= Line;
            Item.Col:= Col;
            List.Add(Item);
          end;
        end;
      end;
      Inc(I, Width);
      if Width = 2 then
        Inc(Col);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

function LostCharsText(const ALost: TArray<TLostChar>): string;
var
  I: Integer;
begin
  Result:= '';
  for I:= 0 to High(ALost) do
  begin
    if I > 0 then
      Result:= Result + sLineBreak;  // dl:ok concat-in-loop@c7fe -- REVIEWED 2026-10-26 at most LOST_CHARS_SHOWN entries (a dialog listing), not a hot path
    Result:= Result + Format('line %d: U+%.4X', [ALost[I].Line, ALost[I].Code]);  // dl:ok concat-in-loop@7389 -- REVIEWED 2026-10-26 at most LOST_CHARS_SHOWN entries (a dialog listing), not a hot path
  end;
end;

function SaveLevelFor(ACurrent: TTextLevel): TTextLevel;
begin
  if ACurrent = tlUtf16 then
    Result:= tlUtf16Bom
  else
    Result:= ACurrent;
end;

function RaiseTarget(ACurrent, ANeeded: TTextLevel): TTextLevel;
begin
  if ACurrent in [tlAscii7, tlAscii8] then
    Result:= tlUtf8
  else
    Result:= ACurrent;
  if LevelRank(ANeeded) > LevelRank(Result) then
    Result:= ANeeded;
end;

function LowerOffer(ACurrent, ANeeded: TTextLevel): TTextLevel;
begin
  if (ACurrent in [tlUtf16, tlUtf16Bom]) and (LevelRank(ANeeded) < RANK_UTF16) then
  begin
    if ANeeded = tlAscii8 then
      Result:= tlUtf8
    else
      Result:= ANeeded;
  end
  else
    Result:= ACurrent;
end;

function PreSaveDecision(const AText: string; ACurrent: TTextLevel): TPreSaveDecision;
var
  L, Needed: TTextLevel;
begin
  L:= SaveLevelFor(ACurrent);
  Result.WriteLevel:= L;
  Result.RaiseTo:= L;
  Result.LostTotal:= 0;
  Result.Lost:= nil;
  Result.Note:= '';
  Needed:= NeededLevel(AText);
  if RoundTrips(AText, L) then
  begin
    Result.Action:= psaWrite;
    if ACurrent = tlUtf16 then
      Result.Note:= NOTE_UTF16_BOM_ADDED
    else if LevelRank(Needed) > 0 then
      Result.Note:= Format(NOTE_FITS_AFTER_ALL, [LevelName(L)]);
  end
  else
  begin
    Result.Action:= psaAsk;
    Result.RaiseTo:= RaiseTarget(ACurrent, Needed);
    Result.Lost:= LostChars(AText, L, LOST_CHARS_SHOWN, Result.LostTotal);
  end;
end;

function ReadTextDetect(const APath: string; out ADetected: TDetectedText): string;
var
  Bytes: TBytes;
begin
  Bytes:= TFile.ReadAllBytes(APath);
  ADetected:= DetectTextLevel(Bytes);
  Result:= DecodeText(Bytes, ADetected.Level);
end;

procedure WriteTextAtLevel(const APath, AText: string; ALevel: TTextLevel);
begin
  TFile.WriteAllBytes(APath, EncodeText(AText, ALevel));
end;

end.
