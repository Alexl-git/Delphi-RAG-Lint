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
  , DRagLint.Refactor.MultiProjectRename
  , DRagLint.Refactor.TextEdit
  ;

const
  KIND_TEXT: array[TOwnerKind] of string = ('project', 'library');
  MEMBERSHIP_TEXT: array[TDbMembership] of string = ('member', 'notmember', 'unknown');
  FRESHNESS_TEXT: array[TOwnerFreshness] of string = ('fresh', 'reindexed', 'unverified');
  REINDEX_TIMEOUT_MS = 120000;
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
  Result:= CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, PChar(W), SI, PI);
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

procedure RefreshChecks;
var
  C    : TArray<string>;
  Store: ISymbolStore  ;
  Rep  : TFreshnessReport;
  F    : string        ;
begin
  Writeln('r.changed_fresh=', Length(Changed(W + 'A.sqlite')));
  Refresh('r.fresh', W + 'A.sqlite', W + 'A\A.dpr', ShellReindex());

  { An index whose completed-run stamp is gone is STALE, not fresh. }
  Store:= TSQLiteSymbolStore.Create(W + 'A_nostamp.sqlite');
  Store.SetMetaValue(INDEXED_AT_KEY, '');
  Store:= nil;
  Refresh('r.nostamp', W + 'A_nostamp.sqlite', W + 'A\A.dpr', FakeReindex(True));

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
  Edits:= [GuardEdit(F1, 3, 3, 'My_Const', 'MyConst'), GuardEdit(F2, 2, 7, 'my_const', 'MyConst')];
  Writeln('wg.fresh=', if FindStaleEdit(Edits, Bad) then 'stale' else 'ok');
  TFile.WriteAllText(F2, 'unit wg2;'#13#10'  // moved'#13#10'  X:= My_Const;'#13#10, TEncoding.ANSI);
  Writeln('wg.moved=', if FindStaleEdit(Edits, Bad) then 'stale' else 'ok');
  Writeln('wg.moved.at=', ExtractFileName(Bad.FilePath), ':', Bad.Line);
  TFile.Delete(F2);
  Writeln('wg.gone=', if FindStaleEdit(Edits, Bad) then 'stale' else 'ok');
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
    Writeln('DONE');
  except
    on E: Exception do Writeln('EXCEPTION=', E.ClassName, ': ', E.Message);
  end; // try
end.
