{ apply/1 encoding_refused, the convert_encoding_guard feature, the raise run (Task 5).
  The refused characters are Cyrillic: cp1252 cannot hold them, so the engine refuses them. }

const
  ENC_OK_JSON = '{"schema":"apply/1","mode":"dry-run","ok":true,"error":"","refused":false,"reason":"","rule_errors":[],"edits_count":1}';

function EncRefusedRow(const AUnit: string; AStatus: TConvertStatus; AWithRefusal: Boolean): TConvertRow;
begin
  Result:= Default(TConvertRow);
  Result.UnitPas:= AUnit;
  Result.Status := AStatus;
  Result.Apply.Refused:= AStatus = csRefused;
  if AWithRefusal then
    Result.Apply.EncodingRefusal.FileName:= 'C:\p\Form1.pas';
end;

{ The engine-gated half: a dry convert of a BOM-less ANSI unit whose book writes a Cyrillic name. }
procedure TestEncodingApplyLive;
var
  Exe, Dir, Db, Dpr, UnitPas, Book, Output, Json: string;
  Eng: TEngineAdapter;
  Row: TApplyRow;
begin
  Exe:= ResolveExe;
  if (Exe = '') or not TFile.Exists(LibWin64) then
  begin
    Skip('enc.live.capability', 'exe or library-Win64 absent: ' + GEngineWhy);
    Exit;
  end;
  Eng:= TEngineAdapter.Create(Exe, []);
  try
    if not Eng.HasCapability(CAPABILITY_ENCODING_GUARD) then
    begin
      Skip('enc.live.capability', 'engine lacks ' + CAPABILITY_ENCODING_GUARD);
      Exit;
    end;
  finally
    Eng.Free;
  end; // try
  Dir:= TPath.Combine(TPath.GetTempPath, 'encrun-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Dpr    := TPath.Combine(Dir, 'Fix.dpr');
    UnitPas:= TPath.Combine(Dir, 'FixUnit.pas');
    Db     := TPath.Combine(Dir, 'Fix.sqlite');
    Book   := TPath.Combine(Dir, 'Fix.rules');
    TFile.WriteAllText(Dpr, 'program Fix;' + sLineBreak + 'uses' + sLineBreak + '  FixUnit in ''FixUnit.pas'';' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(UnitPas, 'unit FixUnit;' + sLineBreak + 'interface' + sLineBreak + 'procedure OldName;' + sLineBreak + 'implementation' + sLineBreak +
      'procedure OldName;' + sLineBreak + 'begin' + sLineBreak + 'end;' + sLineBreak + 'procedure Use;' + sLineBreak + 'begin' + sLineBreak + '  OldName;' + sLineBreak +
      'end;' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(Book, '#use New' + Chr($0414) + 'me' + sLineBreak, TEncoding.Unicode);
    Eng:= TEngineAdapter.Create(Exe, [Db, LibWin64]);
    try
      Check('enc.live.index', Eng.IndexProject(Dpr, Db, Output) = 0, Output);
      Eng.ApplyConversion(UnitPas, Book, [Db, LibWin64], nil, Json);
      Row:= ParseApplyJson(Json, APPLY_FEATURES_ALL);
      Check('enc.live.capability', HasEncodingRefusal(Row), Json);
    finally
      Eng.Free;
    end; // try
  finally
    TDirectory.Delete(Dir, True);
  end; // try
end;

procedure TestEncodingApply;
var
  LRow, LAbsent, LBad1, LBad2: TApplyRow;
  LBatch: TApplyBatch;
  LRef  : TEncodingRefusal;
  LJob  : TConvertJob;
  LRows : TArray<TConvertRow>;
  LFiles: TArray<string>;
begin
  Check('enc.feature.map', (afEncodingGuard in ApplyFeaturesOf(['convert_encoding_guard'])) and not (afEncodingGuard in ApplyFeaturesOf(['batch_units'])));

  LRow:= ParseApplyJson(Apply1270Fixture('apply-encoding-refused-contract.json'), []);
  Check('enc.parse.row', LRow.Refused and HasEncodingRefusal(LRow) and LRow.EncodingRefusal.FileName.EndsWith('Form1.pas')
    and (LRow.EncodingRefusal.FileEncoding = 'ansi') and (LRow.EncodingRefusal.RaiseTo = 'utf8-bom') and (LRow.EncodingRefusal.CharsTotal = 2)
    and (Length(LRow.EncodingRefusal.Chars) = 2) and (LRow.EncodingRefusal.Chars[0].Code = $0413) and (LRow.EncodingRefusal.Chars[0].Line = 57)
    and (LRow.EncodingRefusal.Chars[1].Text = Chr($0414)), LRow.EncodingRefusal.FileName);

  LAbsent:= ParseApplyJson(ENC_OK_JSON, []);
  Check('enc.parse.absent', LAbsent.Ok and not HasEncodingRefusal(LAbsent) and (LAbsent.EncodingRefusal.FileName = ''));

  LBad1:= ParseApplyJson('{"schema":"apply/1","ok":false,"refused":true,"reason":"x","encoding_refused":"notanobject"}', []);
  LBad2:= ParseApplyJson('{"schema":"apply/1","ok":false,"refused":true,"reason":"x","encoding_refused":{"file":5,"chars":"no"}}', []);
  Check('enc.parse.badshape', LBad1.Refused and not HasEncodingRefusal(LBad1) and (LBad1.EncodingRefusal.FileName = '')
    and LBad2.Refused and not HasEncodingRefusal(LBad2) and (LBad2.EncodingRefusal.FileName = '') and (Length(LBad2.EncodingRefusal.Chars) = 0));

  LBatch:= ParseApplyBatchJson(Apply1270Fixture('batch-encoding-refused-contract.json'), []);
  Check('enc.parse.batch', LBatch.Valid and (Length(LBatch.Units) = 2) and HasEncodingRefusal(LBatch.Units[1]) and not HasEncodingRefusal(LBatch.Units[0]));

  LRef:= LRow.EncodingRefusal;
  Check('enc.text', EncodingRefusalText(LRef) = 'U+0413 line 57, U+0414 line 60', EncodingRefusalText(LRef));
  LRef.Chars:= LRef.Chars + LRef.Chars + LRef.Chars + LRef.Chars;  // 8 listed
  LRef.CharsTotal:= 10;
  Check('enc.text.more', EncodingRefusalText(LRef).EndsWith(', +2 more'), EncodingRefusalText(LRef));
  LRef:= LRow.EncodingRefusal;
  Check('enc.question', EncodingRaiseQuestion('C:\p\Form1.pas', LRef).StartsWith('Form1.pas: 2 character(s)')
    and (Pos('Yes = raise Form1.pas to UTF-8 with BOM', EncodingRaiseQuestion('C:\p\Form1.pas', LRef)) > 0), EncodingRaiseQuestion('C:\p\Form1.pas', LRef));

  LFiles:= RaiseFilesOf(['C:\p\A.pas', 'C:\p\A.dfm', 'C:\p\B.pas'], 'C:\P\a.pas');
  Check('raise.files.of', (Length(LFiles) = 2) and (LFiles[0] = 'C:\p\A.pas') and (LFiles[1] = 'C:\p\A.dfm')
    and (Length(RaiseFilesOf(['C:\p\A.pas', 'C:\p\A.dfm', 'C:\p\B.pas'], 'C:\p\C.pas')) = 0));

  LJob:= Default(TConvertJob);
  LJob.Units         := ['A.pas', 'B.pas', 'C.pas'];
  LJob.BatchSupported:= True;
  Check('raise.job.batched.without', JobRunsBatched(LJob));
  LJob.RaiseFiles:= ['x'];
  Check('raise.job.not.batched', not JobRunsBatched(LJob));

  LRows:= EncodingRefusedRows([EncRefusedRow('U1', csConverted, True), EncRefusedRow('U1', csRefused, True), EncRefusedRow('U2', csRefused, False),
    EncRefusedRow('U1', csRefused, True)]);
  Check('refused.rows', (Length(LRows) = 1) and (LRows[0].UnitPas = 'U1'));

  TestEncodingApplyLive;
end;