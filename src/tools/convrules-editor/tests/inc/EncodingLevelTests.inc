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

procedure TestEncodingLevels;
begin
  TestEncodingLevelBasics;
  TestEncodingDetect;
  TestEncodingRoundTrip;
  TestEncodingLost;
  TestEncodingPreSave;
  TestEncodingFile;
end;
