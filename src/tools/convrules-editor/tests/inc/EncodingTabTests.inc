{ The Convert tab's encoding decisions (Task 6): the lower-the-book offer, the lossless
  lowering of a book that is not the open one, the re-run job and the raise-question guard.
  The forms are outside this closure: every decision the tab takes is a pure function here.
  The lossy character is Cyrillic (U+0414): cp1252 cannot hold it. }

function EncTabBytesText(const ABytes: TBytes): string;
begin
  Result:= '';
  for var I: Integer:= 0 to High(ABytes) do
    if I < 8 then
      Result:= Result + IntToHex(ABytes[I], 2) + ' ';
end;

procedure TestEncodingTab;
var
  Dir, B1, B2, B3, Bak, Err: string;
  Cands: TArray<TLowerCandidate>;
  Job, Re: TConvertJob;
  Bytes: TBytes;
  Rows: TArray<TConvertRow>;
  Ref: TConvertRow;
begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'enctab-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    B1:= TPath.Combine(Dir, 'b1.rules');
    B2:= TPath.Combine(Dir, 'b2.rules');
    B3:= TPath.Combine(Dir, 'b3.rules');
    TFile.WriteAllText(B1, '#convert A.TX -> B.TY, B' + sLineBreak, TEncoding.ASCII);
    TFile.WriteAllText(B2, '#convert A.TX -> B.TY, B' + sLineBreak, TEncoding.Unicode);
    TFile.WriteAllText(B3, '#migrate Old -> New' + Chr($0414) + ', U' + sLineBreak, TEncoding.Unicode);

    // lower.candidates: only the UTF-16 books whose characters fit a lower level are offered.
    Cands:= LowerCandidates([B1, B2, B3], nil);
    Check('lower.candidates', (Length(Cands) = 2)
      and (Cands[0].Path = B2) and (Cands[0].Current = tlUtf16Bom) and (Cands[0].Offer = tlAscii7)
      and (Cands[1].Path = B3) and (Cands[1].Current = tlUtf16Bom) and (Cands[1].Offer = tlUtf8),
      Format('count=%d', [Length(Cands)]));
    // Asked once per session: a path already asked (any case) is skipped.
    Cands:= LowerCandidates([B1, B2, B3], [UpperCase(B2)]);
    Check('lower.candidates.asked', (Length(Cands) = 1) and (Cands[0].Path = B3), Format('count=%d', [Length(Cands)]));
    // A book that cannot be read is not offered (the run itself reports it).
    Cands:= LowerCandidates([TPath.Combine(Dir, 'missing.rules')], nil);
    Check('lower.candidates.missing', Length(Cands) = 0, Format('count=%d', [Length(Cands)]));

    // lower.file: a book that is not the open one is re-encoded byte for byte, with a backup.
    Err:= LowerBookFile(B2, tlAscii7, Bak);
    Bytes:= TFile.ReadAllBytes(B2);
    Check('lower.file.ok', (Err = '') and (Length(Bytes) > 0) and (Bytes[0] = Ord('#'))
      and (TEncoding.ASCII.GetString(Bytes) = '#convert A.TX -> B.TY, B' + sLineBreak), Err + ' | ' + EncTabBytesText(Bytes));
    Check('lower.file.backup', (Bak <> '') and TFile.Exists(Bak) and (EncTabBytesText(TFile.ReadAllBytes(Bak)).StartsWith('FF FE')), Bak);
    // A level the text does not fit: refused, the file is untouched, no backup.
    Bytes:= TFile.ReadAllBytes(B3);
    Err:= LowerBookFile(B3, tlAscii7, Bak);
    Check('lower.file.lossy', Err.StartsWith('Lowering of b3.rules aborted') and (Bak = '')
      and (EncTabBytesText(TFile.ReadAllBytes(B3)) = EncTabBytesText(Bytes)) and (Length(TFile.ReadAllBytes(B3)) = Length(Bytes)), Err);
    Err:= LowerBookFile(TPath.Combine(Dir, 'missing.rules'), tlAscii7, Bak);
    Check('lower.file.missing', Err.StartsWith('Lowering of missing.rules aborted') and (Bak = ''), Err);
    // the abort text is also used when SaveBook failed AFTER bytes were written: it must not claim 'not changed'
    Check('lower.aborted.wording', (Pos('may be unchanged', LOWER_ABORTED_FMT) > 0) and (Pos('was not changed', LOWER_ABORTED_FMT) = 0));
  finally
    TDirectory.Delete(Dir, True);
  end; // try

  // rerun.job: the chosen units with their files. Books stay ALL the job's books: a refusal
  // restores the unit (earlier books' rows become csRolledBack), so every book must run again.
  // RunId stays: StartRun numbers every run (ruling I2).
  Job:= Default(TConvertJob);
  Job.Units    := ['A.pas', 'B.pas', 'C.pas'];
  Job.Books    := ['X.rules', 'Y.rules'];
  Job.Dbs      := ['p.sqlite', 'lib.sqlite'];
  Job.ProjectDb:= 'p.sqlite';
  Job.RunId    := 3;
  Re:= RerunJob(Job, ['B.pas'], ['B.pas']);
  Check('rerun.job', (Length(Re.Units) = 1) and (Re.Units[0] = 'B.pas') and (Length(Re.RaiseFiles) = 1) and (Re.RaiseFiles[0] = 'B.pas')
    and (Re.RunId = 3) and (Length(Re.Books) = 2) and (Re.Books[1] = 'Y.rules') and (Length(Re.Dbs) = 2) and (Re.ProjectDb = 'p.sqlite'));
  Check('rerun.job.source.untouched', (Length(Job.Units) = 3) and (Length(Job.RaiseFiles) = 0));

  // encoding.rerun.rows: the data rule does not know about re-runs -- a refused row of a raise
  // run is still returned. The "never ask twice" rule is ShouldAskRaise's (Review Focus 4).
  Ref:= Default(TConvertRow);
  Ref.UnitPas:= 'B.pas';
  Ref.Status := csRefused;
  Ref.Apply.Refused:= True;
  Ref.Apply.EncodingRefusal.FileName:= 'B.pas';
  Rows:= [Ref];
  Check('encoding.rerun.rows', Length(EncodingRefusedRows(Rows)) = 1);

  // ask.raise.guard (ruling I8): asked only after an ordinary, uncancelled run of an engine with the guard.
  Job.ApplyFeatures:= [afEncodingGuard];
  Check('ask.raise.ordinary', ShouldAskRaise(Job, False));
  Check('ask.raise.cancelled', not ShouldAskRaise(Job, True));
  Re.ApplyFeatures:= [afEncodingGuard];
  Check('ask.raise.rerun.never', not ShouldAskRaise(Re, False));
  Job.ApplyFeatures:= [];
  Check('ask.raise.no.guard', not ShouldAskRaise(Job, False));

  // ask.texts: the formats take their arguments without raising.
  Check('ask.texts.lower', Format(ASK_LOWER_FMT, ['b.rules', LevelName(tlUtf16Bom), LevelName(tlAscii7)]).StartsWith('b.rules is saved as UTF-16 with BOM but every character in it fits ASCII-7.'));
  Check('ask.texts.rerun', Format(RERUN_STATUS_FMT, [1, 'x']) = 'Re-run after raising 1 file(s) to UTF-8 with BOM: x');
  Re.RaiseFiles:= ['C:\p\B.pas', 'C:\p\B.dfm'];
  Check('ask.texts.rerun.status', RerunStatusText(Re) = 'Re-run after raising 2 file(s) to UTF-8 with BOM: B.pas, B.dfm', RerunStatusText(Re));
  Check('ask.texts.rerun.none', RerunStatusText(Job) = '');
end;
