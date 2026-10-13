program RenameOwnersHarness;

{ Pins DRagLint.Storage.FileMembership.DbMembership (spec 8a/8c) and
  DRagLint.Refactor.MultiProjectRename.FindRenameOwners (8a-8d) against
  fixture databases the deployed engine built. Driven by
  tests\autotest\run_rename_owners_harness.ps1, which asserts the key=value
  lines printed here.
  Arg 1: the fixture work folder (shared\, twin\, A.sqlite, T.sqlite, ...). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , FireDAC.Stan.Async { the CLI links it elsewhere; FileMembership's open needs it }
  , System.IOUtils
  , DRagLint.Storage.FileMembership
  , DRagLint.Index.Manifest
  , DRagLint.Refactor.MultiProjectRename
  ;

const
  KIND_TEXT: array[TOwnerKind] of string = ('project', 'library');
  MEMBERSHIP_TEXT: array[TDbMembership] of string = ('member', 'notmember', 'unknown');

var
  W     : string;
  Shared: string;

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

begin
  try
    W     := IncludeTrailingPathDelimiter(ParamStr(1));
    Shared:= W + 'shared\uShared.pas';
    Probe('A'      , W + 'A.sqlite'      , Shared);
    Probe('A_upper', W + 'A.sqlite'      , UpperCase(Shared));
    Probe('T'      , W + 'T.sqlite'      , Shared);
    Probe('bad'    , W + 'bad.sqlite'    , Shared);
    Probe('missing', W + 'missing.sqlite', Shared);
    Discover('', 'owners.json', '');
    Writeln('owners_pref=', OwnerNames('owners.json', W + 'LIB.sqlite'));
    Discover('u.', 'unknown.json', '');
    Writeln('DONE');
  except
    on E: Exception do Writeln('EXCEPTION=', E.ClassName, ': ', E.Message);
  end; // try
end.
