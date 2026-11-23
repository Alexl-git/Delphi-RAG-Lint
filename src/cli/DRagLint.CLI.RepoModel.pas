unit DRagLint.CLI.RepoModel;

{ drag-lint 1.53 -- lane FR-MODEL: the `repo` sub-verbs of the repository model v2: migrate, check
  (design 2026-11-22-field-repository-v2-design.md section 4.6). DRagLint.CLI.Repo resolves the repository path
  and dispatches here in ONE line; the flags are read from the command line (ParseArgs only has to accept them). }

interface

/// <summary>True for the sub-verbs this unit runs: migrate, check.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True when RunRepoModelVerb handles it.</returns>
function IsRepoModelSub(const pSub: string): Boolean;

/// <summary>Runs `repo migrate` or `repo check` on a resolved repository path.</summary>
/// <param name="pSub">migrate or check.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project).</param>
/// <param name="pJson">--json: machine-readable output (check).</param>
/// <returns>0 = success / clean; 1 = findings (check), a missing file or a usage error.</returns>
/// <remarks>migrate is a dry run unless `--apply` is on the command line. Not thread-safe.</remarks>
function RunRepoModelVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.Migrate,
  DRagLint.FieldRepo.Check;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  SUB_MIGRATE = 'migrate';
  SUB_CHECK = 'check';

function CommandLineFlag(const pFlag: string): Boolean;
var
  VI: Integer;
begin
  Result := False;
  for VI := 1 to ParamCount do
    if SameText(ParamStr(VI), pFlag) then
      Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), pFlag) then
      Exit(ParamStr(VI + 1));
end;

function IsRepoModelSub(const pSub: string): Boolean;
begin
  Result := MatchText(pSub, [SUB_MIGRATE, SUB_CHECK]);
end;

function RunMigrate(const pPath: string): Integer;
var
  VRes: TFrMigrateResult;
  VApply: Boolean;
begin
  VApply := CommandLineFlag('--apply');
  VRes := MigrateRepository(pPath, VApply);
  if VRes.AlreadyCurrent then
  begin
    Writeln('already at schema 2');
    Exit(EXIT_OK);
  end;
  Writeln(VRes.Plan);
  if VRes.Applied then
  begin
    Writeln('before-migrate backup: ', VRes.BackupFile);
    Writeln('migrated: ', pPath);
  end
  else
    Writeln('dry run: nothing written (use --apply)');
  Result := EXIT_OK;
end;

function RunCheck(const pPath: string; pJson: Boolean): Integer;
var
  VConn: TFDConnection;
  VFindings: TArray<TFrCheckFinding>;
  VLine: string;
begin
  VConn := OpenRepository(pPath, True);
  try
    VFindings := CheckRepository(VConn);
  finally
    VConn.Free;
  end;
  if pJson then
    Writeln(RenderCheckJson(VFindings))
  else
    for VLine in RenderCheckText(VFindings) do
      Writeln(VLine);
  Result := if Length(VFindings) = 0 then EXIT_OK else EXIT_FAIL;
end;

function RunRepoModelVerb(const pSub, pPath: string; pJson: Boolean): Integer;
begin
  if not TFile.Exists(pPath) then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': the repository does not exist: ', pPath);
    Exit(EXIT_FAIL);
  end;
  if SameText(pSub, SUB_MIGRATE) then
    Result := RunMigrate(pPath)
  else if SameText(pSub, SUB_CHECK) then
    Result := RunCheck(pPath, pJson)
  else
    Result := EXIT_FAIL;
end;

end.
