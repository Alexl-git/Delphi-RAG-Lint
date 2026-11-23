unit DRagLint.CLI.RepoConstGen;

{ drag-lint 1.53 -- `repo gen-const` (lane FR-CONSTGEN; spec
  docs\superpowers\specs\2026-11-22-field-repository-v2-design.md section 7).
  The CLI adapter of DRagLint.FieldRepo.ConstGen: flag reading, argument checks, the one file write.
  Writes only to the --output path it is given; there is no default path (FR-1). }

interface

/// <summary>Runs `drag-lint repo gen-const`: writes the registry unit generated from a repository.</summary>
/// <param name="pRepoPath">Resolved repository file (from --repo or --project).</param>
/// <param name="pOutFile">--output value: the unit file to write; required unless --dry-run.</param>
/// <returns>0 = written (or dry run reported); 1 = the repository is missing or unreadable;
/// 2 = bad arguments (unknown or refused --table, --unit not an identifier, no --output, its folder missing).</returns>
/// <remarks>
/// The other flags are read from the command line here: --unit (default uFieldRegistry), --table (comma list;
/// default the four registry tables), --memtable, --dry-run (prints the row counts, writes nothing).
/// The repository is opened read only. Not thread-safe; main thread only.
/// </remarks>
function RunRepoGenConst(const pRepoPath, pOutFile: string): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ConstGen,
  FireDAC.Comp.Client;

const
  EXIT_OK    = 0;
  EXIT_FAIL  = 1;
  EXIT_USAGE = 2;
  VERB       = 'repo gen-const';
  DEFAULT_UNIT = 'uFieldRegistry';

function CommandLineFlag(const pFlag: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), pFlag) then
      Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), pFlag) then
      Exit(ParamStr(I + 1));
end;

function ReadOptions(const pRepoPath: string): TConstGenOptions;
var
  VTables, VName: string;
begin
  Result := Default(TConstGenOptions);
  Result.UnitName := CommandLineValue('--unit');
  if Result.UnitName = '' then
    Result.UnitName := DEFAULT_UNIT;
  Result.SourceName := ChangeFileExt(ExtractFileName(pRepoPath), '');
  Result.MemTable := CommandLineFlag('--memtable');
  VTables := CommandLineValue('--table');
  if VTables <> '' then
    for VName in VTables.Split([',']) do
      if Trim(VName) <> '' then
        Result.Tables := Result.Tables + [UpperCase(Trim(VName))];
end;

{ Writes pText as ASCII bytes (no BOM), replacing the file. }
procedure WriteUnitFile(const pFile, pText: string);
begin
  TFile.WriteAllBytes(pFile, TEncoding.ASCII.GetBytes(pText));
end;

function Generate(const pRepoPath, pOutFile: string; const pOptions: TConstGenOptions; pDry: Boolean): Integer;
var
  VConn: TFDConnection;
  VCount: TConstGenCount;
  VCounts: TArray<TConstGenCount>;
  VText: string;
  VTotal: Integer;
begin
  VConn := OpenRepository(pRepoPath, True);
  try
    VCounts := CountConstRows(VConn, pOptions);
    VTotal := 0;
    for VCount in VCounts do
    begin
      Inc(VTotal, VCount.Rows);
      Writeln(VCount.Table, ': ', VCount.Rows, ' rows');
    end;
    if pDry then
    begin
      Writeln('dry run: ', Length(VCounts), ' tables, ', VTotal, ' rows; nothing written');
      Exit(EXIT_OK);
    end;
    VText := GenRepoConstUnit(VConn, pOptions);
  finally
    VConn.Free;
  end;
  WriteUnitFile(pOutFile, VText);
  Writeln('wrote ', pOutFile, ': unit ', pOptions.UnitName, ', ', Length(VCounts), ' tables, ', VTotal, ' rows');
  Result := EXIT_OK;
end;

function RunRepoGenConst(const pRepoPath, pOutFile: string): Integer;
var
  VOpt: TConstGenOptions;
  VDry: Boolean;
begin
  VDry := CommandLineFlag('--dry-run');
  if not TFile.Exists(pRepoPath) then
  begin
    Writeln(ErrOutput, VERB, ': the repository does not exist: ', pRepoPath);
    Exit(EXIT_FAIL);
  end;
  if (not VDry) and (pOutFile = '') then
  begin
    Writeln(ErrOutput, VERB, ': give --output <file.pas> (there is no default path)');
    Exit(EXIT_USAGE);
  end;
  if (not VDry) and (not TDirectory.Exists(ExtractFilePath(ExpandFileName(pOutFile)))) then
  begin
    Writeln(ErrOutput, VERB, ': the output folder does not exist: ', ExtractFilePath(ExpandFileName(pOutFile)));
    Exit(EXIT_USAGE);
  end;
  VOpt := ReadOptions(pRepoPath);
  if not IsPasIdent(VOpt.UnitName) then
  begin
    Writeln(ErrOutput, VERB, ': --unit "', VOpt.UnitName, '" is not an identifier');
    Exit(EXIT_USAGE);
  end;
  try
    Result := Generate(pRepoPath, ExpandFileName(pOutFile), VOpt, VDry);
  except
    on E: EConstGenError do
    begin
      Writeln(ErrOutput, VERB, ': ', E.Message);
      Result := EXIT_USAGE;
    end;
  end;
end;

end.
