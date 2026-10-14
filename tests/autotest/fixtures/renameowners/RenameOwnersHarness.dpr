program RenameOwnersHarness;

{ Pins DRagLint.Storage.FileMembership.DbMembership (spec 8a/8c) and
  DRagLint.Refactor.MultiProjectRename.FindRenameOwners (8a-8d) against
  fixture databases the deployed engine built, and RefreshOwner /
  ChangedFilePaths (criteria 3-5) against copies of them. Driven by
  tests\autotest\run_rename_owners_harness.ps1, which asserts the key=value
  lines printed here.
  Arg 1: the fixture work folder (shared\, twin\, A.sqlite, T.sqlite, ...).
  Arg 2: the engine exe RefreshOwner's reindex callback shells. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , FireDAC.Stan.Async { the CLI links it elsewhere; FileMembership's open needs it }
  , System.IOUtils
  , System.DateUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Storage.SQLite
  , DRagLint.Index.Freshness
  , Winapi.Windows
  , DRagLint.Storage.FileMembership
  , DRagLint.Index.Manifest
  , DRagLint.Project.Coherence
  , DRagLint.Refactor.MultiProjectRename
  , DRagLint.Refactor.TextEdit
  ;

const
  KIND_TEXT: array[TOwnerKind] of string = ('project', 'library');
  MEMBERSHIP_TEXT: array[TDbMembership] of string = ('member', 'notmember', 'unknown');
  FRESHNESS_TEXT: array[TOwnerFreshness] of string = ('fresh', 'reindexed', 'unverified', 'stale');
  REINDEX_TIMEOUT_MS = 120000;
  { the wg fixture's edit positions: My_Const in wg1 (line 3 col 3), its use in wg2 (line 2 col 7) }
  WG_DECL_LINE = 3;
  WG_DECL_COL  = 3;
  WG_USE_LINE  = 2;
  WG_USE_COL   = 7;
  TOUCH_AHEAD_SEC = 10; { mtime_unix is in SECONDS: an edit in the second the DB was built would read as unchanged }

var
  W           : string ;
  Shared      : string ;
  Exe         : string ;
  ReindexCalls: Integer;
  ReindexArgs : string ;

procedure Probe(const AKey, ADb, AFile: string);
var
  Reason: string;
  M     : TDbMembership;
begin
  M:= DbMembership(ADb, AFile, Reason);
  Writeln(AKey, '=', MEMBERSHIP_TEXT[M]);
  Writeln(AKey, '.reason=', Reason);
end; // procedure

procedure Discover(const APrefix, AManifestFile, APreferredDb: string);
var
  Man  : TIndexManifest ;
  D    : TOwnerDiscovery;
  Names: string         ;
  Kinds: string         ;
  I    : Integer        ;
begin
  Man:= TManifestIO.ParseText(TFile.ReadAllText(W + AManifestFile), W);
  D  := FindRenameOwners(Man, 'Win64', Shared, APreferredDb);
  Names:= '';
  Kinds:= '';
  for I:= 0 to High(D.Owners) do
  begin
    Names:= Names + (if I > 0 then ',' else '') + D.Owners[I].SectionName;
    Kinds:= Kinds + (if I > 0 then ',' else '') + KIND_TEXT[D.Owners[I].Kind];
    Writeln(APrefix, 'owner_projfile.', I, '=', D.Owners[I].ProjectFile);
  end;
  Writeln(APrefix, 'probed=', D.Probed);
  Writeln(APrefix, 'owners=', Names);
  Writeln(APrefix, 'owner_kinds=', Kinds);
  Writeln(APrefix, 'unknown_count=', Length(D.Unknown));
  for I:= 0 to High(D.Unknown) do
    Writeln(APrefix, 'unknown.', I, '=', D.Unknown[I]);
  Writeln(APrefix, 'unindexed_count=', Length(D.Unindexed));
  for I:= 0 to High(D.Unindexed) do
    Writeln(APrefix, 'unindexed.', I, '=', D.Unindexed[I]);
end; // procedure

function OwnerNames(const AManifestFile, APreferredDb: string): string;
var
  D: TOwnerDiscovery;
  I: Integer        ;
begin
  D:= FindRenameOwners(TManifestIO.ParseText(TFile.ReadAllText(W + AManifestFile), W), 'Win64', Shared, APreferredDb);
  Result:= '';
  for I:= 0 to High(D.Owners) do
    Result:= Result + (if I > 0 then ',' else '') + D.Owners[I].SectionName;
end; // function

{ --- RefreshOwner / ChangedFilePaths (criteria 3-5) --- }

function Changed(const ADb: string): TArray<string>;
var
  Store: ISymbolStore;
begin
  Store := TSQLiteSymbolStore.Create(ADb, True);
  Result:= ChangedFilePaths(Store);
end; // function

procedure Touch(const APath: string);
begin
  TFile.AppendAllText(APath, '{ edited }'#13#10, TEncoding.ASCII);
  TFile.SetLastWriteTime(APath, IncSecond(Now, TOUCH_AHEAD_SEC));
end; // procedure

{ The callback the CLI will supply in Task 5, as a test double: the deployed
  engine's incremental `index --project` -- never `index <dir>`. }
function RunQuiet(const ACmd: string): Boolean;
var
  SI  : TStartupInfo       ;
  PI  : TProcessInformation;
  Cmd : string             ;
  Code: DWORD              ;
begin
  { cmd /c with output to NUL: the engine's progress lines must not mix with
    the key=value lines the .ps1 parses. }
  Cmd:= 'cmd.exe /c "' + ACmd + ' >NUL 2>&1"';
  UniqueString(Cmd);
  SI:= Default(TStartupInfo);
  SI.cb:= SizeOf(SI);
  Result:= CreateProcess(PChar(GetEnvironmentVariable('ComSpec')), PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, PChar(W), SI, PI);
  if not Result then Exit;
  try
    Result:= (WaitForSingleObject(PI.hProcess, REINDEX_TIMEOUT_MS) = WAIT_OBJECT_0)
      and GetExitCodeProcess(PI.hProcess, Code) and (Code = 0);
  finally
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  end; // try
end; // function

function ShellReindex: TFunc<string, string, Boolean>;
begin
  Result:= function(AProj, ADb: string): Boolean
    begin
      Inc(ReindexCalls);
      ReindexArgs:= AProj + '|' + ADb;
      Result:= RunQuiet('"' + Exe + '" index --project "' + AProj + '" --db "' + ADb + '"');
    end;
end; // function

{ Counts the call and touches nothing: proves what RefreshOwner does with the
  callback's answer, independent of the engine. }
function FakeReindex(AAnswer: Boolean): TFunc<string, string, Boolean>;
begin
  Result:= function(AProj, ADb: string): Boolean
    begin
      Inc(ReindexCalls);
      ReindexArgs:= AProj + '|' + ADb;
      Result:= AAnswer;
    end;
end; // function

procedure Refresh(const AKey, ADb, AProj: string; const AReindex: TFunc<string, string, Boolean>);
var
  O     : TRenameOwner   ;
  Reason: string         ;
  F     : TOwnerFreshness;
  Before: Integer        ;
begin
  O:= Default(TRenameOwner);
  O.DbPath     := ADb;
  O.SectionName:= AKey;
  O.ProjectFile:= AProj;
  Before:= ReindexCalls;
  F:= RefreshOwner(O, AReindex, Reason);
  Writeln(AKey, '=', FRESHNESS_TEXT[F]);
  Writeln(AKey, '.reason=', Reason);
  Writeln(AKey, '.reindex_calls=', ReindexCalls - Before);
end; // procedure

{ Size and last-write time of a file, for a "was it written?" check. }
function FileStamp(const APath: string): string;
begin
  Result:= IntToStr(TFile.GetSize(APath)) + '|' + FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTimeUtc(APath));
end; // function

procedure RefreshChecks;
var
  C    : TArray<string>;
  Store: ISymbolStore  ;
  Rep  : TFreshnessReport;
  F    : string        ;
  Stamp: string        ;
begin
  Writeln('r.changed_fresh=', Length(Changed(W + 'A.sqlite')));
  Refresh('r.fresh', W + 'A.sqlite', W + 'A\A.dpr', ShellReindex());

  { An index whose completed-run stamp is gone is STALE, not fresh. }
  Store:= TSQLiteSymbolStore.Create(W + 'A_nostamp.sqlite');
  Store.SetMetaValue(INDEXED_AT_KEY, '');
  Store:= nil;
  Refresh('r.nostamp', W + 'A_nostamp.sqlite', W + 'A\A.dpr', FakeReindex(True));

  { T1: an index stamped with ANOTHER project's tag is not this project's
    index, however fresh its rows are -- unverified, and never reindexed. }
  Refresh('r.wrongtag', W + 'A_tag.sqlite', W + 'T\T.dpr', FakeReindex(True));
  { ... but an EMPTY tag (an index built before the stamp) is no mismatch. }
  Store:= TSQLiteSymbolStore.Create(W + 'A_notag.sqlite');
  Store.SetMetaValue(PROJECT_TAG_KEY, '');
  Store:= nil;
  Refresh('r.notag', W + 'A_notag.sqlite', W + 'T\T.dpr', FakeReindex(True));

  { T2: a .dproj member the index does not hold (added after indexing). A
    preview reports it stale and writes nothing; an apply reindexes once; a
    reindex that still leaves it out is unverified with the rebuild hint. }
  Stamp:= FileStamp(W + 'M_preview.sqlite');
  Refresh('r.member', W + 'M_preview.sqlite', W + 'M\M.dproj', nil);
  Writeln('r.member.db_unchanged=', FileStamp(W + 'M_preview.sqlite') = Stamp);
  Refresh('r.memberapply', W + 'M_apply.sqlite', W + 'M\M.dproj', ShellReindex());
  Refresh('r.membernoop', W + 'M_noop.sqlite', W + 'M\M.dproj', FakeReindex(True));

  Touch(Shared);
  C:= Changed(W + 'A.sqlite');
  Writeln('r.changed_before=', Length(C));
  if Length(C) > 0 then Writeln('r.changed_before.0=', C[0]);

  { The FULL list: five changed files where the probe keeps three examples. }
  for F in TDirectory.GetFiles(W + 'many', '*.pas') do Touch(F);
  Writeln('m.changed=', Length(Changed(W + 'many.sqlite')));
  Store:= TSQLiteSymbolStore.Create(W + 'many.sqlite', True);
  Rep  := ProbeIndexFreshness(Store);
  Store:= nil;
  Writeln('m.probe_changed=', Rep.Changed);
  Writeln('m.probe_examples=', Length(Rep.Examples));

  { A PREVIEW (no reindex callback, Ruling 12): a stale project owner is
    reported stale with its changed-file count and the DB is not written; a
    stale folder DB is unverified exactly as on an apply. }
  Stamp:= FileStamp(W + 'A_preview.sqlite');
  Refresh('r.preview', W + 'A_preview.sqlite', W + 'A\A.dpr', nil);
  Writeln('r.preview.db_unchanged=', FileStamp(W + 'A_preview.sqlite') = Stamp);
  Refresh('r.previewfolder', W + 'LIB.sqlite', '', nil);

  Refresh('r.stale', W + 'A.sqlite', W + 'A\A.dpr', ShellReindex());
  Writeln('r.stale.args=', ReindexArgs);
  Writeln('r.changed_after=', Length(Changed(W + 'A.sqlite')));

  Refresh('r.fail'   , W + 'A_fail.sqlite', W + 'A\A.dpr', FakeReindex(False));
  Refresh('r.noop'   , W + 'A_noop.sqlite', W + 'A\A.dpr', FakeReindex(True));
  Refresh('r.bad'    , W + 'bad.sqlite'   , W + 'A\A.dpr', ShellReindex());
  Refresh('r.missing', W + 'missing.sqlite', W + 'A\A.dpr', ShellReindex());
  Refresh('r.folder' , W + 'LIB.sqlite'   , ''           , ShellReindex());
end; // procedure

{ The write-time all-or-nothing guard (fix round 1, ruling 8): FindStaleEdit
  on a rename's edit set, against a file as written, then after ONE of the
  edits' lines is changed on disk. }
function GuardEdit(const AFile: string; ALine, ACol: Integer; const AOld, ANew: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath  := AFile;
  Result.Kind      := tekReplaceInLine;
  Result.Line      := ALine;
  Result.Col       := ACol;
  Result.EndCol    := ACol + Length(AOld);
  Result.Text      := ANew;
  Result.ExpectText:= AOld;
end; // function

procedure WriteGuardChecks;
var
  F1, F2: string           ;
  Edits : TArray<TTextEdit>;
  Bad   : TTextEdit        ;
begin
  F1:= W + 'wg1.pas';
  F2:= W + 'wg2.pas';
  TFile.WriteAllText(F1, 'unit wg1;'#13#10'const'#13#10'  My_Const = 1;'#13#10, TEncoding.ANSI);
  TFile.WriteAllText(F2, 'unit wg2;'#13#10'  X:= My_Const;'#13#10, TEncoding.ANSI);
  Edits:= [GuardEdit(F1, WG_DECL_LINE, WG_DECL_COL, 'My_Const', 'MyConst'), GuardEdit(F2, WG_USE_LINE, WG_USE_COL, 'my_const', 'MyConst')];
  Writeln('wg.fresh=', if FindStaleEdit(Edits, Bad) then 'stale' else 'ok');
  TFile.WriteAllText(F2, 'unit wg2;'#13#10'  // moved'#13#10'  X:= My_Const;'#13#10, TEncoding.ANSI);
  Writeln('wg.moved=', if FindStaleEdit(Edits, Bad) then 'stale' else 'ok');
  Writeln('wg.moved.at=', ExtractFileName(Bad.FilePath), ':', Bad.Line);
  TFile.Delete(F2);
  Writeln('wg.gone=', if FindStaleEdit(Edits, Bad) then 'stale' else 'ok');
end; // procedure

{ Ruling 13: two owners spelling ONE file in two cases (BASICS.PAS vs
  Basics.pas) is one file -- merged to one spelling, applied as one group,
  backed up once from the original bytes, and checked for overlapping deletes
  as one group. }
procedure CaseChecks;
const
  WC_ORIGINAL = 'unit wc;'#13#10'const'#13#10'  My_Const = 1;'#13#10'  Y = My_Const;'#13#10;
  WC_RENAMED  = 'unit wc;'#13#10'const'#13#10'  MyConst = 1;'#13#10'  Y = MyConst;'#13#10;
  WC_USE_LINE = 4;
  WC_USE_COL  = 7;
var
  F, UpPath: string        ;
  Merged: TArray<TTextEdit>;
  Why   : string           ;
  D1, D2: TTextEdit        ;
begin
  F  := W + 'wc.pas';
  UpPath:= UpperCase(F);
  TFile.WriteAllText(F, WC_ORIGINAL, TEncoding.ANSI);
  { owner B (upper case) holds the declaration edit A has AND a use only B has }
  Why:= MergeEdits([[GuardEdit(F, WG_DECL_LINE, WG_DECL_COL, 'My_Const', 'MyConst')],
    [GuardEdit(UpPath, WG_DECL_LINE, WG_DECL_COL, 'My_Const', 'MyConst'), GuardEdit(UpPath, WC_USE_LINE, WC_USE_COL, 'My_Const', 'MyConst')]],
    F, Merged);
  Writeln('wc.why=[', Why, ']');
  Writeln('wc.merged=', Length(Merged));
  Writeln('wc.one_spelling=', (Length(Merged) = 2) and (Merged[0].FilePath = F) and (Merged[1].FilePath = F));
  { the applier alone, given the two spellings unmerged }
  Writeln('wc.touched=', TTextEditApplier.Apply([GuardEdit(F, WG_DECL_LINE, WG_DECL_COL, 'My_Const', 'MyConst'),
    GuardEdit(UpPath, WC_USE_LINE, WC_USE_COL, 'My_Const', 'MyConst')], True));
  Writeln('wc.text_ok=', TFile.ReadAllText(F, TEncoding.ANSI) = WC_RENAMED);
  Writeln('wc.bak_is_original=', TFile.ReadAllText(F + '.bak', TEncoding.ANSI) = WC_ORIGINAL);
  D1        := Default(TTextEdit);
  D1.FilePath:= F;
  D1.Kind    := tekDeleteLines;
  D1.Line    := WG_DECL_LINE - 1;
  D1.EndLine := WG_DECL_LINE;
  D2         := D1;
  D2.FilePath:= UpPath;
  D2.Line    := WG_DECL_LINE;
  D2.EndLine := WC_USE_LINE;
  Writeln('wc.overlap_refused=', TTextEditApplier.RefusalOf([D1, D2]) <> '');
end; // procedure

{ T5: the write-time guard over a RUN's plans. Two applied plans, the second's
  file changed on disk: a batch drops only the stale one; a single fix
  (--fix-line, criterion 9) drops BOTH -- all or nothing per run. }
function AwPlan(const AFile, AOld, ANew: string): TTargetPlan;
begin
  Result                := Default(TTargetPlan);
  Result.Target.OldName := AOld;
  Result.NewName        := ANew;
  Result.Decision       := rdApply;
  Result.Edits          := [GuardEdit(AFile, WG_DECL_LINE, WG_DECL_COL, AOld, ANew)];
end; // function

procedure AtWriteChecks;
var
  F1, F2: string              ;
  Plans : TArray<TTargetPlan> ;
  Edits : TArray<TTextEdit>   ;
  Notes : TArray<string>      ;
  N     : Integer             ;
begin
  F1:= W + 'aw1.pas';
  F2:= W + 'aw2.pas';
  TFile.WriteAllText(F1, 'unit aw1;'#13#10'const'#13#10'  My_Const = 1;'#13#10, TEncoding.ANSI);
  TFile.WriteAllText(F2, 'unit aw2;'#13#10'// moved'#13#10'const'#13#10'  Other_Const = 2;'#13#10, TEncoding.ANSI);
  Plans:= [AwPlan(F1, 'My_Const', 'MyConst'), AwPlan(F2, 'Other_Const', 'OtherConst')];
  N:= GuardPlansAtWrite(Plans, False, Edits, Notes);
  Writeln('aw.batch=', N, '|', Length(Edits), '|', Length(Notes), '|', Ord(Plans[0].Decision), Ord(Plans[1].Decision));
  Plans:= [AwPlan(F1, 'My_Const', 'MyConst'), AwPlan(F2, 'Other_Const', 'OtherConst')];
  N:= GuardPlansAtWrite(Plans, True, Edits, Notes);
  Writeln('aw.single=', N, '|', Length(Edits), '|', Length(Notes), '|', Ord(Plans[0].Decision), Ord(Plans[1].Decision));
  Writeln('aw.single.reason0=', Plans[0].Reason);
  Writeln('aw.single.edits0=', Length(Plans[0].Edits));
end; // procedure

begin  try
    W     := IncludeTrailingPathDelimiter(ParamStr(1));
    Shared:= W + 'shared\uShared.pas';
    Exe   := ParamStr(2);
    Probe('A'      , W + 'A.sqlite'      , Shared);
    Probe('A_upper', W + 'A.sqlite'      , UpperCase(Shared));
    Probe('T'      , W + 'T.sqlite'      , Shared);
    Probe('bad'    , W + 'bad.sqlite'    , Shared);
    Probe('missing', W + 'missing.sqlite', Shared);
    Discover('', 'owners.json', '');
    Writeln('owners_pref=', OwnerNames('owners.json', W + 'LIB.sqlite'));
    Discover('u.', 'unknown.json', '');
    RefreshChecks;
    WriteGuardChecks;
    CaseChecks;
    AtWriteChecks;
    Writeln('DONE');
  except
    on E: Exception do Writeln('EXCEPTION=', E.ClassName, ': ', E.Message);
  end; // try
end.
