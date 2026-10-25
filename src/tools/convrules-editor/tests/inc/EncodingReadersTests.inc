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
end;
