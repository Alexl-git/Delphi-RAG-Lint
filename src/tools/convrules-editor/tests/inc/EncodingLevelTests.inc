{ ConvRules.TextEncoding: the ladder, detection, round trip, lost characters, pre-save decision. }

function EncBytesEqual(const A, B: TBytes): Boolean;
begin
  Result:= (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure TestEncodingLevelBasics;
var
  L, X: TTextLevel;
  AllOk: Boolean;
begin
  Check('rank.order', (LevelRank(tlAscii7) = 0) and (LevelRank(tlAscii8) = 1) and (LevelRank(tlUtf8) = 2)
    and (LevelRank(tlUtf8Bom) = 2) and (LevelRank(tlUtf16) = 3) and (LevelRank(tlUtf16Bom) = 3));
  AllOk:= True;
  for L:= Low(TTextLevel) to High(TTextLevel) do
    if not (LevelFromName(LevelName(L), X) and (X = L)) then
      AllOk:= False;
  Check('name.roundtrip', AllOk);
  Check('save.level.d-b', (SaveLevelFor(tlUtf16) = tlUtf16Bom) and (SaveLevelFor(tlUtf8) = tlUtf8));
  Check('raise.target', (RaiseTarget(tlAscii7, tlUtf8) = tlUtf8) and (RaiseTarget(tlAscii8, tlUtf8) = tlUtf8)
    and (RaiseTarget(tlUtf8Bom, tlUtf8) = tlUtf8Bom));
  Check('lower.offer', (LowerOffer(tlUtf16Bom, tlAscii7) = tlAscii7) and (LowerOffer(tlUtf16, tlUtf8) = tlUtf8)
    and (LowerOffer(tlUtf16Bom, tlAscii8) = tlUtf8) and (LowerOffer(tlUtf8Bom, tlAscii7) = tlUtf8Bom) and (LowerOffer(tlUtf16Bom, tlUtf16) = tlUtf16Bom));
end;

procedure TestEncodingDetect;
var
  D: TDetectedText;
  Utf8Text: string;
  B: TBytes;
begin
  D:= DetectTextLevel(nil);
  Check('detect.empty', (D.Level = tlAscii7) and D.Sure);
  D:= DetectTextLevel(TEncoding.ANSI.GetBytes('abc'#13#10));
  Check('detect.ascii7', D.Level = tlAscii7);
  Utf8Text:= 'Gr'#$00F6'sse';
  D:= DetectTextLevel(TEncoding.UTF8.GetBytes(Utf8Text));
  Check('detect.utf8.nobom', (D.Level = tlUtf8) and D.Sure);
  D:= DetectTextLevel(TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(Utf8Text));
  Check('detect.utf8.bom', D.Level = tlUtf8Bom);
  D:= DetectTextLevel(TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes('ab'));
  Check('detect.utf16.bom', D.Level = tlUtf16Bom);
  B:= TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes('ab');
  D:= DetectTextLevel(B);
  Check('detect.utf16be.bom', (D.Level = tlUtf16Bom) and (DecodeText(B, tlUtf16Bom) = 'ab'));
  D:= DetectTextLevel(TEncoding.Unicode.GetBytes('#convert A -> B, U'));
  Check('detect.utf16.nobom', (D.Level = tlUtf16) and D.Sure);
  D:= DetectTextLevel(TEncoding.Unicode.GetBytes('a'));
  Check('detect.utf16.short.unsure', (D.Level = tlAscii8) and (not D.Sure) and (D.Note = DETECT_UTF16_UNSURE));
  B:= TEncoding.ANSI.GetBytes('abcdefghijklmnopqrst');
  B[9]:= 0;
  D:= DetectTextLevel(B);
  Check('detect.ascii.with.nul.nosuspect', (D.Level = tlAscii8) and D.Sure and (D.Note = ''));
  D:= DetectTextLevel(TBytes.Create($47, $72, $E9));
  Check('detect.latin1.ascii8', (D.Level = tlAscii8) and D.Sure);
end;

procedure TestEncodingRoundTrip;
var
  B: TBytes;
begin
  if TEncoding.ANSI.CodePage <> 1252 then
    Skip('roundtrip.ascii8.bytes', 'ANSI code page is not 1252')
  else
  begin
    B:= TBytes.Create($47, $72, $E9);
    Check('roundtrip.ascii8.bytes', EncBytesEqual(EncodeText(DecodeText(B, tlAscii8), tlAscii8), B));
  end;
  Check('needed.ascii7', NeededLevel('abc') = tlAscii7);
  if TEncoding.ANSI.CodePage <> 1252 then
    Skip('needed.ascii8', 'ANSI code page is not 1252')
  else
    Check('needed.ascii8', NeededLevel('Gr'#$00F6'sse') = tlAscii8);
  Check('needed.utf8', NeededLevel('A'#$0413) = tlUtf8);
  Check('roundtrip.utf16.astral', RoundTrips(#$D83D#$DE00, tlUtf16Bom));
end;

procedure TestEncodingLost;
var
  Lost: TArray<TLostChar>;
  T, I: Integer;
  S: string;
  E: TLostChar;
begin
  Lost:= LostChars('a'#13#10'b'#$00F6#$00F6'c'#$0413, tlAscii7, 8, T);
  Check('lost.ascii7', (Length(Lost) = 2) and (T = 2) and (Lost[0].Code = $F6) and (Lost[0].Line = 2)
    and (Lost[0].Col = 2) and (Lost[1].Code = $413));
  S:= '';
  for I:= 0 to 9 do
    S:= S + Char($0400 + I);
  Lost:= LostChars(S, tlAscii7, 8, T);
  Check('lost.max', (Length(Lost) = 8) and (T = 10));
  Lost:= LostChars(#$D83D#$DE00, tlAscii7, 8, T);
  Check('lost.surrogate.pair', (Length(Lost) = 1) and (Lost[0].Code = $1F600));
  E.Code:= $F6;
  E.Line:= 2;
  E.Col:= 2;
  Check('lost.text', LostCharsText(TArray<TLostChar>.Create(E)) = 'line 2: U+00F6');
end;

procedure TestEncodingPreSave;
var
  P: TPreSaveDecision;
begin
  P:= PreSaveDecision('#use A', tlAscii7);
  Check('presave.ascii.silent', (P.Action = psaWrite) and (P.WriteLevel = tlAscii7) and (P.Note = ''));
  P:= PreSaveDecision('#default Caption = '''#$0413'''', tlAscii7);
  Check('presave.ask', (P.Action = psaAsk) and (P.RaiseTo = tlUtf8) and (P.LostTotal = 1)
    and (Length(P.Lost) = 1) and (P.Lost[0].Code = $413));
  P:= PreSaveDecision('x'#$0413, tlUtf8);
  Check('presave.fits.note', (P.Action = psaWrite) and (P.Note = Format(NOTE_FITS_AFTER_ALL, ['UTF-8'])));
  P:= PreSaveDecision('abc', tlUtf16);
  Check('presave.utf16.bom', (P.Action = psaWrite) and (P.WriteLevel = tlUtf16Bom) and (P.Note = NOTE_UTF16_BOM_ADDED));
end;

procedure TestEncodingFile;
var
  Tmp: string;
  D: TDetectedText;
  Text: string;
begin
  Tmp:= TPath.GetTempFileName;
  try
    WriteTextAtLevel(Tmp, 'Gr'#$00F6, tlUtf8Bom);
    Text:= ReadTextDetect(Tmp, D);
    Check('file.roundtrip', (Text = 'Gr'#$00F6) and (D.Level = tlUtf8Bom));
  finally
    TFile.Delete(Tmp);
  end;
end;

procedure TestEncodingBookState;
var
  D: TPreSaveDecision;
  Noted: Boolean;
begin
  // BookIsDirty: text OR encoding differing from the last load / save
  Check('dirty.clean', not BookIsDirty('a', 'a', tlUtf8, tlUtf8));
  Check('dirty.text', BookIsDirty('a', 'b', tlUtf8, tlUtf8));
  Check('dirty.level.only', BookIsDirty('a', 'a', tlUtf16Bom, tlUtf8));
  Check('dirty.both', BookIsDirty('a', 'b', tlAscii7, tlUtf8));
  // Utf16BomNote: the BOM note once per open book, any other note every time
  D:= PreSaveDecision('abc', tlUtf16);
  Noted:= False;
  Check('bomnote.first', (Utf16BomNote(D, Noted) = ' ' + NOTE_UTF16_BOM_ADDED) and Noted);
  Check('bomnote.second.silent', (Utf16BomNote(D, Noted) = '') and Noted);
  Noted:= False;
  D:= PreSaveDecision('x'#$0413, tlUtf8);
  Check('bomnote.other.always', (Utf16BomNote(D, Noted) = ' ' + Format(NOTE_FITS_AFTER_ALL, ['UTF-8'])) and (not Noted)
    and (Utf16BomNote(D, Noted) <> ''));
  D:= PreSaveDecision('#use A', tlAscii7);
  Check('bomnote.none', (Utf16BomNote(D, Noted) = '') and (not Noted));
end;

// ENC-a (Task 1 deferred minors) and TK: detect branches, surrogate columns, lone surrogate,
// BOM sniffing and a byte-exact non-ASCII Save round trip.
procedure TestEncodingDeferredMinors;
const
  CYR = #$0413;
var
  D: TDetectedText;
  B: TBytes;
  Lost: TArray<TLostChar>;
  Total: Integer;
  P: TPreSaveDecision;
  Tmp, Text: string;
  Got: TBytes;
  Level: TTextLevel;
begin
  // --- UTF-16 detection: an ODD byte count is never sure, even at share 1.0 ---
  B:= TEncoding.Unicode.GetBytes('abcdefgh') + TBytes.Create($41);
  D:= DetectTextLevel(B);
  Check('detect.utf16.odd.length.unsure', (D.Level = tlAscii8) and (not D.Sure) and (D.Note = DETECT_UTF16_UNSURE));
  // --- share between SUSPECT (0.5) and SURE (0.9): 5 of 8 odd bytes are NUL = 0.625 ---
  B:= TEncoding.Unicode.GetBytes('abcdefgh');
  B[1]:= $41;
  B[3]:= $41;
  B[5]:= $41;
  D:= DetectTextLevel(B);
  Check('detect.utf16.share.mid.unsure', (D.Level = tlAscii8) and (not D.Sure) and (D.Note = DETECT_UTF16_UNSURE));
  // --- a NUL under the suspect share (1 of 8 odd bytes = 0.125) is plain ANSI, sure, no note ---
  B:= TEncoding.ANSI.GetBytes('abcdefghijklmnop');
  B[1]:= 0;
  D:= DetectTextLevel(B);
  Check('detect.nul.low.share.sure', (D.Level = tlAscii8) and D.Sure and (D.Note = ''));
  // --- strict UTF-8: overlong, truncated tail, bad continuation byte are NOT UTF-8 ---
  D:= DetectTextLevel(TBytes.Create($61, $C0, $80));
  Check('detect.utf8.overlong.c0', (D.Level = tlAscii8) and D.Sure);
  D:= DetectTextLevel(TBytes.Create($61, $E0, $80, $80));
  Check('detect.utf8.overlong.e0', D.Level = tlAscii8);
  D:= DetectTextLevel(TBytes.Create($61, $C3));
  Check('detect.utf8.truncated.tail', D.Level = tlAscii8);
  D:= DetectTextLevel(TBytes.Create($C3, $41));
  Check('detect.utf8.bad.continuation', D.Level = tlAscii8);
  D:= DetectTextLevel(TBytes.Create($C3, $A9));
  Check('detect.utf8.valid.at.end', D.Level = tlUtf8);
  // --- FF FE first is read as a UTF-16 BOM even when the file is Latin-1 (inherent to BOM sniffing) ---
  D:= DetectTextLevel(TBytes.Create($FF, $FE, $61, $62));
  Check('detect.ff.fe.latin1.is.utf16.bom', D.Level = tlUtf16Bom);

  // --- LostChars columns count UTF-16 units: a surrogate pair is 2 columns ---
  Lost:= LostChars(#$D83D#$DE00'x'#$0413, tlAscii7, 8, Total);
  Check('lost.col.after.surrogate', (Total = 2) and (Length(Lost) = 2) and (Lost[0].Col = 1) and (Lost[1].Col = 4) and (Lost[1].Line = 1),
    IntToStr(Lost[1].Col));
  // --- a lone surrogate cannot be written at UTF-8: asked, and the raise target is UTF-16 with BOM
  //     (owner ruling 2026-10-26; this pin was RaiseTo = tlUtf8, a no-op offer) ---
  P:= PreSaveDecision('a'#$D83D'b', tlUtf8);
  Check('presave.lone.surrogate.utf8', (P.Action = psaAsk) and (P.LostTotal = 1) and (P.Lost[0].Code = $D83D) and (P.RaiseTo = tlUtf16Bom),
    LevelName(P.RaiseTo));
  P:= PreSaveDecision('a'#$D83D'b', tlAscii7);
  Check('presave.lone.surrogate.ascii7', (P.Action = psaAsk) and (P.RaiseTo = tlUtf16Bom), LevelName(P.RaiseTo));
  P:= PreSaveDecision('a'#$D83D'b', tlUtf16Bom);
  Check('presave.lone.surrogate.utf16.writes', (P.Action = psaWrite) and (P.WriteLevel = tlUtf16Bom));
  Check('needed.lone.surrogate', NeededLevel('a'#$D83D'b') = tlUtf16Bom, LevelName(NeededLevel('a'#$D83D'b')));
  Check('lower.offer.lone.surrogate.none', LowerOffer(tlUtf16Bom, NeededLevel('a'#$D83D'b')) = tlUtf16Bom);
  Check('lost.text.lone.surrogate.says.so', LostCharsText(LostChars('a'#$D83D'b', tlUtf8, 8, Total)).Contains('lone surrogate'),
    LostCharsText(LostChars('a'#$D83D'b', tlUtf8, 8, Total)));
  Check('lost.text.plain.unchanged', LostCharsText(LostChars('a'#$0413, tlAscii7, 8, Total)) = 'line 1: U+0413');

  // --- RaiseTarget: ASCII levels go to UTF-8; a UTF level stays; text that needs UTF-16 gets UTF-16 with BOM ---
  Check('raise.target.utf16.stays', (RaiseTarget(tlUtf16, tlUtf8) = tlUtf16) and (RaiseTarget(tlUtf16Bom, tlUtf8) = tlUtf16Bom)
    and (RaiseTarget(tlUtf8, tlUtf8) = tlUtf8));
  Check('raise.target.needs.utf16', (RaiseTarget(tlUtf8, tlUtf16Bom) = tlUtf16Bom) and (RaiseTarget(tlAscii7, tlUtf16Bom) = tlUtf16Bom)
    and (RaiseTarget(tlUtf8Bom, tlUtf16Bom) = tlUtf16Bom));

  // --- non-ASCII Save round trip: the exact bytes on disk, and the text and level read back ---
  Tmp:= TPath.GetTempFileName;
  try
    Text:= 'a' + CYR;
    for Level in [tlUtf8, tlUtf8Bom, tlUtf16, tlUtf16Bom] do
    begin
      P:= PreSaveDecision(Text, Level);
      WriteTextAtLevel(Tmp, Text, P.WriteLevel);
      Got:= TFile.ReadAllBytes(Tmp);
      case Level of
        tlUtf8: B:= TBytes.Create($61, $D0, $93);
        tlUtf8Bom: B:= TBytes.Create($EF, $BB, $BF, $61, $D0, $93);
      else
        B:= TBytes.Create($FF, $FE, $61, $00, $13, $04); // tlUtf16 is saved WITH a BOM (D-B)
      end;
      Check('save.bytes.exact.' + LevelName(Level), (P.Action = psaWrite) and EncBytesEqual(Got, B));
      Check('save.readback.' + LevelName(Level), (ReadTextDetect(Tmp, D) = Text) and (D.Level = P.WriteLevel));
    end;
  finally
    TFile.Delete(Tmp);
  end;
end;

procedure TestEncodingLevels;
begin
  TestEncodingLevelBasics;
  TestEncodingDetect;
  TestEncodingRoundTrip;
  TestEncodingLost;
  TestEncodingPreSave;
  TestEncodingFile;
  TestEncodingBookState;
  TestEncodingDeferredMinors;
end;
