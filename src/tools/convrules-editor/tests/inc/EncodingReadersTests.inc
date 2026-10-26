{ Task 3 (lane C): the curation, catalog and request readers detect the book's encoding, and the
  curation writer keeps the file's level. Fixtures are written at test time (no non-ASCII files in the tree). }

const
  ENC_CYR      = #$0413;
  ENC_BOOK_HDR = '#convert A.TFrom -> B.TTo, B' + #13#10;

function EncLatin1Bytes(const APrefix, ASuffix: string): TBytes;
begin
  Result:= TEncoding.ASCII.GetBytes(APrefix) + TBytes.Create($E9) + TEncoding.ASCII.GetBytes(ASuffix);
end;

function EncLatin1Expected: string;
begin
  Result:= 'caf' + TEncoding.ANSI.GetString(TBytes.Create($E9));
end;

procedure TestEncodingAsk;
var
  Dir, P, B, Msg: string;
  WS     : TWorkingSet;
  Calls  : Integer;
  Seen   : TTextLevel;
  SeenTot: Integer;
  Lv     : TTextLevel;
  Ok     : Boolean;
  Raised : Boolean;
  Text   : string;
  AskYes, AskNo: TRaiseAsk;
begin
  Calls:= 0;
  AskYes:= function(const APath: string; ALevel, ARaiseTo: TTextLevel; const ALost: TArray<TLostChar>; ALostTotal: Integer): Boolean
    begin
      Inc(Calls);
      Seen:= ARaiseTo;
      SeenTot:= ALostTotal;
      Result:= True;
    end;
  AskNo:= function(const APath: string; ALevel, ARaiseTo: TTextLevel; const ALost: TArray<TLostChar>; ALostTotal: Integer): Boolean
    begin
      Inc(Calls);
      Result:= False;
    end;
  Text:= ENC_BOOK_HDR + '// ' + ENC_CYR + #13#10;
  Dir:= TPath.Combine(TPath.GetTempPath, 'enc3ask-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    P:= TPath.Combine(Dir, 'a.rules');
    // SaveFile never raises the level on its own
    TFile.WriteAllBytes(P, TEncoding.ASCII.GetBytes('orig'));
    WS:= TWorkingSet.Create;
    try
      WS.AddTextAt(P, Text, tlAscii7);
      Raised:= False;
      Msg:= '';
      try
        WS.SaveFile(0);
      except
        on E: EInOutError do
        begin
          Raised:= True;
          Msg:= E.Message;
        end;
      end;
      Check('savefile.nofit.raises.untouched', Raised and (Pos('encoding:', Msg) = 1) and (TEncoding.ASCII.GetString(TFile.ReadAllBytes(P)) = 'orig')
        and (WS.LevelOf(0) = tlAscii7) and (not TFile.Exists(P + '.bak')), Msg);
      // Cancel: nothing written, level kept
      Calls:= 0;
      WS.SaveFileAsking(0, AskNo, Ok);
      Check('savefile.asking.cancel', (not Ok) and (Calls = 1) and (TEncoding.ASCII.GetString(TFile.ReadAllBytes(P)) = 'orig')
        and (WS.LevelOf(0) = tlAscii7) and (not TFile.Exists(P + '.bak')));
      // Yes: level raised, written, backup kept
      Calls:= 0;
      B:= WS.SaveFileAsking(0, AskYes, Ok);
      Check('savefile.asking.yes', Ok and (Calls = 1) and (Seen = tlUtf8) and (SeenTot = 1) and (WS.LevelOf(0) = tlUtf8)
        and (DecodeText(TFile.ReadAllBytes(P), tlUtf8) = Text) and (B <> '') and TFile.Exists(B));
      // fits now: no question
      Calls:= 0;
      WS.SaveFileAsking(0, AskNo, Ok);
      Check('savefile.asking.fits.no.question', Ok and (Calls = 0));
      // SetLevel
      WS.SetLevel(0, tlUtf16Bom);
      Check('ws.setlevel', WS.LevelOf(0) = tlUtf16Bom);
      WS.SetLevel(99, tlAscii7);
      Check('ws.setlevel.out.of.range.noop', WS.LevelOf(0) = tlUtf16Bom);
    finally
      WS.Free;
    end;

    // the compose / WriteBlocksTo rule: a NEW target is written at NeededLevel without a question
    P:= TPath.Combine(Dir, 'new.rules');
    Calls:= 0;
    Ok:= WriteTextAskingRaise(P, Text, NeededLevel(Text), AskNo, Lv, B);
    Check('compose.new.target.no.question', Ok and (Calls = 0) and (Lv = NeededLevel(Text)) and (B = '') and (DecodeText(TFile.ReadAllBytes(P), Lv) = Text));
    // an EXISTING target keeps its level: Cancel leaves it untouched ...
    P:= TPath.Combine(Dir, 'old.rules');
    TFile.WriteAllBytes(P, TEncoding.ASCII.GetBytes('orig'));
    Calls:= 0;
    Ok:= WriteTextAskingRaise(P, Text, tlAscii7, AskNo, Lv, B);
    Check('compose.existing.cancel', (not Ok) and (Calls = 1) and (Lv = tlAscii7) and (B = '') and (TEncoding.ASCII.GetString(TFile.ReadAllBytes(P)) = 'orig')
      and (not TFile.Exists(P + '.bak')));
    // ... and a nil question counts as Cancel
    Ok:= WriteTextAskingRaise(P, Text, tlAscii7, nil, Lv, B);
    Check('compose.existing.nil.ask.is.cancel', (not Ok) and (TEncoding.ASCII.GetString(TFile.ReadAllBytes(P)) = 'orig'));
    // ... Yes raises the level
    Calls:= 0;
    Ok:= WriteTextAskingRaise(P, Text, tlAscii7, AskYes, Lv, B);
    Check('compose.existing.yes.raises', Ok and (Calls = 1) and (Lv = tlUtf8) and (B <> '') and (DecodeText(TFile.ReadAllBytes(P), tlUtf8) = Text));
    // text that fits: no question
    Calls:= 0;
    Ok:= WriteTextAskingRaise(P, Text, tlUtf8, AskNo, Lv, B);
    Check('compose.existing.fits.no.question', Ok and (Calls = 0) and (Lv = tlUtf8));
    Msg:= SaveAskMessage('C:\x\book.rules', tlAscii7, tlUtf8, nil, 3);
    Check('ask.message', (Pos('3 character(s) in book.rules', Msg) = 1) and (Pos(LevelName(tlUtf8), Msg) > 0));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestEncodingAddTextAt;
var
  WS: TWorkingSet;
  P: string;
begin
  WS:= TWorkingSet.Create;
  try
    P:= 'C:\x\direct.rules';
    WS.AddTextAt(P, ENC_BOOK_HDR, tlUtf16Bom);
    WS.AddTextAt(P + '2', ENC_BOOK_HDR, tlAscii7);
    Check('addtextat.count', WS.Count = 2);
    Check('addtextat.level.kept.not.needed', (WS.LevelOf(0) = tlUtf16Bom) and (WS.LevelOf(1) = tlAscii7));
    WS.AddText(P + '3', ENC_BOOK_HDR + '// ' + ENC_CYR);
    Check('addtext.level.needed', (WS.LevelOf(2) = NeededLevel(ENC_BOOK_HDR + '// ' + ENC_CYR)) and (WS.LevelOf(2) <> tlAscii7));
    Check('backupnote.some', BackupNote('C:\x\a.rules.bak') = ' (backup a.rules.bak)');
    Check('backupnote.none', BackupNote('') = '');
  finally
    WS.Free;
  end;
end;

procedure TestEncodingReaders;
var
  Dir, P, B, Msg: string;
  WS : TWorkingSet;
  Cat: TRuleCatalog;
  Errs: TArray<string>;
  Names: TArray<string>;
  Sc : TConvertScope;
  Inst: TDfmInstance;
  Raised: Boolean;
  Bytes: TBytes;
  Ansi1252: Boolean;

  ExpEacute: string;

  procedure NewScope(const ATypeName: string);
  begin
    Inst:= Default(TDfmInstance);
    Inst.Name    := 'Label1';
    Inst.TypeName:= ATypeName;
    Sc:= Default(TConvertScope);
    Sc.Kind     := skSelected;
    Sc.UnitPas  := 'P\U.pas';
    Sc.Instances:= [Inst];
  end;

  function FirstTag(const AFolder: string): string;
  begin
    Cat:= ScanRulesFolder(AFolder, Errs);
    if (Length(Cat) = 1) and (Length(Cat[0].Tags) = 1) then
      Result:= Cat[0].Tags[0]
    else
      Result:= '<' + IntToStr(Length(Cat)) + ' entries; errors ' + string.Join('|', Errs) + '>';
  end;

  procedure ClearDir;
  var
    F: string;
  begin
    for F in TDirectory.GetFiles(Dir) do
      TFile.Delete(F);
  end;

begin
  Ansi1252:= GetACP = 1252;
  ExpEacute:= EncLatin1Expected;
  Dir:= TPath.Combine(TPath.GetTempPath, 'enc3-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    // ---- curation: TWorkingSet.AddFile / write ----
    P:= TPath.Combine(Dir, 'ws.rules');
    TFile.WriteAllBytes(P, EncodeText(ENC_BOOK_HDR + '#tag x' + ENC_CYR + #13#10, tlUtf8Bom));
    WS:= TWorkingSet.Create;
    try
      WS.AddFile(P);
      Check('ws.addfile.level', (WS.LevelOf(0) = tlUtf8Bom) and (Pos(ENC_CYR, JoinBlocks(WS.Item(0).Blocks)) > 0));
      Check('curation.reads.utf8.book', Pos(ENC_CYR, JoinBlocks(WS.Item(0).Blocks)) > 0);
      WS.AddText(TPath.Combine(Dir, 'plain.rules'), ENC_BOOK_HDR);
      Check('ws.addtext.level', WS.LevelOf(1) = tlAscii7);
      WS.AddText(TPath.Combine(Dir, 'wide.rules'), ENC_BOOK_HDR + '#tag x' + ENC_CYR + #13#10);
      Check('ws.addtext.level.needed', WS.LevelOf(2) = NeededLevel(ENC_BOOK_HDR + '#tag x' + ENC_CYR + #13#10));
    finally
      WS.Free;
    end;

    P:= TPath.Combine(Dir, 'at.rules');
    WriteTextWithBackupAt(P, 'a' + ENC_CYR, tlUtf8, B);
    Bytes:= TFile.ReadAllBytes(P);
    Check('ws.write.at.level', (B = '') and (Length(Bytes) = Length(EncodeText('a' + ENC_CYR, tlUtf8))) and (DecodeText(Bytes, tlUtf8) = 'a' + ENC_CYR));
    WriteTextWithBackupAt(P, 'b' + ENC_CYR, tlUtf8, B);
    Check('ws.write.at.backup', (B <> '') and TFile.Exists(B));

    P:= TPath.Combine(Dir, 'lossy.rules');
    TFile.WriteAllBytes(P, TEncoding.ASCII.GetBytes('orig'));
    Raised:= False;
    Msg:= '';
    try
      WriteTextWithBackupAt(P, 'a' + ENC_CYR, tlAscii7, B);
    except
      on E: EInOutError do
      begin
        Raised:= True;
        Msg:= E.Message;
      end;
    end;
    Check('ws.write.lossy.raises', Raised and (Pos('encoding:', Msg) = 1) and (TEncoding.ASCII.GetString(TFile.ReadAllBytes(P)) = 'orig'), Msg);

    P:= TPath.Combine(Dir, 'legacy.rules');
    WriteTextWithBackup(P, 'a' + ENC_CYR, B);
    Check('ws.write.legacy.lossless', DecodeText(TFile.ReadAllBytes(P), tlUtf8) = 'a' + ENC_CYR);
    ClearDir;

    // ---- catalog: ScanRulesFolder ----
    P:= TPath.Combine(Dir, 'c.rules');
    TFile.WriteAllBytes(P, EncodeText(ENC_BOOK_HDR + '#tag x' + ENC_CYR + #13#10, tlUtf8));
    Check('catalog.reads.utf8.book', FirstTag(Dir) = 'x' + ENC_CYR, FirstTag(Dir));
    if Ansi1252 then
    begin
      TFile.WriteAllBytes(P, EncLatin1Bytes(ENC_BOOK_HDR + '#tag caf', #13#10));
      Check('catalog.reads.latin1.book', FirstTag(Dir) = ExpEacute, FirstTag(Dir));
    end
    else
      Skip('catalog.reads.latin1.book', 'ANSI code page is not 1252');
    TFile.WriteAllBytes(P, EncodeText(ENC_BOOK_HDR + '#tag abc' + #13#10 + '#default Caption = ''x''' + #13#10, tlUtf16));
    Check('catalog.reads.utf16.book', FirstTag(Dir) = 'abc', FirstTag(Dir));
    ClearDir;

    // ---- request: ScopedNamesForBookFile ----
    P:= TPath.Combine(Dir, 'r.rules');
    NewScope('TLabel' + ENC_CYR);
    TFile.WriteAllBytes(P, EncodeText('#convert TLabel' + ENC_CYR + ' -> TStaticText' + #13#10, tlUtf8));
    Check('request.reads.utf8.book', ScopedNamesForBookFile(Sc, 'P\U.pas', P, Names) and (string.Join(',', Names) = 'Label1'), string.Join(',', Names));
    if Ansi1252 then
    begin
      NewScope('TL' + TEncoding.ANSI.GetString(TBytes.Create($E9)) + 'bel');
      TFile.WriteAllBytes(P, EncLatin1Bytes('#convert TL', 'bel -> TStaticText' + #13#10));
      Check('request.reads.latin1.book', ScopedNamesForBookFile(Sc, 'P\U.pas', P, Names) and (string.Join(',', Names) = 'Label1'), string.Join(',', Names));
    end
    else
      Skip('request.reads.latin1.book', 'ANSI code page is not 1252');
    NewScope('TLabel');
    TFile.WriteAllBytes(P, EncodeText('#convert TLabel -> TStaticText' + #13#10 + '#link Caption <- Caption' + #13#10, tlUtf16));
    Check('request.reads.utf16.book', ScopedNamesForBookFile(Sc, 'P\U.pas', P, Names) and (string.Join(',', Names) = 'Label1'), string.Join(',', Names));
    ClearDir;

    // ---- curation reader on Latin-1 / UTF-16 ----
    P:= TPath.Combine(Dir, 'cur.rules');
    WS:= TWorkingSet.Create;
    try
      if Ansi1252 then
      begin
        TFile.WriteAllBytes(P, EncLatin1Bytes(ENC_BOOK_HDR + '// caf', #13#10));
        WS.AddFile(P);
        Check('curation.reads.latin1.book', (Pos(ExpEacute, JoinBlocks(WS.Item(WS.Count - 1).Blocks)) > 0) and (WS.LevelOf(WS.Count - 1) = tlAscii8));
      end
      else
        Skip('curation.reads.latin1.book', 'ANSI code page is not 1252');
      TFile.WriteAllBytes(P, EncodeText(ENC_BOOK_HDR + '// abc' + #13#10 + '#default Caption = ''x''' + #13#10, tlUtf16));
      WS.AddFile(P);
      Check('curation.reads.utf16.book', (Pos('// abc', JoinBlocks(WS.Item(WS.Count - 1).Blocks)) > 0) and (WS.LevelOf(WS.Count - 1) = tlUtf16));
    finally
      WS.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
  TestEncodingAsk;
  TestEncodingAddTextAt;
end;
